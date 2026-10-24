-- =============================================================================
-- ModVault: A Mod Repository and Compatibility Intelligence System
-- Build order  --  run_all.sql
--
-- PURPOSE
--   Builds the whole database in dependency order. transactions.sql,
--   queries.sql, ddl_demo.sql, seed_expectations.sql and tests/run_tests.sql
--   run after this file, one at a time.
--
-- HOW TO RUN
--   python scripts/db_reset.py      (drops schema public, then runs this file)
-- =============================================================================

SET client_encoding = 'UTF8';

\ir schema.sql
\ir indexes.sql
\ir functions.sql
\ir triggers.sql
\ir views.sql
\ir rls.sql
\ir seed.sql
REFRESH MATERIALIZED VIEW mv_game_leaderboard;
