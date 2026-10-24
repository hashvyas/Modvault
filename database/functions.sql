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
-- CONTRACT
--   Every function and procedure in sections 2 to 6 has a frozen signature
--   (person1.md / person2.md section 6). Phase 0 writes them as stubs; later
--   phases replace the bodies only. Names, arguments, return columns and
--   types never change.
--
--   Custom errors: RAISE EXCEPTION USING ERRCODE = 'P0001',
--                  MESSAGE = 'MODVAULT:<CODE>: <human text>'
--   Codes: NOT_FOUND, FORBIDDEN, GAME_MISMATCH, DUPLICATE, INVALID_MANIFEST,
--          INVALID_INPUT.
--   No procedure runs COMMIT or ROLLBACK. The caller owns the transaction.
--
-- DEPENDENCY
--   Run AFTER schema.sql and indexes.sql. triggers.sql and views.sql run after
--   this file.
--
-- HOW TO RUN
--   Do not run this file alone. It is included by database/run_all.sql.
--   Rebuild everything with:  python scripts/db_reset.py
-- =============================================================================

SET client_encoding = 'UTF8';


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
--   IF NEW.position = 0 AND rows exist for the loadout THEN
--     SELECT MAX(position) + 1 INTO NEW.position
--     FROM loadout_mods WHERE loadout_id = NEW.loadout_id;
--   END IF;
--   RETURN NEW;
-- -----------------------------------------------------------------------------

-- (CREATE OR REPLACE FUNCTION fn_loadout_mods_auto_position() will be added here)


-- -----------------------------------------------------------------------------
-- fn_audit_log()  RETURNS TRIGGER
--
-- Generic audit trigger function (SECURITY DEFINER). Inserts a row into
-- audit_log (schema.sql) for every INSERT / UPDATE / DELETE on the calling
-- table. Primary key column name comes from TG_ARGV[0]. Strips
-- password_hash, embedding, search_tsv. changed_by = fn_current_user_id().
-- -----------------------------------------------------------------------------

-- (CREATE OR REPLACE FUNCTION fn_audit_log() will be added here)


-- =============================================================================
-- SECTION 2 -- SESSION HELPERS
-- Every app transaction sets app.user_id and app.role with set_config(..., true).
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_current_user_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$ SELECT NULL::uuid $$;

CREATE OR REPLACE FUNCTION fn_current_role()
RETURNS text
LANGUAGE sql STABLE
AS $$ SELECT NULL::text $$;


-- =============================================================================
-- SECTION 3 -- AUTH (SECURITY DEFINER)
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_register_user(p_username text, p_email text, p_password text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION fn_authenticate(p_username text, p_password text)
RETURNS TABLE(user_id uuid, username text, role user_role_enum)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$ SELECT NULL::uuid, NULL::text, NULL::user_role_enum WHERE false $$;


-- =============================================================================
-- SECTION 4 -- SEARCH
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_search_mods_hybrid(p_query text, p_embedding vector(384), p_game_id uuid, p_limit int)
RETURNS TABLE(mod_id uuid, name text, summary text, game_id uuid,
              semantic_rank int, keyword_rank int, score float8)
LANGUAGE sql STABLE
AS $$
    SELECT NULL::uuid, NULL::text, NULL::text, NULL::uuid,
           NULL::int, NULL::int, NULL::float8
    WHERE false
$$;

CREATE OR REPLACE FUNCTION fn_search_mods_by_tag(VARIADIC p_tags text[])
RETURNS SETOF mods
LANGUAGE sql STABLE
AS $$ SELECT * FROM mods WHERE false $$;


-- =============================================================================
-- SECTION 5 -- MODS
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_get_mod_dependency_tree(p_version_id uuid)
RETURNS TABLE(version_id uuid, mod_id uuid, mod_name text, parent_version_id uuid,
              depth int, dep_type dep_type_enum, path uuid[])
LANGUAGE sql STABLE
AS $$
    SELECT NULL::uuid, NULL::uuid, NULL::text, NULL::uuid,
           NULL::int, NULL::dep_type_enum, NULL::uuid[]
    WHERE false
$$;

CREATE OR REPLACE FUNCTION fn_mod_stats(p_mod_id uuid)
RETURNS TABLE(version_count int, dependent_count int, conflict_count int,
              rating_avg numeric, rating_count int, download_count int)
LANGUAGE sql STABLE
AS $$
    SELECT NULL::int, NULL::int, NULL::int, NULL::numeric, NULL::int, NULL::int
    WHERE false
$$;

CREATE OR REPLACE FUNCTION fn_semver_satisfies(p_installed text, p_constraint text)
RETURNS boolean
LANGUAGE sql IMMUTABLE
AS $$ SELECT false $$;


-- =============================================================================
-- SECTION 6 -- LOADOUTS
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_check_loadout_compatibility(p_loadout_id uuid)
RETURNS TABLE(issue_type text, severity text, version_id uuid, other_version_id uuid,
              related_mod_id uuid, message text)
LANGUAGE sql STABLE
AS $$
    SELECT NULL::text, NULL::text, NULL::uuid, NULL::uuid, NULL::uuid, NULL::text
    WHERE false
$$;

CREATE OR REPLACE FUNCTION fn_loadout_health_score(p_loadout_id uuid)
RETURNS int
LANGUAGE sql STABLE
AS $$ SELECT 0 $$;

CREATE OR REPLACE FUNCTION fn_suggest_load_order(p_loadout_id uuid)
RETURNS TABLE(version_id uuid, suggested_position int)
LANGUAGE sql STABLE
AS $$ SELECT NULL::uuid, NULL::int WHERE false $$;

CREATE OR REPLACE FUNCTION fn_export_loadout(p_loadout_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE
AS $$ SELECT '{}'::jsonb $$;


-- =============================================================================
-- SECTION 7 -- STORED PROCEDURES
-- =============================================================================

CREATE OR REPLACE PROCEDURE pr_publish_mod(p_game_id uuid, p_name text, p_summary text, p_category text,
                                           p_semver text, p_tags text[], p_embedding vector(384),
                                           INOUT p_mod_id uuid DEFAULT NULL)
LANGUAGE plpgsql
AS $$
BEGIN
    NULL;
END;
$$;

CREATE OR REPLACE PROCEDURE pr_add_mod_to_loadout(p_loadout_id uuid, p_version_id uuid)
LANGUAGE plpgsql
AS $$
BEGIN
    NULL;
END;
$$;

CREATE OR REPLACE PROCEDURE pr_apply_load_order(p_loadout_id uuid)
LANGUAGE plpgsql
AS $$
BEGIN
    NULL;
END;
$$;

CREATE OR REPLACE PROCEDURE pr_import_loadout(p_manifest jsonb,
                                              INOUT p_loadout_id uuid DEFAULT NULL,
                                              INOUT p_skipped int DEFAULT NULL)
LANGUAGE plpgsql
AS $$
BEGIN
    NULL;
END;
$$;

CREATE OR REPLACE PROCEDURE pr_promote_version(p_version_id uuid)
LANGUAGE plpgsql
AS $$
BEGIN
    NULL;
END;
$$;

CREATE OR REPLACE PROCEDURE pr_upsert_compatibility(p_version_a uuid, p_version_b uuid,
                                                    p_status compat_status_enum, p_detail jsonb)
LANGUAGE plpgsql
AS $$
BEGIN
    NULL;
END;
$$;

-- Admin only.
CREATE OR REPLACE PROCEDURE pr_set_user_role(p_user_id uuid, p_role user_role_enum)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    NULL;
END;
$$;

-- Admin only.
CREATE OR REPLACE PROCEDURE pr_refresh_reports()
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    NULL;
END;
$$;
