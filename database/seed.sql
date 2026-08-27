-- =============================================================================
-- ModVault: A Mod Repository and Compatibility Intelligence System
-- Seed / Sample Data  --  seed.sql
--
-- PURPOSE
--   This file populates the database with realistic sample data for
--   development, testing, and demonstration purposes.
--
--   It demonstrates core DML operations:
--     * INSERT INTO ... VALUES (...)          -- single-row inserts
--     * INSERT INTO ... SELECT ...            -- bulk / derived inserts
--     * INSERT INTO ... ON CONFLICT DO ...    -- upsert pattern
--     * UPDATE ... WHERE ...                  -- conditional updates
--     * DELETE FROM ... WHERE ...             -- conditional deletes
--     * TRUNCATE TABLE ... RESTART IDENTITY   -- full table reset
--
-- DATA CATEGORIES
--   1. Extensions (already enabled by schema.sql -- no inserts needed)
--   2. Users       -- at least one modder, one curator, one admin
--   3. Games       -- several supported game titles (e.g. Skyrim SE, Fallout 4)
--   4. Tags        -- common mod taxonomy tags
--   5. Mods        -- representative mods linked to games and authors
--   6. Mod Versions -- one or more semver releases per mod
--   7. Mod Dependencies  -- dependency relationships between versions
--   8. Reviews     -- user ratings and review bodies
--   9. Mod Tags    -- tag associations for mods
--  10. Loadouts    -- user loadout collections
--  11. Loadout Mods -- mod versions assigned to loadouts
--  12. Compatibility Matrix -- pairwise version compatibility records
--
-- NOTES
--   * UUIDs are declared as variables so cross-row FK references stay readable.
--   * No pgvector embeddings are inserted here; the embedding column is left
--     NULL and will be populated by an application-layer embedding job.
--   * All data is fictional and for demonstration only.
--
-- DEPENDENCY
--   Run AFTER schema.sql (and optionally ddl_demo.sql) have been applied.
--
-- HOW TO RUN
--   psql -d modvault -f database/schema.sql
--   psql -d modvault -f database/seed.sql
-- =============================================================================


-- =============================================================================
-- SECTION 1 -- INSERT: USERS
--
-- Create at least three users covering all three roles:
--   * admin   -- platform administrator
--   * curator -- trusted compatibility reviewer
--   * modder  -- regular mod author (multiple)
--
-- Uses INSERT ... ON CONFLICT DO NOTHING so re-running seed.sql is safe.
-- =============================================================================

-- (INSERT INTO users ... statements will be added here)


-- =============================================================================
-- SECTION 2 -- INSERT: GAMES
--
-- Populate the games table with several well-known moddable titles.
-- The domain and nexus_game_id columns will match Nexus Mods conventions
-- where applicable.
--
-- Planned games:
--   Skyrim Special Edition  (nexus domain: skyrimspecialedition)
--   Fallout 4               (nexus domain: fallout4)
--   Cyberpunk 2077          (nexus domain: cyberpunk2077)
--   Baldur's Gate 3         (nexus domain: baldursgate3)
-- =============================================================================

-- (INSERT INTO games ... statements will be added here)


-- =============================================================================
-- SECTION 3 -- INSERT: TAGS
--
-- Populate the flat taxonomy of mod tags.
-- Slugs are URL-safe lowercased versions of the name.
--
-- Planned tags:
--   armor, weapons, quests, textures, ui, gameplay, new-lands,
--   lore-friendly, nsfw, adult-only, immersion, performance, followers,
--   animation, lighting, cities, magic, companions
-- =============================================================================

-- (INSERT INTO tags ... statements will be added here)


-- =============================================================================
-- SECTION 4 -- INSERT: MODS
--
-- Populate mods linked to the users and games inserted above.
-- The embedding column is intentionally left NULL here.
--
-- Planned mods (mix of games and categories):
--   Several Skyrim SE mods (armor, quests, graphics)
--   Several Fallout 4 mods (settlements, weapons, UI)
--   At least one mod per other game
-- =============================================================================

-- (INSERT INTO mods ... statements will be added here)


-- =============================================================================
-- SECTION 5 -- INSERT: MOD VERSIONS
--
-- Each mod receives at least one semver release.
-- Demonstrate multiple versions for at least two mods to exercise the
-- semver UNIQUE constraint and the is_primary flag.
--
-- Planned:
--   For each mod: version 1.0.0 (is_primary = TRUE)
--   For two mods: add 1.1.0 and 2.0.0 to demonstrate multi-version mods
-- =============================================================================

-- (INSERT INTO mod_versions ... statements will be added here)


-- =============================================================================
-- SECTION 6 -- INSERT: MOD DEPENDENCIES
--
-- Record dependency relationships between mod versions and required mods.
-- Covers all dep_type_enum values: required, optional, conflicts, recommends.
-- Covers all dep_source_enum values: manual, nexus, inferred.
-- =============================================================================

-- (INSERT INTO mod_dependencies ... statements will be added here)


-- =============================================================================
-- SECTION 7 -- INSERT: REVIEWS
--
-- Populate reviews from multiple users across multiple mods.
-- The uq_reviews_user_mod constraint (one review per user per mod) is
-- demonstrated by attempting a duplicate (and resolving it with ON CONFLICT).
-- =============================================================================

-- (INSERT INTO reviews ... statements will be added here)


-- =============================================================================
-- SECTION 8 -- INSERT: MOD TAGS
--
-- Associate mods with tags via the mod_tags join table.
-- Each mod receives 2-5 tags.
-- =============================================================================

-- (INSERT INTO mod_tags ... statements will be added here)


-- =============================================================================
-- SECTION 9 -- INSERT: LOADOUTS
--
-- Create loadouts belonging to different users for different games.
-- At least one loadout is public (is_public = TRUE) and one is private.
-- =============================================================================

-- (INSERT INTO loadouts ... statements will be added here)


-- =============================================================================
-- SECTION 10 -- INSERT: LOADOUT MODS
--
-- Assign mod versions to loadouts with explicit position ordering.
-- Demonstrates the chk_loadout_mods_position CHECK constraint
-- and the uq_loadout_mods_loadout_version UNIQUE constraint.
-- =============================================================================

-- (INSERT INTO loadout_mods ... statements will be added here)


-- =============================================================================
-- SECTION 11 -- INSERT: COMPATIBILITY MATRIX
--
-- Record pairwise compatibility status between mod versions.
-- Covers all compat_status_enum values: compatible, incompatible, unknown, partial.
-- The conflict_detail JSONB column is populated for incompatible/partial rows.
-- Pair canonicalisation (lower UUID as version_a_id) is done in application logic;
-- commented documentation explains the convention.
-- =============================================================================

-- (INSERT INTO compatibility_matrix ... statements will be added here)


-- =============================================================================
-- SECTION 12 -- UPDATE EXAMPLES
--
-- Demonstrate UPDATE ... WHERE ... patterns:
--   * Mark a mod as featured (mods.is_featured = TRUE) after the column is added
--   * Update a loadout name
--   * Promote a newer version to is_primary = TRUE while demoting the old one
--   * Change a compatibility status from 'unknown' to 'compatible'
-- =============================================================================

-- (UPDATE statements will be added here)


-- =============================================================================
-- SECTION 13 -- DELETE EXAMPLES
--
-- Demonstrate DELETE ... WHERE ... patterns:
--   * Remove a specific review (by review_id)
--   * Remove all mod tags for a given mod
--   * Cascade deletion: delete a loadout and observe loadout_mods cascade
-- =============================================================================

-- (DELETE statements will be added here)
