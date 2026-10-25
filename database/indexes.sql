-- =============================================================================
-- ModVault: A Mod Repository and Compatibility Intelligence System
-- Index Definitions  --  indexes.sql
--
-- PURPOSE
--   This file defines all non-primary-key indexes for the ModVault schema.
--   Indexes are maintained separately from schema.sql so that they can be
--   added, dropped, or rebuilt independently of the table definitions.
--
--   This file demonstrates:
--     * CREATE INDEX using PostgreSQL's default B-tree indexes
--     * Supplementary indexes on frequently queried foreign-key columns
--     * Indexes designed around expected ModVault query patterns
--
-- NOTES
--   * Primary key indexes are created automatically by PostgreSQL when the
--     PRIMARY KEY constraint is declared in schema.sql; they are NOT repeated
--     here to avoid duplication.
--   * UNIQUE constraints declared inline in schema.sql also create backing
--     indexes automatically.  Only supplementary indexes are defined here.
--   * Index names follow the convention:  idx_<table>_<column(s)>
--
-- DEPENDENCY
--   Included by database/run_all.sql, after schema.sql.
--
-- HOW TO RUN
--   Do not run this file alone. It is included by database/run_all.sql.
--   Rebuild everything with:  python scripts/db_reset.py
-- =============================================================================

SET client_encoding = 'UTF8';


-- =============================================================================
-- SECTION 1 -- INDEXES ON: users
-- =============================================================================
-- No core indexes implemented here yet.
-- Planned: idx_users_role (role filter), idx_users_created_at DESC (analytics).


-- =============================================================================
-- SECTION 2 -- INDEXES ON: mods
-- =============================================================================

-- Speeds up "all mods for a given game" queries, which are the primary
-- browsing query on the ModVault front page and in loadout-building flows.
CREATE INDEX idx_mods_game_id
    ON mods (game_id);

-- Speeds up "all mods by a given author" queries used on user profile pages
-- and for enforcing per-author limits at the application layer.
CREATE INDEX idx_mods_author_id
    ON mods (author_id);

-- HNSW approximate nearest-neighbour index for semantic search
-- (embedding <=> query, cosine distance).
CREATE INDEX idx_mods_embedding_hnsw
    ON mods USING hnsw (embedding vector_cosine_ops);

-- GIN index for full-text keyword search (search_tsv @@ tsquery).
CREATE INDEX idx_mods_search_tsv
    ON mods USING gin (search_tsv);


-- =============================================================================
-- SECTION 3 -- INDEXES ON: mod_versions
-- =============================================================================

-- Speeds up "list all versions of a mod" and "find primary version" queries.
-- mod_versions is joined to mods on nearly every version-aware query, so this
-- FK lookup index has broad impact across the application.
CREATE INDEX idx_mod_versions_mod_id
    ON mod_versions (mod_id);

-- GIN index for array containment on supported game versions
-- (supported_game_versions @> ARRAY['1.6.1170']).
CREATE INDEX idx_mod_versions_supported
    ON mod_versions USING gin (supported_game_versions);

-- Partial unique index: at most one primary version per mod. Backstop for
-- trg_mod_version_single_primary.
CREATE UNIQUE INDEX uq_mod_versions_one_primary
    ON mod_versions (mod_id) WHERE is_primary;


-- =============================================================================
-- SECTION 4 -- INDEXES ON: mod_dependencies
-- =============================================================================

-- Speeds up forward dependency lookups: "what does version X depend on?"
-- This is the hot path for dependency-tree traversal and conflict detection.
CREATE INDEX idx_mod_dependencies_dependent_version
    ON mod_dependencies (dependent_version_id);

-- Speeds up reverse dependency lookups: "which versions depend on mod X?"
CREATE INDEX idx_mod_dependencies_required_mod
    ON mod_dependencies (required_mod_id);


-- =============================================================================
-- SECTION 5 -- INDEXES ON: reviews
-- =============================================================================

-- Speeds up "all reviews for a mod" queries and the average-rating aggregate
-- used on mod detail pages and leaderboards.
CREATE INDEX idx_reviews_mod_id
    ON reviews (mod_id);


-- =============================================================================
-- SECTION 6 -- INDEXES ON: mod_tags
-- =============================================================================
-- No core indexes implemented here yet.
-- Planned: idx_mod_tags_tag_id (reverse tag lookup through join table).


-- =============================================================================
-- SECTION 7 -- INDEXES ON: loadouts
-- =============================================================================

-- Speeds up "all loadouts owned by a user" queries used on the user
-- dashboard and profile pages.
CREATE INDEX idx_loadouts_user_id
    ON loadouts (user_id);


-- =============================================================================
-- SECTION 8 -- INDEXES ON: loadout_mods
-- =============================================================================

-- Speeds up "all mod versions in a loadout" queries.  This is the primary
-- join used whenever a loadout is rendered or exported.
CREATE INDEX idx_loadout_mods_loadout_id
    ON loadout_mods (loadout_id);


-- =============================================================================
-- SECTION 9 -- INDEXES ON: compatibility_matrix
-- =============================================================================

-- Speeds up lookups of all compatibility records where a given version
-- appears as the left-hand (A) side of the pair.
CREATE INDEX idx_compatibility_version_a
    ON compatibility_matrix (version_a_id);

-- Speeds up lookups of all compatibility records where a given version
-- appears as the right-hand (B) side of the pair.  Together with
-- idx_compatibility_version_a, every version-centric compatibility query
-- is covered without a sequential scan.
CREATE INDEX idx_compatibility_version_b
    ON compatibility_matrix (version_b_id);


-- =============================================================================
-- SECTION 10 -- INDEXES ON: audit_log
-- =============================================================================

-- Speeds up "recent changes to table X" in the admin audit view.
CREATE INDEX idx_audit_log_table_time
    ON audit_log (table_name, changed_at DESC);

-- Speeds up "all changes made by user X".
CREATE INDEX idx_audit_log_changed_by
    ON audit_log (changed_by);
