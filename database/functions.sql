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

-- -----------------------------------------------------------------------------
-- fn_register_user(username, email, password)  RETURNS uuid
-- Validates input, stores a bcrypt hash and returns the new user id.
-- New accounts are always 'modder'; only pr_set_user_role raises a role.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_register_user(p_username text, p_email text, p_password text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id    uuid;
    v_constraint text;
BEGIN
    IF p_username IS NULL OR p_username !~ '^[a-zA-Z0-9_]{3,50}$' THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'MODVAULT:INVALID_INPUT: username must be 3 to 50 letters, digits or underscores';
    END IF;
    IF p_email IS NULL OR position('@' IN p_email) = 0 OR length(p_email) > 255 THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'MODVAULT:INVALID_INPUT: email must contain @ and be at most 255 characters';
    END IF;
    IF p_password IS NULL OR length(p_password) < 8 THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'MODVAULT:INVALID_INPUT: password must be at least 8 characters';
    END IF;

    INSERT INTO users (username, email, password_hash, role)
    VALUES (p_username, p_email, crypt(p_password, gen_salt('bf', 10)), 'modder')
    RETURNING users.user_id INTO v_user_id;

    RETURN v_user_id;
EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    RAISE EXCEPTION USING ERRCODE = 'P0001',
        MESSAGE = CASE v_constraint
                      WHEN 'uq_users_email' THEN 'MODVAULT:DUPLICATE: email is already registered'
                      ELSE 'MODVAULT:DUPLICATE: username is already taken'
                  END;
END;
$$;

-- -----------------------------------------------------------------------------
-- fn_authenticate(username, password)  RETURNS TABLE(user_id, username, role)
-- One row on success, zero rows otherwise. An unknown username is checked
-- against a fixed dummy bcrypt hash (same cost), so it takes as long as a
-- wrong password and does not reveal which usernames exist.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_authenticate(p_username text, p_password text)
RETURNS TABLE(user_id uuid, username text, role user_role_enum)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT u.user_id, u.username::text, u.role
    FROM   (SELECT 1) AS one
    LEFT   JOIN users u ON u.username = p_username
    WHERE  crypt(p_password, coalesce(u.password_hash,
                 '$2a$10$XhWEMUq0R6aFcHBIxAzrmOubhOUptiv5fYR/rPcFOu9WJO44AZMFu')) = u.password_hash
      AND  u.is_active
$$;


-- =============================================================================
-- SECTION 4 -- SEARCH
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_search_mods_hybrid(query, embedding, game_id, limit)
-- Hybrid search: top 50 by vector cosine distance (HNSW) and top 50 by
-- full-text rank (GIN), fused with Reciprocal Rank Fusion, k = 60:
--   score = 1 / (60 + semantic_rank) + 1 / (60 + keyword_rank)
-- A NULL embedding or a blank query switches that half off. p_game_id NULL
-- means all games. The limit is capped at 50.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_search_mods_hybrid(p_query text, p_embedding vector(384), p_game_id uuid, p_limit int)
RETURNS TABLE(mod_id uuid, name text, summary text, game_id uuid,
              semantic_rank int, keyword_rank int, score float8)
LANGUAGE sql STABLE
AS $$
    WITH sem AS (
        -- LIMIT before ROW_NUMBER, so the ORDER BY ... LIMIT can use the HNSW index.
        SELECT s.mod_id, (ROW_NUMBER() OVER (ORDER BY s.dist, s.mod_id))::int AS rnk
        FROM (
            SELECT m.mod_id, m.embedding <=> p_embedding AS dist
            FROM   mods m
            WHERE  p_embedding IS NOT NULL
              AND  m.embedding IS NOT NULL
              AND  (p_game_id IS NULL OR m.game_id = p_game_id)
            ORDER  BY m.embedding <=> p_embedding
            LIMIT  50
        ) s
    ),
    kw AS (
        SELECT k.mod_id, (ROW_NUMBER() OVER (ORDER BY k.r DESC, k.mod_id))::int AS rnk
        FROM (
            SELECT m.mod_id, ts_rank_cd(m.search_tsv, q.tsq) AS r
            -- A blank query becomes NULL: no keyword hits, and no "no lexemes" NOTICE.
            FROM   mods m,
                   websearch_to_tsquery('english', nullif(trim(p_query), '')) AS q(tsq)
            WHERE  m.search_tsv @@ q.tsq
              AND  (p_game_id IS NULL OR m.game_id = p_game_id)
            ORDER  BY r DESC
            LIMIT  50
        ) k
    )
    SELECT m.mod_id, m.name::text, m.summary, m.game_id,
           sem.rnk, kw.rnk,
           (coalesce(1.0 / (60 + sem.rnk), 0) + coalesce(1.0 / (60 + kw.rnk), 0))::float8 AS score
    FROM   sem
    FULL   OUTER JOIN kw ON kw.mod_id = sem.mod_id
    JOIN   mods m ON m.mod_id = coalesce(sem.mod_id, kw.mod_id)
    ORDER  BY score DESC, m.name, m.mod_id
    LIMIT  least(greatest(coalesce(p_limit, 50), 0), 50)
$$;

-- -----------------------------------------------------------------------------
-- fn_search_mods_by_tag(VARIADIC tag slugs)  RETURNS SETOF mods
-- Mods that have every given tag slug (AND match). No slugs, no rows.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_search_mods_by_tag(VARIADIC p_tags text[])
RETURNS SETOF mods
LANGUAGE sql STABLE
AS $$
    SELECT m.*
    FROM   mods m
    WHERE  m.mod_id IN (
               SELECT mt.mod_id
               FROM   mod_tags mt
               JOIN   tags t ON t.tag_id = mt.tag_id
               WHERE  t.slug = ANY (p_tags)
               GROUP  BY mt.mod_id
               HAVING count(DISTINCT t.slug) = (SELECT count(DISTINCT x) FROM unnest(p_tags) AS x)
           )
    ORDER  BY m.name
$$;


-- =============================================================================
-- SECTION 5 -- MODS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_get_mod_dependency_tree(version_id)
-- Recursive CTE. Depth 0 is the given version. Each step follows required,
-- optional and recommends dependencies to the primary version of the required
-- mod. path holds the versions visited so far and stops cycles. Max depth 10.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_get_mod_dependency_tree(p_version_id uuid)
RETURNS TABLE(version_id uuid, mod_id uuid, mod_name text, parent_version_id uuid,
              depth int, dep_type dep_type_enum, path uuid[])
LANGUAGE sql STABLE
AS $$
    WITH RECURSIVE tree AS (
        SELECT v.version_id, v.mod_id, m.name::text AS mod_name,
               NULL::uuid AS parent_version_id, 0 AS depth,
               NULL::dep_type_enum AS dep_type, ARRAY[v.version_id] AS path
        FROM   mod_versions v
        JOIN   mods m ON m.mod_id = v.mod_id
        WHERE  v.version_id = p_version_id

        UNION ALL

        SELECT pv.version_id, pv.mod_id, m.name::text,
               t.version_id, t.depth + 1, d.dep_type, t.path || pv.version_id
        FROM   tree t
        JOIN   mod_dependencies d ON d.dependent_version_id = t.version_id
                                 AND d.dep_type IN ('required', 'optional', 'recommends')
        JOIN   mod_versions pv    ON pv.mod_id = d.required_mod_id AND pv.is_primary
        JOIN   mods m             ON m.mod_id = pv.mod_id
        WHERE  t.depth < 10
          AND  pv.version_id <> ALL (t.path)
    )
    SELECT * FROM tree ORDER BY depth, mod_name, version_id
$$;

-- -----------------------------------------------------------------------------
-- fn_mod_stats(mod_id)  One row for a known mod, zero rows otherwise.
--   dependent_count: distinct other mods with a non-conflict dependency on it.
--   conflict_count:  declared conflicts in either direction + incompatible
--                    matrix pairs touching any version of the mod.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_mod_stats(p_mod_id uuid)
RETURNS TABLE(version_count int, dependent_count int, conflict_count int,
              rating_avg numeric, rating_count int, download_count int)
LANGUAGE sql STABLE
AS $$
    SELECT (SELECT count(*) FROM mod_versions v WHERE v.mod_id = m.mod_id)::int,
           (SELECT count(DISTINCT dv.mod_id)
            FROM   mod_dependencies d
            JOIN   mod_versions dv ON dv.version_id = d.dependent_version_id
            WHERE  d.required_mod_id = m.mod_id
              AND  d.dep_type <> 'conflicts'
              AND  dv.mod_id <> m.mod_id)::int,
           ((SELECT count(*)
             FROM   mod_dependencies d
             JOIN   mod_versions dv ON dv.version_id = d.dependent_version_id
             WHERE  d.dep_type = 'conflicts'
               AND  (d.required_mod_id = m.mod_id OR dv.mod_id = m.mod_id))
            +
            (SELECT count(*)
             FROM   compatibility_matrix c
             JOIN   mod_versions va ON va.version_id = c.version_a_id
             JOIN   mod_versions vb ON vb.version_id = c.version_b_id
             WHERE  c.status = 'incompatible'
               AND  m.mod_id IN (va.mod_id, vb.mod_id)))::int,
           m.rating_avg::numeric, m.rating_count, m.download_count
    FROM   mods m
    WHERE  m.mod_id = p_mod_id
$$;

-- -----------------------------------------------------------------------------
-- fn_semver_satisfies(installed, constraint)  RETURNS boolean
-- Versions compare as numeric arrays of their digit groups, padded with
-- zeros to the same length (at least 3): '1.2' = {1,2,0}, so '1.10' > '1.9'.
-- Operators: *, =x, >=x, >x, <=x, <x, ^x (same major, at least x), and a
-- plain x, which means >=x. NULL or empty constraint, or an unparseable
-- installed version, gives true.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_semver_satisfies(p_installed text, p_constraint text)
RETURNS boolean
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
    v_match text[];
    v_op    text;
    v_inst  numeric[];
    v_req   numeric[];
    v_len   int;
BEGIN
    IF p_constraint IS NULL OR trim(p_constraint) IN ('', '*') THEN
        RETURN true;
    END IF;

    -- numeric, not int, so a long build number cannot overflow.
    v_inst := ARRAY(SELECT x[1]::numeric
                    FROM regexp_matches(regexp_replace(coalesce(p_installed, ''), '^\s*[vV]', ''), '\d+', 'g') AS x);
    IF cardinality(v_inst) = 0 THEN
        RETURN true;
    END IF;

    v_match := regexp_match(trim(p_constraint), '^(>=|<=|>|<|=|\^)?\s*(.*)$');
    v_op    := coalesce(v_match[1], '>=');
    v_req   := ARRAY(SELECT x[1]::numeric FROM regexp_matches(v_match[2], '\d+', 'g') AS x);
    -- ASSUMPTION: a constraint with no digits (for example '>=abc') cannot be
    -- checked, so it is treated as satisfied, like an unparseable installed version.
    IF cardinality(v_req) = 0 THEN
        RETURN true;
    END IF;

    v_len  := greatest(3, cardinality(v_inst), cardinality(v_req));
    v_inst := v_inst || array_fill(0::numeric, ARRAY[v_len - cardinality(v_inst)]);
    v_req  := v_req  || array_fill(0::numeric, ARRAY[v_len - cardinality(v_req)]);

    RETURN CASE v_op
               WHEN '='  THEN v_inst =  v_req
               WHEN '>=' THEN v_inst >= v_req
               WHEN '>'  THEN v_inst >  v_req
               WHEN '<=' THEN v_inst <= v_req
               WHEN '<'  THEN v_inst <  v_req
               WHEN '^'  THEN v_inst[1] = v_req[1] AND v_inst >= v_req
           END;
END;
$$;


-- =============================================================================
-- SECTION 6 -- LOADOUTS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_check_loadout_compatibility(loadout_id)
-- The health check engine: one CTE per issue type (contract section 6.6),
-- combined with UNION ALL. Only enabled loadout rows count. An unknown or
-- invisible loadout gives zero rows.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_check_loadout_compatibility(p_loadout_id uuid)
RETURNS TABLE(issue_type text, severity text, version_id uuid, other_version_id uuid,
              related_mod_id uuid, message text)
LANGUAGE sql STABLE
AS $$
    WITH lm AS (
        SELECT x.version_id, x.position, v.mod_id, v.semver, v.supported_game_versions,
               m.name::text AS mod_name, l.game_version
        FROM   loadout_mods x
        JOIN   loadouts l     ON l.loadout_id = x.loadout_id
        JOIN   mod_versions v ON v.version_id = x.version_id
        JOIN   mods m         ON m.mod_id = v.mod_id
        WHERE  x.loadout_id = p_loadout_id
          AND  x.enabled
    ),
    -- Every dependency of a loadout version, with the loadout's version of the
    -- target mod when one is present (b.* NULL when absent).
    deps AS (
        SELECT a.version_id, a.mod_name, a.position, d.dep_type, d.version_constraint,
               d.required_mod_id, rm.name::text AS req_name,
               b.version_id AS req_version_id, b.position AS req_position, b.semver AS req_semver
        FROM   lm a
        JOIN   mod_dependencies d ON d.dependent_version_id = a.version_id
        JOIN   mods rm            ON rm.mod_id = d.required_mod_id
        LEFT   JOIN lm b          ON b.mod_id = d.required_mod_id
    ),
    -- Matrix rows whose two versions are both in the loadout.
    pairs AS (
        SELECT c.status, c.conflict_detail,
               a.version_id AS a_id, a.mod_name AS a_name,
               b.version_id AS b_id, b.mod_name AS b_name
        FROM   compatibility_matrix c
        JOIN   lm a ON a.version_id = c.version_a_id
        JOIN   lm b ON b.version_id = c.version_b_id
    ),
    missing_dependency AS (
        SELECT 'MISSING_DEPENDENCY'::text, 'error'::text, version_id, NULL::uuid, required_mod_id,
               format('%s requires %s, which is not in this loadout', mod_name, req_name)
        FROM   deps
        WHERE  dep_type = 'required' AND req_version_id IS NULL
    ),
    declared_conflict AS (
        -- A conflict declared on both sides is one pair: keep one row per unordered pair.
        SELECT DISTINCT ON (least(version_id, req_version_id), greatest(version_id, req_version_id))
               'DECLARED_CONFLICT'::text, 'error'::text, version_id, req_version_id, required_mod_id,
               format('%s conflicts with %s', mod_name, req_name)
        FROM   deps
        WHERE  dep_type = 'conflicts' AND req_version_id IS NOT NULL
        ORDER  BY least(version_id, req_version_id), greatest(version_id, req_version_id), version_id
    ),
    incompatible_pair AS (
        SELECT 'INCOMPATIBLE_PAIR'::text, 'error'::text, a_id, b_id, NULL::uuid,
               format('%s is incompatible with %s', a_name, b_name)
        FROM   pairs
        WHERE  status = 'incompatible'
    ),
    load_order AS (
        SELECT 'LOAD_ORDER'::text, 'warning'::text, version_id, req_version_id, required_mod_id,
               format('%s loads before %s, which it requires', mod_name, req_name)
        FROM   deps
        WHERE  dep_type = 'required' AND req_position > position
    ),
    version_constraint AS (
        -- ASSUMPTION: a version constraint on a 'conflicts' row is not a
        -- requirement, so only required, optional and recommends rows are checked.
        SELECT 'VERSION_CONSTRAINT'::text, 'warning'::text, version_id, req_version_id, required_mod_id,
               format('%s needs %s %s, but %s is installed', mod_name, req_name, version_constraint, req_semver)
        FROM   deps
        WHERE  dep_type <> 'conflicts'
          AND  req_version_id IS NOT NULL
          AND  NOT fn_semver_satisfies(req_semver, version_constraint)
    ),
    game_version_mismatch AS (
        SELECT 'GAME_VERSION_MISMATCH'::text, 'warning'::text, version_id, NULL::uuid, NULL::uuid,
               format('%s %s does not support game version %s', mod_name, semver, game_version)
        FROM   lm
        WHERE  game_version IS NOT NULL
          AND  cardinality(supported_game_versions) > 0
          AND  NOT (game_version = ANY (supported_game_versions))
    ),
    partial_pair AS (
        SELECT 'PARTIAL_PAIR'::text, 'warning'::text, a_id, b_id, NULL::uuid,
               format('%s and %s are only partly compatible', a_name, b_name)
                   || coalesce(': ' || (conflict_detail ->> 'reason'), '')
        FROM   pairs
        WHERE  status = 'partial'
    ),
    missing_recommended AS (
        SELECT 'MISSING_RECOMMENDED'::text, 'info'::text, version_id, NULL::uuid, required_mod_id,
               format('%s %s %s, which is not in this loadout', mod_name,
                      CASE dep_type WHEN 'optional' THEN 'can use' ELSE 'recommends' END, req_name)
        FROM   deps
        WHERE  dep_type IN ('optional', 'recommends') AND req_version_id IS NULL
    ),
    unverified_pair AS (
        -- a < b is the canonical matrix order (trg_compat_canonicalise_pair).
        SELECT 'UNVERIFIED_PAIR'::text, 'info'::text, a.version_id, b.version_id, NULL::uuid,
               format('%s and %s have not been checked together', a.mod_name, b.mod_name)
        FROM   lm a
        JOIN   lm b ON a.version_id < b.version_id AND a.mod_id <> b.mod_id
        LEFT   JOIN compatibility_matrix c ON c.version_a_id = a.version_id AND c.version_b_id = b.version_id
        WHERE  c.compat_id IS NULL OR c.status = 'unknown'
    )
    SELECT i.*
    FROM (
        SELECT * FROM missing_dependency
        UNION ALL SELECT * FROM declared_conflict
        UNION ALL SELECT * FROM incompatible_pair
        UNION ALL SELECT * FROM load_order
        UNION ALL SELECT * FROM version_constraint
        UNION ALL SELECT * FROM game_version_mismatch
        UNION ALL SELECT * FROM partial_pair
        UNION ALL SELECT * FROM missing_recommended
        UNION ALL SELECT * FROM unverified_pair
    ) AS i(issue_type, severity, version_id, other_version_id, related_mod_id, message)
    ORDER BY CASE i.severity WHEN 'error' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END,
             i.issue_type, i.message
$$;

-- -----------------------------------------------------------------------------
-- fn_loadout_health_score(loadout_id)  RETURNS int
-- GREATEST(0, 100 - 25 * errors - 10 * warnings). Info issues do not count.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_loadout_health_score(p_loadout_id uuid)
RETURNS int
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM loadouts WHERE loadout_id = p_loadout_id) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'MODVAULT:NOT_FOUND: loadout not found';
    END IF;

    RETURN (SELECT greatest(0, 100 - 25 * count(*) FILTER (WHERE c.severity = 'error')
                                   - 10 * count(*) FILTER (WHERE c.severity = 'warning'))::int
            FROM   fn_check_loadout_compatibility(p_loadout_id) c);
END;
$$;

-- -----------------------------------------------------------------------------
-- fn_suggest_load_order(loadout_id)
-- Dependencies before dependents. An edge goes from a loadout version to each
-- present dependency (required, optional, recommends). A version's depth is
-- its longest dependency chain inside the loadout, found by walking every path
-- with a recursive CTE (path array stops cycles). Sort by depth, then current
-- position, then mod name. Positions are 0 to n-1.
-- ASSUMPTION: disabled rows are ordered too (they keep a slot when re-enabled),
-- so pr_apply_load_order can renumber every row of the loadout.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_suggest_load_order(p_loadout_id uuid)
RETURNS TABLE(version_id uuid, suggested_position int)
LANGUAGE sql STABLE
AS $$
    WITH RECURSIVE lm AS (
        SELECT x.version_id, x.position, v.mod_id, m.name AS mod_name
        FROM   loadout_mods x
        JOIN   mod_versions v ON v.version_id = x.version_id
        JOIN   mods m         ON m.mod_id = v.mod_id
        WHERE  x.loadout_id = p_loadout_id
    ),
    edge AS (
        SELECT DISTINCT a.version_id AS from_v, b.version_id AS to_v
        FROM   lm a
        JOIN   mod_dependencies d ON d.dependent_version_id = a.version_id
                                 AND d.dep_type IN ('required', 'optional', 'recommends')
        JOIN   lm b ON b.mod_id = d.required_mod_id AND b.version_id <> a.version_id
    ),
    -- shortcut: enumerates every dependency path, which grows fast in dense graphs; fine for loadouts of tens of mods, switch to iterative longest-path if loadouts reach hundreds.
    walk AS (
        SELECT lm.version_id AS start_v, lm.version_id AS cur_v, 0 AS len, ARRAY[lm.version_id] AS path
        FROM   lm
        UNION ALL
        SELECT w.start_v, e.to_v, w.len + 1, w.path || e.to_v
        FROM   walk w
        JOIN   edge e ON e.from_v = w.cur_v
        WHERE  e.to_v <> ALL (w.path)
    ),
    depth AS (
        SELECT start_v, max(len) AS depth FROM walk GROUP BY start_v
    )
    SELECT lm.version_id,
           (ROW_NUMBER() OVER (ORDER BY d.depth, lm.position, lm.mod_name, lm.version_id) - 1)::int
    FROM   lm
    JOIN   depth d ON d.start_v = lm.version_id
    ORDER  BY 2
$$;

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
