-- =============================================================================
-- ModVault: A Mod Repository and Compatibility Intelligence System
-- Stored Functions & Procedures  --  functions.sql
--
-- PURPOSE
--   This file defines all PostgreSQL stored functions and procedures for
--   ModVault.  Stored functions are one of the four required advanced
--   database concepts.
--
--   All trigger support functions (those called by triggers.sql) are also
--   defined here so that triggers.sql only contains CREATE TRIGGER statements.
--
--   Demonstrated features:
--     * PL/pgSQL functions (CREATE OR REPLACE FUNCTION ... LANGUAGE plpgsql)
--     * SQL functions (CREATE OR REPLACE FUNCTION ... LANGUAGE sql)
--     * Trigger functions (RETURNS TRIGGER)
--     * Functions with IN / OUT / INOUT parameters
--     * Functions that return TABLE (set-returning functions / SRFs)
--     * Functions that return SETOF <type>
--     * RAISE NOTICE / RAISE EXCEPTION for error handling
--     * Looping and conditional logic in PL/pgSQL
--     * Recursive dependency resolution logic
--     * Stored PROCEDURE (CREATE PROCEDURE) for transaction-capable routines
--
-- DEPENDENCY
--   Run AFTER schema.sql (and ddl_demo.sql for the extra columns).
--   triggers.sql must be run AFTER this file.
--
-- HOW TO RUN
--   psql -d modvault -f database/schema.sql
--   psql -d modvault -f database/ddl_demo.sql
--   psql -d modvault -f database/functions.sql
--   psql -d modvault -f database/triggers.sql
-- =============================================================================


-- =============================================================================
-- SECTION 1 -- TRIGGER SUPPORT FUNCTIONS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_compat_canonicalise_pair()  RETURNS TRIGGER
--
-- Called by: trg_compat_canonicalise_pair (triggers.sql)
-- Logic:
--   IF NEW.version_a_id > NEW.version_b_id THEN
--     SWAP(NEW.version_a_id, NEW.version_b_id)
--   END IF;
--   RETURN NEW;
-- -----------------------------------------------------------------------------

-- (CREATE OR REPLACE FUNCTION fn_compat_canonicalise_pair() will be added here)


-- -----------------------------------------------------------------------------
-- fn_mod_version_single_primary()  RETURNS TRIGGER
--
-- Called by: trg_mod_version_single_primary (triggers.sql)
-- Logic:
--   IF NEW.is_primary = TRUE THEN
--     UPDATE mod_versions SET is_primary = FALSE
--     WHERE mod_id = NEW.mod_id AND version_id <> NEW.version_id;
--   END IF;
--   RETURN NEW;
-- -----------------------------------------------------------------------------

-- (CREATE OR REPLACE FUNCTION fn_mod_version_single_primary() will be added here)


-- -----------------------------------------------------------------------------
-- fn_refresh_mv_mod_ratings()  RETURNS TRIGGER
--
-- Called by: trg_refresh_mv_mod_ratings (triggers.sql)
-- Logic:
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_mod_ratings;
--   RETURN NULL;  -- statement-level trigger must return NULL
-- -----------------------------------------------------------------------------

-- (CREATE OR REPLACE FUNCTION fn_refresh_mv_mod_ratings() will be added here)


-- -----------------------------------------------------------------------------
-- fn_set_updated_at()  RETURNS TRIGGER
--
-- Generic updated_at setter.  Reused by any table with an updated_at column.
-- Logic:
--   NEW.updated_at := NOW();
--   RETURN NEW;
-- -----------------------------------------------------------------------------

-- (CREATE OR REPLACE FUNCTION fn_set_updated_at() will be added here)


-- -----------------------------------------------------------------------------
-- fn_loadout_mods_auto_position()  RETURNS TRIGGER
--
-- Called by: trg_loadout_mods_position (triggers.sql)
-- Logic:
--   IF NEW.position IS NULL OR NEW.position = 0 (and no rows yet) THEN
--     SELECT COALESCE(MAX(position), -1) + 1 INTO next_pos
--     FROM loadout_mods WHERE loadout_id = NEW.loadout_id;
--     NEW.position := next_pos;
--   END IF;
--   RETURN NEW;
-- -----------------------------------------------------------------------------

-- (CREATE OR REPLACE FUNCTION fn_loadout_mods_auto_position() will be added here)


-- -----------------------------------------------------------------------------
-- fn_audit_log()  RETURNS TRIGGER
--
-- Generic audit trigger function.  Inserts a row into audit_log for every
-- INSERT / UPDATE / DELETE on the calling table.
-- Logic:
--   INSERT INTO audit_log (table_name, operation, old_row, new_row, changed_at)
--   VALUES (TG_TABLE_NAME, TG_OP,
--           row_to_json(OLD)::JSONB,
--           row_to_json(NEW)::JSONB,
--           NOW());
--   RETURN COALESCE(NEW, OLD);
-- Note: The audit_log table definition is in Section 2 below.
-- -----------------------------------------------------------------------------

-- (CREATE OR REPLACE FUNCTION fn_audit_log() will be added here)


-- =============================================================================
-- SECTION 2 -- AUDIT LOG TABLE
--
-- Supporting table for fn_audit_log().
-- Defined here (not in schema.sql) because it is only needed when the audit
-- trigger functions are active.
--
-- Columns:
--   audit_id    UUID PRIMARY KEY DEFAULT gen_random_uuid()
--   table_name  TEXT NOT NULL
--   operation   TEXT NOT NULL  -- 'INSERT', 'UPDATE', 'DELETE'
--   old_row     JSONB          -- NULL for INSERT
--   new_row     JSONB          -- NULL for DELETE
--   changed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
-- =============================================================================

-- (CREATE TABLE audit_log ... will be added here)


-- =============================================================================
-- SECTION 3 -- UTILITY / BUSINESS LOGIC FUNCTIONS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_get_mod_dependency_tree(p_version_id UUID)
--   RETURNS TABLE (version_id UUID, mod_name TEXT, semver TEXT, depth INTEGER)
--
-- Recursively traverses the dependency graph for a given mod version and
-- returns all transitive dependencies as a flat table.
-- Uses a recursive CTE internally (WITH RECURSIVE).
-- Cycle guard: tracks visited version IDs to prevent infinite loops.
-- -----------------------------------------------------------------------------

-- (CREATE OR REPLACE FUNCTION fn_get_mod_dependency_tree() will be added here)


-- -----------------------------------------------------------------------------
-- fn_check_loadout_compatibility(p_loadout_id UUID)
--   RETURNS TABLE (
--     version_a_id UUID, mod_a_name TEXT,
--     version_b_id UUID, mod_b_name TEXT,
--     status compat_status_enum
--   )
--
-- Checks every pair of mod versions in a loadout against compatibility_matrix
-- and returns all pairs that are incompatible or of unknown status.
-- Useful for the "validate loadout" feature.
-- -----------------------------------------------------------------------------

-- (CREATE OR REPLACE FUNCTION fn_check_loadout_compatibility() will be added here)


-- -----------------------------------------------------------------------------
-- fn_mod_stats(p_mod_id UUID)
--   RETURNS TABLE (
--     mod_id UUID, mod_name TEXT, avg_rating NUMERIC,
--     review_count BIGINT, version_count BIGINT,
--     latest_semver TEXT, total_downloads BIGINT
--   )
--
-- Aggregates key statistics for a single mod.
-- Demonstrates: joins, aggregate functions, COALESCE, RETURNS TABLE.
-- -----------------------------------------------------------------------------

-- (CREATE OR REPLACE FUNCTION fn_mod_stats() will be added here)


-- -----------------------------------------------------------------------------
-- fn_search_mods_by_tag(VARIADIC p_tags TEXT[])
--   RETURNS SETOF mods
--
-- Returns mods that have ALL of the specified tags (conjunction search).
-- Uses VARIADIC parameters and array operations.
-- -----------------------------------------------------------------------------

-- (CREATE OR REPLACE FUNCTION fn_search_mods_by_tag() will be added here)


-- =============================================================================
-- SECTION 4 -- STORED PROCEDURES (transaction-capable routines)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- pr_add_mod_to_loadout(
--   p_loadout_id UUID,
--   p_version_id UUID,
--   p_position   INTEGER DEFAULT NULL
-- )
--
-- Inserts a mod version into a loadout at the specified position.
-- If p_position is NULL, auto-assigns the next sequential position.
-- Raises an exception if the version is already in the loadout.
-- Demonstrates: PROCEDURE, BEGIN/EXCEPTION block, CALL syntax.
-- -----------------------------------------------------------------------------

-- (CREATE OR REPLACE PROCEDURE pr_add_mod_to_loadout() will be added here)


-- -----------------------------------------------------------------------------
-- pr_promote_version(p_version_id UUID)
--
-- Promotes a specific version to is_primary = TRUE for its mod,
-- demoting any currently primary version.  Runs as a single atomic
-- operation inside the procedure body.
-- Demonstrates: PROCEDURE with multiple DML statements, atomicity.
-- -----------------------------------------------------------------------------

-- (CREATE OR REPLACE PROCEDURE pr_promote_version() will be added here)


-- -----------------------------------------------------------------------------
-- pr_upsert_compatibility(
--   p_version_a_id  UUID,
--   p_version_b_id  UUID,
--   p_status        compat_status_enum,
--   p_conflict_detail JSONB DEFAULT NULL,
--   p_verified_by   UUID  DEFAULT NULL
-- )
--
-- Inserts or updates a compatibility record between two versions.
-- Canonicalises the pair order (lower UUID as A) before the upsert.
-- Demonstrates: PROCEDURE, INSERT ... ON CONFLICT DO UPDATE, LEAST/GREATEST.
-- -----------------------------------------------------------------------------

-- (CREATE OR REPLACE PROCEDURE pr_upsert_compatibility() will be added here)
