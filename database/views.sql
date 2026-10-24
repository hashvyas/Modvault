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

CREATE OR REPLACE VIEW loadout_summary_view AS
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
-- VIEW 4: loadout_health_view  (Phase 0 stub, filled in Phase 3)
--
-- Columns: loadout_id, error_count, warning_count, info_count, score, status
-- Will call fn_check_loadout_compatibility for every loadout via LATERAL.
-- status is 'broken', 'warnings' or 'healthy'.
-- ASSUMPTION: counts are bigint (what COUNT(*) produces) and score is int
--             (matches fn_loadout_health_score).
-- =============================================================================

CREATE OR REPLACE VIEW loadout_health_view AS
SELECT
    NULL::uuid   AS loadout_id,
    NULL::bigint AS error_count,
    NULL::bigint AS warning_count,
    NULL::bigint AS info_count,
    NULL::int    AS score,
    NULL::text   AS status
WHERE false;


-- =============================================================================
-- VIEW 5: mod_conflict_summary_view  (Phase 0 stub, filled in Phase 3)
--
-- Columns: mod_id, mod_name, incompatible_pairs, partial_pairs,
--          declared_conflicts, dependent_mods
-- ASSUMPTION: counts are bigint (what COUNT(*) produces).
-- =============================================================================

CREATE OR REPLACE VIEW mod_conflict_summary_view AS
SELECT
    NULL::uuid   AS mod_id,
    NULL::text   AS mod_name,
    NULL::bigint AS incompatible_pairs,
    NULL::bigint AS partial_pairs,
    NULL::bigint AS declared_conflicts,
    NULL::bigint AS dependent_mods
WHERE false;


-- =============================================================================
-- VIEW 6: mv_game_leaderboard  (materialized; Phase 0 stub, filled in Phase 3)
--
-- Columns: game_id, mod_id, mod_name, rating_count, rating_avg, bayes_score,
--          download_count, rank_in_game
-- The unique index allows REFRESH MATERIALIZED VIEW CONCURRENTLY.
-- ASSUMPTION: types follow the mods columns (int, numeric) and RANK() (bigint).
-- =============================================================================

CREATE MATERIALIZED VIEW mv_game_leaderboard AS
SELECT
    NULL::uuid    AS game_id,
    NULL::uuid    AS mod_id,
    NULL::text    AS mod_name,
    NULL::int     AS rating_count,
    NULL::numeric AS rating_avg,
    NULL::numeric AS bayes_score,
    NULL::int     AS download_count,
    NULL::bigint  AS rank_in_game
WHERE false;

CREATE UNIQUE INDEX uq_mv_game_leaderboard_game_mod
    ON mv_game_leaderboard (game_id, mod_id);
