-- =============================================================================
-- ModVault: A Mod Repository and Compatibility Intelligence System
-- Health check tests  --  tests/test_health.sql
--
-- One fixture loadout per issue type (contract section 6.6). Each test asserts
-- its issue appears exactly once with the right severity. Also: a clean
-- loadout scores 100, a disabled conflicting mod is ignored, the score follows
-- the formula and unknown ids behave as the contract says.
--
-- Each check runs inside BEGIN ... ROLLBACK and leaves no data behind.
-- A failed ASSERT stops the run (ON_ERROR_STOP=1). Each passing check prints
-- a NOTICE starting with PASS.
--
-- Fixture versions used (game A unless noted):
--   d1 Script Extender 2.2.6 (supports 1.6.1170)   d2 SkyUI 5.2.0
--   d4 Unofficial Patch 4.3.0   d5 Alternate UI 1.0.0
--   d6 F4 Script Extender 0.6.23 (game B)   d7 Armorsmith 2.0.0 (game B)
--   d2 requires c1 '>=2.2', recommends c3, conflicts c4. d5 optional c1.
--   Matrix: (d2,d4) compatible, (d2,d5) incompatible, (d1,d4) unknown,
--   (d6,d7) partial.
--
-- HOW TO RUN (after run_all.sql and tests/fixtures.sql)
--   psql "postgresql://modvault_owner:modvault_owner_dev@localhost:5432/modvault" -v ON_ERROR_STOP=1 -f database/tests/test_health.sql
-- =============================================================================

SET client_encoding = 'UTF8';

-- Test helpers, dropped with the session.
-- Creates a loadout owned by fx_modder holding the given versions in array order.
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

-- Asserts the issue type appears exactly once in the loadout, with the given severity.
CREATE FUNCTION pg_temp.fx_assert_once(p_loadout uuid, p_type text, p_severity text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    ASSERT (SELECT count(*) FROM fn_check_loadout_compatibility(p_loadout) WHERE issue_type = p_type) = 1,
        format('%s does not appear exactly once', p_type);
    ASSERT (SELECT severity FROM fn_check_loadout_compatibility(p_loadout) WHERE issue_type = p_type) = p_severity,
        format('%s severity is not %s', p_type, p_severity);
END $$;


-- 1. MISSING_DEPENDENCY: SkyUI without its required script extender.
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


-- 2. DECLARED_CONFLICT: conflict declared on both sides is still one pair.
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


-- 3. INCOMPATIBLE_PAIR: matrix says (d2, d5) incompatible.
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


-- 4. LOAD_ORDER: SkyUI at position 0, its requirement at position 1.
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


-- 5. VERSION_CONSTRAINT: SkyUI needs script extender >=3.0, 2.2.6 is installed.
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


-- 6. GAME_VERSION_MISMATCH: script extender supports 1.6.1170 only.
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


-- 7. PARTIAL_PAIR: game B pair marked partial; message carries the reason.
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


-- 8. MISSING_RECOMMENDED: SkyUI recommends the unofficial patch.
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


-- 9. UNVERIFIED_PAIR: once for an 'unknown' matrix row, once for no row at all.
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


-- 10. Clean loadout: no errors or warnings, score 100, status rule gives healthy.
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


-- 11. A disabled conflicting mod produces no issue at all.
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


-- 12. Score formula, result order, unknown ids.
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

    -- Severity order error, warning, info.
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
