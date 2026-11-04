

SET client_encoding = 'UTF8';
BEGIN;
DO $$
DECLARE
    a uuid := 'd0000000-0000-0000-0000-000000000003';
    b uuid := 'd0000000-0000-0000-0000-000000000004';
    dup boolean := false;
BEGIN
    INSERT INTO compatibility_matrix (version_a_id, version_b_id, status) VALUES (b, a, 'compatible');
    ASSERT (SELECT count(*) FROM compatibility_matrix WHERE version_a_id = a AND version_b_id = b) = 1,
        'pair (B, A) was not stored as (A, B)';
    BEGIN
        INSERT INTO compatibility_matrix (version_a_id, version_b_id, status) VALUES (a, b, 'compatible');
    EXCEPTION WHEN unique_violation THEN
        dup := true;
    END;
    ASSERT dup, 'inserting (A, B) after (B, A) did not violate the unique constraint';
    RAISE NOTICE 'PASS 1 compat pair canonicalised';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    old_primary uuid := 'd0000000-0000-0000-0000-000000000002';
    new_primary uuid := 'd0000000-0000-0000-0000-000000000003';
BEGIN
    UPDATE mod_versions SET is_primary = TRUE WHERE version_id = new_primary;
    ASSERT NOT (SELECT is_primary FROM mod_versions WHERE version_id = old_primary), 'old primary still primary';
    ASSERT (SELECT is_primary FROM mod_versions WHERE version_id = new_primary), 'new version not primary';
    ASSERT (SELECT count(*) FROM mod_versions
            WHERE mod_id = 'c0000000-0000-0000-0000-000000000002' AND is_primary) = 1,
        'mod does not have exactly one primary version';
    RAISE NOTICE 'PASS 2 single primary version';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    raised boolean := false;
BEGIN
    BEGIN
        INSERT INTO loadout_mods (loadout_id, version_id)
        VALUES ('e0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000006');
    EXCEPTION WHEN raise_exception THEN
        raised := SQLERRM LIKE 'MODVAULT:GAME_MISMATCH: %';
    END;
    ASSERT raised, 'cross-game insert did not raise GAME_MISMATCH';
    RAISE NOTICE 'PASS 3 game mismatch rejected';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    m  uuid := 'c0000000-0000-0000-0000-000000000002';
    m2 uuid := 'c0000000-0000-0000-0000-000000000003';
BEGIN
    INSERT INTO reviews (user_id, mod_id, rating) VALUES
        ('b0000000-0000-0000-0000-000000000001', m, 5),
        ('b0000000-0000-0000-0000-000000000002', m, 4),
        ('b0000000-0000-0000-0000-000000000003', m, 4);
    ASSERT (SELECT mo.rating_avg = v.avg_rating AND mo.rating_count = v.review_count
            FROM mods mo JOIN mod_ratings_view v USING (mod_id) WHERE mo.mod_id = m),
        'rating cache does not match mod_ratings_view after inserts';
    ASSERT (SELECT rating_avg FROM mods WHERE mod_id = m) = 4.33, 'rating_avg is not 4.33';
    UPDATE reviews SET mod_id = m2 WHERE user_id = 'b0000000-0000-0000-0000-000000000001' AND mod_id = m;
    ASSERT (SELECT count(*) FROM mods mo JOIN mod_ratings_view v USING (mod_id)
            WHERE mo.mod_id IN (m, m2)
              AND mo.rating_count = v.review_count AND mo.rating_avg = v.avg_rating) = 2,
        'rating cache wrong for OLD or NEW mod after update';
    DELETE FROM reviews WHERE mod_id = m2;
    ASSERT (SELECT rating_avg = 0 AND rating_count = 0 FROM mods WHERE mod_id = m2),
        'rating cache not reset after deleting the last review';
    RAISE NOTICE 'PASS 4 rating rollup';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    actor uuid := 'b0000000-0000-0000-0000-000000000003';
    target uuid := 'b0000000-0000-0000-0000-000000000001';
    a audit_log;
BEGIN
    PERFORM set_config('app.user_id', actor::text, true);
    UPDATE users SET email = 'fx_modder_new@example.com' WHERE user_id = target;
    SELECT * INTO a FROM audit_log ORDER BY audit_id DESC LIMIT 1;
    ASSERT a.table_name = 'users' AND a.operation = 'U' AND a.row_pk = target, 'newest audit row is not the user update';
    ASSERT NOT (a.old_row ? 'password_hash') AND NOT (a.new_row ? 'password_hash'), 'audit row contains password_hash';
    ASSERT a.new_row ->> 'email' = 'fx_modder_new@example.com', 'audit row does not hold the new email';
    ASSERT a.changed_by = actor, 'changed_by is not the session user';
    RAISE NOTICE 'PASS 5 audit row without password_hash';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    raised boolean := false;
BEGIN
    ASSERT (SELECT count(*) FROM audit_log) > 0, 'audit_log is empty; load fixtures first';
    BEGIN
        DELETE FROM audit_log;
    EXCEPTION WHEN raise_exception THEN
        raised := SQLERRM LIKE 'MODVAULT:FORBIDDEN: %';
    END;
    ASSERT raised, 'DELETE FROM audit_log did not raise FORBIDDEN';
    RAISE NOTICE 'PASS 6 audit log is append-only';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    l uuid := gen_random_uuid();
BEGIN
    INSERT INTO loadouts (loadout_id, user_id, game_id, name)
    VALUES (l, 'b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'FX empty loadout');
    INSERT INTO loadout_mods (loadout_id, version_id) VALUES (l, 'd0000000-0000-0000-0000-000000000001');
    INSERT INTO loadout_mods (loadout_id, version_id) VALUES (l, 'd0000000-0000-0000-0000-000000000002');
    ASSERT (SELECT array_agg(position ORDER BY position) FROM loadout_mods WHERE loadout_id = l) = ARRAY[0, 1],
        'positions are not 0 and 1';
    RAISE NOTICE 'PASS 7 auto position';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    raised boolean := false;
BEGIN
    ASSERT (SELECT count(*) FROM audit_log) > 0, 'audit_log is empty; load fixtures first';
    BEGIN
        UPDATE audit_log SET old_row = '{"tampered": true}'
        WHERE audit_id = (SELECT min(audit_id) FROM audit_log);
    EXCEPTION WHEN raise_exception THEN
        raised := SQLERRM LIKE 'MODVAULT:FORBIDDEN: %';
    END;
    ASSERT raised, 'UPDATE of audit_log.old_row did not raise FORBIDDEN';
    RAISE NOTICE 'PASS 8 audit row old_row cannot be changed';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    u      uuid := gen_random_uuid();
    before audit_log;
    after  audit_log;
BEGIN
    INSERT INTO users (user_id, username, email, password_hash)
    VALUES (u, 'fx_temp', 'fx_temp@example.com', crypt('fixture-pass', gen_salt('bf', 4)));

    PERFORM set_config('app.user_id', u::text, true);
    UPDATE loadouts SET description = 'edited by fx_temp'
    WHERE loadout_id = 'e0000000-0000-0000-0000-000000000001';
    SELECT * INTO before FROM audit_log ORDER BY audit_id DESC LIMIT 1;
    ASSERT before.table_name = 'loadouts' AND before.changed_by = u, 'audit row for the change is missing';
    PERFORM set_config('app.user_id', 'b0000000-0000-0000-0000-000000000003', true);
    DELETE FROM users WHERE user_id = u;
    ASSERT NOT EXISTS (SELECT 1 FROM users WHERE user_id = u), 'user was not deleted';

    SELECT * INTO after FROM audit_log WHERE audit_id = before.audit_id;
    ASSERT after.changed_by IS NULL, 'changed_by was not set to NULL';
    ASSERT after.old_row = before.old_row AND after.new_row = before.new_row, 'old_row or new_row changed';
    RAISE NOTICE 'PASS 9 user delete nulls changed_by only';
END $$;
ROLLBACK;
