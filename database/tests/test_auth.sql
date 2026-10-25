-- =============================================================================
-- ModVault: A Mod Repository and Compatibility Intelligence System
-- Auth and semver tests  --  tests/test_auth.sql
--
-- Each check runs inside BEGIN ... ROLLBACK and leaves no data behind.
-- A failed ASSERT stops the run (ON_ERROR_STOP=1). Each passing check prints
-- a NOTICE starting with PASS.
--
-- HOW TO RUN (after run_all.sql and tests/fixtures.sql)
--   psql "postgresql://modvault_owner:modvault_owner_dev@localhost:5432/modvault" -v ON_ERROR_STOP=1 -f database/tests/test_auth.sql
-- =============================================================================

SET client_encoding = 'UTF8';


-- 1. fn_register_user then fn_authenticate returns the new user as a modder.
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


-- 2. Wrong password, unknown user and inactive user return zero rows.
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


-- 3. Duplicate username or email raises DUPLICATE.
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


-- 4. Bad username, email or password raises INVALID_INPUT.
BEGIN;
DO $$
DECLARE
    c record;
    raised boolean;
BEGIN
    FOR c IN SELECT * FROM (VALUES
        ('ab',           'fx_ok@example.com', 'correct-horse'),   -- username too short
        ('bad name',     'fx_ok@example.com', 'correct-horse'),   -- space in username
        ('fx_ok',        'no-at-sign',        'correct-horse'),   -- email without @
        ('fx_ok',        'fx_ok@example.com', 'short'),           -- password under 8
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


-- 5. fn_semver_satisfies: operator and parsing cases.
DO $$
DECLARE
    c record;
    n int := 0;
BEGIN
    FOR c IN SELECT * FROM (VALUES
        ('1.10.0',  '>=1.9',   true),    -- numeric, not string, compare
        ('2.0.0',   '^1.0',    false),   -- caret keeps the major
        ('v1.2',    '=1.2.0',  true),    -- leading v and padding
        ('1.5.0',   '^1.2',    true),
        ('1.1.0',   '^1.2',    false),
        ('1.2.3',   '>1.2.3',  false),
        ('1.2.4',   '>1.2.3',  true),
        ('1.2.3',   '<=1.2.3', true),
        ('1.2.3',   '<1.2.3',  false),
        ('1.2.2',   '<1.2.3',  true),
        ('2.2.6',   '2.2',     true),    -- plain x means >=x
        ('2.1.0',   '2.2',     false),
        ('1.2.3',   '*',       true),
        ('1.2.3',   NULL,      true),
        ('1.2.3',   '',        true),
        ('abc',     '>=1.0',   true),    -- unparseable installed version
        ('1.2.0.1', '=1.2.0',  false),   -- fourth part counts
        ('0.6.23',  '>= 0.6',  true)     -- space after operator
    ) AS t(installed, cons, expected)
    LOOP
        ASSERT fn_semver_satisfies(c.installed, c.cons) = c.expected,
            format('fn_semver_satisfies(%L, %L) is not %s', c.installed, c.cons, c.expected);
        n := n + 1;
    END LOOP;
    RAISE NOTICE 'PASS 5 semver (% cases)', n;
END $$;
