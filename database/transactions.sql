

SET client_encoding = 'UTF8';
SELECT g.game_id                                                AS skyrim,
       (SELECT user_id FROM users WHERE username = 'curator')  AS curator,
       (SELECT user_id FROM users WHERE username = 'admin')    AS admin,
       (SELECT mod_id  FROM mods  WHERE name = 'SkyUI')        AS skyui_mod,
       (SELECT mod_id  FROM mods  WHERE name = 'RaceMenu')     AS racemenu_mod,
       (SELECT mod_id  FROM mods  WHERE name = 'Better Settlers') AS settlers_mod
FROM   games g
WHERE  g.domain = 'skyrimspecialedition' \gset

SELECT max(v.version_id::text) FILTER (WHERE m.name = 'MCM Helper')                  AS v_mcm,
       max(v.version_id::text) FILTER (WHERE m.name = 'RaceMenu')                    AS v_racemenu,
       max(v.version_id::text) FILTER (WHERE m.name = 'Ordinator - Perks of Skyrim') AS v_ordinator,
       max(v.version_id::text) FILTER (WHERE m.name LIKE 'Campfire%')                AS v_campfire,
       max(v.version_id::text) FILTER (WHERE m.name = 'SkyUI')                       AS v_skyui,
       max(v.version_id::text) FILTER (WHERE m.name = 'Better Dialogue Controls')    AS v_bdc
FROM   mod_versions v
JOIN   mods m ON m.mod_id = v.mod_id
WHERE  v.is_primary \gset
BEGIN;
INSERT INTO mods (game_id, name, summary, category, nexus_author)
VALUES (:'skyrim', 'Demo: Atomic Publish', 'Transaction demo mod', 'Utilities', 'demo')
RETURNING mod_id AS demo_mod \gset
INSERT INTO mod_versions (mod_id, semver, is_primary) VALUES (:'demo_mod', '1.0.0', TRUE);
COMMIT;
SELECT m.name, v.semver, v.is_primary
FROM   mods m JOIN mod_versions v ON v.mod_id = m.mod_id
WHERE  m.name = 'Demo: Atomic Publish';
BEGIN;
INSERT INTO mods (game_id, name, summary, nexus_author)
VALUES (:'skyrim', 'Demo: Broken Publish', 'Never committed', 'demo')
RETURNING mod_id AS broken_mod \gset
\set ON_ERROR_STOP off
INSERT INTO mod_versions (mod_id, semver, is_primary)
VALUES (:'broken_mod', '1.0.0-this-is-far-too-long', TRUE);
\set ON_ERROR_STOP on
ROLLBACK;
SELECT count(*) AS broken_mods FROM mods WHERE name = 'Demo: Broken Publish';

BEGIN;

SAVEPOINT before_record_1;
INSERT INTO compatibility_matrix (version_a_id, version_b_id, status, conflict_detail, verified_by)
VALUES (:'v_mcm', :'v_racemenu', 'compatible', '{"reason": "demo batch record 1"}', :'curator');
RELEASE SAVEPOINT before_record_1;

SAVEPOINT before_record_2;
\set ON_ERROR_STOP off
INSERT INTO compatibility_matrix (version_a_id, version_b_id, status, verified_by)
VALUES (:'v_mcm', :'v_mcm', 'compatible', :'curator');
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT before_record_2;

SAVEPOINT before_record_3;
INSERT INTO compatibility_matrix (version_a_id, version_b_id, status, conflict_detail, verified_by)
VALUES (:'v_ordinator', :'v_campfire', 'compatible', '{"reason": "demo batch record 3"}', :'curator');
RELEASE SAVEPOINT before_record_3;

COMMIT;
SELECT conflict_detail ->> 'reason' AS reason, status
FROM   compatibility_matrix
WHERE  conflict_detail ->> 'reason' LIKE 'demo batch record %'
ORDER  BY 1;
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SELECT h.status, h.score
FROM   loadout_health_view h JOIN loadouts l ON l.loadout_id = h.loadout_id
WHERE  l.name = 'Healthy Skyrim Essentials';
SELECT m.name
FROM   loadout_mods x
JOIN   loadouts l     ON l.loadout_id = x.loadout_id
JOIN   mod_versions v ON v.version_id = x.version_id
JOIN   mods m         ON m.mod_id = v.mod_id
WHERE  l.name = 'Healthy Skyrim Essentials'
ORDER  BY x.position;
COMMIT;
BEGIN;
SELECT semver, is_primary
FROM   mod_versions
WHERE  mod_id = :'skyui_mod'
ORDER  BY uploaded_at
FOR UPDATE;

UPDATE mod_versions SET is_primary = TRUE WHERE mod_id = :'skyui_mod' AND semver = '6.10';
SELECT semver FROM mod_versions WHERE mod_id = :'skyui_mod' AND is_primary;
ROLLBACK;
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT count(*) AS existing
FROM   compatibility_matrix
WHERE  version_a_id = least(:'v_skyui'::uuid, :'v_ordinator'::uuid)
  AND  version_b_id = greatest(:'v_skyui'::uuid, :'v_ordinator'::uuid);
INSERT INTO compatibility_matrix (version_a_id, version_b_id, status, verified_by)
VALUES (least(:'v_skyui'::uuid, :'v_ordinator'::uuid), greatest(:'v_skyui'::uuid, :'v_ordinator'::uuid),
        'compatible', :'curator');
ROLLBACK;
BEGIN;
\set ON_ERROR_STOP off
INSERT INTO reviews (user_id, mod_id, rating, body)
VALUES (:'admin', :'settlers_mod', 6, 'Great mod!');
\set ON_ERROR_STOP on
COMMIT;
BEGIN;
INSERT INTO reviews (user_id, mod_id, rating, body)
VALUES (:'admin', :'settlers_mod', 5, 'Great mod!');
COMMIT;
SELECT r.rating, m.rating_avg, m.rating_count
FROM   reviews r JOIN mods m ON m.mod_id = r.mod_id
WHERE  r.user_id = :'admin' AND r.mod_id = :'settlers_mod';
BEGIN;
SELECT mod_id, name
FROM   mods
WHERE  mod_id IN (:'skyui_mod', :'racemenu_mod')
ORDER  BY mod_id
FOR UPDATE;
ROLLBACK;

BEGIN;
DELETE FROM reviews WHERE user_id = :'admin' AND mod_id = :'settlers_mod';
DELETE FROM compatibility_matrix WHERE conflict_detail ->> 'reason' LIKE 'demo batch record %';
DELETE FROM mods WHERE name = 'Demo: Atomic Publish';
COMMIT;
SELECT (SELECT count(*) FROM mods) AS mods,
       (SELECT count(*) FROM compatibility_matrix) AS matrix_rows,
       (SELECT count(*) FROM reviews) AS reviews;
