

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
