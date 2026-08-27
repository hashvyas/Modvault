-- =============================================================================
-- ModVault: A Mod Repository and Compatibility Intelligence System
-- Trigger Definitions  --  triggers.sql
--
-- PURPOSE
--   This file defines all PostgreSQL triggers for ModVault.
--   Triggers are one of the four required advanced database concepts.
--
--   Trigger functions (PL/pgSQL) are defined in functions.sql.
--   This file only contains CREATE TRIGGER statements that attach those
--   functions to tables.
--
--   Demonstrated features:
--     * BEFORE INSERT / UPDATE / DELETE row-level triggers
--     * AFTER INSERT / UPDATE / DELETE row-level triggers
--     * AFTER INSERT / UPDATE / DELETE statement-level triggers
--     * INSTEAD OF triggers on views (for updatable view emulation)
--     * Triggers that enforce data-integrity rules (e.g. pair canonicalisation)
--     * Triggers that maintain denormalised / cached data automatically
--     * Triggers that log audit events
--
-- DEPENDENCY
--   Run AFTER schema.sql AND functions.sql (trigger functions must exist
--   before the trigger itself can be created).
--
-- HOW TO RUN
--   psql -d modvault -f database/schema.sql
--   psql -d modvault -f database/functions.sql
--   psql -d modvault -f database/triggers.sql
-- =============================================================================


-- =============================================================================
-- SECTION 1 -- COMPATIBILITY MATRIX: PAIR CANONICALISATION
--
-- Trigger: trg_compat_canonicalise_pair
-- Timing:  BEFORE INSERT OR UPDATE ON compatibility_matrix
-- Level:   ROW
-- Function: fn_compat_canonicalise_pair()  (defined in functions.sql)
--
-- Purpose:
--   Enforces the rule that version_a_id must always be the lexicographically
--   smaller UUID so that (A, B) and (B, A) are never stored as separate rows.
--   If an INSERT or UPDATE arrives with version_a_id > version_b_id, the
--   trigger swaps the two values before the row is written.
--
-- Why a trigger (not a CHECK constraint):
--   A CHECK constraint cannot swap column values; it can only reject the row.
--   The trigger silently normalises the pair, providing a better UX.
-- =============================================================================

-- (CREATE TRIGGER trg_compat_canonicalise_pair ... will be added here)


-- =============================================================================
-- SECTION 2 -- MOD VERSIONS: PRIMARY VERSION ENFORCEMENT
--
-- Trigger: trg_mod_version_single_primary
-- Timing:  BEFORE INSERT OR UPDATE ON mod_versions
-- Level:   ROW
-- Function: fn_mod_version_single_primary()  (defined in functions.sql)
--
-- Purpose:
--   Ensures that at most one version per mod has is_primary = TRUE.
--   When a new version is inserted / updated with is_primary = TRUE, the
--   trigger first sets is_primary = FALSE on all other versions of that mod,
--   then allows the new row to be written as TRUE.
--
-- Why a trigger (not a UNIQUE constraint):
--   A UNIQUE constraint on (mod_id) WHERE is_primary = TRUE would work for
--   simple cases, but the trigger additionally handles the UPDATE path
--   (demoting old primary) atomically in one operation.
-- =============================================================================

-- (CREATE TRIGGER trg_mod_version_single_primary ... will be added here)


-- =============================================================================
-- SECTION 3 -- REVIEWS: MATERIALIZED VIEW REFRESH
--
-- Trigger: trg_refresh_mv_mod_ratings
-- Timing:  AFTER INSERT OR UPDATE OR DELETE ON reviews
-- Level:   STATEMENT
-- Function: fn_refresh_mv_mod_ratings()  (defined in functions.sql)
--
-- Purpose:
--   Automatically refreshes the mv_mod_ratings materialized view whenever
--   a review is inserted, updated, or deleted.  This keeps the cached
--   aggregate ratings current without requiring manual REFRESH calls.
--
-- Trade-off note (documented for demonstration):
--   REFRESH MATERIALIZED VIEW acquires an exclusive lock.  For high-traffic
--   production deployments, REFRESH ... CONCURRENTLY is preferred but
--   requires a unique index on the materialized view.  The trigger will be
--   implemented with CONCURRENTLY and a suitable fallback.
-- =============================================================================

-- (CREATE TRIGGER trg_refresh_mv_mod_ratings ... will be added here)


-- =============================================================================
-- SECTION 4 -- MODS: UPDATED_AT TIMESTAMP MAINTENANCE
--
-- Trigger: trg_mods_updated_at
-- Timing:  BEFORE UPDATE ON mods
-- Level:   ROW
-- Function: fn_set_updated_at()  (generic function defined in functions.sql)
--
-- Purpose:
--   Automatically sets an updated_at column to NOW() on every UPDATE.
--   (The updated_at column is added to mods in ddl_demo.sql.)
--   The same generic function is reused for any other table that gains
--   an updated_at column.
-- =============================================================================

-- (CREATE TRIGGER trg_mods_updated_at ... will be added here)


-- =============================================================================
-- SECTION 5 -- LOADOUT MODS: POSITION GAP PREVENTION
--
-- Trigger: trg_loadout_mods_position
-- Timing:  BEFORE INSERT OR UPDATE ON loadout_mods
-- Level:   ROW
-- Function: fn_loadout_mods_auto_position()  (defined in functions.sql)
--
-- Purpose:
--   When a new mod is added to a loadout without an explicit position, the
--   trigger assigns it the next sequential position value (MAX(position)+1)
--   within that loadout automatically.  This prevents gaps in the ordering
--   and removes the burden from the application layer.
-- =============================================================================

-- (CREATE TRIGGER trg_loadout_mods_position ... will be added here)


-- =============================================================================
-- SECTION 6 -- AUDIT LOG TRIGGER (all sensitive tables)
--
-- Trigger: trg_audit_<table>
-- Timing:  AFTER INSERT OR UPDATE OR DELETE ON <table>
-- Level:   ROW
-- Function: fn_audit_log()  (defined in functions.sql)
--
-- Purpose:
--   Writes a row to an audit_log table (created in functions.sql or a
--   separate migration) for every INSERT, UPDATE, or DELETE on sensitive
--   tables: users, mods, compatibility_matrix.
--   The audit log captures: table_name, operation, old_row (JSONB),
--   new_row (JSONB), changed_at (TIMESTAMPTZ), changed_by (current_user).
--
-- Tables to audit:
--   users, mods, compatibility_matrix
-- =============================================================================

-- (CREATE TRIGGER trg_audit_users ...)
-- (CREATE TRIGGER trg_audit_mods ...)
-- (CREATE TRIGGER trg_audit_compat ...)
-- (Trigger statements will be added here)
