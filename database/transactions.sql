-- =============================================================================
-- ModVault: A Mod Repository and Compatibility Intelligence System
-- Transaction Demonstrations  --  transactions.sql
--
-- PURPOSE
--   This file demonstrates explicit transaction control in PostgreSQL.
--   Transactions are one of the four required advanced database concepts.
--
--   Demonstrated features:
--     * BEGIN / COMMIT / ROLLBACK
--     * SAVEPOINT / ROLLBACK TO SAVEPOINT / RELEASE SAVEPOINT
--     * Transaction isolation levels:
--         READ COMMITTED (default), REPEATABLE READ, SERIALIZABLE
--     * SELECT ... FOR UPDATE row locking
--     * Automatic abort on a constraint violation, and the retry pattern
--     * Serialization failure and retry
--     * Deadlock detection, and lock ordering to prevent it
--
-- HOW TO READ THIS FILE
--   Every section has a scenario comment, runnable SQL, and the expected
--   output as a comment.
--   Sections 3, 4, 5 and 7 need two sessions. Their two-session timeline is
--   written as numbered SESSION A / SESSION B steps in comments: open two
--   psql windows and paste the steps in order. Each of those sections also
--   has a runnable single-session part.
--   The timelines were run on the seed; the expected output shown is what
--   PostgreSQL 18 printed.
--
-- INTENTIONAL ERRORS
--   Sections 1, 2 and 6 cause errors on purpose to show rollback. Those
--   statements are wrapped in \set ON_ERROR_STOP off / on, so the file still
--   runs with -v ON_ERROR_STOP=1 and stops on any unexpected error. psql
--   prints the expected ERROR lines.
--
-- DATA
--   Sections 1, 2 and 6 COMMIT demo rows. Section 8 deletes them again, so
--   the seed row counts are unchanged afterwards (seed_expectations.sql still
--   passes). The audit_log keeps the history of those rows; it is append-only.
--
-- DEPENDENCY
--   Run AFTER database/run_all.sql has built and seeded the database.
--
-- HOW TO RUN
--   python scripts/db_reset.py
--   psql "postgresql://modvault_owner:modvault_owner_dev@localhost:5432/modvault" -v ON_ERROR_STOP=1 -f database/transactions.sql
-- =============================================================================

SET client_encoding = 'UTF8';

-- Look up the seed rows used below once, as psql variables (:'name').
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


-- =============================================================================
-- SECTION 1 -- BASIC TRANSACTION: ATOMIC MOD PUBLISH
--
-- Scenario:
--   Publishing a new mod requires inserting into both `mods` and
--   `mod_versions` atomically.  If the version insert fails, the mod
--   row must also be rolled back.
--
-- Demonstrates: BEGIN / INSERT / COMMIT, and ROLLBACK on error.
-- (pr_publish_mod does the same work inside the caller's transaction.)
-- =============================================================================

-- 1a. Happy path: both rows commit together.
BEGIN;
INSERT INTO mods (game_id, name, summary, category, nexus_author)
VALUES (:'skyrim', 'Demo: Atomic Publish', 'Transaction demo mod', 'Utilities', 'demo')
RETURNING mod_id AS demo_mod \gset
INSERT INTO mod_versions (mod_id, semver, is_primary) VALUES (:'demo_mod', '1.0.0', TRUE);
COMMIT;

-- Expected: Demo: Atomic Publish | 1.0.0 | t
SELECT m.name, v.semver, v.is_primary
FROM   mods m JOIN mod_versions v ON v.mod_id = m.mod_id
WHERE  m.name = 'Demo: Atomic Publish';

-- 1b. Failure path: the version insert fails, so the mod insert is undone too.
BEGIN;
INSERT INTO mods (game_id, name, summary, nexus_author)
VALUES (:'skyrim', 'Demo: Broken Publish', 'Never committed', 'demo')
RETURNING mod_id AS broken_mod \gset
\set ON_ERROR_STOP off
-- Expected: ERROR:  value too long for type character varying(20)
INSERT INTO mod_versions (mod_id, semver, is_primary)
VALUES (:'broken_mod', '1.0.0-this-is-far-too-long', TRUE);
\set ON_ERROR_STOP on
ROLLBACK;

-- Expected: 0. The mod row went with the failed transaction.
SELECT count(*) AS broken_mods FROM mods WHERE name = 'Demo: Broken Publish';


-- =============================================================================
-- SECTION 2 -- SAVEPOINT: PARTIAL ROLLBACK ON BATCH INSERT
--
-- Scenario:
--   Importing a batch of compatibility records from an external API.
--   If any individual record violates a constraint, roll back that single
--   record (via SAVEPOINT) and continue with the remaining records.
--
-- Demonstrates: SAVEPOINT, ROLLBACK TO SAVEPOINT, RELEASE SAVEPOINT.
-- (pr_import_loadout uses the same idea: a BEGIN ... EXCEPTION block per
-- entry is an implicit savepoint.)
-- =============================================================================

BEGIN;

SAVEPOINT before_record_1;
INSERT INTO compatibility_matrix (version_a_id, version_b_id, status, conflict_detail, verified_by)
VALUES (:'v_mcm', :'v_racemenu', 'compatible', '{"reason": "demo batch record 1"}', :'curator');
RELEASE SAVEPOINT before_record_1;

SAVEPOINT before_record_2;
\set ON_ERROR_STOP off
-- Expected: ERROR:  new row for relation "compatibility_matrix" violates check constraint "chk_compat_no_self_compare"
INSERT INTO compatibility_matrix (version_a_id, version_b_id, status, verified_by)
VALUES (:'v_mcm', :'v_mcm', 'compatible', :'curator');
\set ON_ERROR_STOP on
-- Only record 2 is undone; record 1 is still pending in the transaction.
ROLLBACK TO SAVEPOINT before_record_2;

SAVEPOINT before_record_3;
INSERT INTO compatibility_matrix (version_a_id, version_b_id, status, conflict_detail, verified_by)
VALUES (:'v_ordinator', :'v_campfire', 'compatible', '{"reason": "demo batch record 3"}', :'curator');
RELEASE SAVEPOINT before_record_3;

COMMIT;

-- Expected: 2 rows, demo batch record 1 and demo batch record 3.
SELECT conflict_detail ->> 'reason' AS reason, status
FROM   compatibility_matrix
WHERE  conflict_detail ->> 'reason' LIKE 'demo batch record %'
ORDER  BY 1;


-- =============================================================================
-- SECTION 3 -- ISOLATION LEVEL: REPEATABLE READ FOR LOADOUT VALIDATION
--
-- Scenario:
--   Validating a loadout's compatibility requires reading mod versions and
--   compatibility_matrix consistently.  Under REPEATABLE READ the whole
--   transaction sees one snapshot, so a curator's concurrent change cannot
--   make the health report contradict itself halfway through.
--
-- Demonstrates: SET TRANSACTION ISOLATION LEVEL REPEATABLE READ,
--               read-only transaction, consistent snapshot.
-- =============================================================================

-- Single-session part: a read-only REPEATABLE READ health report.
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
-- Expected: healthy | 100
SELECT h.status, h.score
FROM   loadout_health_view h JOIN loadouts l ON l.loadout_id = h.loadout_id
WHERE  l.name = 'Healthy Skyrim Essentials';
-- Expected: the same 5 mods (SkyUI, Better Dialogue Controls, ...).
SELECT m.name
FROM   loadout_mods x
JOIN   loadouts l     ON l.loadout_id = x.loadout_id
JOIN   mod_versions v ON v.version_id = x.version_id
JOIN   mods m         ON m.mod_id = v.mod_id
WHERE  l.name = 'Healthy Skyrim Essentials'
ORDER  BY x.position;
COMMIT;

-- Two-session timeline (the pair SkyUI 6.11 / Better Dialogue Controls 1.2 is
-- in the loadout and is 'compatible' in the seed):
--
--   1. SESSION A:  BEGIN ISOLATION LEVEL REPEATABLE READ;
--   2. SESSION A:  SELECT h.status FROM loadout_health_view h JOIN loadouts l USING (loadout_id)
--                  WHERE l.name = 'Healthy Skyrim Essentials';
--                  -- healthy   (the snapshot is taken here, at the first query)
--   3. SESSION B:  UPDATE compatibility_matrix SET status = 'incompatible'
--                  WHERE version_a_id = least(<SkyUI 6.11>, <BDC 1.2>)
--                    AND version_b_id = greatest(<SkyUI 6.11>, <BDC 1.2>);
--                  -- UPDATE 1, autocommitted
--   4. SESSION A:  (same SELECT as step 2)
--                  -- healthy   (B's committed change is invisible to A's snapshot)
--   5. SESSION A:  COMMIT;
--   6. SESSION A:  (same SELECT again, new transaction)
--                  -- broken    (now A sees B's change)
--   7. SESSION B:  set the status back to 'compatible' to restore the seed.
--
--   Under READ COMMITTED step 4 would already print "broken": each statement
--   takes a new snapshot.


-- =============================================================================
-- SECTION 4 -- PESSIMISTIC LOCKING: FOR UPDATE ON MOD VERSION PROMOTION
--
-- Scenario:
--   Two concurrent requests attempt to promote different versions of the
--   same mod to is_primary = TRUE.  SELECT ... FOR UPDATE on all versions of
--   the mod makes the second request wait for the first, so they never
--   interleave. trg_mod_version_single_primary demotes the old primary.
--   This is exactly what pr_promote_version does.
--
-- Demonstrates: SELECT ... FOR UPDATE, row-level locking.
-- =============================================================================

-- Single-session part: lock, promote SkyUI 6.10, check, undo.
BEGIN;
-- Expected: 6 rows locked (all SkyUI versions).
SELECT semver, is_primary
FROM   mod_versions
WHERE  mod_id = :'skyui_mod'
ORDER  BY uploaded_at
FOR UPDATE;

UPDATE mod_versions SET is_primary = TRUE WHERE mod_id = :'skyui_mod' AND semver = '6.10';

-- Expected: 6.10 is the only primary.
SELECT semver FROM mod_versions WHERE mod_id = :'skyui_mod' AND is_primary;
ROLLBACK;

-- Two-session timeline:
--
--   1. SESSION A:  BEGIN;
--   2. SESSION A:  SELECT * FROM mod_versions WHERE mod_id = <SkyUI> FOR UPDATE;
--                  -- 6 rows, now locked by A
--   3. SESSION A:  UPDATE mod_versions SET is_primary = TRUE WHERE mod_id = <SkyUI> AND semver = '6.10';
--   4. SESSION B:  BEGIN;
--   5. SESSION B:  SELECT semver, is_primary FROM mod_versions WHERE mod_id = <SkyUI> FOR UPDATE;
--                  -- blocks: B waits for A's row locks (measured: 1.5 s, until step 6)
--   6. SESSION A:  COMMIT;
--                  -- B's SELECT returns at once, showing A's result: 6.10 true, 6.11 false
--   7. SESSION B:  UPDATE mod_versions SET is_primary = TRUE WHERE mod_id = <SkyUI> AND semver = '6.9';
--   8. SESSION B:  COMMIT;
--   9. Either:     SELECT semver FROM mod_versions WHERE mod_id = <SkyUI> AND is_primary;
--                  -- 6.9   (exactly one primary; restore 6.11 afterwards)
--
--   Without FOR UPDATE, B could read the old state while A is mid-change and
--   act on stale data.


-- =============================================================================
-- SECTION 5 -- SERIALIZABLE: PREVENTING COMPATIBILITY DOUBLE-ENTRY
--
-- Scenario:
--   Two curators simultaneously validate the same pair of mod versions.
--   Both run "does this pair exist?", both see no row, both INSERT.
--   SERIALIZABLE detects that no serial order explains both transactions and
--   cancels one with SQLSTATE 40001. The application retries it; the retry
--   sees the committed row and updates it instead.
--
-- Demonstrates: SET TRANSACTION ISOLATION LEVEL SERIALIZABLE,
--               serialisation failure handling.
-- =============================================================================

-- Single-session part: the check-then-write a curator runs (undone here).
BEGIN ISOLATION LEVEL SERIALIZABLE;
-- Expected: 0 (SkyUI / Ordinator has no matrix row in the seed), then INSERT 0 1.
SELECT count(*) AS existing
FROM   compatibility_matrix
WHERE  version_a_id = least(:'v_skyui'::uuid, :'v_ordinator'::uuid)
  AND  version_b_id = greatest(:'v_skyui'::uuid, :'v_ordinator'::uuid);
INSERT INTO compatibility_matrix (version_a_id, version_b_id, status, verified_by)
VALUES (least(:'v_skyui'::uuid, :'v_ordinator'::uuid), greatest(:'v_skyui'::uuid, :'v_ordinator'::uuid),
        'compatible', :'curator');
ROLLBACK;

-- Two-session timeline (pair Ordinator / Campfire after section 8 cleanup,
-- or any pair with no row):
--
--   1. SESSION A:  BEGIN ISOLATION LEVEL SERIALIZABLE;
--   2. SESSION A:  SELECT count(*) FROM compatibility_matrix WHERE version_a_id = <a> AND version_b_id = <b>;
--                  -- 0
--   3. SESSION B:  BEGIN ISOLATION LEVEL SERIALIZABLE;
--   4. SESSION B:  (same SELECT)
--                  -- 0
--   5. SESSION A:  INSERT INTO compatibility_matrix (version_a_id, version_b_id, status)
--                  VALUES (<a>, <b>, 'compatible');
--                  -- INSERT 0 1
--   6. SESSION B:  INSERT INTO compatibility_matrix (version_a_id, version_b_id, status)
--                  VALUES (<a>, <b>, 'partial');
--                  -- ERROR:  could not serialize access due to read/write dependencies among transactions
--                  -- DETAIL:  Reason code: Canceled on identification as a pivot, during write.
--                  -- HINT:  The transaction might succeed if retried.
--   7. SESSION B:  ROLLBACK;
--   8. SESSION A:  COMMIT;
--   9. SESSION B (retry):
--                  BEGIN ISOLATION LEVEL SERIALIZABLE;
--                  SELECT count(*), max(status::text) FROM compatibility_matrix WHERE ...;
--                  -- 1 | compatible     (A's row is now visible)
--                  UPDATE compatibility_matrix SET status = 'partial' WHERE ...;
--                  COMMIT;
--                  -- final: 1 row, status partial. No duplicate, no lost decision.
--
--   The application treats SQLSTATE 40001 as "retry the whole transaction".
--   pr_upsert_compatibility avoids the race in one statement with
--   INSERT ... ON CONFLICT DO UPDATE.


-- =============================================================================
-- SECTION 6 -- ROLLBACK DEMONSTRATION: CONSTRAINT VIOLATION RECOVERY
--
-- Scenario:
--   Attempt to insert a review with rating = 6 (violates chk_reviews_rating).
--   The entire transaction is rolled back automatically.
--   Then demonstrate the correct insert in a new transaction.
--
-- Demonstrates: automatic ROLLBACK on constraint violation,
--               and the clean retry pattern.
-- =============================================================================

-- Transaction 1: fails, and COMMIT cannot save it.
BEGIN;
\set ON_ERROR_STOP off
-- Expected: ERROR:  new row for relation "reviews" violates check constraint "chk_reviews_rating"
INSERT INTO reviews (user_id, mod_id, rating, body)
VALUES (:'admin', :'settlers_mod', 6, 'Great mod!');
\set ON_ERROR_STOP on
-- Expected: ROLLBACK. COMMIT on an aborted transaction rolls it back.
COMMIT;

-- Transaction 2: the corrected retry.
BEGIN;
INSERT INTO reviews (user_id, mod_id, rating, body)
VALUES (:'admin', :'settlers_mod', 5, 'Great mod!');
COMMIT;

-- Expected: one review, rating 5; the rating trigger updated the mod: 5.00 | 1
SELECT r.rating, m.rating_avg, m.rating_count
FROM   reviews r JOIN mods m ON m.mod_id = r.mod_id
WHERE  r.user_id = :'admin' AND r.mod_id = :'settlers_mod';


-- =============================================================================
-- SECTION 7 -- DEADLOCK
--
-- Scenario:
--   Session A locks mod row X then tries to lock mod row Y.
--   Session B locks mod row Y then tries to lock mod row X.
--   PostgreSQL detects the cycle after deadlock_timeout (1 s) and rolls back
--   one session; the other continues.
--
-- Prevention strategy for ModVault:
--   Always acquire locks in a deterministic order (by mod_id), as below.
-- =============================================================================

-- Single-session part: the safe pattern. Both mods locked in one statement in
-- mod_id order, so two sessions doing this queue up instead of deadlocking.
BEGIN;
-- Expected: 2 rows, ordered by mod_id.
SELECT mod_id, name
FROM   mods
WHERE  mod_id IN (:'skyui_mod', :'racemenu_mod')
ORDER  BY mod_id
FOR UPDATE;
ROLLBACK;

-- Two-session timeline (X = SkyUI, Y = RaceMenu):
--
--   1. SESSION A:  BEGIN;
--   2. SESSION A:  SELECT 1 FROM mods WHERE mod_id = <X> FOR UPDATE;   -- A holds X
--   3. SESSION B:  BEGIN;
--   4. SESSION B:  SELECT 1 FROM mods WHERE mod_id = <Y> FOR UPDATE;   -- B holds Y
--   5. SESSION A:  SELECT 1 FROM mods WHERE mod_id = <Y> FOR UPDATE;   -- A waits for B
--   6. SESSION B:  SELECT 1 FROM mods WHERE mod_id = <X> FOR UPDATE;   -- B waits for A: a cycle
--                  -- after 1 s, one session gets (here it was A):
--                  -- ERROR:  deadlock detected
--                  -- DETAIL:  Process 1532 waits for ShareLock on transaction 4246; blocked by process 1900.
--                  --          Process 1900 waits for ShareLock on transaction 4245; blocked by process 1532.
--                  -- CONTEXT:  while locking tuple (4,3) in relation "mods"
--                  -- and the other session's lock request succeeds.
--   7. Both:       ROLLBACK / COMMIT.  The victim retries.
--
--   With the ordered pattern above, step 6 never forms a cycle: both
--   sessions ask for the lower mod_id first, so the second one simply waits.


-- =============================================================================
-- SECTION 8 -- CLEANUP
--
-- Removes the rows committed by sections 1, 2 and 6, so the seed counts are
-- back to normal. One transaction: all or nothing.
-- =============================================================================

BEGIN;
DELETE FROM reviews WHERE user_id = :'admin' AND mod_id = :'settlers_mod';
DELETE FROM compatibility_matrix WHERE conflict_detail ->> 'reason' LIKE 'demo batch record %';
DELETE FROM mods WHERE name = 'Demo: Atomic Publish';   -- its version goes by ON DELETE CASCADE
COMMIT;

-- Expected: 45 | 27 | 40 (the seed counts).
SELECT (SELECT count(*) FROM mods) AS mods,
       (SELECT count(*) FROM compatibility_matrix) AS matrix_rows,
       (SELECT count(*) FROM reviews) AS reviews;
