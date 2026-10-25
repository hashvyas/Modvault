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
-- Called by: trg_compat_canonicalise_pair. Stores the lower UUID as version A
-- so (A, B) and (B, A) map to one row of uq_compat_version_pair.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_compat_canonicalise_pair()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_tmp uuid;
BEGIN
    IF NEW.version_a_id > NEW.version_b_id THEN
        v_tmp            := NEW.version_a_id;
        NEW.version_a_id := NEW.version_b_id;
        NEW.version_b_id := v_tmp;
    END IF;
    RETURN NEW;
END;
$$;


-- -----------------------------------------------------------------------------
-- fn_mod_version_single_primary()  RETURNS TRIGGER
-- Called by: trg_mod_version_single_primary. Demotes the other versions of the
-- mod before the new primary row is written, so uq_mod_versions_one_primary
-- never sees two primaries.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_mod_version_single_primary()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.is_primary THEN
        UPDATE mod_versions
        SET    is_primary = FALSE
        WHERE  mod_id = NEW.mod_id
          AND  version_id <> NEW.version_id
          AND  is_primary;
    END IF;
    RETURN NEW;
END;
$$;


-- -----------------------------------------------------------------------------
-- fn_set_updated_at()  RETURNS TRIGGER
-- Generic updated_at setter for users, mods, loadouts, compatibility_matrix.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;


-- -----------------------------------------------------------------------------
-- fn_loadout_mods_auto_position()  RETURNS TRIGGER
-- Called by: trg_loadout_mods_position. Position 0 means "append": when the
-- loadout already has rows, the new row goes to max(position) + 1.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_loadout_mods_auto_position()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.position = 0 THEN
        -- shortcut: two concurrent inserts into one loadout can get the same position; fine for single-user editing, add a loadout row lock if that changes.
        SELECT coalesce(max(position) + 1, 0)
        INTO   NEW.position
        FROM   loadout_mods
        WHERE  loadout_id = NEW.loadout_id;
    END IF;
    RETURN NEW;
END;
$$;


-- -----------------------------------------------------------------------------
-- fn_loadout_mods_game_check()  RETURNS TRIGGER
-- Called by: trg_loadout_mods_game_check. A loadout may only hold versions of
-- mods made for the loadout's game.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_loadout_mods_game_check()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_loadout_game uuid;
    v_mod_game     uuid;
    v_mod_name     text;
BEGIN
    SELECT game_id INTO v_loadout_game FROM loadouts WHERE loadout_id = NEW.loadout_id;

    SELECT m.game_id, m.name INTO v_mod_game, v_mod_name
    FROM   mod_versions v
    JOIN   mods m ON m.mod_id = v.mod_id
    WHERE  v.version_id = NEW.version_id;

    -- Missing rows are left to the foreign keys.
    IF v_loadout_game <> v_mod_game THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = format('MODVAULT:GAME_MISMATCH: %s is made for a different game than this loadout', v_mod_name);
    END IF;
    RETURN NEW;
END;
$$;


-- -----------------------------------------------------------------------------
-- fn_reviews_rating_rollup()  RETURNS TRIGGER
-- Called by: trg_reviews_rating_rollup. Recomputes mods.rating_avg and
-- mods.rating_count for the affected mod ids only (OLD and NEW on UPDATE).
-- SECURITY DEFINER because review authors have no UPDATE right on mods.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_reviews_rating_rollup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_mod_ids uuid[];
BEGIN
    v_mod_ids := CASE TG_OP
                     WHEN 'INSERT' THEN ARRAY[NEW.mod_id]
                     WHEN 'DELETE' THEN ARRAY[OLD.mod_id]
                     ELSE ARRAY[OLD.mod_id, NEW.mod_id]
                 END;

    -- Same rounding as mod_ratings_view.
    UPDATE mods m
    SET    rating_avg   = coalesce((SELECT round(avg(r.rating)::numeric, 2)
                                    FROM reviews r WHERE r.mod_id = m.mod_id), 0),
           rating_count = (SELECT count(*) FROM reviews r WHERE r.mod_id = m.mod_id)
    WHERE  m.mod_id = ANY (v_mod_ids);

    RETURN NULL;
END;
$$;


-- -----------------------------------------------------------------------------
-- fn_audit_log()  RETURNS TRIGGER
-- Generic AFTER ROW audit trigger. TG_ARGV[0] is the primary key column name.
-- Stored JSON omits password_hash, embedding, search_tsv. An UPDATE that only
-- touches updated_at, rating_avg, rating_count, embedding or search_tsv is not
-- logged. changed_by = fn_current_user_id().
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_audit_log()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_old     jsonb;
    v_new     jsonb;
    v_hidden  CONSTANT text[] := ARRAY['password_hash', 'embedding', 'search_tsv'];
    v_ignored CONSTANT text[] := ARRAY['updated_at', 'rating_avg', 'rating_count', 'embedding', 'search_tsv'];
BEGIN
    IF TG_OP <> 'INSERT' THEN v_old := to_jsonb(OLD); END IF;
    IF TG_OP <> 'DELETE' THEN v_new := to_jsonb(NEW); END IF;

    -- Compare before hiding columns, so a password change is still logged (without the hash).
    IF TG_OP = 'UPDATE' AND (v_old - v_ignored) = (v_new - v_ignored) THEN
        RETURN NULL;
    END IF;

    INSERT INTO audit_log (table_name, operation, row_pk, old_row, new_row, changed_by)
    VALUES (TG_TABLE_NAME,
            left(TG_OP, 1),
            (coalesce(v_new, v_old) ->> TG_ARGV[0])::uuid,
            v_old - v_hidden,
            v_new - v_hidden,
            fn_current_user_id());

    RETURN NULL;
END;
$$;


-- -----------------------------------------------------------------------------
-- fn_audit_log_immutable()  RETURNS TRIGGER
-- Called by: trg_audit_log_immutable. audit_log is append-only.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_audit_log_immutable()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- ASSUMPTION: the FK action ON DELETE SET NULL on changed_by must still work,
    -- otherwise no user with audit history could ever be deleted. That one
    -- update (changed_by to NULL, nothing else changed) is let through.
    IF TG_OP = 'UPDATE' AND NEW.changed_by IS NULL
       AND (to_jsonb(NEW) - 'changed_by') = (to_jsonb(OLD) - 'changed_by') THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION USING ERRCODE = 'P0001',
        MESSAGE = 'MODVAULT:FORBIDDEN: audit_log is append-only';
END;
$$;


-- =============================================================================
-- SECTION 2 -- SESSION HELPERS
-- Every app transaction sets app.user_id and app.role with set_config(..., true).
-- =============================================================================

-- ASSUMPTION: filled in Phase 1 instead of P1-03, because fn_audit_log and
-- trigger test 5 (changed_by = session user) need them. The bodies are the
-- exact one-liners from contract section 6.1.
CREATE OR REPLACE FUNCTION fn_current_user_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$ SELECT NULLIF(current_setting('app.user_id', true), '')::uuid $$;

CREATE OR REPLACE FUNCTION fn_current_role()
RETURNS text
LANGUAGE sql STABLE
AS $$ SELECT coalesce(NULLIF(current_setting('app.role', true), ''), 'anonymous') $$;


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
