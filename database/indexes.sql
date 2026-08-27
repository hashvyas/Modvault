-- =============================================================================
-- ModVault: A Mod Repository and Compatibility Intelligence System
-- Index Definitions  --  indexes.sql
--
-- PURPOSE
--   This file defines all non-primary-key indexes for the ModVault schema.
--   Indexes are maintained separately from schema.sql so that they can be
--   added, dropped, or rebuilt independently of the table definitions.
--
--   Required by the project rubric:
--     * CREATE INDEX (B-Tree, default)
--     * CREATE INDEX USING GIN  (for JSONB and full-text search columns)
--     * CREATE INDEX USING ivfflat / hnsw  (pgvector ANN search)
--     * CREATE UNIQUE INDEX  (enforces business-rule uniqueness on expressions)
--     * CONCURRENTLY option  (shown in comments; safe for production)
--     * Composite (multi-column) indexes
--     * Partial indexes (WHERE clause)
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
--   Run AFTER schema.sql (and optionally ddl_demo.sql for new columns).
--
-- HOW TO RUN
--   psql -d modvault -f database/schema.sql
--   psql -d modvault -f database/indexes.sql
-- =============================================================================


-- =============================================================================
-- SECTION 1 -- INDEXES ON: users
--
-- role index: accelerates user listing and RBAC filter queries.
-- created_at index: supports date-range analytics and recent-user queries.
-- =============================================================================

-- idx_users_role          ON users (role)
-- idx_users_created_at    ON users (created_at DESC)

-- (CREATE INDEX statements will be added here)


-- =============================================================================
-- SECTION 2 -- INDEXES ON: mods
--
-- author_id   FK lookup: accelerates "mods by user" queries.
-- game_id     FK lookup: accelerates "mods for game" queries.
-- created_at  DESC: supports "latest mods" feed and analytics.
-- is_featured PARTIAL: small index covering only featured mods for dashboards.
-- (is_featured column added by ddl_demo.sql)
-- =============================================================================

-- idx_mods_author_id       ON mods (author_id)
-- idx_mods_game_id         ON mods (game_id)
-- idx_mods_created_at      ON mods (created_at DESC)
-- idx_mods_featured        ON mods (game_id) WHERE is_featured = TRUE   -- partial

-- Full-text search index on mod name + summary:
-- idx_mods_fts             ON mods USING GIN (
--     to_tsvector('english', coalesce(name,'') || ' ' || coalesce(summary,''))
-- )

-- pgvector ANN index for semantic similarity search on mods.embedding:
-- idx_mods_embedding_ivfflat  ON mods USING ivfflat (embedding vector_cosine_ops)
--     WITH (lists = 100)
-- Alternative: HNSW (lower latency, higher build time)
-- idx_mods_embedding_hnsw     ON mods USING hnsw (embedding vector_cosine_ops)
--     WITH (m = 16, ef_construction = 64)

-- (CREATE INDEX statements will be added here)


-- =============================================================================
-- SECTION 3 -- INDEXES ON: mod_versions
--
-- mod_id FK lookup: accelerates version listing per mod.
-- uploaded_at DESC: supports "latest version" and changelog queries.
-- is_primary PARTIAL: tiny index to find primary versions instantly.
-- (mod_id, is_primary) composite: covers the "get primary version of mod" pattern.
-- =============================================================================

-- idx_mod_versions_mod_id       ON mod_versions (mod_id)
-- idx_mod_versions_uploaded_at  ON mod_versions (uploaded_at DESC)
-- idx_mod_versions_primary      ON mod_versions (mod_id, version_id) WHERE is_primary = TRUE

-- (CREATE INDEX statements will be added here)


-- =============================================================================
-- SECTION 4 -- INDEXES ON: mod_dependencies
--
-- dependent_version_id FK: accelerates forward dependency lookups.
-- required_mod_id FK: accelerates reverse dependency lookups (who needs this mod).
-- dep_type: filter by dependency kind (required, conflicts, etc.).
-- (dependent_version_id, dep_type) composite: combined filter.
-- =============================================================================

-- idx_mod_dependencies_dep_version   ON mod_dependencies (dependent_version_id)
-- idx_mod_dependencies_req_mod       ON mod_dependencies (required_mod_id)
-- idx_mod_dependencies_type          ON mod_dependencies (dep_type)

-- (CREATE INDEX statements will be added here)


-- =============================================================================
-- SECTION 5 -- INDEXES ON: reviews
--
-- user_id FK: accelerates "reviews by user" queries.
-- mod_id FK: accelerates "reviews for mod" and average-rating queries.
-- rating: accelerates rating-filtered queries and leaderboards.
-- created_at DESC: "latest reviews" feed.
-- =============================================================================

-- idx_reviews_user_id    ON reviews (user_id)
-- idx_reviews_mod_id     ON reviews (mod_id)
-- idx_reviews_rating     ON reviews (mod_id, rating)
-- idx_reviews_created_at ON reviews (created_at DESC)

-- (CREATE INDEX statements will be added here)


-- =============================================================================
-- SECTION 6 -- INDEXES ON: mod_tags
--
-- tag_id: accelerates "mods with this tag" queries (reverse lookup through join).
-- The (mod_id, tag_id) composite primary key already covers forward lookup.
-- =============================================================================

-- idx_mod_tags_tag_id    ON mod_tags (tag_id)

-- (CREATE INDEX statements will be added here)


-- =============================================================================
-- SECTION 7 -- INDEXES ON: loadouts
--
-- user_id FK: accelerates "loadouts by user" queries.
-- game_id FK: accelerates "loadouts for game" queries.
-- is_public PARTIAL: covers browsing of public loadouts only.
-- =============================================================================

-- idx_loadouts_user_id   ON loadouts (user_id)
-- idx_loadouts_game_id   ON loadouts (game_id)
-- idx_loadouts_public    ON loadouts (game_id, created_at DESC) WHERE is_public = TRUE

-- (CREATE INDEX statements will be added here)


-- =============================================================================
-- SECTION 8 -- INDEXES ON: loadout_mods
--
-- loadout_id FK: accelerates "mods in a loadout" queries.
-- version_id FK: accelerates "which loadouts contain this version" queries.
-- (loadout_id, position): composite for ordered loadout retrieval.
-- enabled PARTIAL: covers queries that show only active mods in a loadout.
-- =============================================================================

-- idx_loadout_mods_loadout_id  ON loadout_mods (loadout_id)
-- idx_loadout_mods_version_id  ON loadout_mods (version_id)
-- idx_loadout_mods_order       ON loadout_mods (loadout_id, position)
-- idx_loadout_mods_enabled     ON loadout_mods (loadout_id) WHERE enabled = TRUE

-- (CREATE INDEX statements will be added here)


-- =============================================================================
-- SECTION 9 -- INDEXES ON: compatibility_matrix
--
-- version_a_id FK: accelerates lookup of all records involving version A.
-- version_b_id FK: accelerates lookup of all records involving version B.
-- status: filter by compatibility status (e.g., all incompatible pairs).
-- verified_by FK: find records verified by a specific curator.
-- conflict_detail GIN: query inside the JSONB column (operator ? ->> @>).
-- updated_at DESC: most recently updated records.
-- =============================================================================

-- idx_compat_version_a      ON compatibility_matrix (version_a_id)
-- idx_compat_version_b      ON compatibility_matrix (version_b_id)
-- idx_compat_status         ON compatibility_matrix (status)
-- idx_compat_verified_by    ON compatibility_matrix (verified_by)
-- idx_compat_conflict_gin   ON compatibility_matrix USING GIN (conflict_detail)
-- idx_compat_updated_at     ON compatibility_matrix (updated_at DESC)

-- (CREATE INDEX statements will be added here)
