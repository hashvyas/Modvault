

SET client_encoding = 'UTF8';
CREATE FUNCTION pg_temp.fx_loadout(p_game uuid, p_game_version text, p_versions uuid[])
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
    l uuid;
BEGIN
    INSERT INTO loadouts (user_id, game_id, name, game_version)
    VALUES ('b0000000-0000-0000-0000-000000000001', p_game, 'FX health test', p_game_version)
    RETURNING loadout_id INTO l;
    INSERT INTO loadout_mods (loadout_id, version_id, position)
    SELECT l, v, (o - 1)::int FROM unnest(p_versions) WITH ORDINALITY AS t(v, o);
    RETURN l;
END $$;
CREATE FUNCTION pg_temp.fx_assert_once(p_loadout uuid, p_type text, p_severity text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    ASSERT (SELECT count(*) FROM fn_check_loadout_compatibility(p_loadout) WHERE issue_type = p_type) = 1,
        format('%s does not appear exactly once', p_type);
    ASSERT (SELECT severity FROM fn_check_loadout_compatibility(p_loadout) WHERE issue_type = p_type) = p_severity,
        format('%s severity is not %s', p_type, p_severity);
END $$;
BEGIN;
DO $$
DECLARE
    l uuid := pg_temp.fx_loadout('a0000000-0000-0000-0000-000000000001', NULL,
        ARRAY['d0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000004']::uuid[]);
BEGIN
    PERFORM pg_temp.fx_assert_once(l, 'MISSING_DEPENDENCY', 'error');
    ASSERT (SELECT related_mod_id = 'c0000000-0000-0000-0000-000000000001'
                   AND message = 'FX SkyUI requires FX Script Extender, which is not in this loadout'
            FROM fn_check_loadout_compatibility(l) WHERE issue_type = 'MISSING_DEPENDENCY'),
        'MISSING_DEPENDENCY has the wrong related mod or message';
    RAISE NOTICE 'PASS 1 MISSING_DEPENDENCY';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    l uuid;
BEGIN
    INSERT INTO mod_dependencies (dependent_version_id, required_mod_id, dep_type)
    VALUES ('d0000000-0000-0000-0000-000000000005', 'c0000000-0000-0000-0000-000000000002', 'conflicts');
    l := pg_temp.fx_loadout('a0000000-0000-0000-0000-000000000001', NULL,
        ARRAY['d0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002',
              'd0000000-0000-0000-0000-000000000004', 'd0000000-0000-0000-0000-000000000005']::uuid[]);
    PERFORM pg_temp.fx_assert_once(l, 'DECLARED_CONFLICT', 'error');
    RAISE NOTICE 'PASS 2 DECLARED_CONFLICT';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    l uuid := pg_temp.fx_loadout('a0000000-0000-0000-0000-000000000001', NULL,
        ARRAY['d0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000005']::uuid[]);
BEGIN
    PERFORM pg_temp.fx_assert_once(l, 'INCOMPATIBLE_PAIR', 'error');
    RAISE NOTICE 'PASS 3 INCOMPATIBLE_PAIR';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    l uuid := pg_temp.fx_loadout('a0000000-0000-0000-0000-000000000001', NULL,
        ARRAY['d0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000001',
              'd0000000-0000-0000-0000-000000000004']::uuid[]);
BEGIN
    PERFORM pg_temp.fx_assert_once(l, 'LOAD_ORDER', 'warning');
    RAISE NOTICE 'PASS 4 LOAD_ORDER';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    l uuid;
BEGIN
    UPDATE mod_dependencies SET version_constraint = '>=3.0'
    WHERE dependent_version_id = 'd0000000-0000-0000-0000-000000000002'
      AND required_mod_id = 'c0000000-0000-0000-0000-000000000001';
    l := pg_temp.fx_loadout('a0000000-0000-0000-0000-000000000001', NULL,
        ARRAY['d0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002',
              'd0000000-0000-0000-0000-000000000004']::uuid[]);
    PERFORM pg_temp.fx_assert_once(l, 'VERSION_CONSTRAINT', 'warning');
    RAISE NOTICE 'PASS 5 VERSION_CONSTRAINT';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    l uuid := pg_temp.fx_loadout('a0000000-0000-0000-0000-000000000001', '1.5.97',
        ARRAY['d0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000004']::uuid[]);
BEGIN
    PERFORM pg_temp.fx_assert_once(l, 'GAME_VERSION_MISMATCH', 'warning');
    RAISE NOTICE 'PASS 6 GAME_VERSION_MISMATCH';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    l uuid := pg_temp.fx_loadout('a0000000-0000-0000-0000-000000000002', NULL,
        ARRAY['d0000000-0000-0000-0000-000000000006', 'd0000000-0000-0000-0000-000000000007']::uuid[]);
BEGIN
    PERFORM pg_temp.fx_assert_once(l, 'PARTIAL_PAIR', 'warning');
    ASSERT (SELECT message LIKE '%needs the F4SE build for 1.10.163'
            FROM fn_check_loadout_compatibility(l) WHERE issue_type = 'PARTIAL_PAIR'),
        'PARTIAL_PAIR message does not include the reason';
    RAISE NOTICE 'PASS 7 PARTIAL_PAIR';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    l uuid := pg_temp.fx_loadout('a0000000-0000-0000-0000-000000000001', NULL,
        ARRAY['d0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002']::uuid[]);
BEGIN
    PERFORM pg_temp.fx_assert_once(l, 'MISSING_RECOMMENDED', 'info');
    RAISE NOTICE 'PASS 8 MISSING_RECOMMENDED';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    l_unknown uuid := pg_temp.fx_loadout('a0000000-0000-0000-0000-000000000001', NULL,
        ARRAY['d0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000004']::uuid[]);
    l_no_row  uuid := pg_temp.fx_loadout('a0000000-0000-0000-0000-000000000001', NULL,
        ARRAY['d0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000005']::uuid[]);
BEGIN
    PERFORM pg_temp.fx_assert_once(l_unknown, 'UNVERIFIED_PAIR', 'info');
    PERFORM pg_temp.fx_assert_once(l_no_row, 'UNVERIFIED_PAIR', 'info');
    RAISE NOTICE 'PASS 9 UNVERIFIED_PAIR';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    l uuid;
BEGIN
    UPDATE compatibility_matrix SET status = 'compatible'
    WHERE version_a_id = 'd0000000-0000-0000-0000-000000000001'
      AND version_b_id = 'd0000000-0000-0000-0000-000000000004';
    l := pg_temp.fx_loadout('a0000000-0000-0000-0000-000000000001', '1.6.1170',
        ARRAY['d0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000004']::uuid[]);
    ASSERT (SELECT count(*) FROM fn_check_loadout_compatibility(l) WHERE severity IN ('error', 'warning')) = 0,
        'clean loadout has errors or warnings';
    ASSERT fn_loadout_health_score(l) = 100, 'clean loadout score is not 100';
    RAISE NOTICE 'PASS 10 clean loadout scores 100';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    l uuid := pg_temp.fx_loadout('a0000000-0000-0000-0000-000000000001', NULL,
        ARRAY['d0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002',
              'd0000000-0000-0000-0000-000000000004', 'd0000000-0000-0000-0000-000000000005']::uuid[]);
BEGIN
    ASSERT (SELECT count(*) FROM fn_check_loadout_compatibility(l)
            WHERE issue_type IN ('DECLARED_CONFLICT', 'INCOMPATIBLE_PAIR')) = 2,
        'enabled conflicting mod should give DECLARED_CONFLICT and INCOMPATIBLE_PAIR';
    UPDATE loadout_mods SET enabled = FALSE
    WHERE loadout_id = l AND version_id = 'd0000000-0000-0000-0000-000000000005';
    ASSERT (SELECT count(*) FROM fn_check_loadout_compatibility(l)
            WHERE 'd0000000-0000-0000-0000-000000000005' IN (version_id, other_version_id)
               OR related_mod_id = 'c0000000-0000-0000-0000-000000000004') = 0,
        'disabled mod still produces an issue';
    RAISE NOTICE 'PASS 11 disabled mod ignored';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    l uuid := pg_temp.fx_loadout('a0000000-0000-0000-0000-000000000001', '1.5.97',
        ARRAY['d0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000001',
              'd0000000-0000-0000-0000-000000000005']::uuid[]);
    errors   int;
    warnings int;
    raised   boolean := false;
BEGIN
    SELECT count(*) FILTER (WHERE severity = 'error'), count(*) FILTER (WHERE severity = 'warning')
    INTO errors, warnings FROM fn_check_loadout_compatibility(l);
    ASSERT errors > 0 AND warnings > 0, 'score test loadout needs errors and warnings';
    ASSERT fn_loadout_health_score(l) = greatest(0, 100 - 25 * errors - 10 * warnings), 'score does not follow the formula';
    ASSERT (SELECT bool_and(s >= prev_s) FROM (
                SELECT s, lag(s, 1, 0) OVER (ORDER BY o) AS prev_s
                FROM fn_check_loadout_compatibility(l)
                     WITH ORDINALITY AS c(issue_type, severity, version_id, other_version_id, related_mod_id, message, o),
                     LATERAL (SELECT CASE c.severity WHEN 'error' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END) AS x(s)) t),
        'results are not ordered by severity';

    ASSERT (SELECT count(*) FROM fn_check_loadout_compatibility(gen_random_uuid())) = 0,
        'unknown loadout returned rows';
    BEGIN
        PERFORM fn_loadout_health_score(gen_random_uuid());
    EXCEPTION WHEN raise_exception THEN
        raised := SQLERRM LIKE 'MODVAULT:NOT_FOUND: %';
    END;
    ASSERT raised, 'score of unknown loadout did not raise NOT_FOUND';
    RAISE NOTICE 'PASS 12 score formula, order, unknown ids';
END $$;
ROLLBACK;
