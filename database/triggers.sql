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
--     * BEFORE INSERT / UPDATE row-level triggers that rewrite NEW
--     * BEFORE UPDATE OF <column> triggers
--     * AFTER INSERT / UPDATE / DELETE row-level triggers
--     * Triggers that enforce data-integrity rules (pair canonicalisation,
--       single primary version, same-game loadouts, append-only audit log)
--     * Triggers that maintain denormalised / cached data (rating rollup)
--     * One generic trigger function reused across tables via TG_ARGV
--
-- DEPENDENCY
--   Included by database/run_all.sql, after functions.sql.
--
-- HOW TO RUN
--   Do not run this file alone. It is included by database/run_all.sql.
--   Rebuild everything with:  python scripts/db_reset.py
-- =============================================================================

SET client_encoding = 'UTF8';


-- =============================================================================
-- SECTION 1 -- COMPATIBILITY MATRIX: PAIR CANONICALISATION
--
-- Swaps version_a_id / version_b_id when A > B, so (A, B) and (B, A) are the
-- same row. A CHECK constraint could only reject the row, not fix it.
-- =============================================================================

CREATE TRIGGER trg_compat_canonicalise_pair
    BEFORE INSERT OR UPDATE ON compatibility_matrix
    FOR EACH ROW EXECUTE FUNCTION fn_compat_canonicalise_pair();


-- =============================================================================
-- SECTION 2 -- MOD VERSIONS: SINGLE PRIMARY VERSION
--
-- When a version becomes primary, the other versions of the mod are demoted
-- first. uq_mod_versions_one_primary (indexes.sql) is the hard backstop.
-- =============================================================================

CREATE TRIGGER trg_mod_version_single_primary
    BEFORE INSERT OR UPDATE OF is_primary ON mod_versions
    FOR EACH ROW EXECUTE FUNCTION fn_mod_version_single_primary();


-- =============================================================================
-- SECTION 3 -- UPDATED_AT TIMESTAMP MAINTENANCE
--
-- One generic function, fn_set_updated_at, on every table with updated_at.
-- =============================================================================

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_mods_updated_at
    BEFORE UPDATE ON mods
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_loadouts_updated_at
    BEFORE UPDATE ON loadouts
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_compatibility_matrix_updated_at
    BEFORE UPDATE ON compatibility_matrix
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- =============================================================================
-- SECTION 4 -- LOADOUT MODS: AUTO POSITION AND GAME CHECK
--
-- trg_loadout_mods_position:   position 0 on insert means "append at the end".
-- trg_loadout_mods_game_check: raises GAME_MISMATCH when the version's mod is
--                              for a different game than the loadout.
-- BEFORE triggers on one event fire in name order: game check, then position.
-- =============================================================================

CREATE TRIGGER trg_loadout_mods_position
    BEFORE INSERT ON loadout_mods
    FOR EACH ROW EXECUTE FUNCTION fn_loadout_mods_auto_position();

CREATE TRIGGER trg_loadout_mods_game_check
    BEFORE INSERT OR UPDATE ON loadout_mods
    FOR EACH ROW EXECUTE FUNCTION fn_loadout_mods_game_check();


-- =============================================================================
-- SECTION 5 -- REVIEWS: RATING ROLLUP
--
-- Keeps mods.rating_avg and mods.rating_count in step with reviews, for the
-- affected mods only. Replaces the old plan of refreshing a ratings
-- materialized view on every review.
-- =============================================================================

CREATE TRIGGER trg_reviews_rating_rollup
    AFTER INSERT OR UPDATE OR DELETE ON reviews
    FOR EACH ROW EXECUTE FUNCTION fn_reviews_rating_rollup();


-- =============================================================================
-- SECTION 6 -- AUDIT LOG
--
-- fn_audit_log(<primary key column>) writes one audit_log row per changed row.
-- trg_audit_log_immutable makes audit_log append-only.
-- =============================================================================

CREATE TRIGGER trg_audit_users
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('user_id');

CREATE TRIGGER trg_audit_mods
    AFTER INSERT OR UPDATE OR DELETE ON mods
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('mod_id');

CREATE TRIGGER trg_audit_mod_versions
    AFTER INSERT OR UPDATE OR DELETE ON mod_versions
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('version_id');

CREATE TRIGGER trg_audit_mod_dependencies
    AFTER INSERT OR UPDATE OR DELETE ON mod_dependencies
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('dep_id');

CREATE TRIGGER trg_audit_compatibility_matrix
    AFTER INSERT OR UPDATE OR DELETE ON compatibility_matrix
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('compat_id');

CREATE TRIGGER trg_audit_loadouts
    AFTER INSERT OR UPDATE OR DELETE ON loadouts
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('loadout_id');

CREATE TRIGGER trg_audit_loadout_mods
    AFTER INSERT OR UPDATE OR DELETE ON loadout_mods
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('id');

CREATE TRIGGER trg_audit_reviews
    AFTER INSERT OR UPDATE OR DELETE ON reviews
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('review_id');

CREATE TRIGGER trg_audit_log_immutable
    BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log_immutable();
