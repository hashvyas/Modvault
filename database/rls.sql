-- =============================================================================
-- ModVault: A Mod Repository and Compatibility Intelligence System
-- Roles and Row-Level Security  --  rls.sql
--
-- PURPOSE
--   Creates the modvault_app login role, its grants, and the Row-Level
--   Security policies. Filled in Phase 3 (P1-09). Phase 0 placeholder.
--
-- DEPENDENCY
--   Included by database/run_all.sql, after views.sql.
--
-- HOW TO RUN
--   Do not run this file alone. It is included by database/run_all.sql.
--   Rebuild everything with:  python scripts/db_reset.py
-- =============================================================================

SET client_encoding = 'UTF8';
