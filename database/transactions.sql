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
--         SET TRANSACTION ISOLATION LEVEL READ COMMITTED   (default)
--         SET TRANSACTION ISOLATION LEVEL REPEATABLE READ
--         SET TRANSACTION ISOLATION LEVEL SERIALIZABLE
--     * FOR UPDATE / FOR SHARE locking clauses
--     * Error handling with EXCEPTION blocks (inside functions, shown here
--       as annotated examples)
--     * Deadlock scenario (documented, not run automatically)
--     * Concurrent read anomaly prevention examples
--
-- HOW TO READ THIS FILE
--   Each section is a self-contained transaction block wrapped in
--   BEGIN ... COMMIT (or ROLLBACK).  Each block is annotated with the
--   feature it demonstrates and why that feature matters for ModVault.
--
-- DEPENDENCY
--   Requires schema.sql + seed.sql to have meaningful data.
--   Some transactions also require ddl_demo.sql (extra columns).
--
-- HOW TO RUN
--   psql -d modvault -f database/schema.sql
--   psql -d modvault -f database/seed.sql
--   psql -d modvault -f database/transactions.sql
-- =============================================================================


-- =============================================================================
-- SECTION 1 -- BASIC TRANSACTION: ATOMIC MOD PUBLISH
--
-- Scenario:
--   Publishing a new mod requires inserting into both `mods` and
--   `mod_versions` atomically.  If the version insert fails, the mod
--   row must also be rolled back.
--
-- Demonstrates: BEGIN / INSERT / COMMIT, and ROLLBACK on error.
-- =============================================================================

-- BEGIN;
--
--   -- Step 1: insert the mod header
--   INSERT INTO mods (...) VALUES (...);
--
--   -- Step 2: insert the initial version
--   INSERT INTO mod_versions (...) VALUES (...);
--
-- COMMIT;

-- (Transaction SQL will be added here)


-- =============================================================================
-- SECTION 2 -- SAVEPOINT: PARTIAL ROLLBACK ON BATCH INSERT
--
-- Scenario:
--   Importing a batch of compatibility records from an external API.
--   If any individual record violates a constraint, roll back that single
--   record (via SAVEPOINT) and continue with the remaining records.
--
-- Demonstrates: SAVEPOINT, ROLLBACK TO SAVEPOINT, RELEASE SAVEPOINT.
-- =============================================================================

-- BEGIN;
--
--   SAVEPOINT before_record_1;
--   INSERT INTO compatibility_matrix (...) VALUES (...);
--   RELEASE SAVEPOINT before_record_1;
--
--   SAVEPOINT before_record_2;
--   -- This record intentionally violates chk_compat_no_self_compare:
--   INSERT INTO compatibility_matrix (...) VALUES (same_id, same_id, ...);
--   -- On error, roll back only this record:
--   ROLLBACK TO SAVEPOINT before_record_2;
--
--   SAVEPOINT before_record_3;
--   INSERT INTO compatibility_matrix (...) VALUES (...);
--   RELEASE SAVEPOINT before_record_3;
--
-- COMMIT;

-- (Transaction SQL will be added here)


-- =============================================================================
-- SECTION 3 -- ISOLATION LEVEL: REPEATABLE READ FOR LOADOUT VALIDATION
--
-- Scenario:
--   Validating a loadout's compatibility requires reading mod versions and
--   compatibility_matrix consistently.  Without REPEATABLE READ, a concurrent
--   transaction could alter compatibility records mid-validation, producing
--   a snapshot inconsistency.
--
-- Demonstrates: SET TRANSACTION ISOLATION LEVEL REPEATABLE READ,
--               read-only transaction, consistent snapshot.
-- =============================================================================

-- BEGIN;
-- SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
--
--   -- Read loadout contents (snapshot is fixed at this point)
--   SELECT version_id FROM loadout_mods WHERE loadout_id = '...';
--
--   -- Read compatibility matrix (same snapshot; concurrent writes not visible)
--   SELECT * FROM compatibility_matrix WHERE version_a_id IN (...);
--
-- COMMIT;

-- (Transaction SQL will be added here)


-- =============================================================================
-- SECTION 4 -- PESSIMISTIC LOCKING: FOR UPDATE ON MOD VERSION PROMOTION
--
-- Scenario:
--   Two concurrent requests attempt to promote different versions of the
--   same mod to is_primary = TRUE.  Using SELECT ... FOR UPDATE ensures
--   only one proceeds at a time, preventing a race condition where both
--   versions end up as is_primary = TRUE before the trigger fires.
--
-- Demonstrates: SELECT ... FOR UPDATE, row-level locking.
-- =============================================================================

-- BEGIN;
--
--   -- Lock all versions of the target mod
--   SELECT version_id, is_primary
--   FROM mod_versions
--   WHERE mod_id = '...'
--   FOR UPDATE;
--
--   -- Safely demote old primary and promote new one
--   UPDATE mod_versions SET is_primary = FALSE WHERE mod_id = '...';
--   UPDATE mod_versions SET is_primary = TRUE  WHERE version_id = '...';
--
-- COMMIT;

-- (Transaction SQL will be added here)


-- =============================================================================
-- SECTION 5 -- SERIALIZABLE: PREVENTING COMPATIBILITY DOUBLE-ENTRY
--
-- Scenario:
--   Two curators simultaneously validate the same pair of mod versions.
--   Without SERIALIZABLE isolation, both might pass the "does this pair
--   already exist?" check and both attempt to INSERT, causing one to fail
--   with a unique-constraint violation.
--   SERIALIZABLE detects the conflict and aborts one transaction cleanly.
--
-- Demonstrates: SET TRANSACTION ISOLATION LEVEL SERIALIZABLE,
--               serialisation failure handling.
-- =============================================================================

-- BEGIN;
-- SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
--
--   -- Check if the pair already exists
--   SELECT 1 FROM compatibility_matrix
--   WHERE version_a_id = '...' AND version_b_id = '...';
--
--   -- If not, insert (SERIALIZABLE ensures no phantom insert between check and write)
--   INSERT INTO compatibility_matrix (...) VALUES (...);
--
-- COMMIT;
-- -- On serialisation failure: ROLLBACK is automatic; application retries.

-- (Transaction SQL will be added here)


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

-- -- Transaction 1: will fail and roll back
-- BEGIN;
--   INSERT INTO reviews (user_id, mod_id, rating, body)
--   VALUES ('...', '...', 6, 'Great mod!');  -- rating = 6 violates CHECK
-- COMMIT;  -- never reached; PostgreSQL aborts the transaction
--
-- -- Transaction 2: correct insert after retry
-- BEGIN;
--   INSERT INTO reviews (user_id, mod_id, rating, body)
--   VALUES ('...', '...', 5, 'Great mod!');
-- COMMIT;

-- (Transaction SQL will be added here)


-- =============================================================================
-- SECTION 7 -- DEADLOCK DOCUMENTATION
--
-- This section documents (but does NOT run) a classic deadlock scenario
-- to explain how PostgreSQL detects and resolves deadlocks.
--
-- Scenario:
--   Session A locks mod row X then tries to lock mod row Y.
--   Session B locks mod row Y then tries to lock mod row X.
--   PostgreSQL detects the cycle and rolls back one session with:
--     ERROR: deadlock detected
--
-- Prevention strategy for ModVault:
--   Always acquire locks in a deterministic order (e.g., by mod_id UUID
--   lexicographic order) to avoid circular lock dependencies.
-- =============================================================================

-- Session A:
--   BEGIN;
--   SELECT * FROM mods WHERE mod_id = '<lower_uuid>' FOR UPDATE;
--   -- (pause)
--   SELECT * FROM mods WHERE mod_id = '<higher_uuid>' FOR UPDATE;
--   COMMIT;
--
-- Session B (concurrent):
--   BEGIN;
--   SELECT * FROM mods WHERE mod_id = '<higher_uuid>' FOR UPDATE;
--   -- (pause)
--   SELECT * FROM mods WHERE mod_id = '<lower_uuid>' FOR UPDATE;
--   -- ^ deadlock detected here; PostgreSQL rolls back Session B
--   COMMIT;

-- (Documentation only -- no executable SQL for this section)
