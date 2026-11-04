

SET client_encoding = 'UTF8';
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
CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;
CREATE OR REPLACE FUNCTION fn_loadout_mods_auto_position()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.position = 0 THEN
        SELECT coalesce(max(position) + 1, 0)
        INTO   NEW.position
        FROM   loadout_mods
        WHERE  loadout_id = NEW.loadout_id;
    END IF;
    RETURN NEW;
END;
$$;
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
    IF v_loadout_game <> v_mod_game THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = format('MODVAULT:GAME_MISMATCH: %s is made for a different game than this loadout', v_mod_name);
    END IF;
    RETURN NEW;
END;
$$;
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
    UPDATE mods m
    SET    rating_avg   = coalesce((SELECT round(avg(r.rating)::numeric, 2)
                                    FROM reviews r WHERE r.mod_id = m.mod_id), 0),
           rating_count = (SELECT count(*) FROM reviews r WHERE r.mod_id = m.mod_id)
    WHERE  m.mod_id = ANY (v_mod_ids);

    RETURN NULL;
END;
$$;
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
CREATE OR REPLACE FUNCTION fn_audit_log_immutable()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.changed_by IS NULL
       AND (to_jsonb(NEW) - 'changed_by') = (to_jsonb(OLD) - 'changed_by') THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION USING ERRCODE = 'P0001',
        MESSAGE = 'MODVAULT:FORBIDDEN: audit_log is append-only';
END;
$$;
CREATE OR REPLACE FUNCTION fn_current_user_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$ SELECT NULLIF(current_setting('app.user_id', true), '')::uuid $$;

CREATE OR REPLACE FUNCTION fn_current_role()
RETURNS text
LANGUAGE sql STABLE
AS $$ SELECT coalesce(NULLIF(current_setting('app.role', true), ''), 'anonymous') $$;
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
CREATE OR REPLACE FUNCTION fn_search_mods_hybrid(p_query text, p_embedding vector(384), p_game_id uuid, p_limit int)
RETURNS TABLE(mod_id uuid, name text, summary text, game_id uuid,
              semantic_rank int, keyword_rank int, score float8)
LANGUAGE sql STABLE
AS $$
    WITH sem AS (
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
           (SELECT count(DISTINCT x.other_mod)
            FROM (
                SELECT CASE WHEN dv.mod_id = m.mod_id THEN d.required_mod_id ELSE dv.mod_id END AS other_mod
                FROM   mod_dependencies d
                JOIN   mod_versions dv ON dv.version_id = d.dependent_version_id
                WHERE  d.dep_type = 'conflicts'
                  AND  (d.required_mod_id = m.mod_id OR dv.mod_id = m.mod_id)
                UNION ALL
                SELECT CASE WHEN va.mod_id = m.mod_id THEN vb.mod_id ELSE va.mod_id END
                FROM   compatibility_matrix c
                JOIN   mod_versions va ON va.version_id = c.version_a_id
                JOIN   mod_versions vb ON vb.version_id = c.version_b_id
                WHERE  c.status = 'incompatible'
                  AND  m.mod_id IN (va.mod_id, vb.mod_id)
            ) x
            WHERE  x.other_mod <> m.mod_id)::int,
           m.rating_avg::numeric, m.rating_count, m.download_count
    FROM   mods m
    WHERE  m.mod_id = p_mod_id
$$;
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
    v_inst := ARRAY(SELECT x[1]::numeric
                    FROM regexp_matches(regexp_replace(coalesce(p_installed, ''), '^\s*[vV]', ''), '\d+', 'g') AS x);
    IF cardinality(v_inst) = 0 THEN
        RETURN true;
    END IF;

    v_match := regexp_match(trim(p_constraint), '^(>=|<=|>|<|=|\^)?\s*(.*)$');
    v_op    := coalesce(v_match[1], '>=');
    v_req   := ARRAY(SELECT x[1]::numeric FROM regexp_matches(v_match[2], '\d+', 'g') AS x);
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
    deps AS (
        SELECT a.version_id, a.mod_name, a.position, d.dep_type, d.version_constraint,
               d.required_mod_id, rm.name::text AS req_name,
               b.version_id AS req_version_id, b.position AS req_position, b.semver AS req_semver
        FROM   lm a
        JOIN   mod_dependencies d ON d.dependent_version_id = a.version_id
        JOIN   mods rm            ON rm.mod_id = d.required_mod_id
        LEFT   JOIN lm b          ON b.mod_id = d.required_mod_id
    ),
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
AS $$
    SELECT jsonb_build_object(
               'format',       'modvault-loadout/1',
               'name',         l.name,
               'description',  l.description,
               'game_domain',  g.domain,
               'game_version', l.game_version,
               'mods', coalesce((
                   SELECT jsonb_agg(jsonb_build_object(
                              'nexus_mod_id', m.nexus_mod_id,
                              'semver',       v.semver,
                              'position',     x.position,
                              'enabled',      x.enabled)
                          ORDER BY x.position, m.name, v.version_id)
                   FROM   loadout_mods x
                   JOIN   mod_versions v ON v.version_id = x.version_id
                   JOIN   mods m         ON m.mod_id = v.mod_id
                   WHERE  x.loadout_id = l.loadout_id), '[]'::jsonb))
    FROM   loadouts l
    JOIN   games g ON g.game_id = l.game_id
    WHERE  l.loadout_id = p_loadout_id
$$;
CREATE OR REPLACE PROCEDURE pr_publish_mod(p_game_id uuid, p_name text, p_summary text, p_category text,
                                           p_semver text, p_tags text[], p_embedding vector(384),
                                           INOUT p_mod_id uuid DEFAULT NULL)
LANGUAGE plpgsql
AS $$
DECLARE
    v_tags text[];
BEGIN
    IF fn_current_user_id() IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'MODVAULT:FORBIDDEN: log in to publish a mod';
    END IF;
    IF coalesce(trim(p_name), '') = '' OR coalesce(trim(p_semver), '') = '' THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'MODVAULT:INVALID_INPUT: name and version are required';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM games WHERE game_id = p_game_id) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'MODVAULT:NOT_FOUND: game not found';
    END IF;

    INSERT INTO mods (author_id, game_id, name, summary, category, embedding)
    VALUES (fn_current_user_id(), p_game_id, trim(p_name), p_summary, p_category, p_embedding)
    RETURNING mod_id INTO p_mod_id;

    INSERT INTO mod_versions (mod_id, semver, is_primary)
    VALUES (p_mod_id, trim(p_semver), TRUE);

    v_tags := ARRAY(SELECT DISTINCT trim(t) FROM unnest(p_tags) AS t WHERE coalesce(trim(t), '') <> '');

    INSERT INTO tags (name, slug)
    SELECT t, t FROM unnest(v_tags) AS t
    ON CONFLICT DO NOTHING;

    INSERT INTO mod_tags (mod_id, tag_id)
    SELECT p_mod_id, tag_id FROM tags WHERE slug = ANY (v_tags);
END;
$$;
CREATE OR REPLACE PROCEDURE pr_add_mod_to_loadout(p_loadout_id uuid, p_version_id uuid)
LANGUAGE plpgsql
AS $$
DECLARE
    v_owner uuid;
BEGIN
    SELECT user_id INTO v_owner FROM loadouts WHERE loadout_id = p_loadout_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'MODVAULT:NOT_FOUND: loadout not found';
    END IF;
    IF v_owner IS DISTINCT FROM fn_current_user_id() THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'MODVAULT:FORBIDDEN: only the owner can change this loadout';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM mod_versions WHERE version_id = p_version_id) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'MODVAULT:NOT_FOUND: mod version not found';
    END IF;
    IF EXISTS (SELECT 1 FROM loadout_mods WHERE loadout_id = p_loadout_id AND version_id = p_version_id) THEN
        RETURN;
    END IF;

    UPDATE loadout_mods x
    SET    version_id = p_version_id
    FROM   mod_versions cur, mod_versions new
    WHERE  x.loadout_id = p_loadout_id
      AND  cur.version_id = x.version_id
      AND  new.version_id = p_version_id
      AND  cur.mod_id = new.mod_id;

    IF NOT FOUND THEN
        INSERT INTO loadout_mods (loadout_id, version_id) VALUES (p_loadout_id, p_version_id);
    END IF;
END;
$$;
CREATE OR REPLACE PROCEDURE pr_apply_load_order(p_loadout_id uuid)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE loadout_mods x
    SET    position = s.suggested_position
    FROM   fn_suggest_load_order(p_loadout_id) s
    WHERE  x.loadout_id = p_loadout_id
      AND  x.version_id = s.version_id
      AND  x.position <> s.suggested_position;
END;
$$;
CREATE OR REPLACE PROCEDURE pr_import_loadout(p_manifest jsonb,
                                              INOUT p_loadout_id uuid DEFAULT NULL,
                                              INOUT p_skipped int DEFAULT NULL)
LANGUAGE plpgsql
AS $$
DECLARE
    v_game_id    uuid;
    v_mod_id     uuid;
    v_version_id uuid;
    v_entry      jsonb;
BEGIN
    IF fn_current_user_id() IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'MODVAULT:FORBIDDEN: log in to import a loadout';
    END IF;
    IF p_manifest ->> 'format' IS DISTINCT FROM 'modvault-loadout/1' THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'MODVAULT:INVALID_MANIFEST: format must be modvault-loadout/1';
    END IF;
    IF coalesce(trim(p_manifest ->> 'name'), '') = '' OR jsonb_typeof(p_manifest -> 'mods') IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'MODVAULT:INVALID_MANIFEST: name and a mods array are required';
    END IF;

    SELECT game_id INTO v_game_id FROM games WHERE domain = p_manifest ->> 'game_domain';
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = format('MODVAULT:INVALID_MANIFEST: unknown game %s', coalesce(p_manifest ->> 'game_domain', '(none)'));
    END IF;

    INSERT INTO loadouts (user_id, game_id, name, description, game_version)
    VALUES (fn_current_user_id(), v_game_id, trim(p_manifest ->> 'name'),
            p_manifest ->> 'description', p_manifest ->> 'game_version')
    RETURNING loadout_id INTO p_loadout_id;

    p_skipped := 0;
    FOR v_entry IN
        SELECT e FROM jsonb_array_elements(p_manifest -> 'mods') WITH ORDINALITY AS t(e, o)
        ORDER  BY CASE WHEN jsonb_typeof(e -> 'position') = 'number' THEN (e ->> 'position')::numeric END NULLS LAST, o
    LOOP
        BEGIN
            v_mod_id := NULL;
            v_version_id := NULL;

            SELECT mod_id INTO v_mod_id
            FROM   mods
            WHERE  game_id = v_game_id AND nexus_mod_id = v_entry ->> 'nexus_mod_id';

            SELECT version_id INTO v_version_id
            FROM   mod_versions
            WHERE  mod_id = v_mod_id AND (semver = v_entry ->> 'semver' OR is_primary)
            ORDER  BY (semver = v_entry ->> 'semver') DESC
            LIMIT  1;

            IF v_version_id IS NULL THEN
                p_skipped := p_skipped + 1;
                CONTINUE;
            END IF;
            IF EXISTS (SELECT 1 FROM loadout_mods lm
                       JOIN mod_versions mv ON lm.version_id = mv.version_id
                       WHERE lm.loadout_id = p_loadout_id AND mv.mod_id = v_mod_id) THEN
                p_skipped := p_skipped + 1;
                CONTINUE;
            END IF;

            INSERT INTO loadout_mods (loadout_id, version_id, position, enabled)
            VALUES (p_loadout_id, v_version_id,
                    coalesce((v_entry ->> 'position')::int, 0),
                    coalesce((v_entry ->> 'enabled')::boolean, TRUE));
        EXCEPTION WHEN others THEN
            p_skipped := p_skipped + 1;
        END;
    END LOOP;
END;
$$;
CREATE OR REPLACE PROCEDURE pr_promote_version(p_version_id uuid)
LANGUAGE plpgsql
AS $$
DECLARE
    v_mod_id uuid;
BEGIN
    IF fn_current_role() NOT IN ('curator', 'admin') THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'MODVAULT:FORBIDDEN: only curators and admins can promote a version';
    END IF;

    SELECT mod_id INTO v_mod_id FROM mod_versions WHERE version_id = p_version_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'MODVAULT:NOT_FOUND: mod version not found';
    END IF;

    PERFORM 1 FROM mod_versions WHERE mod_id = v_mod_id FOR UPDATE;

    UPDATE mod_versions SET is_primary = TRUE WHERE version_id = p_version_id AND NOT is_primary;
END;
$$;
CREATE OR REPLACE PROCEDURE pr_upsert_compatibility(p_version_a uuid, p_version_b uuid,
                                                    p_status compat_status_enum, p_detail jsonb)
LANGUAGE plpgsql
AS $$
BEGIN
    IF fn_current_role() NOT IN ('curator', 'admin') THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'MODVAULT:FORBIDDEN: only curators and admins can record compatibility';
    END IF;
    IF p_version_a IS NULL OR p_version_b IS NULL OR p_version_a = p_version_b OR p_status IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'MODVAULT:INVALID_INPUT: two different versions and a status are required';
    END IF;

    INSERT INTO compatibility_matrix (version_a_id, version_b_id, status, conflict_detail, verified_by)
    VALUES (least(p_version_a, p_version_b), greatest(p_version_a, p_version_b),
            p_status, p_detail, fn_current_user_id())
    ON CONFLICT (version_a_id, version_b_id) DO UPDATE
    SET    status          = EXCLUDED.status,
           conflict_detail = EXCLUDED.conflict_detail,
           verified_by     = EXCLUDED.verified_by;
END;
$$;
CREATE OR REPLACE PROCEDURE pr_set_user_role(p_user_id uuid, p_role user_role_enum)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF fn_current_role() <> 'admin' THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'MODVAULT:FORBIDDEN: only admins can change roles';
    END IF;
    IF p_role IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'MODVAULT:INVALID_INPUT: role is required';
    END IF;

    UPDATE users SET role = p_role WHERE user_id = p_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'MODVAULT:NOT_FOUND: user not found';
    END IF;
END;
$$;
CREATE OR REPLACE PROCEDURE pr_refresh_reports()
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF fn_current_role() <> 'admin' THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'MODVAULT:FORBIDDEN: only admins can refresh reports';
    END IF;

    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_game_leaderboard;
END;
$$;
