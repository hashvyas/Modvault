-- =============================================================================
-- ModVault: A Mod Repository and Compatibility Intelligence System
-- Test runner  --  tests/run_tests.sql
--
-- PURPOSE
--   Runs every SQL test file in order. Each test prints NOTICE lines starting
--   with PASS; a failed ASSERT stops the run (ON_ERROR_STOP=1) with a
--   non-zero exit code.
--
--   The tests need tests/fixtures.sql. It is loaded here when its rows are
--   not in the database yet, so this file works both on a fresh
--   `python scripts/db_reset.py --with-tests` and after loading fixtures by
--   hand (CI does the latter).
--
--   Fixtures COMMIT their rows. Run seed_expectations.sql before this file,
--   not after: its exact row counts do not include the fixtures.
--
-- HOW TO RUN
--   python scripts/db_reset.py --with-tests
--   or, after run_all.sql:
--   psql "postgresql://modvault_owner:modvault_owner_dev@localhost:5432/modvault" -v ON_ERROR_STOP=1 -f database/tests/run_tests.sql
-- =============================================================================

SET client_encoding = 'UTF8';

SELECT NOT EXISTS (SELECT 1 FROM games WHERE domain = 'fx-game-a') AS need_fixtures \gset
\if :need_fixtures
    \echo 'run_tests: loading fixtures.sql'
    \ir fixtures.sql
\endif

\echo 'run_tests: test_triggers.sql'
\ir test_triggers.sql
\echo 'run_tests: test_auth.sql'
\ir test_auth.sql
\echo 'run_tests: test_health.sql'
\ir test_health.sql
\echo 'run_tests: test_graph.sql'
\ir test_graph.sql
\echo 'run_tests: test_search.sql'
\ir test_search.sql
\echo 'run_tests: test_procedures.sql'
\ir test_procedures.sql
\echo 'run_tests: test_views.sql'
\ir test_views.sql
\echo 'run_tests: test_rls.sql'
\ir test_rls.sql

\echo 'run_tests: all test files passed'
