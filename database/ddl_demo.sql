-- =============================================================================
-- ModVault: A Mod Repository and Compatibility Intelligence System
-- PostgreSQL DDL Demonstrations  --  ddl_demo.sql
--
-- PURPOSE
--   This file demonstrates post-creation DDL operations required by the
--   project rubric:
--     * ALTER TABLE  (add/drop/rename columns, change data types)
--     * ADD CONSTRAINT / DROP CONSTRAINT  (CHECK, UNIQUE added and removed
--       after table creation)
--     * DROP VIEW / DROP INDEX / DROP TABLE (teardown in dependency order)
--
--   PostgreSQL DDL is transactional: everything between BEGIN and ROLLBACK
--   below is undone, including CREATE, ALTER and DROP. The whole demo runs in
--   one transaction and ends with ROLLBACK, so the real schema never changes.
--   The checks after the ROLLBACK prove it with information_schema.
--
-- NOTE
--   The Phase 0 outline planned users.is_active, mods.download_count,
--   mods.is_featured and loadouts.description here. The final schema already
--   has them, so they are not added again.
--
-- DEPENDENCY
--   Run AFTER database/run_all.sql has built and seeded the database.
--
-- HOW TO RUN
--   python scripts/db_reset.py
--   psql "postgresql://modvault_owner:modvault_owner_dev@localhost:5432/modvault" -v ON_ERROR_STOP=1 -f database/ddl_demo.sql
-- =============================================================================

SET client_encoding = 'UTF8';

-- Fingerprint of every column in schema public before the demo (psql variable).
SELECT md5(string_agg(table_name || '.' || column_name || ':' || data_type || ':' ||
                      coalesce(character_maximum_length::text, '-'), ',' ORDER BY table_name, column_name))
       AS columns_before
FROM   information_schema.columns
WHERE  table_schema = 'public' \gset

BEGIN;


-- =============================================================================
-- SECTION 1 -- ALTER TABLE: ADD COLUMN
--
-- New nullable columns need no rewrite of existing rows.
-- =============================================================================

ALTER TABLE users                ADD COLUMN bio             TEXT;
ALTER TABLE users                ADD COLUMN avatar_url      TEXT;
ALTER TABLE mod_versions         ADD COLUMN file_size_bytes BIGINT;
ALTER TABLE mod_versions         ADD COLUMN checksum_sha256 CHAR(64);
ALTER TABLE compatibility_matrix ADD COLUMN notes           TEXT;

-- Inside the transaction the five columns exist.
-- Expected: 5 rows.
SELECT table_name, column_name, data_type
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND  (table_name, column_name) IN (('users', 'bio'), ('users', 'avatar_url'),
                                     ('mod_versions', 'file_size_bytes'), ('mod_versions', 'checksum_sha256'),
                                     ('compatibility_matrix', 'notes'))
ORDER  BY table_name, column_name;

-- They are usable like any column.
UPDATE users SET bio = 'Keeps the compatibility matrix honest.' WHERE username = 'curator';
SELECT username, bio FROM users WHERE username = 'curator';


-- =============================================================================
-- SECTION 2 -- ALTER TABLE: ALTER COLUMN
--
-- Widening a VARCHAR is a catalog-only change. Narrowing would fail if any
-- row were longer than the new limit.
-- mod_versions.semver is used because no view depends on it; mods.category
-- feeds the generated search_tsv column and mod_catalog_view, and PostgreSQL
-- refuses to change the type of a column those depend on.
-- =============================================================================

ALTER TABLE mod_versions ALTER COLUMN semver TYPE VARCHAR(30);
ALTER TABLE loadouts     ALTER COLUMN name SET DEFAULT 'My Loadout';

-- Expected: semver | 30, and the new default on loadouts.name.
SELECT column_name, character_maximum_length, column_default
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND  ((table_name = 'mod_versions' AND column_name = 'semver')
     OR (table_name = 'loadouts'     AND column_name = 'name'));

ALTER TABLE loadouts ALTER COLUMN name DROP DEFAULT;


-- =============================================================================
-- SECTION 3 -- ALTER TABLE: RENAME COLUMN
--
-- A rename only changes the catalog; generated columns and views refer to the
-- column by number, so search_tsv keeps working.
-- =============================================================================

ALTER TABLE mods RENAME COLUMN summary TO description;

-- Expected: one row, column description.
SELECT column_name FROM information_schema.columns
WHERE  table_schema = 'public' AND table_name = 'mods' AND column_name IN ('summary', 'description');

-- Full-text search still works through the renamed column. Expected: 5 mod names.
SELECT name FROM mods WHERE search_tsv @@ websearch_to_tsquery('english', 'menu') ORDER BY name LIMIT 5;

ALTER TABLE mods RENAME COLUMN description TO summary;


-- =============================================================================
-- SECTION 4 -- ALTER TABLE: ADD CONSTRAINT / DROP CONSTRAINT
-- =============================================================================

-- CHECK on the new column: a file has a positive size.
ALTER TABLE mod_versions ADD CONSTRAINT chk_mod_versions_file_size CHECK (file_size_bytes > 0);

-- The constraint is enforced at once. Expected: NOTICE "rejected: ... violates check constraint".
DO $$
BEGIN
    UPDATE mod_versions SET file_size_bytes = -1 WHERE is_primary;
    RAISE EXCEPTION 'negative file size was accepted';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'rejected: %', SQLERRM;
END $$;

-- A checksum is exactly 64 hex characters.
ALTER TABLE mod_versions ADD CONSTRAINT chk_mod_versions_checksum
    CHECK (checksum_sha256 ~ '^[0-9a-f]{64}$');

-- UNIQUE added after creation.
ALTER TABLE users ADD CONSTRAINT uq_users_avatar_url UNIQUE (avatar_url);

-- Expected: the three new constraints.
SELECT conname, pg_get_constraintdef(oid) AS definition
FROM   pg_constraint
WHERE  conname IN ('chk_mod_versions_file_size', 'chk_mod_versions_checksum', 'uq_users_avatar_url')
ORDER  BY conname;

-- Drop and re-add an existing constraint to show both directions.
ALTER TABLE reviews DROP CONSTRAINT chk_reviews_rating;
ALTER TABLE reviews ADD  CONSTRAINT chk_reviews_rating CHECK (rating BETWEEN 1 AND 5);

ALTER TABLE mod_versions DROP CONSTRAINT chk_mod_versions_file_size;
ALTER TABLE mod_versions DROP CONSTRAINT chk_mod_versions_checksum;
ALTER TABLE users        DROP CONSTRAINT uq_users_avatar_url;


-- =============================================================================
-- SECTION 5 -- DROP OBJECTS (teardown in reverse-dependency order)
--
-- Still inside the transaction, so the ROLLBACK below brings everything back.
-- =============================================================================

DROP VIEW  mod_conflict_summary_view;
DROP INDEX idx_audit_log_changed_by;
-- CASCADE also drops the policies on the table.
DROP TABLE compatibility_matrix CASCADE;

-- Expected: 0.
SELECT count(*) AS still_there
FROM   information_schema.tables
WHERE  table_schema = 'public' AND table_name IN ('compatibility_matrix', 'mod_conflict_summary_view');

-- Drop a column added in section 1.
ALTER TABLE users DROP COLUMN avatar_url;


ROLLBACK;


-- =============================================================================
-- SECTION 6 -- AFTER ROLLBACK: THE SCHEMA IS UNCHANGED
-- =============================================================================

-- Expected: 0 rows. None of the demo columns survived.
SELECT table_name, column_name
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND  (table_name, column_name) IN (('users', 'bio'), ('users', 'avatar_url'),
                                     ('mod_versions', 'file_size_bytes'), ('mod_versions', 'checksum_sha256'),
                                     ('compatibility_matrix', 'notes'), ('mods', 'description'));

-- Expected: semver | 20, summary present, dropped objects back, fingerprint unchanged.
SELECT (SELECT character_maximum_length FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'mod_versions' AND column_name = 'semver') AS semver_length,
       EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'mods' AND column_name = 'summary') AS summary_exists,
       (SELECT count(*) FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name IN ('compatibility_matrix', 'mod_conflict_summary_view')) AS dropped_objects_back,
       (SELECT md5(string_agg(table_name || '.' || column_name || ':' || data_type || ':' ||
                              coalesce(character_maximum_length::text, '-'), ',' ORDER BY table_name, column_name))
        FROM information_schema.columns WHERE table_schema = 'public') = :'columns_before' AS schema_unchanged;

-- Fails the run (ON_ERROR_STOP) if anything leaked out of the transaction.
DO $$
BEGIN
    ASSERT NOT EXISTS (SELECT 1 FROM information_schema.columns
                       WHERE table_schema = 'public'
                         AND column_name IN ('bio', 'avatar_url', 'file_size_bytes', 'checksum_sha256', 'notes', 'description')
                         AND table_name IN ('users', 'mod_versions', 'compatibility_matrix', 'mods')),
        'a demo column survived the ROLLBACK';
    RAISE NOTICE 'ddl_demo: schema unchanged after ROLLBACK (0 new columns)';
END $$;
