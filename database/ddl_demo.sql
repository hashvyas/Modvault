

SET client_encoding = 'UTF8';
SELECT md5(string_agg(table_name || '.' || column_name || ':' || data_type || ':' ||
                      coalesce(character_maximum_length::text, '-'), ',' ORDER BY table_name, column_name))
       AS columns_before
FROM   information_schema.columns
WHERE  table_schema = 'public' \gset

BEGIN;

ALTER TABLE users                ADD COLUMN bio             TEXT;
ALTER TABLE users                ADD COLUMN avatar_url      TEXT;
ALTER TABLE mod_versions         ADD COLUMN file_size_bytes BIGINT;
ALTER TABLE mod_versions         ADD COLUMN checksum_sha256 CHAR(64);
ALTER TABLE compatibility_matrix ADD COLUMN notes           TEXT;
SELECT table_name, column_name, data_type
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND  (table_name, column_name) IN (('users', 'bio'), ('users', 'avatar_url'),
                                     ('mod_versions', 'file_size_bytes'), ('mod_versions', 'checksum_sha256'),
                                     ('compatibility_matrix', 'notes'))
ORDER  BY table_name, column_name;
UPDATE users SET bio = 'Keeps the compatibility matrix honest.' WHERE username = 'curator';
SELECT username, bio FROM users WHERE username = 'curator';

ALTER TABLE mod_versions ALTER COLUMN semver TYPE VARCHAR(30);
ALTER TABLE loadouts     ALTER COLUMN name SET DEFAULT 'My Loadout';
SELECT column_name, character_maximum_length, column_default
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND  ((table_name = 'mod_versions' AND column_name = 'semver')
     OR (table_name = 'loadouts'     AND column_name = 'name'));

ALTER TABLE loadouts ALTER COLUMN name DROP DEFAULT;

ALTER TABLE mods RENAME COLUMN summary TO description;
SELECT column_name FROM information_schema.columns
WHERE  table_schema = 'public' AND table_name = 'mods' AND column_name IN ('summary', 'description');
SELECT name FROM mods WHERE search_tsv @@ websearch_to_tsquery('english', 'menu') ORDER BY name LIMIT 5;

ALTER TABLE mods RENAME COLUMN description TO summary;
ALTER TABLE mod_versions ADD CONSTRAINT chk_mod_versions_file_size CHECK (file_size_bytes > 0);
DO $$
BEGIN
    UPDATE mod_versions SET file_size_bytes = -1 WHERE is_primary;
    RAISE EXCEPTION 'negative file size was accepted';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'rejected: %', SQLERRM;
END $$;
ALTER TABLE mod_versions ADD CONSTRAINT chk_mod_versions_checksum
    CHECK (checksum_sha256 ~ '^[0-9a-f]{64}$');
ALTER TABLE users ADD CONSTRAINT uq_users_avatar_url UNIQUE (avatar_url);
SELECT conname, pg_get_constraintdef(oid) AS definition
FROM   pg_constraint
WHERE  conname IN ('chk_mod_versions_file_size', 'chk_mod_versions_checksum', 'uq_users_avatar_url')
ORDER  BY conname;
ALTER TABLE reviews DROP CONSTRAINT chk_reviews_rating;
ALTER TABLE reviews ADD  CONSTRAINT chk_reviews_rating CHECK (rating BETWEEN 1 AND 5);

ALTER TABLE mod_versions DROP CONSTRAINT chk_mod_versions_file_size;
ALTER TABLE mod_versions DROP CONSTRAINT chk_mod_versions_checksum;
ALTER TABLE users        DROP CONSTRAINT uq_users_avatar_url;

DROP VIEW  mod_conflict_summary_view;
DROP INDEX idx_audit_log_changed_by;
DROP TABLE compatibility_matrix CASCADE;
SELECT count(*) AS still_there
FROM   information_schema.tables
WHERE  table_schema = 'public' AND table_name IN ('compatibility_matrix', 'mod_conflict_summary_view');
ALTER TABLE users DROP COLUMN avatar_url;

ROLLBACK;
SELECT table_name, column_name
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND  (table_name, column_name) IN (('users', 'bio'), ('users', 'avatar_url'),
                                     ('mod_versions', 'file_size_bytes'), ('mod_versions', 'checksum_sha256'),
                                     ('compatibility_matrix', 'notes'), ('mods', 'description'));
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
DO $$
BEGIN
    ASSERT NOT EXISTS (SELECT 1 FROM information_schema.columns
                       WHERE table_schema = 'public'
                         AND column_name IN ('bio', 'avatar_url', 'file_size_bytes', 'checksum_sha256', 'notes', 'description')
                         AND table_name IN ('users', 'mod_versions', 'compatibility_matrix', 'mods')),
        'a demo column survived the ROLLBACK';
    RAISE NOTICE 'ddl_demo: schema unchanged after ROLLBACK (0 new columns)';
END $$;
