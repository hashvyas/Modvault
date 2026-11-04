

SET client_encoding = 'UTF8';
BEGIN;
INSERT INTO loadouts (loadout_id, user_id, game_id, name)
VALUES ('e0000000-0000-0000-0000-0000000000b1', 'b0000000-0000-0000-0000-000000000002',
        'a0000000-0000-0000-0000-000000000001', 'FX B private');
INSERT INTO loadout_mods (loadout_id, version_id)
VALUES ('e0000000-0000-0000-0000-0000000000b1', 'd0000000-0000-0000-0000-000000000001');
SET LOCAL ROLE modvault_app;
DO $$
DECLARE
    b uuid := 'e0000000-0000-0000-0000-0000000000b1';
BEGIN
    PERFORM set_config('app.user_id', 'b0000000-0000-0000-0000-000000000001', true);
    PERFORM set_config('app.role', 'modder', true);

    ASSERT (SELECT count(*) FROM loadouts WHERE loadout_id = b) = 0, 'B''s private loadout is visible';
    ASSERT (SELECT count(*) FROM loadout_mods WHERE loadout_id = b) = 0, 'B''s loadout rows are visible';
    ASSERT (SELECT count(*) FROM loadout_summary_view WHERE loadout_id = b) = 0, 'summary view leaks B''s loadout';
    ASSERT (SELECT count(*) FROM loadout_health_view WHERE loadout_id = b) = 0, 'health view leaks B''s loadout';
    ASSERT fn_export_loadout(b) IS NULL, 'export leaks B''s loadout';

    ASSERT (SELECT count(*) FROM loadouts WHERE loadout_id = 'e0000000-0000-0000-0000-000000000001') = 1,
        'A cannot see own loadout';
    ASSERT (SELECT count(*) FROM loadouts WHERE loadout_id = 'e0000000-0000-0000-0000-000000000002') = 1,
        'A cannot see a public loadout';
    UPDATE loadouts SET name = 'hijack' WHERE loadout_id = 'e0000000-0000-0000-0000-000000000002';
    ASSERT NOT FOUND, 'A renamed a public loadout of another user';
    PERFORM set_config('app.user_id', 'b0000000-0000-0000-0000-000000000002', true);
    PERFORM set_config('app.role', 'curator', true);
    ASSERT (SELECT count(*) FROM loadouts WHERE loadout_id = 'e0000000-0000-0000-0000-000000000001') = 0,
        'A''s private loadout is visible to B';
    ASSERT (SELECT count(*) FROM loadout_summary_view WHERE loadout_id = 'e0000000-0000-0000-0000-000000000001') = 0,
        'summary view leaks A''s loadout to B';
    ASSERT (SELECT count(*) FROM loadout_health_view WHERE loadout_id = 'e0000000-0000-0000-0000-000000000001') = 0,
        'health view leaks A''s loadout to B';
    ASSERT (SELECT count(*) FROM loadout_summary_view WHERE loadout_id = 'e0000000-0000-0000-0000-0000000000b1') = 1
       AND (SELECT count(*) FROM loadout_health_view  WHERE loadout_id = 'e0000000-0000-0000-0000-0000000000b1') = 1,
        'B cannot see own loadout in the views';
    RAISE NOTICE 'PASS 1 private loadouts are hidden in both directions, tables and views';
END $$;
ROLLBACK;
BEGIN;
INSERT INTO loadouts (loadout_id, user_id, game_id, name)
VALUES ('e0000000-0000-0000-0000-0000000000b1', 'b0000000-0000-0000-0000-000000000002',
        'a0000000-0000-0000-0000-000000000001', 'FX B private');
SET LOCAL ROLE modvault_app;
DO $$
BEGIN
    PERFORM set_config('app.user_id', 'b0000000-0000-0000-0000-000000000003', true);
    PERFORM set_config('app.role', 'admin', true);
    ASSERT (SELECT count(*) FROM loadouts WHERE loadout_id = 'e0000000-0000-0000-0000-0000000000b1') = 1,
        'admin cannot see a private loadout';
    RAISE NOTICE 'PASS 2 admin sees private loadouts';
END $$;
ROLLBACK;
BEGIN;
SET LOCAL ROLE modvault_app;
DO $$
DECLARE
    denied boolean := false;
BEGIN
    PERFORM username, email, role FROM users;
    BEGIN
        PERFORM password_hash FROM users;
    EXCEPTION WHEN insufficient_privilege THEN denied := true;
    END;
    ASSERT denied, 'SELECT password_hash did not raise permission denied';
    RAISE NOTICE 'PASS 3 password_hash is not readable';
END $$;
ROLLBACK;
BEGIN;
SET LOCAL ROLE modvault_app;
DO $$
DECLARE
    denied boolean := false;
BEGIN
    PERFORM set_config('app.user_id', 'b0000000-0000-0000-0000-000000000001', true);
    PERFORM set_config('app.role', 'modder', true);
    BEGIN
        INSERT INTO compatibility_matrix (version_a_id, version_b_id, status)
        VALUES ('d0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000005', 'compatible');
    EXCEPTION WHEN insufficient_privilege THEN denied := true;
    END;
    ASSERT denied, 'modder inserted into compatibility_matrix';

    denied := false;
    BEGIN
        INSERT INTO mod_dependencies (dependent_version_id, required_mod_id)
        VALUES ('d0000000-0000-0000-0000-000000000005', 'c0000000-0000-0000-0000-000000000003');
    EXCEPTION WHEN insufficient_privilege THEN denied := true;
    END;
    ASSERT denied, 'modder inserted into mod_dependencies';

    PERFORM set_config('app.user_id', 'b0000000-0000-0000-0000-000000000002', true);
    PERFORM set_config('app.role', 'curator', true);
    CALL pr_upsert_compatibility('d0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000005',
                                 'compatible', NULL);
    ASSERT (SELECT count(*) FROM compatibility_matrix
            WHERE version_a_id = 'd0000000-0000-0000-0000-000000000001'
              AND version_b_id = 'd0000000-0000-0000-0000-000000000005') = 1, 'curator upsert failed under RLS';
    RAISE NOTICE 'PASS 4 compatibility writes need curator or admin';
END $$;
ROLLBACK;
BEGIN;
SET LOCAL ROLE modvault_app;
DO $$
DECLARE
    denied boolean := false;
BEGIN
    PERFORM set_config('app.user_id', 'b0000000-0000-0000-0000-000000000001', true);
    PERFORM set_config('app.role', 'modder', true);
    INSERT INTO reviews (user_id, mod_id, rating) VALUES ('b0000000-0000-0000-0000-000000000001',
                                                          'c0000000-0000-0000-0000-000000000002', 5);
    BEGIN
        INSERT INTO reviews (user_id, mod_id, rating) VALUES ('b0000000-0000-0000-0000-000000000002',
                                                              'c0000000-0000-0000-0000-000000000002', 1);
    EXCEPTION WHEN insufficient_privilege THEN denied := true;
    END;
    ASSERT denied, 'modder wrote a review as another user';
    ASSERT (SELECT rating_count FROM mods WHERE mod_id = 'c0000000-0000-0000-0000-000000000002') = 1,
        'rating rollup did not run under the app role';
    RAISE NOTICE 'PASS 5 reviews belong to their author';
END $$;
ROLLBACK;
BEGIN;
SET LOCAL ROLE modvault_app;
DO $$
DECLARE
    denied boolean := false;
BEGIN
    PERFORM set_config('app.role', 'modder', true);
    ASSERT (SELECT count(*) FROM audit_log) = 0, 'modder can read audit_log';
    PERFORM set_config('app.role', 'admin', true);
    ASSERT (SELECT count(*) FROM audit_log) > 0, 'admin cannot read audit_log';
    BEGIN
        INSERT INTO audit_log (table_name, operation) VALUES ('x', 'I');
    EXCEPTION WHEN insufficient_privilege THEN denied := true;
    END;
    ASSERT denied, 'app role inserted into audit_log';
    RAISE NOTICE 'PASS 6 audit_log is admin read-only';
END $$;
ROLLBACK;
BEGIN;
SET LOCAL ROLE modvault_app;
DO $$
DECLARE
    l uuid;
    s int;
    m uuid;
    v uuid;
BEGIN
    PERFORM set_config('app.user_id', 'b0000000-0000-0000-0000-000000000001', true);
    PERFORM set_config('app.role', 'modder', true);

    CALL pr_add_mod_to_loadout('e0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000005');
    CALL pr_apply_load_order('e0000000-0000-0000-0000-000000000001');
    CALL pr_import_loadout(fn_export_loadout('e0000000-0000-0000-0000-000000000001'), l, s);
    ASSERT s = 0 AND (SELECT count(*) FROM loadout_mods WHERE loadout_id = l) = 4, 'import under app role failed';
    ASSERT fn_loadout_health_score(l) BETWEEN 0 AND 100, 'health score failed under app role';
    CALL pr_publish_mod('a0000000-0000-0000-0000-000000000001', 'FX App Mod', 's', 'c', '1.0.0',
                        ARRAY['fx-app-tag'], NULL, m);
    PERFORM set_config('app.user_id', 'b0000000-0000-0000-0000-000000000002', true);
    PERFORM set_config('app.role', 'curator', true);
    SELECT version_id INTO v FROM mod_versions WHERE mod_id = m;
    CALL pr_promote_version(v);
    RAISE NOTICE 'PASS 7 procedures work under the app role';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    leaked text;
BEGIN
    SELECT string_agg(p.oid::regprocedure::text, ', ') INTO leaked
    FROM   pg_proc p
    WHERE  p.pronamespace = 'public'::regnamespace AND p.prosecdef
      AND  has_function_privilege('public', p.oid, 'EXECUTE');
    ASSERT leaked IS NULL, format('PUBLIC can execute SECURITY DEFINER routines: %s', leaked);

    SELECT string_agg(p.oid::regprocedure::text, ', ') INTO leaked
    FROM   pg_proc p
    WHERE  p.pronamespace = 'public'::regnamespace AND p.prosecdef
      AND  NOT has_function_privilege('modvault_app', p.oid, 'EXECUTE');
    ASSERT leaked IS NULL, format('modvault_app cannot execute: %s', leaked);
END $$;

SET LOCAL ROLE modvault_app;
DO $$
DECLARE
    audits_before bigint;
BEGIN
    PERFORM set_config('app.user_id', 'b0000000-0000-0000-0000-000000000001', true);
    PERFORM set_config('app.role', 'modder', true);
    ASSERT (SELECT count(*) FROM fn_authenticate('fx_modder', 'fixture-pass')) = 1,
        'fn_authenticate failed under the app role';

    SET LOCAL ROLE modvault_owner;
    SELECT count(*) INTO audits_before FROM audit_log;
    SET LOCAL ROLE modvault_app;
    DELETE FROM reviews WHERE user_id = 'b0000000-0000-0000-0000-000000000001'
                          AND mod_id = 'c0000000-0000-0000-0000-000000000002';
    INSERT INTO reviews (user_id, mod_id, rating) VALUES
        ('b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002', 4);
    ASSERT (SELECT rating_count FROM mods WHERE mod_id = 'c0000000-0000-0000-0000-000000000002')
         = (SELECT count(*) FROM reviews WHERE mod_id = 'c0000000-0000-0000-0000-000000000002'),
        'rating rollup trigger did not run under the app role';

    SET LOCAL ROLE modvault_owner;
    ASSERT (SELECT count(*) FROM audit_log) > audits_before, 'audit trigger did not run under the app role';
    RAISE NOTICE 'PASS 8 SECURITY DEFINER routines: no PUBLIC execute, app role and triggers work';
END $$;
ROLLBACK;
