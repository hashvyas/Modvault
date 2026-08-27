-- =============================================================================
-- ModVault: A Mod Repository and Compatibility Intelligence System
-- View Definitions  --  views.sql
--
-- PURPOSE
--   This file creates all PostgreSQL VIEWs and MATERIALIZED VIEWs for
--   ModVault.  Views are required by the project rubric and serve two
--   purposes:
--     1. Simplify complex joins for application queries.
--     2. Expose pre-aggregated / pre-joined "virtual tables" for reporting
--        and API layers without duplicating join logic.
--
--   Demonstrated SQL features:
--     * CREATE VIEW (simple updatable views and read-only join views)
--     * CREATE MATERIALIZED VIEW ... WITH DATA  (cached aggregates)
--     * REFRESH MATERIALIZED VIEW  (manual refresh command shown in comments)
--     * CREATE OR REPLACE VIEW  (safe idempotent re-creation)
--     * Aggregate views (COUNT, AVG, COALESCE, ROUND)
--     * CTEs inside view definitions
--     * Window functions inside view definitions
--     * JSONB column exposure in views
--
-- NAMING CONVENTION
--   v_<feature>    -- regular view
--   mv_<feature>   -- materialized view
--
-- DEPENDENCY
--   Run AFTER schema.sql (and ddl_demo.sql for the extra columns).
--
-- HOW TO RUN
--   psql -d modvault -f database/schema.sql
--   psql -d modvault -f database/ddl_demo.sql   -- (adds is_featured, download_count, etc.)
--   psql -d modvault -f database/views.sql
-- =============================================================================


-- =============================================================================
-- SECTION 1 -- USER VIEWS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- v_user_profiles
-- Public-safe view of user data (excludes password_hash).
-- Joins: users only.
-- Columns: user_id, username, role, created_at
-- Use case: safe user lookup for API responses.
-- -----------------------------------------------------------------------------

-- (CREATE OR REPLACE VIEW v_user_profiles AS ... will be added here)


-- =============================================================================
-- SECTION 2 -- MOD CATALOGUE VIEWS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- v_mod_catalogue
-- Full mod listing with author username, game name, tag list, and review stats.
-- Joins: mods -> users, mods -> games, mods -> mod_tags -> tags, mods -> reviews
-- Columns: mod_id, name, summary, category, author_username, game_name,
--          tags (array), avg_rating, review_count, download_count, created_at
-- Use case: primary browseable mod list.
-- -----------------------------------------------------------------------------

-- (CREATE OR REPLACE VIEW v_mod_catalogue AS ... will be added here)


-- -----------------------------------------------------------------------------
-- v_mod_primary_versions
-- Returns only the primary (current) version for each mod.
-- Joins: mods -> mod_versions (WHERE is_primary = TRUE)
-- Columns: mod_id, mod_name, version_id, semver, uploaded_at
-- Use case: "current version" lookups without requiring callers to filter.
-- -----------------------------------------------------------------------------

-- (CREATE OR REPLACE VIEW v_mod_primary_versions AS ... will be added here)


-- =============================================================================
-- SECTION 3 -- DEPENDENCY VIEWS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- v_mod_dependency_summary
-- Flat view of dependency edges with human-readable mod names.
-- Joins: mod_dependencies -> mod_versions -> mods (dependent side),
--        mod_dependencies -> mods (required side)
-- Columns: dep_id, dependent_mod_name, dependent_semver,
--          required_mod_name, dep_type, version_constraint, source
-- Use case: dependency browser and audit reports.
-- -----------------------------------------------------------------------------

-- (CREATE OR REPLACE VIEW v_mod_dependency_summary AS ... will be added here)


-- =============================================================================
-- SECTION 4 -- COMPATIBILITY VIEWS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- v_compatibility_report
-- Human-readable compatibility report joining version pairs to mod names.
-- Joins: compatibility_matrix -> mod_versions (a + b) -> mods (a + b)
--        -> users (verified_by)
-- Columns: compat_id, mod_a_name, version_a_semver, mod_b_name,
--          version_b_semver, status, conflict_detail, verified_by_username,
--          updated_at
-- Use case: compatibility browser and curator review queue.
-- -----------------------------------------------------------------------------

-- (CREATE OR REPLACE VIEW v_compatibility_report AS ... will be added here)


-- -----------------------------------------------------------------------------
-- v_incompatible_pairs
-- Filters v_compatibility_report to incompatible entries only.
-- Use case: conflict warning dashboard.
-- -----------------------------------------------------------------------------

-- (CREATE OR REPLACE VIEW v_incompatible_pairs AS ... will be added here)


-- =============================================================================
-- SECTION 5 -- LOADOUT VIEWS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- v_loadout_summary
-- Loadout metadata with owner username, game name, and mod count.
-- Joins: loadouts -> users, loadouts -> games,
--        loadouts -> loadout_mods (COUNT)
-- Columns: loadout_id, name, is_public, owner_username, game_name,
--          mod_count, created_at
-- Use case: loadout browser and user dashboard.
-- -----------------------------------------------------------------------------

-- (CREATE OR REPLACE VIEW v_loadout_summary AS ... will be added here)


-- -----------------------------------------------------------------------------
-- v_loadout_mods_detail
-- Full detail of every mod version in every loadout, ordered by position.
-- Joins: loadout_mods -> loadouts -> mod_versions -> mods -> users (author)
-- Columns: loadout_id, loadout_name, position, enabled, mod_name,
--          author_username, semver, version_id
-- Use case: loadout detail page and export manifest.
-- -----------------------------------------------------------------------------

-- (CREATE OR REPLACE VIEW v_loadout_mods_detail AS ... will be added here)


-- =============================================================================
-- SECTION 6 -- ANALYTICS MATERIALIZED VIEWS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- mv_mod_ratings
-- Materialized aggregate of ratings per mod.
-- Refresh strategy: manually (REFRESH MATERIALIZED VIEW mv_mod_ratings)
--   or via a trigger on reviews (see triggers.sql).
-- Columns: mod_id, avg_rating (NUMERIC 3,2), review_count, min_rating,
--          max_rating, last_refreshed
-- Use case: leaderboards, search ranking, featured-mod selection.
-- NOTE: REFRESH MATERIALIZED VIEW mv_mod_ratings;
-- -----------------------------------------------------------------------------

-- (CREATE MATERIALIZED VIEW mv_mod_ratings AS ... will be added here)


-- -----------------------------------------------------------------------------
-- mv_game_mod_stats
-- Per-game statistics: mod count, version count, average rating, total downloads.
-- Refresh strategy: manually after bulk imports.
-- Columns: game_id, game_name, mod_count, version_count, avg_rating,
--          total_downloads, last_refreshed
-- Use case: game landing pages and platform-level analytics.
-- NOTE: REFRESH MATERIALIZED VIEW mv_game_mod_stats;
-- -----------------------------------------------------------------------------

-- (CREATE MATERIALIZED VIEW mv_game_mod_stats AS ... will be added here)


-- -----------------------------------------------------------------------------
-- mv_tag_popularity
-- Tag usage counts across all mods, ranked by frequency.
-- Columns: tag_id, tag_name, slug, mod_count, rank
-- Use case: tag cloud, trending tags sidebar.
-- NOTE: REFRESH MATERIALIZED VIEW mv_tag_popularity;
-- -----------------------------------------------------------------------------

-- (CREATE MATERIALIZED VIEW mv_tag_popularity AS ... will be added here)
