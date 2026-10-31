-- =============================================================================
-- ModVault: A Mod Repository and Compatibility Intelligence System
-- Application Queries  --  queries.sql
--
-- PURPOSE
--   This file collects the primary SELECT queries that power ModVault
--   features.  It demonstrates:
--     * Basic SELECT with WHERE, ORDER BY, LIMIT, OFFSET (pagination)
--     * JOIN patterns: INNER JOIN, LEFT JOIN, multiple-table joins
--     * Aggregate functions: COUNT, AVG, SUM, MAX, MIN with GROUP BY / HAVING
--     * Subqueries: correlated and non-correlated, EXISTS / NOT EXISTS
--     * Common Table Expressions (CTEs) -- WITH ... AS (...)
--     * Window functions: ROW_NUMBER, RANK, DENSE_RANK, LAG, LEAD,
--       PARTITION BY, ORDER BY within window
--     * JSONB operators for querying compatibility_matrix.conflict_detail
--     * Full-text search with tsvector / tsquery (PostgreSQL built-in)
--     * Recursive CTE for dependency-chain traversal
--
-- ORGANISATION
--   Queries are grouped by feature area.  Each query is preceded by one
--   comment line on what it proves.  Queries look rows up by natural keys
--   (username, game domain, mod name) so they read well and survive a reseed.
--
-- SEED NOTES
--   Seeded mods come from Nexus: author_id is NULL and nexus_author holds the
--   author name, and every mods.created_at is the seed time. Author queries
--   therefore fall back to nexus_author, and time-series queries use
--   mod_versions.uploaded_at (real Nexus upload dates).
--
-- WRITES
--   5.6, 7.7 and 7.8 change data. Each runs inside BEGIN ... ROLLBACK, so the
--   file leaves the database unchanged.
--
-- DEPENDENCY
--   Run AFTER database/run_all.sql has built and seeded the database.
--
-- HOW TO RUN
--   python scripts/db_reset.py
--   psql "postgresql://modvault_owner:modvault_owner_dev@localhost:5432/modvault" -v ON_ERROR_STOP=1 -f database/queries.sql
-- =============================================================================

SET client_encoding = 'UTF8';


-- =============================================================================
-- SECTION 1 -- USER QUERIES
-- =============================================================================

-- 1.1  List all users sorted by registration date (basic SELECT + ORDER BY)
-- Proves: ORDER BY with a tie-breaker gives a stable listing.
SELECT username, role, created_at
FROM   users
ORDER  BY created_at, username;

-- 1.2  Find a user by username (equality filter)
-- Proves: equality lookup served by the uq_users_username unique index.
SELECT user_id, username, email, role, is_active
FROM   users
WHERE  username = 'curator';

-- 1.3  Count users per role (aggregate: COUNT + GROUP BY)
-- Proves: GROUP BY on an enum column, ordered by the enum's declared order.
SELECT role, count(*) AS users
FROM   users
GROUP  BY role
ORDER  BY role;

-- 1.4  Find users who have never written a review (NOT EXISTS subquery)
-- Proves: correlated NOT EXISTS anti-join (empty on the seed: every user reviewed).
SELECT u.username
FROM   users u
WHERE  NOT EXISTS (SELECT 1 FROM reviews r WHERE r.user_id = u.user_id)
ORDER  BY u.username;

-- 1.5  Find the most recently registered user per role (window: RANK OVER PARTITION BY)
-- Proves: RANK() restarts per partition; ties share rank 1.
SELECT role, username, created_at
FROM (
    SELECT role, username, created_at,
           RANK() OVER (PARTITION BY role ORDER BY created_at DESC) AS rnk
    FROM   users
) t
WHERE  rnk = 1
ORDER  BY role, username;


-- =============================================================================
-- SECTION 2 -- MOD BROWSE & SEARCH QUERIES
-- =============================================================================

-- 2.1  List all mods for a given game with author username (INNER JOIN)
-- Proves: INNER JOIN to games filters by game; LEFT JOIN to users keeps Nexus mods (author_id NULL).
SELECT m.name, coalesce(u.username, m.nexus_author) AS author, m.category
FROM   mods m
JOIN   games g      ON g.game_id = m.game_id
LEFT   JOIN users u ON u.user_id = m.author_id
WHERE  g.domain = 'skyrimspecialedition'
ORDER  BY m.name;

-- 2.2  List mods with their average rating and review count
--        (LEFT JOIN + AVG + COUNT + GROUP BY)
-- Proves: LEFT JOIN keeps unreviewed mods with count 0 and NULL average.
SELECT m.name, count(r.review_id) AS reviews, round(avg(r.rating), 2) AS avg_rating
FROM   mods m
LEFT   JOIN reviews r ON r.mod_id = m.mod_id
GROUP  BY m.mod_id, m.name
ORDER  BY avg_rating DESC NULLS LAST, m.name
LIMIT  15;

-- 2.3  List mods filtered by tag name (join through mod_tags)
-- Proves: many-to-many traversal mods -> mod_tags -> tags.
SELECT m.name, g.name AS game
FROM   mods m
JOIN   mod_tags mt ON mt.mod_id = m.mod_id
JOIN   tags t      ON t.tag_id = mt.tag_id
JOIN   games g     ON g.game_id = m.game_id
WHERE  t.slug = 'user-interface'
ORDER  BY g.name, m.name;

-- 2.4  Top-10 highest-rated mods for a game (ORDER BY + LIMIT)
-- Proves: ORDER BY on the trigger-maintained rating columns, ties broken by downloads.
SELECT m.name, m.rating_avg, m.rating_count, m.download_count
FROM   mods m
JOIN   games g ON g.game_id = m.game_id
WHERE  g.domain = 'stardewvalley'
ORDER  BY m.rating_avg DESC, m.download_count DESC
LIMIT  10;

-- 2.5  Full-text search on mod name and summary using tsvector/tsquery
-- Proves: the generated search_tsv column (GIN-indexed) with websearch_to_tsquery and ts_rank_cd.
SELECT m.name, round(ts_rank_cd(m.search_tsv, q)::numeric, 4) AS rank
FROM   mods m,
       websearch_to_tsquery('english', 'menu interface') AS q
WHERE  m.search_tsv @@ q
ORDER  BY rank DESC, m.name;

-- 2.6  Find featured mods (uses mods.is_featured)
-- Proves: boolean filter; one row per featured mod with its game.
SELECT g.name AS game, m.name
FROM   mods m
JOIN   games g ON g.game_id = m.game_id
WHERE  m.is_featured
ORDER  BY g.name, m.name;

-- 2.7  List mods with no reviews yet (LEFT JOIN ... WHERE IS NULL)
-- Proves: LEFT JOIN anti-join pattern (same answer as NOT EXISTS in 1.4).
SELECT m.name
FROM   mods m
LEFT   JOIN reviews r ON r.mod_id = m.mod_id
WHERE  r.review_id IS NULL
ORDER  BY m.name;

-- 2.8  Mod catalogue with pagination: page N, M results per page
--        (OFFSET / LIMIT pattern)
-- Proves: page 2 of 10 = rows 11..20 of a deterministic order.
SELECT mod_name, game_name, author_name
FROM   mod_catalog_view
ORDER  BY mod_name, mod_id
LIMIT  10 OFFSET (2 - 1) * 10;


-- =============================================================================
-- SECTION 3 -- VERSION & DEPENDENCY QUERIES
-- =============================================================================

-- 3.1  List all versions of a specific mod ordered by upload date
-- Proves: one-to-many listing; newest first.
SELECT v.semver, v.is_primary, v.uploaded_at
FROM   mod_versions v
JOIN   mods m ON m.mod_id = v.mod_id
WHERE  m.name = 'SkyUI'
ORDER  BY v.uploaded_at DESC;

-- 3.2  Find the primary version of every mod (is_primary = TRUE)
-- Proves: exactly one primary per mod (uq_mod_versions_one_primary): 45 rows.
SELECT m.name, v.semver
FROM   mods m
JOIN   mod_versions v ON v.mod_id = m.mod_id AND v.is_primary
ORDER  BY m.name;

-- 3.3  List direct dependencies of a mod version (dep_type = required)
-- Proves: join from a version to the mods it requires, with the version constraint.
SELECT rm.name AS requires, d.version_constraint
FROM   mod_dependencies d
JOIN   mod_versions v ON v.version_id = d.dependent_version_id AND v.is_primary
JOIN   mods m         ON m.mod_id = v.mod_id
JOIN   mods rm        ON rm.mod_id = d.required_mod_id
WHERE  m.name = 'Automate' AND d.dep_type = 'required'
ORDER  BY rm.name;

-- 3.4  Recursive CTE: full dependency tree for a mod version
--        (WITH RECURSIVE ... demonstrates graph traversal)
-- Proves: WITH RECURSIVE walks required/optional/recommends edges level by level (depth 0 = root).
WITH RECURSIVE tree AS (
    SELECT v.version_id, m.name::text AS mod_name, 0 AS depth, ARRAY[v.version_id] AS path
    FROM   mod_versions v
    JOIN   mods m ON m.mod_id = v.mod_id
    WHERE  m.name = 'Sim Settlements 2' AND v.is_primary
    UNION ALL
    SELECT pv.version_id, pm.name::text, t.depth + 1, t.path || pv.version_id
    FROM   tree t
    JOIN   mod_dependencies d ON d.dependent_version_id = t.version_id AND d.dep_type <> 'conflicts'
    JOIN   mod_versions pv    ON pv.mod_id = d.required_mod_id AND pv.is_primary
    JOIN   mods pm            ON pm.mod_id = pv.mod_id
    WHERE  pv.version_id <> ALL (t.path) AND t.depth < 10
)
SELECT repeat('  ', depth) || mod_name AS tree, depth
FROM   tree
ORDER  BY path;

-- 3.5  Find all mods that depend on a specific mod (reverse lookup)
-- Proves: reverse edge lookup through idx_mod_dependencies_required_mod.
SELECT DISTINCT m.name AS dependent_mod, d.dep_type
FROM   mod_dependencies d
JOIN   mods target         ON target.mod_id = d.required_mod_id
JOIN   mod_versions v      ON v.version_id = d.dependent_version_id
JOIN   mods m              ON m.mod_id = v.mod_id
WHERE  target.name = 'SMAPI - Stardew Modding API' AND m.mod_id <> target.mod_id
ORDER  BY m.name, d.dep_type;

-- 3.6  Detect potential self-dependency cycles (recursive CTE guard)
-- Proves: the CYCLE clause (PostgreSQL 14+) stops a walk at a mod already on its path, so
-- the recursion ends; a row whose to_mod equals start_mod is a cycle through that mod.
-- The seed has no required-dependency cycle, so one is planted (SMAPI requires Automate,
-- while Automate requires SMAPI) inside BEGIN ... ROLLBACK; the query then finds both mods.
BEGIN;
INSERT INTO mod_dependencies (dependent_version_id, required_mod_id, dep_type)
SELECT v.version_id, a.mod_id, 'required'
FROM   mods s
JOIN   mod_versions v ON v.mod_id = s.mod_id AND v.is_primary
JOIN   mods a         ON a.name = 'Automate'
WHERE  s.name = 'SMAPI - Stardew Modding API';

WITH RECURSIVE edge AS (
    SELECT DISTINCT v.mod_id AS from_mod, d.required_mod_id AS to_mod
    FROM   mod_dependencies d
    JOIN   mod_versions v ON v.version_id = d.dependent_version_id
    WHERE  d.dep_type = 'required' AND v.is_primary AND v.mod_id <> d.required_mod_id
),
walk AS (
    SELECT from_mod AS start_mod, to_mod FROM edge
    UNION ALL
    SELECT w.start_mod, e.to_mod
    FROM   walk w
    JOIN   edge e ON e.from_mod = w.to_mod
) CYCLE to_mod SET is_cycle USING path
SELECT m.name AS mod_in_cycle, count(*) AS cyclic_paths
FROM   walk w
JOIN   mods m ON m.mod_id = w.start_mod
WHERE  w.to_mod = w.start_mod                  -- the walk came back to where it started
GROUP  BY m.name
ORDER  BY m.name;
ROLLBACK;

-- 3.7  List mods with conflicting dependencies (dep_type = 'conflicts')
-- Proves: declared conflicts, one row per (mod, conflicting mod) pair.
SELECT DISTINCT m.name AS mod_name, cm.name AS conflicts_with
FROM   mod_dependencies d
JOIN   mod_versions v ON v.version_id = d.dependent_version_id
JOIN   mods m         ON m.mod_id = v.mod_id
JOIN   mods cm        ON cm.mod_id = d.required_mod_id
WHERE  d.dep_type = 'conflicts'
ORDER  BY m.name, cm.name;


-- =============================================================================
-- SECTION 4 -- COMPATIBILITY MATRIX QUERIES
-- =============================================================================

-- 4.1  Find all compatibility records for a specific mod version
-- Proves: a version can sit on either side of a canonical pair, so both columns are checked.
SELECT other_m.name AS other_mod, other_v.semver, c.status
FROM   compatibility_matrix c
JOIN   mod_versions v ON v.version_id IN (c.version_a_id, c.version_b_id)
JOIN   mods m         ON m.mod_id = v.mod_id AND v.is_primary
JOIN   mod_versions other_v ON other_v.version_id = CASE WHEN c.version_a_id = v.version_id
                                                         THEN c.version_b_id ELSE c.version_a_id END
JOIN   mods other_m   ON other_m.mod_id = other_v.mod_id
WHERE  m.name = 'SkyUI'
ORDER  BY other_m.name;

-- 4.2  Count compatibility records grouped by status
-- Proves: GROUP BY on compat_status_enum.
SELECT status, count(*) AS pairs
FROM   compatibility_matrix
GROUP  BY status
ORDER  BY status;

-- 4.3  List all incompatible pairs for a given game
--        (join through mod_versions -> mods -> games)
-- Proves: two-sided join of the matrix to mods, filtered by game.
SELECT ma.name AS mod_a, mb.name AS mod_b, c.conflict_detail ->> 'reason' AS reason
FROM   compatibility_matrix c
JOIN   mod_versions va ON va.version_id = c.version_a_id
JOIN   mods ma         ON ma.mod_id = va.mod_id
JOIN   mod_versions vb ON vb.version_id = c.version_b_id
JOIN   mods mb         ON mb.mod_id = vb.mod_id
JOIN   games g         ON g.game_id = ma.game_id
WHERE  g.domain = 'skyrimspecialedition' AND c.status = 'incompatible';

-- 4.4  Find pairs with conflict_detail JSONB containing a specific key
--        (JSONB operator: conflict_detail ? 'files')
-- Proves: the ? key-exists operator and jsonb_array_elements_text to unnest the file list.
-- ASSUMPTION: the seed stores affected files under the key "files", not "affected_files".
SELECT c.status, f.file
FROM   compatibility_matrix c,
       jsonb_array_elements_text(c.conflict_detail -> 'files') AS f(file)
WHERE  c.conflict_detail ? 'files'
ORDER  BY c.status, f.file;

-- 4.5  Find unverified compatibility records (verified_by IS NULL)
-- Proves: IS NULL filter (every 'unknown' row in the seed is unverified).
SELECT ma.name AS mod_a, mb.name AS mod_b, c.status
FROM   compatibility_matrix c
JOIN   mod_versions va ON va.version_id = c.version_a_id
JOIN   mods ma         ON ma.mod_id = va.mod_id
JOIN   mod_versions vb ON vb.version_id = c.version_b_id
JOIN   mods mb         ON mb.mod_id = vb.mod_id
WHERE  c.verified_by IS NULL
ORDER  BY ma.name;

-- 4.6  List compatibility records verified by a given curator
-- Proves: join through verified_by to users.
SELECT ma.name AS mod_a, mb.name AS mod_b, c.status, c.updated_at
FROM   compatibility_matrix c
JOIN   users u         ON u.user_id = c.verified_by
JOIN   mod_versions va ON va.version_id = c.version_a_id
JOIN   mods ma         ON ma.mod_id = va.mod_id
JOIN   mod_versions vb ON vb.version_id = c.version_b_id
JOIN   mods mb         ON mb.mod_id = vb.mod_id
WHERE  u.username = 'curator'
ORDER  BY c.status, ma.name
LIMIT  10;


-- =============================================================================
-- SECTION 5 -- LOADOUT QUERIES
-- =============================================================================

-- 5.1  List all public loadouts with owner username and game name
-- Proves: three-table join with a boolean filter (5 of the 6 seed loadouts are public).
SELECT l.name AS loadout, u.username AS owner, g.name AS game
FROM   loadouts l
JOIN   users u ON u.user_id = l.user_id
JOIN   games g ON g.game_id = l.game_id
WHERE  l.is_public
ORDER  BY g.name, l.name;

-- 5.2  List all mod versions in a specific loadout ordered by position
-- Proves: load order is the position column.
SELECT x.position, m.name, v.semver, x.enabled
FROM   loadout_mods x
JOIN   loadouts l     ON l.loadout_id = x.loadout_id
JOIN   mod_versions v ON v.version_id = x.version_id
JOIN   mods m         ON m.mod_id = v.mod_id
WHERE  l.name = 'Broken Skyrim UI'
ORDER  BY x.position;

-- 5.3  Count mods in each loadout (COUNT + GROUP BY)
-- Proves: COUNT with FILTER separates enabled from all rows.
SELECT l.name, count(x.id) AS mods, count(x.id) FILTER (WHERE x.enabled) AS enabled
FROM   loadouts l
LEFT   JOIN loadout_mods x ON x.loadout_id = l.loadout_id
GROUP  BY l.loadout_id, l.name
ORDER  BY l.name;

-- 5.4  Find loadouts that contain a specific mod (any version)
-- Proves: EXISTS against a join, true whichever version of the mod is used.
SELECT l.name
FROM   loadouts l
WHERE  EXISTS (SELECT 1
               FROM   loadout_mods x
               JOIN   mod_versions v ON v.version_id = x.version_id
               JOIN   mods m         ON m.mod_id = v.mod_id
               WHERE  x.loadout_id = l.loadout_id AND m.name = 'Address Library for SKSE Plugins')
ORDER  BY l.name;

-- 5.5  Check a loadout for incompatible mod pairs
--        (cross-join loadout_mods x compatibility_matrix)
-- Proves: a self-join of the loadout's rows matched against the canonical matrix pair (a < b).
SELECT ma.name AS mod_a, mb.name AS mod_b, c.status
FROM   loadouts l
JOIN   loadout_mods xa ON xa.loadout_id = l.loadout_id
JOIN   loadout_mods xb ON xb.loadout_id = l.loadout_id AND xa.version_id < xb.version_id
JOIN   compatibility_matrix c ON c.version_a_id = xa.version_id AND c.version_b_id = xb.version_id
JOIN   mod_versions va ON va.version_id = xa.version_id
JOIN   mods ma         ON ma.mod_id = va.mod_id
JOIN   mod_versions vb ON vb.version_id = xb.version_id
JOIN   mods mb         ON mb.mod_id = vb.mod_id
WHERE  l.name = 'Broken Skyrim UI' AND c.status = 'incompatible';

-- 5.6  Clone/copy a loadout: INSERT INTO ... SELECT pattern
--        (shows how to duplicate a loadout for a new user)
-- Proves: a data-modifying CTE inserts the loadout and its rows in one statement; positions survive.
BEGIN;
WITH src AS (
    SELECT * FROM loadouts WHERE name = 'Broken Skyrim UI'
),
new_l AS (
    INSERT INTO loadouts (user_id, game_id, name, description, game_version)
    SELECT (SELECT user_id FROM users WHERE username = 'admin'),
           src.game_id, src.name || ' (copy)', src.description, src.game_version
    FROM   src
    RETURNING loadout_id
)
INSERT INTO loadout_mods (loadout_id, version_id, position, enabled)
SELECT new_l.loadout_id, x.version_id, x.position, x.enabled
FROM   new_l, src
JOIN   loadout_mods x ON x.loadout_id = src.loadout_id
ORDER  BY x.position;

SELECT l.name, u.username AS owner, x.position, m.name AS mod_name
FROM   loadouts l
JOIN   users u        ON u.user_id = l.user_id
JOIN   loadout_mods x ON x.loadout_id = l.loadout_id
JOIN   mod_versions v ON v.version_id = x.version_id
JOIN   mods m         ON m.mod_id = v.mod_id
WHERE  l.name = 'Broken Skyrim UI (copy)'
ORDER  BY x.position;
ROLLBACK;


-- =============================================================================
-- SECTION 6 -- ANALYTICS & REPORTING QUERIES
-- =============================================================================

-- 6.1  Monthly mod upload trend (DATE_TRUNC + COUNT + GROUP BY)
-- Proves: DATE_TRUNC buckets real Nexus upload dates by month (last 12 months with uploads).
SELECT date_trunc('month', uploaded_at)::date AS month, count(*) AS versions_uploaded
FROM   mod_versions
GROUP  BY 1
ORDER  BY 1 DESC
LIMIT  12;

-- 6.2  Top modders by mod count and average mod rating
--        (multi-level aggregation with CTE)
-- Proves: aggregate per mod in one CTE, then per author over that result.
WITH per_mod AS (
    SELECT coalesce(u.username, m.nexus_author) AS author, m.mod_id, avg(r.rating) AS mod_avg
    FROM   mods m
    LEFT   JOIN users u   ON u.user_id = m.author_id
    LEFT   JOIN reviews r ON r.mod_id = m.mod_id
    GROUP  BY 1, m.mod_id
)
SELECT author, count(*) AS mods, round(avg(mod_avg), 2) AS avg_rating
FROM   per_mod
GROUP  BY author
ORDER  BY mods DESC, avg_rating DESC NULLS LAST, author
LIMIT  10;

-- 6.3  Game with the most mods (subquery in FROM clause)
-- Proves: derived table in FROM, then a filter on its maximum.
SELECT g.name, t.mods
FROM  (SELECT game_id, count(*) AS mods FROM mods GROUP BY game_id) t
JOIN   games g ON g.game_id = t.game_id
WHERE  t.mods = (SELECT max(c) FROM (SELECT count(*) AS c FROM mods GROUP BY game_id) x)
ORDER  BY g.name;

-- 6.4  Download count leaderboard (uses mods.download_count)
-- Proves: DENSE_RANK over all games.
SELECT DENSE_RANK() OVER (ORDER BY m.download_count DESC) AS rank, m.name, g.name AS game, m.download_count
FROM   mods m
JOIN   games g ON g.game_id = m.game_id
ORDER  BY rank, m.name
LIMIT  10;

-- 6.5  Window function: running total of mods uploaded per game
--        (SUM OVER (PARTITION BY game_id ORDER BY created_at))
-- Proves: a running SUM per partition. Uses each mod's first upload date (see SEED NOTES).
WITH first_upload AS (
    SELECT m.game_id, m.name, min(v.uploaded_at) AS first_uploaded
    FROM   mods m
    JOIN   mod_versions v ON v.mod_id = m.mod_id
    GROUP  BY m.game_id, m.mod_id, m.name
)
SELECT g.name AS game, f.name AS mod_name, f.first_uploaded::date,
       count(*) OVER (PARTITION BY f.game_id ORDER BY f.first_uploaded, f.name) AS running_total
FROM   first_upload f
JOIN   games g ON g.game_id = f.game_id
ORDER  BY g.name, f.first_uploaded, f.name;

-- 6.6  Window function: percentile rank of mods by average rating
--        (PERCENT_RANK OVER (...))
-- Proves: PERCENT_RANK gives 0 to 1 within the reviewed mods of each game.
SELECT g.name AS game, m.name, m.rating_avg,
       round(PERCENT_RANK() OVER (PARTITION BY m.game_id ORDER BY m.rating_avg)::numeric, 2) AS pct_rank
FROM   mods m
JOIN   games g ON g.game_id = m.game_id
WHERE  m.rating_count > 0
ORDER  BY g.name, pct_rank DESC, m.name;

-- 6.7  Tag co-occurrence matrix: which two tags appear together most often
--        (self-join on mod_tags)
-- Proves: self-join with a.tag_id < b.tag_id counts each unordered pair once.
SELECT ta.slug AS tag_a, tb.slug AS tag_b, count(*) AS mods_with_both
FROM   mod_tags a
JOIN   mod_tags b ON b.mod_id = a.mod_id AND a.tag_id < b.tag_id
JOIN   tags ta    ON ta.tag_id = a.tag_id
JOIN   tags tb    ON tb.tag_id = b.tag_id
GROUP  BY ta.slug, tb.slug
ORDER  BY mods_with_both DESC, tag_a, tag_b
LIMIT  10;

-- 6.8  Compatibility coverage: percentage of version pairs with known status
-- Proves: pair count n(n-1)/2 from a self-join versus matrix rows with a definite status.
WITH prim AS (
    SELECT v.version_id, m.game_id
    FROM   mod_versions v
    JOIN   mods m ON m.mod_id = v.mod_id
    WHERE  v.is_primary
),
pairs AS (
    SELECT a.game_id, a.version_id AS va, b.version_id AS vb
    FROM   prim a
    JOIN   prim b ON b.game_id = a.game_id AND a.version_id < b.version_id
)
SELECT g.name AS game,
       count(*) AS primary_pairs,
       count(c.compat_id) FILTER (WHERE c.status <> 'unknown') AS known,
       round(100.0 * count(c.compat_id) FILTER (WHERE c.status <> 'unknown') / count(*), 1) AS pct_known
FROM   pairs p
JOIN   games g ON g.game_id = p.game_id
LEFT   JOIN compatibility_matrix c ON c.version_a_id = p.va AND c.version_b_id = p.vb
GROUP  BY g.name
ORDER  BY g.name;


-- =============================================================================
-- SECTION 7 -- ADVANCED / DEMONSTRATION QUERIES
-- =============================================================================

-- 7.1  Pivot-style report: compatibility status counts per game
--        (FILTER aggregate or CASE-in-aggregate technique)
-- Proves: FILTER turns status rows into columns.
SELECT g.name AS game,
       count(*) FILTER (WHERE c.status = 'compatible')   AS compatible,
       count(*) FILTER (WHERE c.status = 'incompatible') AS incompatible,
       count(*) FILTER (WHERE c.status = 'partial')      AS partial,
       count(*) FILTER (WHERE c.status = 'unknown')      AS unknown
FROM   compatibility_matrix c
JOIN   mod_versions v ON v.version_id = c.version_a_id
JOIN   mods m         ON m.mod_id = v.mod_id
JOIN   games g        ON g.game_id = m.game_id
GROUP  BY g.name
ORDER  BY g.name;

-- 7.2  LATERAL join: for each mod, get its latest version inline
-- Proves: LATERAL runs a per-row "top 1" subquery; latest upload may differ from the primary.
SELECT m.name, latest.semver AS latest_semver, latest.uploaded_at::date, latest.is_primary
FROM   mods m
CROSS  JOIN LATERAL (
    SELECT v.semver, v.uploaded_at, v.is_primary
    FROM   mod_versions v
    WHERE  v.mod_id = m.mod_id
    ORDER  BY v.uploaded_at DESC
    LIMIT  1
) latest
ORDER  BY m.name
LIMIT  15;

-- 7.3  DISTINCT ON: one row per mod showing its best review
-- Proves: DISTINCT ON keeps the first row per mod under the ORDER BY.
SELECT DISTINCT ON (m.mod_id) m.name, r.rating, u.username AS reviewer, left(r.body, 60) AS excerpt
FROM   reviews r
JOIN   mods m  ON m.mod_id = r.mod_id
JOIN   users u ON u.user_id = r.user_id
ORDER  BY m.mod_id, r.rating DESC, r.created_at DESC
LIMIT  15;

-- 7.4  Array aggregation: list tags per mod as a PostgreSQL array
--        (ARRAY_AGG + GROUP BY)
-- Proves: ARRAY_AGG with ORDER BY inside the aggregate.
SELECT m.name, array_agg(t.slug ORDER BY t.slug) AS tags
FROM   mods m
JOIN   mod_tags mt ON mt.mod_id = m.mod_id
JOIN   tags t      ON t.tag_id = mt.tag_id
GROUP  BY m.mod_id, m.name
ORDER  BY m.name
LIMIT  15;

-- 7.5  JSON aggregation: produce a JSON loadout manifest
--        (JSON_AGG + ROW_TO_JSON)
-- Proves: row_to_json per mod, json_agg ordered by position; same shape as fn_export_loadout.
SELECT json_build_object(
           'format', 'modvault-loadout/1',
           'name', l.name,
           'game_domain', g.domain,
           'game_version', l.game_version,
           'mods', (SELECT json_agg(row_to_json(e) ORDER BY e.position)
                    FROM (SELECT m.nexus_mod_id, v.semver, x.position, x.enabled
                          FROM   loadout_mods x
                          JOIN   mod_versions v ON v.version_id = x.version_id
                          JOIN   mods m         ON m.mod_id = v.mod_id
                          WHERE  x.loadout_id = l.loadout_id) e)) AS manifest
FROM   loadouts l
JOIN   games g ON g.game_id = l.game_id
WHERE  l.name = 'Healthy Skyrim Essentials';

-- 7.6  EXISTS subquery: find games that have at least one public loadout
-- Proves: EXISTS stops at the first match per game.
SELECT g.name
FROM   games g
WHERE  EXISTS (SELECT 1 FROM loadouts l WHERE l.game_id = g.game_id AND l.is_public)
ORDER  BY g.name;

-- 7.7  Multi-row UPDATE with JOIN (UPDATE ... FROM ...)
-- Proves: UPDATE ... FROM joins to the leaderboard to feature each game's top-3 mods.
BEGIN;
UPDATE mods m
SET    is_featured = TRUE
FROM   mv_game_leaderboard lb
WHERE  lb.mod_id = m.mod_id AND lb.rank_in_game <= 3 AND NOT m.is_featured
RETURNING m.name, m.is_featured;
ROLLBACK;

-- 7.8  Upsert pattern: INSERT INTO ... ON CONFLICT (col) DO UPDATE SET ...
-- Proves: ON CONFLICT on the slug key updates the existing tag and inserts the new one.
BEGIN;
INSERT INTO tags (name, slug) VALUES
    ('User Interface (UI)', 'user-interface'),
    ('Performance',         'performance')
ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name
RETURNING slug, name, (xmax::text <> '0') AS was_update;
ROLLBACK;
