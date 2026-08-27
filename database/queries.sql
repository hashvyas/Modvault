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
--   Queries are grouped by feature area.  Each query is preceded by a
--   comment describing its business purpose and the SQL features it
--   demonstrates.
--
-- DEPENDENCY
--   Requires schema.sql (and seed.sql for meaningful results).
--
-- HOW TO RUN
--   psql -d modvault -f database/schema.sql
--   psql -d modvault -f database/seed.sql
--   psql -d modvault -f database/queries.sql
-- =============================================================================


-- =============================================================================
-- SECTION 1 -- USER QUERIES
-- =============================================================================

-- 1.1  List all users sorted by registration date (basic SELECT + ORDER BY)
-- 1.2  Find a user by username (equality filter)
-- 1.3  Count users per role (aggregate: COUNT + GROUP BY)
-- 1.4  Find users who have never written a review (NOT EXISTS subquery)
-- 1.5  Find the most recently registered user per role (window: RANK OVER PARTITION BY)

-- (Query SQL will be added here)


-- =============================================================================
-- SECTION 2 -- MOD BROWSE & SEARCH QUERIES
-- =============================================================================

-- 2.1  List all mods for a given game with author username (INNER JOIN)
-- 2.2  List mods with their average rating and review count
--        (LEFT JOIN + AVG + COUNT + GROUP BY)
-- 2.3  List mods filtered by tag name (join through mod_tags)
-- 2.4  Top-10 highest-rated mods for a game (ORDER BY + LIMIT)
-- 2.5  Full-text search on mod name and summary using tsvector/tsquery
-- 2.6  Find featured mods (uses is_featured column added in ddl_demo.sql)
-- 2.7  List mods with no reviews yet (LEFT JOIN ... WHERE IS NULL)
-- 2.8  Mod catalogue with pagination: page N, M results per page
--        (OFFSET / LIMIT pattern)

-- (Query SQL will be added here)


-- =============================================================================
-- SECTION 3 -- VERSION & DEPENDENCY QUERIES
-- =============================================================================

-- 3.1  List all versions of a specific mod ordered by upload date
-- 3.2  Find the primary version of every mod (is_primary = TRUE)
-- 3.3  List direct dependencies of a mod version (dep_type = required)
-- 3.4  Recursive CTE: full dependency tree for a mod version
--        (WITH RECURSIVE ... demonstrates graph traversal)
-- 3.5  Find all mods that depend on a specific mod (reverse lookup)
-- 3.6  Detect potential self-dependency cycles (recursive CTE guard)
-- 3.7  List mods with conflicting dependencies (dep_type = 'conflicts')

-- (Query SQL will be added here)


-- =============================================================================
-- SECTION 4 -- COMPATIBILITY MATRIX QUERIES
-- =============================================================================

-- 4.1  Find all compatibility records for a specific mod version
-- 4.2  Count compatibility records grouped by status
-- 4.3  List all incompatible pairs for a given game
--        (join through mod_versions -> mods -> games)
-- 4.4  Find pairs with conflict_detail JSONB containing a specific key
--        (JSONB operator: conflict_detail ? 'affected_files')
-- 4.5  Find unverified compatibility records (verified_by IS NULL)
-- 4.6  List compatibility records verified by a given curator

-- (Query SQL will be added here)


-- =============================================================================
-- SECTION 5 -- LOADOUT QUERIES
-- =============================================================================

-- 5.1  List all public loadouts with owner username and game name
-- 5.2  List all mod versions in a specific loadout ordered by position
-- 5.3  Count mods in each loadout (COUNT + GROUP BY)
-- 5.4  Find loadouts that contain a specific mod (any version)
-- 5.5  Check a loadout for incompatible mod pairs
--        (cross-join loadout_mods x compatibility_matrix)
-- 5.6  Clone/copy a loadout: INSERT INTO ... SELECT pattern
--        (shows how to duplicate a loadout for a new user)

-- (Query SQL will be added here)


-- =============================================================================
-- SECTION 6 -- ANALYTICS & REPORTING QUERIES
-- =============================================================================

-- 6.1  Monthly mod upload trend (DATE_TRUNC + COUNT + GROUP BY)
-- 6.2  Top modders by mod count and average mod rating
--        (multi-level aggregation with CTE)
-- 6.3  Game with the most mods (subquery in FROM clause)
-- 6.4  Download count leaderboard (uses download_count added in ddl_demo.sql)
-- 6.5  Window function: running total of mods uploaded per game
--        (SUM OVER (PARTITION BY game_id ORDER BY created_at))
-- 6.6  Window function: percentile rank of mods by average rating
--        (PERCENT_RANK OVER (...))
-- 6.7  Tag co-occurrence matrix: which two tags appear together most often
--        (self-join on mod_tags)
-- 6.8  Compatibility coverage: percentage of version pairs with known status

-- (Query SQL will be added here)


-- =============================================================================
-- SECTION 7 -- ADVANCED / DEMONSTRATION QUERIES
-- =============================================================================

-- 7.1  Pivot-style report: compatibility status counts per game
--        (FILTER aggregate or CASE-in-aggregate technique)
-- 7.2  LATERAL join: for each mod, get its latest version inline
-- 7.3  DISTINCT ON: one row per mod showing its best review
-- 7.4  Array aggregation: list tags per mod as a PostgreSQL array
--        (ARRAY_AGG + GROUP BY)
-- 7.5  JSON aggregation: produce a JSON loadout manifest
--        (JSON_AGG + ROW_TO_JSON)
-- 7.6  EXISTS subquery: find games that have at least one public loadout
-- 7.7  Multi-row UPDATE with JOIN (UPDATE ... FROM ...)
-- 7.8  Upsert pattern: INSERT INTO ... ON CONFLICT (col) DO UPDATE SET ...

-- (Query SQL will be added here)
