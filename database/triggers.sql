

SET client_encoding = 'UTF8';

CREATE TRIGGER trg_compat_canonicalise_pair
    BEFORE INSERT OR UPDATE ON compatibility_matrix
    FOR EACH ROW EXECUTE FUNCTION fn_compat_canonicalise_pair();

CREATE TRIGGER trg_mod_version_single_primary
    BEFORE INSERT OR UPDATE OF is_primary ON mod_versions
    FOR EACH ROW EXECUTE FUNCTION fn_mod_version_single_primary();

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_mods_updated_at
    BEFORE UPDATE ON mods
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_loadouts_updated_at
    BEFORE UPDATE ON loadouts
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_compatibility_matrix_updated_at
    BEFORE UPDATE ON compatibility_matrix
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_loadout_mods_position
    BEFORE INSERT ON loadout_mods
    FOR EACH ROW EXECUTE FUNCTION fn_loadout_mods_auto_position();

CREATE TRIGGER trg_loadout_mods_game_check
    BEFORE INSERT OR UPDATE ON loadout_mods
    FOR EACH ROW EXECUTE FUNCTION fn_loadout_mods_game_check();

CREATE TRIGGER trg_reviews_rating_rollup
    AFTER INSERT OR UPDATE OR DELETE ON reviews
    FOR EACH ROW EXECUTE FUNCTION fn_reviews_rating_rollup();

CREATE TRIGGER trg_audit_users
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('user_id');

CREATE TRIGGER trg_audit_mods
    AFTER INSERT OR UPDATE OR DELETE ON mods
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('mod_id');

CREATE TRIGGER trg_audit_mod_versions
    AFTER INSERT OR UPDATE OR DELETE ON mod_versions
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('version_id');

CREATE TRIGGER trg_audit_mod_dependencies
    AFTER INSERT OR UPDATE OR DELETE ON mod_dependencies
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('dep_id');

CREATE TRIGGER trg_audit_compatibility_matrix
    AFTER INSERT OR UPDATE OR DELETE ON compatibility_matrix
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('compat_id');

CREATE TRIGGER trg_audit_loadouts
    AFTER INSERT OR UPDATE OR DELETE ON loadouts
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('loadout_id');

CREATE TRIGGER trg_audit_loadout_mods
    AFTER INSERT OR UPDATE OR DELETE ON loadout_mods
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('id');

CREATE TRIGGER trg_audit_reviews
    AFTER INSERT OR UPDATE OR DELETE ON reviews
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('review_id');

CREATE TRIGGER trg_audit_log_immutable
    BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log_immutable();
