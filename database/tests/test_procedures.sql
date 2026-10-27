-- =============================================================================
-- ModVault: A Mod Repository and Compatibility Intelligence System
-- Procedure tests  --  tests/test_procedures.sql
--
-- Covers fn_export_loadout and every pr_ procedure: export then import gives
-- an equal manifest, a bad entry is skipped, role checks raise FORBIDDEN,
-- the compatibility upsert writes verified_by, and so on.
--
-- Each check runs inside BEGIN ... ROLLBACK and leaves no data behind.
-- A failed ASSERT stops the run (ON_ERROR_STOP=1). Each passing check prints
-- a NOTICE starting with PASS.
--
-- Fixture rows used: b..01 fx_modder, b..02 fx_curator, b..03 fx_admin,
-- e..01 fx_modder's private game A loadout (d1, d2, d4 at positions 0, 1, 2).
--
-- HOW TO RUN (after run_all.sql and tests/fixtures.sql)
--   psql "postgresql://modvault_owner:modvault_owner_dev@localhost:5432/modvault" -v ON_ERROR_STOP=1 -f database/tests/test_procedures.sql
-- =============================================================================

SET client_encoding = 'UTF8';


-- 1. Export, import, export again: the two manifests are equal.
BEGIN;
DO $$
DECLARE
    m1 jsonb;
    m2 jsonb;
    l  uuid;
    s  int;
BEGIN
    PERFORM set_config('app.user_id', 'b0000000-0000-0000-0000-000000000001', true);
    m1 := fn_export_loadout('e0000000-0000-0000-0000-000000000001');
    ASSERT m1 ->> 'format' = 'modvault-loadout/1' AND m1 ->> 'game_domain' = 'fx-game-a'
       AND jsonb_array_length(m1 -> 'mods') = 3, 'export has the wrong shape';
    ASSERT m1 -> 'mods' -> 0 = '{"nexus_mod_id": "fx-1", "semver": "2.2.6", "position": 0, "enabled": true}',
        'first exported mod is wrong';

    CALL pr_import_loadout(m1, l, s);
    ASSERT l IS NOT NULL AND s = 0, 'clean import skipped entries';
    ASSERT (SELECT user_id FROM loadouts WHERE loadout_id = l) = 'b0000000-0000-0000-0000-000000000001',
        'imported loadout does not belong to the current user';
    m2 := fn_export_loadout(l);
    ASSERT m1 = m2, format('manifests differ: %s vs %s', m1, m2);
    ASSERT fn_export_loadout(gen_random_uuid()) IS NULL, 'unknown loadout exported something';
    RAISE NOTICE 'PASS 1 export then import gives an equal manifest';
END $$;
ROLLBACK;


-- 2. One unresolved and one broken entry are skipped; the rest is imported.
--    An unknown semver falls back to the primary version.
BEGIN;
DO $$
DECLARE
    l uuid;
    s int;
BEGIN
    PERFORM set_config('app.user_id', 'b0000000-0000-0000-0000-000000000001', true);
    CALL pr_import_loadout('{
        "format": "modvault-loadout/1", "name": "FX import", "game_domain": "fx-game-a",
        "mods": [
            {"nexus_mod_id": "fx-1",    "semver": "2.2.6", "position": 0, "enabled": true},
            {"nexus_mod_id": "no-such", "semver": "1.0.0", "position": 1, "enabled": true},
            {"nexus_mod_id": "fx-2",    "semver": "9.9.9", "position": 2, "enabled": false}
        ]}'::jsonb, l, s);
    ASSERT s = 1, format('expected p_skipped = 1, got %s', s);
    ASSERT (SELECT count(*) FROM loadout_mods WHERE loadout_id = l) = 2, 'expected 2 imported rows';
    ASSERT EXISTS (SELECT 1 FROM loadout_mods WHERE loadout_id = l
                   AND version_id = 'd0000000-0000-0000-0000-000000000002' AND position = 2 AND NOT enabled),
        'unknown semver did not fall back to the primary version, or position/enabled were lost';

    -- A bad position is caught by the entry's own exception block.
    CALL pr_import_loadout('{
        "format": "modvault-loadout/1", "name": "FX import 2", "game_domain": "fx-game-a",
        "mods": [
            {"nexus_mod_id": "fx-1", "semver": "2.2.6", "position": 0},
            {"nexus_mod_id": "fx-3", "semver": "4.3.0", "position": -5}
        ]}'::jsonb, l, s);
    ASSERT s = 1 AND (SELECT count(*) FROM loadout_mods WHERE loadout_id = l) = 1,
        'a failing insert was not skipped';

    -- The same mod twice at different versions: the first entry wins.
    CALL pr_import_loadout('{
        "format": "modvault-loadout/1", "name": "FX import 3", "game_domain": "fx-game-a",
        "mods": [
            {"nexus_mod_id": "fx-2", "semver": "5.1.0", "position": 0},
            {"nexus_mod_id": "fx-2", "semver": "5.2.0", "position": 1}
        ]}'::jsonb, l, s);
    ASSERT s = 1 AND (SELECT array_agg(version_id) FROM loadout_mods WHERE loadout_id = l)
                     = ARRAY['d0000000-0000-0000-0000-000000000003'::uuid],
        'a second version of the same mod was imported';
    RAISE NOTICE 'PASS 2 bad entries are skipped';
END $$;
ROLLBACK;


-- 3. Import errors: wrong format, unknown game, no user.
BEGIN;
DO $$
DECLARE
    l uuid;
    s int;
    msg text;
BEGIN
    PERFORM set_config('app.user_id', 'b0000000-0000-0000-0000-000000000001', true);
    BEGIN
        CALL pr_import_loadout('{"format": "other/1", "name": "x", "game_domain": "fx-game-a", "mods": []}', l, s);
    EXCEPTION WHEN raise_exception THEN msg := SQLERRM; END;
    ASSERT msg LIKE 'MODVAULT:INVALID_MANIFEST: %', 'wrong format did not raise INVALID_MANIFEST';

    msg := NULL;
    BEGIN
        CALL pr_import_loadout('{"format": "modvault-loadout/1", "name": "x", "game_domain": "nope", "mods": []}', l, s);
    EXCEPTION WHEN raise_exception THEN msg := SQLERRM; END;
    ASSERT msg LIKE 'MODVAULT:INVALID_MANIFEST: %', 'unknown game did not raise INVALID_MANIFEST';

    msg := NULL;
    PERFORM set_config('app.user_id', '', true);
    BEGIN
        CALL pr_import_loadout('{"format": "modvault-loadout/1", "name": "x", "game_domain": "fx-game-a", "mods": []}', l, s);
    EXCEPTION WHEN raise_exception THEN msg := SQLERRM; END;
    ASSERT msg LIKE 'MODVAULT:FORBIDDEN: %', 'anonymous import did not raise FORBIDDEN';
    RAISE NOTICE 'PASS 3 import errors';
END $$;
ROLLBACK;


-- 4. A modder may not record compatibility.
BEGIN;
DO $$
DECLARE
    msg text;
BEGIN
    PERFORM set_config('app.user_id', 'b0000000-0000-0000-0000-000000000001', true);
    PERFORM set_config('app.role', 'modder', true);
    BEGIN
        CALL pr_upsert_compatibility('d0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000005',
                                     'compatible', NULL);
    EXCEPTION WHEN raise_exception THEN msg := SQLERRM; END;
    ASSERT msg LIKE 'MODVAULT:FORBIDDEN: %', 'modder upsert did not raise FORBIDDEN';
    RAISE NOTICE 'PASS 4 modder upsert raises FORBIDDEN';
END $$;
ROLLBACK;


-- 5. A curator inserts a new pair and updates an existing one given in reverse order.
BEGIN;
DO $$
BEGIN
    PERFORM set_config('app.user_id', 'b0000000-0000-0000-0000-000000000002', true);
    PERFORM set_config('app.role', 'curator', true);

    CALL pr_upsert_compatibility('d0000000-0000-0000-0000-000000000005', 'd0000000-0000-0000-0000-000000000001',
                                 'partial', '{"reason": "test"}');
    ASSERT (SELECT verified_by FROM compatibility_matrix
            WHERE version_a_id = 'd0000000-0000-0000-0000-000000000001'
              AND version_b_id = 'd0000000-0000-0000-0000-000000000005' AND status = 'partial')
           = 'b0000000-0000-0000-0000-000000000002', 'new pair not written with verified_by';

    -- (d2, d5) is stored; pass it as (d5, d2).
    CALL pr_upsert_compatibility('d0000000-0000-0000-0000-000000000005', 'd0000000-0000-0000-0000-000000000002',
                                 'compatible', NULL);
    ASSERT (SELECT count(*) FROM compatibility_matrix
            WHERE 'd0000000-0000-0000-0000-000000000002' IN (version_a_id, version_b_id)
              AND 'd0000000-0000-0000-0000-000000000005' IN (version_a_id, version_b_id)) = 1,
        'reverse pair created a second row';
    ASSERT (SELECT status = 'compatible' AND conflict_detail IS NULL FROM compatibility_matrix
            WHERE version_a_id = 'd0000000-0000-0000-0000-000000000002'
              AND version_b_id = 'd0000000-0000-0000-0000-000000000005'), 'existing pair not updated';
    RAISE NOTICE 'PASS 5 curator upsert writes verified_by';
END $$;
ROLLBACK;


-- 6. pr_add_mod_to_loadout: swap version in place, append a new mod, guard rails.
BEGIN;
DO $$
DECLARE
    msg text;
BEGIN
    PERFORM set_config('app.user_id', 'b0000000-0000-0000-0000-000000000001', true);

    -- SkyUI 5.2.0 (d2, position 1) becomes 5.1.0 (d3) and keeps position 1.
    CALL pr_add_mod_to_loadout('e0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000003');
    ASSERT (SELECT position FROM loadout_mods WHERE loadout_id = 'e0000000-0000-0000-0000-000000000001'
            AND version_id = 'd0000000-0000-0000-0000-000000000003') = 1, 'version swap lost the position';
    ASSERT NOT EXISTS (SELECT 1 FROM loadout_mods WHERE loadout_id = 'e0000000-0000-0000-0000-000000000001'
                       AND version_id = 'd0000000-0000-0000-0000-000000000002'), 'old version still in loadout';

    -- New mod appends at position 3. Adding it again changes nothing.
    CALL pr_add_mod_to_loadout('e0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000005');
    CALL pr_add_mod_to_loadout('e0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000005');
    ASSERT (SELECT position FROM loadout_mods WHERE loadout_id = 'e0000000-0000-0000-0000-000000000001'
            AND version_id = 'd0000000-0000-0000-0000-000000000005') = 3, 'new mod was not appended';
    ASSERT (SELECT count(*) FROM loadout_mods WHERE loadout_id = 'e0000000-0000-0000-0000-000000000001') = 4,
        'loadout should hold 4 rows';

    BEGIN
        CALL pr_add_mod_to_loadout('e0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000006');
    EXCEPTION WHEN raise_exception THEN msg := SQLERRM; END;
    ASSERT msg LIKE 'MODVAULT:GAME_MISMATCH: %', 'game mismatch not raised';

    msg := NULL;
    BEGIN
        CALL pr_add_mod_to_loadout(gen_random_uuid(), 'd0000000-0000-0000-0000-000000000005');
    EXCEPTION WHEN raise_exception THEN msg := SQLERRM; END;
    ASSERT msg LIKE 'MODVAULT:NOT_FOUND: %', 'unknown loadout did not raise NOT_FOUND';

    -- e..02 belongs to fx_admin.
    msg := NULL;
    BEGIN
        CALL pr_add_mod_to_loadout('e0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000008');
    EXCEPTION WHEN raise_exception THEN msg := SQLERRM; END;
    ASSERT msg LIKE 'MODVAULT:FORBIDDEN: %', 'foreign loadout did not raise FORBIDDEN';
    RAISE NOTICE 'PASS 6 pr_add_mod_to_loadout';
END $$;
ROLLBACK;


-- 7. pr_apply_load_order writes the suggested order: SkyUI after its requirement.
BEGIN;
DO $$
BEGIN
    UPDATE loadout_mods SET position = CASE version_id
        WHEN 'd0000000-0000-0000-0000-000000000002' THEN 0
        WHEN 'd0000000-0000-0000-0000-000000000004' THEN 1
        ELSE 2 END
    WHERE loadout_id = 'e0000000-0000-0000-0000-000000000001';

    CALL pr_apply_load_order('e0000000-0000-0000-0000-000000000001');
    ASSERT NOT EXISTS (
        SELECT 1 FROM fn_suggest_load_order('e0000000-0000-0000-0000-000000000001') s
        JOIN loadout_mods x ON x.version_id = s.version_id AND x.loadout_id = 'e0000000-0000-0000-0000-000000000001'
        WHERE x.position <> s.suggested_position), 'positions do not match the suggestion';
    ASSERT (SELECT count(*) FROM fn_check_loadout_compatibility('e0000000-0000-0000-0000-000000000001')
            WHERE issue_type = 'LOAD_ORDER') = 0, 'LOAD_ORDER issue remains after applying';
    RAISE NOTICE 'PASS 7 pr_apply_load_order';
END $$;
ROLLBACK;


-- 8. pr_promote_version: a modder is refused, a curator moves the primary flag.
BEGIN;
DO $$
DECLARE
    msg text;
BEGIN
    PERFORM set_config('app.user_id', 'b0000000-0000-0000-0000-000000000001', true);
    PERFORM set_config('app.role', 'modder', true);
    BEGIN
        CALL pr_promote_version('d0000000-0000-0000-0000-000000000003');
    EXCEPTION WHEN raise_exception THEN msg := SQLERRM; END;
    ASSERT msg LIKE 'MODVAULT:FORBIDDEN: %', 'modder promote did not raise FORBIDDEN';
    ASSERT (SELECT is_primary FROM mod_versions WHERE version_id = 'd0000000-0000-0000-0000-000000000002'),
        'refused promote still changed the primary';

    msg := NULL;
    PERFORM set_config('app.user_id', 'b0000000-0000-0000-0000-000000000002', true);
    PERFORM set_config('app.role', 'curator', true);
    CALL pr_promote_version('d0000000-0000-0000-0000-000000000003');
    ASSERT (SELECT array_agg(version_id) FROM mod_versions
            WHERE mod_id = 'c0000000-0000-0000-0000-000000000002' AND is_primary)
           = ARRAY['d0000000-0000-0000-0000-000000000003']::uuid[], 'promotion did not leave exactly the new primary';
    BEGIN
        CALL pr_promote_version(gen_random_uuid());
    EXCEPTION WHEN raise_exception THEN msg := SQLERRM; END;
    ASSERT msg LIKE 'MODVAULT:NOT_FOUND: %', 'unknown version did not raise NOT_FOUND';
    RAISE NOTICE 'PASS 8 pr_promote_version: modder refused, curator promotes';
END $$;
ROLLBACK;


-- 9. pr_publish_mod: needs a user; writes mod, primary version and tags.
BEGIN;
DO $$
DECLARE
    m   uuid;
    msg text;
BEGIN
    BEGIN
        CALL pr_publish_mod('a0000000-0000-0000-0000-000000000001', 'FX New', 's', 'c', '1.0.0', NULL, NULL, m);
    EXCEPTION WHEN raise_exception THEN msg := SQLERRM; END;
    ASSERT msg LIKE 'MODVAULT:FORBIDDEN: %', 'anonymous publish did not raise FORBIDDEN';

    INSERT INTO tags (name, slug) VALUES ('FX Existing', 'fx-existing');
    PERFORM set_config('app.user_id', 'b0000000-0000-0000-0000-000000000001', true);
    CALL pr_publish_mod('a0000000-0000-0000-0000-000000000001', 'FX New', 'A new mod', 'Gameplay', '1.0.0',
                        ARRAY['fx-existing', 'fx-brand-new', 'fx-brand-new', ' '], NULL, m);
    ASSERT (SELECT author_id FROM mods WHERE mod_id = m) = 'b0000000-0000-0000-0000-000000000001', 'author not set';
    ASSERT (SELECT count(*) FROM mod_versions WHERE mod_id = m AND is_primary AND semver = '1.0.0') = 1,
        'primary version not created';
    ASSERT (SELECT array_agg(t.slug::text ORDER BY t.slug) FROM mod_tags mt JOIN tags t ON t.tag_id = mt.tag_id
            WHERE mt.mod_id = m) = ARRAY['fx-brand-new', 'fx-existing'], 'tags not linked';
    RAISE NOTICE 'PASS 9 pr_publish_mod';
END $$;
ROLLBACK;


-- 10. Admin only: pr_set_user_role and pr_refresh_reports.
BEGIN;
DO $$
DECLARE
    msg text;
BEGIN
    PERFORM set_config('app.role', 'curator', true);
    BEGIN
        CALL pr_set_user_role('b0000000-0000-0000-0000-000000000001', 'curator');
    EXCEPTION WHEN raise_exception THEN msg := SQLERRM; END;
    ASSERT msg LIKE 'MODVAULT:FORBIDDEN: %', 'curator changed a role';

    msg := NULL;
    BEGIN
        CALL pr_refresh_reports();
    EXCEPTION WHEN raise_exception THEN msg := SQLERRM; END;
    ASSERT msg LIKE 'MODVAULT:FORBIDDEN: %', 'curator refreshed reports';

    PERFORM set_config('app.role', 'admin', true);
    CALL pr_set_user_role('b0000000-0000-0000-0000-000000000001', 'curator');
    ASSERT (SELECT role FROM users WHERE user_id = 'b0000000-0000-0000-0000-000000000001') = 'curator',
        'role not changed';
    CALL pr_refresh_reports();

    msg := NULL;
    BEGIN
        CALL pr_set_user_role(gen_random_uuid(), 'curator');
    EXCEPTION WHEN raise_exception THEN msg := SQLERRM; END;
    ASSERT msg LIKE 'MODVAULT:NOT_FOUND: %', 'unknown user did not raise NOT_FOUND';
    RAISE NOTICE 'PASS 10 admin-only procedures';
END $$;
ROLLBACK;
