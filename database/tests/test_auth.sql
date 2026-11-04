

SET client_encoding = 'UTF8';
BEGIN;
DO $$
DECLARE
    u uuid;
    r record;
BEGIN
    u := fn_register_user('fx_newbie', 'fx_newbie@example.com', 'correct-horse');
    ASSERT u IS NOT NULL, 'register returned NULL';
    ASSERT (SELECT password_hash LIKE '$2a$10$%' FROM users WHERE user_id = u), 'password is not a bcrypt cost 10 hash';
    SELECT * INTO r FROM fn_authenticate('fx_newbie', 'correct-horse');
    ASSERT r.user_id = u AND r.username = 'fx_newbie' AND r.role = 'modder', 'authenticate did not return the new modder';
    RAISE NOTICE 'PASS 1 register then authenticate';
END $$;
ROLLBACK;
BEGIN;
DO $$
BEGIN
    ASSERT (SELECT count(*) FROM fn_authenticate('fx_modder', 'fixture-pass')) = 1, 'fixture user cannot log in';
    ASSERT (SELECT count(*) FROM fn_authenticate('fx_modder', 'wrong-pass')) = 0, 'wrong password returned a row';
    ASSERT (SELECT count(*) FROM fn_authenticate('fx_nobody', 'fixture-pass')) = 0, 'unknown user returned a row';
    ASSERT (SELECT count(*) FROM fn_authenticate(NULL, NULL)) = 0, 'NULL input returned a row';
    UPDATE users SET is_active = FALSE WHERE username = 'fx_modder';
    ASSERT (SELECT count(*) FROM fn_authenticate('fx_modder', 'fixture-pass')) = 0, 'inactive user returned a row';
    RAISE NOTICE 'PASS 2 failed logins return zero rows';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    raised_user  boolean := false;
    raised_email boolean := false;
BEGIN
    BEGIN
        PERFORM fn_register_user('fx_modder', 'someone_else@example.com', 'correct-horse');
    EXCEPTION WHEN raise_exception THEN
        raised_user := SQLERRM LIKE 'MODVAULT:DUPLICATE: %';
    END;
    BEGIN
        PERFORM fn_register_user('fx_someone', 'fx_modder@example.com', 'correct-horse');
    EXCEPTION WHEN raise_exception THEN
        raised_email := SQLERRM LIKE 'MODVAULT:DUPLICATE: email%';
    END;
    ASSERT raised_user, 'duplicate username did not raise DUPLICATE';
    ASSERT raised_email, 'duplicate email did not raise DUPLICATE';
    RAISE NOTICE 'PASS 3 duplicate raises DUPLICATE';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    c record;
    raised boolean;
BEGIN
    FOR c IN SELECT * FROM (VALUES
        ('ab',           'fx_ok@example.com', 'correct-horse'),
        ('bad name',     'fx_ok@example.com', 'correct-horse'),
        ('fx_ok',        'no-at-sign',        'correct-horse'),
        ('fx_ok',        'fx_ok@example.com', 'short'),
        (NULL,           'fx_ok@example.com', 'correct-horse')
    ) AS t(username, email, password)
    LOOP
        raised := false;
        BEGIN
            PERFORM fn_register_user(c.username, c.email, c.password);
        EXCEPTION WHEN raise_exception THEN
            raised := SQLERRM LIKE 'MODVAULT:INVALID_INPUT: %';
        END;
        ASSERT raised, format('no INVALID_INPUT for (%s, %s, %s)', c.username, c.email, c.password);
    END LOOP;
    RAISE NOTICE 'PASS 4 invalid input raises INVALID_INPUT';
END $$;
ROLLBACK;
DO $$
DECLARE
    c record;
    n int := 0;
BEGIN
    FOR c IN SELECT * FROM (VALUES
        ('1.10.0',  '>=1.9',   true),
        ('2.0.0',   '^1.0',    false),
        ('v1.2',    '=1.2.0',  true),
        ('1.5.0',   '^1.2',    true),
        ('1.1.0',   '^1.2',    false),
        ('1.2.3',   '>1.2.3',  false),
        ('1.2.4',   '>1.2.3',  true),
        ('1.2.3',   '<=1.2.3', true),
        ('1.2.3',   '<1.2.3',  false),
        ('1.2.2',   '<1.2.3',  true),
        ('2.2.6',   '2.2',     true),
        ('2.1.0',   '2.2',     false),
        ('1.2.3',   '*',       true),
        ('1.2.3',   NULL,      true),
        ('1.2.3',   '',        true),
        ('abc',     '>=1.0',   true),
        ('1.2.0.1', '=1.2.0',  false),
        ('0.6.23',  '>= 0.6',  true)
    ) AS t(installed, cons, expected)
    LOOP
        ASSERT fn_semver_satisfies(c.installed, c.cons) = c.expected,
            format('fn_semver_satisfies(%L, %L) is not %s', c.installed, c.cons, c.expected);
        n := n + 1;
    END LOOP;
    RAISE NOTICE 'PASS 5 semver (% cases)', n;
END $$;
