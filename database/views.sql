-- =============================================================================
-- ModVault: A Mod Repository and Compatibility Intelligence System
-- View Definitions  --  views.sql
--
-- PURPOSE
--   This file creates PostgreSQL views that simplify complex joins and
--   expose pre-joined "virtual tables" for ModVault application queries.
--
--   This file demonstrates:
--     * CREATE OR REPLACE VIEW  (safe idempotent re-creation)
--     * INNER JOIN across multiple tables
--     * LEFT JOIN to preserve rows with no matching child rows
--     * Aggregate functions: COUNT, AVG, ROUND
--     * GROUP BY on multiple columns
--     * Column aliasing for readable output
--
-- VIEWS DEFINED
--   1. mod_catalog_view          -- mod listing with game name and author name
--   2. mod_ratings_view          -- per-mod review count and average rating
--   3. loadout_summary_view      -- per-loadout mod count with owner and game name
--   4. loadout_health_view       -- per-loadout issue counts, score, status
--   5. mod_conflict_summary_view -- per-mod conflict and dependent counts
--   6. mv_game_leaderboard       -- materialized top mods per game (Bayesian score)
--
-- DEPENDENCY
--   Run AFTER schema.sql and functions.sql have been applied.
--
-- HOW TO RUN
--   Do not run this file alone. It is included by database/run_all.sql.
--   Rebuild everything with:  python scripts/db_reset.py
-- =============================================================================

SET client_encoding = 'UTF8';


-- =============================================================================
-- VIEW 1: mod_catalog_view
--
-- Purpose:
--   Provides a human-readable listing of every mod on the platform by joining
--   the mods table to games (for the game title) and users (for the author's
--   username).  Callers get a single flat row per mod without needing to
--   write the three-table join themselves.
--
-- Tables joined:
--   mods  INNER JOIN  games  ON mods.game_id   = games.game_id
--   mods  LEFT JOIN   users  ON mods.author_id = users.user_id
--   (LEFT JOIN because author_id is NULL for mods imported from Nexus.)
--
-- Columns:
--   mod_id         -- unique identifier of the mod (from mods)
--   mod_name       -- display name of the mod
--   game_name      -- title of the game this mod targets
--   author_name    -- platform username, else the original Nexus author name
--   category       -- mod category (e.g. "Weapons", "Quests"); nullable
--   created_at     -- timestamp when the mod was first published
--
-- ASSUMPTION: author_name replaces the old author_username column rather than
--             sitting beside it, so callers have one author field to read.
--
-- Typical use:
--   SELECT * FROM mod_catalog_view WHERE game_name = 'Skyrim Special Edition';
-- =============================================================================

CREATE OR REPLACE VIEW mod_catalog_view AS
SELECT
    m.mod_id,
    m.name          AS mod_name,
    g.name          AS game_name,
    coalesce(u.username, m.nexus_author) AS author_name,
    m.category,
    m.created_at
FROM mods m
INNER JOIN games g ON m.game_id   = g.game_id
LEFT  JOIN users u ON m.author_id = u.user_id;


-- =============================================================================
-- VIEW 2: mod_ratings_view
--
-- Purpose:
--   Aggregates review data per mod, returning the total number of reviews
--   and the average star rating.  A LEFT JOIN is used so that mods with no
--   reviews still appear in the result with review_count = 0 and
--   avg_rating = NULL, rather than being silently excluded.
--
-- Tables joined:
--   mods  LEFT JOIN  reviews  ON mods.mod_id = reviews.mod_id
--
-- Columns:
--   mod_id        -- unique identifier of the mod
--   mod_name      -- display name of the mod
--   review_count  -- total number of reviews submitted for this mod
--   avg_rating    -- average star rating (1-5), rounded to 2 decimal places;
--                    NULL when the mod has no reviews
--
-- Typical use:
--   SELECT * FROM mod_ratings_view ORDER BY avg_rating DESC NULLS LAST;
-- =============================================================================

CREATE OR REPLACE VIEW mod_ratings_view AS
SELECT
    m.mod_id,
    m.name                                    AS mod_name,
    COUNT(r.review_id)                        AS review_count,
    ROUND(AVG(r.rating)::NUMERIC, 2)          AS avg_rating
FROM mods m
LEFT JOIN reviews r ON m.mod_id = r.mod_id
GROUP BY
    m.mod_id,
    m.name;


-- =============================================================================
-- VIEW 3: loadout_summary_view
--
-- Purpose:
--   Summarises every loadout with its owner's username, the game it targets,
--   and the total number of mod versions it contains.  A LEFT JOIN on
--   loadout_mods ensures that empty loadouts (no mods added yet) are still
--   returned with mod_count = 0.
--
-- Tables joined:
--   loadouts  INNER JOIN  users        ON loadouts.user_id  = users.user_id
--   loadouts  INNER JOIN  games        ON loadouts.game_id  = games.game_id
--   loadouts  LEFT JOIN   loadout_mods ON loadouts.loadout_id = loadout_mods.loadout_id
--
-- Columns:
--   loadout_id      -- unique identifier of the loadout
--   loadout_name    -- display name of the loadout
--   owner_username  -- username of the user who owns this loadout
--   game_name       -- title of the game this loadout is built for
--   mod_count       -- number of mod versions currently in the loadout
--
-- Typical use:
--   SELECT * FROM loadout_summary_view WHERE owner_username = 'hashvyas';
-- =============================================================================

-- security_invoker: the loadouts RLS policies apply to the caller, so private
-- loadouts of other users stay hidden (a plain view reads as its owner).
CREATE OR REPLACE VIEW loadout_summary_view WITH (security_invoker = true) AS
SELECT
    l.loadout_id,
    l.name          AS loadout_name,
    u.username      AS owner_username,
    g.name          AS game_name,
    COUNT(lm.id)    AS mod_count
FROM loadouts l
INNER JOIN users        u  ON l.user_id    = u.user_id
INNER JOIN games        g  ON l.game_id    = g.game_id
LEFT  JOIN loadout_mods lm ON l.loadout_id = lm.loadout_id
GROUP BY
    l.loadout_id,
    l.name,
    u.username,
    g.name;


-- =============================================================================
-- VIEW 4: loadout_health_view
--
-- Purpose:
--   One row per loadout with its health check summary. A LATERAL join calls
--   fn_check_loadout_compatibility once per loadout; counts use aggregate
--   FILTER. Score and status follow contract section 6.6:
--     score  = GREATEST(0, 100 - 25 * errors - 10 * warnings)
--     status = broken (any error), else warnings (any warning), else healthy
--   LEFT JOIN ... ON true keeps empty loadouts (score 100, healthy).
--
-- security_invoker: same reason as loadout_summary_view.
-- ASSUMPTION: counts are bigint (what COUNT(*) produces) and score is int
--             (matches fn_loadout_health_score).
-- =============================================================================

CREATE OR REPLACE VIEW loadout_health_view WITH (security_invoker = true) AS
SELECT
    l.loadout_id,
    count(*) FILTER (WHERE c.severity = 'error')   AS error_count,
    count(*) FILTER (WHERE c.severity = 'warning') AS warning_count,
    count(*) FILTER (WHERE c.severity = 'info')    AS info_count,
    greatest(0, 100 - 25 * count(*) FILTER (WHERE c.severity = 'error')
                    - 10 * count(*) FILTER (WHERE c.severity = 'warning'))::int AS score,
    CASE
        WHEN count(*) FILTER (WHERE c.severity = 'error')   > 0 THEN 'broken'
        WHEN count(*) FILTER (WHERE c.severity = 'warning') > 0 THEN 'warnings'
        ELSE 'healthy'
    END AS status
FROM loadouts l
LEFT JOIN LATERAL fn_check_loadout_compatibility(l.loadout_id) c ON true
GROUP BY l.loadout_id;


-- =============================================================================
-- VIEW 5: mod_conflict_summary_view
--
-- Purpose:
--   Per mod, how often it is involved in trouble, for a "risky mods" report.
--
-- Columns:
--   incompatible_pairs  -- matrix rows with status incompatible touching any
--                          version of the mod
--   partial_pairs       -- same, status partial
--   declared_conflicts  -- 'conflicts' dependencies in either direction
--   dependent_mods      -- distinct other mods with a non-conflict dependency
--                          on this mod (same rule as fn_mod_stats)
-- ASSUMPTION: counts are bigint (what COUNT(*) produces).
-- =============================================================================

CREATE OR REPLACE VIEW mod_conflict_summary_view AS
SELECT
    m.mod_id,
    m.name::text AS mod_name,
    (SELECT count(*) FILTER (WHERE c.status = 'incompatible')
     FROM   compatibility_matrix c
     JOIN   mod_versions va ON va.version_id = c.version_a_id
     JOIN   mod_versions vb ON vb.version_id = c.version_b_id
     WHERE  m.mod_id IN (va.mod_id, vb.mod_id)) AS incompatible_pairs,
    (SELECT count(*) FILTER (WHERE c.status = 'partial')
     FROM   compatibility_matrix c
     JOIN   mod_versions va ON va.version_id = c.version_a_id
     JOIN   mod_versions vb ON vb.version_id = c.version_b_id
     WHERE  m.mod_id IN (va.mod_id, vb.mod_id)) AS partial_pairs,
    (SELECT count(*)
     FROM   mod_dependencies d
     JOIN   mod_versions dv ON dv.version_id = d.dependent_version_id
     WHERE  d.dep_type = 'conflicts'
       AND  (d.required_mod_id = m.mod_id OR dv.mod_id = m.mod_id)) AS declared_conflicts,
    (SELECT count(DISTINCT dv.mod_id)
     FROM   mod_dependencies d
     JOIN   mod_versions dv ON dv.version_id = d.dependent_version_id
     WHERE  d.required_mod_id = m.mod_id
       AND  d.dep_type <> 'conflicts'
       AND  dv.mod_id <> m.mod_id) AS dependent_mods
FROM mods m;


-- =============================================================================
-- VIEW 6: mv_game_leaderboard  (materialized)
--
-- Purpose:
--   Top 20 mods per game by a Bayesian average, so a mod with one 5-star
--   review does not outrank a mod with many 4.8-star reviews:
--     bayes_score = (C * m + rating_count * rating_avg) / (C + rating_count)
--   C = 5 (prior weight), m = average review rating across the same game.
--   RANK() OVER (PARTITION BY game_id ...) numbers mods inside each game.
--   Refreshed by run_all.sql and by pr_refresh_reports (CONCURRENTLY, which
--   the unique index allows).
--
-- ASSUMPTION: a game with no reviews gets m = 0, so every mod there scores 0
--             and the download count decides the order.
-- =============================================================================

CREATE MATERIALIZED VIEW mv_game_leaderboard AS
WITH game_mean AS (
    SELECT m.game_id, avg(r.rating)::numeric AS mean_rating
    FROM   reviews r
    JOIN   mods m ON m.mod_id = r.mod_id
    GROUP  BY m.game_id
),
scored AS (
    SELECT m.game_id, m.mod_id, m.name::text AS mod_name, m.rating_count,
           m.rating_avg::numeric AS rating_avg,
           round((5 * coalesce(gm.mean_rating, 0) + m.rating_count * m.rating_avg)
                 / (5 + m.rating_count), 4) AS bayes_score,
           m.download_count
    FROM   mods m
    LEFT   JOIN game_mean gm ON gm.game_id = m.game_id
),
ranked AS (
    SELECT s.*, RANK() OVER (PARTITION BY s.game_id
                             ORDER BY s.bayes_score DESC, s.download_count DESC) AS rank_in_game
    FROM   scored s
)
SELECT game_id, mod_id, mod_name, rating_count, rating_avg, bayes_score, download_count, rank_in_game
FROM   ranked
WHERE  rank_in_game <= 20;

CREATE UNIQUE INDEX uq_mv_game_leaderboard_game_mod
    ON mv_game_leaderboard (game_id, mod_id);
