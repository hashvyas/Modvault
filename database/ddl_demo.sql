-- =============================================================================
-- ModVault: A Mod Repository and Compatibility Intelligence System
-- PostgreSQL DDL Demonstrations  --  ddl_demo.sql
--
-- PURPOSE
--   This file demonstrates post-creation DDL operations required by the
--   project rubric:
--     * ALTER TABLE  (add/drop/rename columns, change data types, rename tables)
--     * DROP TABLE / DROP TYPE / DROP VIEW (teardown in dependency order)
--     * ADD CONSTRAINT / DROP CONSTRAINT  (primary keys, foreign keys, CHECK,
--       UNIQUE constraints added or removed after table creation)
--     * Structural evolution examples showing schema migration without
--       dropping and recreating the full schema.
--
-- DEPENDENCY
--   Run AFTER database/run_all.sql has built and seeded the database.
--
-- HOW TO RUN
--   python scripts/db_reset.py
--   psql "postgresql://modvault_owner:modvault_owner_dev@localhost:5432/modvault" -v ON_ERROR_STOP=1 -f database/ddl_demo.sql
-- =============================================================================

SET client_encoding = 'UTF8';


-- =============================================================================
-- SECTION 1 -- ALTER TABLE: ADD COLUMN
--
-- Demonstrates extending existing tables with new columns post-creation.
-- All additions use safe defaults so no existing rows are violated.
--
-- Planned columns:
--   users          -> bio TEXT, avatar_url TEXT, is_active BOOLEAN DEFAULT TRUE
--   mods           -> download_count BIGINT DEFAULT 0, is_featured BOOLEAN DEFAULT FALSE
--   mod_versions   -> file_size_bytes BIGINT, checksum_sha256 CHAR(64)
--   loadouts       -> description TEXT
--   compatibility_matrix -> notes TEXT
-- =============================================================================

-- (ALTER TABLE ... ADD COLUMN statements will be added here)


-- =============================================================================
-- SECTION 2 -- ALTER TABLE: ALTER COLUMN
--
-- Demonstrates changing column attributes on existing tables:
--   * Changing VARCHAR lengths (widening is safe; narrowing may fail if data
--     already exceeds the new limit)
--   * Setting / dropping NOT NULL constraints
--   * Changing DEFAULT values
--
-- Planned changes:
--   mods.category       VARCHAR(100)  ->  VARCHAR(150)
--   mod_versions.semver VARCHAR(20)   ->  VARCHAR(30)
--   loadouts.name       SET DEFAULT 'My Loadout'
-- =============================================================================

-- (ALTER TABLE ... ALTER COLUMN statements will be added here)


-- =============================================================================
-- SECTION 3 -- ALTER TABLE: RENAME COLUMN / RENAME TABLE
--
-- Demonstrates renaming operations that do NOT rebuild underlying storage.
--
-- Planned renames:
--   mods.summary          ->  mods.description     (rename for clarity)
--   mods.description      ->  mods.summary         (rename back for compatibility)
-- =============================================================================

-- (RENAME COLUMN / RENAME TABLE statements will be added here)


-- =============================================================================
-- SECTION 4 -- ALTER TABLE: ADD CONSTRAINT / DROP CONSTRAINT
--
-- Demonstrates adding and removing named constraints after initial creation:
--   * ADD CONSTRAINT ... CHECK (...)
--   * ADD CONSTRAINT ... UNIQUE (...)
--   * ADD CONSTRAINT ... FOREIGN KEY (...) REFERENCES ...
--   * DROP CONSTRAINT <name>
--
-- Planned operations:
--   ADD CHECK on mods.download_count       (>= 0)
--   ADD CHECK on mod_versions.file_size_bytes  (> 0)
--   ADD CHECK on users.is_active           (is_active IS NOT NULL)
--   Drop and re-add a constraint to demonstrate both directions
-- =============================================================================

-- (ADD CONSTRAINT / DROP CONSTRAINT statements will be added here)


-- =============================================================================
-- SECTION 5 -- DROP OBJECTS (teardown / cleanup demonstration)
--
-- Demonstrates DROP in safe reverse-dependency order:
--   1. DROP VIEW        (views defined in views.sql)
--   2. DROP INDEX       (indexes defined in indexes.sql)
--   3. DROP TABLE       (leaf tables first, base tables last)
--   4. DROP TYPE        (after all tables using the type are dropped)
--   5. DROP EXTENSION   (only if no longer needed)
--
-- NOTE: This section is shown for demonstration only.
--       Wrap in a transaction and ROLLBACK to test without data loss:
--
--         BEGIN;
--           -- paste DROP statements here
--         ROLLBACK;
--
-- Planned DROP order:
--   DROP TABLE IF EXISTS compatibility_matrix  CASCADE;
--   DROP TABLE IF EXISTS loadout_mods          CASCADE;
--   DROP TABLE IF EXISTS mod_dependencies      CASCADE;
--   DROP TABLE IF EXISTS reviews               CASCADE;
--   DROP TABLE IF EXISTS mod_tags              CASCADE;
--   DROP TABLE IF EXISTS mod_versions          CASCADE;
--   DROP TABLE IF EXISTS mods                  CASCADE;
--   DROP TABLE IF EXISTS loadouts              CASCADE;
--   DROP TABLE IF EXISTS tags                  CASCADE;
--   DROP TABLE IF EXISTS games                 CASCADE;
--   DROP TABLE IF EXISTS users                 CASCADE;
--   DROP TYPE IF EXISTS compat_status_enum     CASCADE;
--   DROP TYPE IF EXISTS dep_source_enum        CASCADE;
--   DROP TYPE IF EXISTS dep_type_enum          CASCADE;
--   DROP TYPE IF EXISTS user_role_enum         CASCADE;
--   DROP EXTENSION IF EXISTS vector;
--   DROP EXTENSION IF EXISTS pgcrypto;
-- =============================================================================

-- (DROP statements will be added here)
