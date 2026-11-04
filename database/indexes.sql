

SET client_encoding = 'UTF8';
CREATE INDEX idx_mods_game_id
    ON mods (game_id);
CREATE INDEX idx_mods_author_id
    ON mods (author_id);
CREATE INDEX idx_mods_embedding_hnsw
    ON mods USING hnsw (embedding vector_cosine_ops);
CREATE INDEX idx_mods_search_tsv
    ON mods USING gin (search_tsv);
CREATE INDEX idx_mod_versions_mod_id
    ON mod_versions (mod_id);
CREATE INDEX idx_mod_versions_supported
    ON mod_versions USING gin (supported_game_versions);
CREATE UNIQUE INDEX uq_mod_versions_one_primary
    ON mod_versions (mod_id) WHERE is_primary;
CREATE INDEX idx_mod_dependencies_dependent_version
    ON mod_dependencies (dependent_version_id);
CREATE INDEX idx_mod_dependencies_required_mod
    ON mod_dependencies (required_mod_id);
CREATE INDEX idx_reviews_mod_id
    ON reviews (mod_id);
CREATE INDEX idx_loadouts_user_id
    ON loadouts (user_id);
CREATE INDEX idx_loadout_mods_loadout_id
    ON loadout_mods (loadout_id);
CREATE INDEX idx_compatibility_version_a
    ON compatibility_matrix (version_a_id);
CREATE INDEX idx_compatibility_version_b
    ON compatibility_matrix (version_b_id);
CREATE INDEX idx_audit_log_table_time
    ON audit_log (table_name, changed_at DESC);
CREATE INDEX idx_audit_log_changed_by
    ON audit_log (changed_by);
