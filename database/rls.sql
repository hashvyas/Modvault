

SET client_encoding = 'UTF8';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'modvault_app') THEN
        CREATE ROLE modvault_app LOGIN PASSWORD 'modvault_app_dev';
    END IF;
END $$;

GRANT USAGE ON SCHEMA public TO modvault_app;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO modvault_app;
REVOKE EXECUTE ON FUNCTION  fn_register_user(text, text, text)        FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION  fn_authenticate(text, text)               FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION  fn_audit_log()                            FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION  fn_reviews_rating_rollup()                FROM PUBLIC;
REVOKE EXECUTE ON PROCEDURE pr_set_user_role(uuid, user_role_enum)    FROM PUBLIC;
REVOKE EXECUTE ON PROCEDURE pr_refresh_reports()                      FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION  fn_register_user(text, text, text)        TO modvault_app;
GRANT  EXECUTE ON FUNCTION  fn_authenticate(text, text)               TO modvault_app;
GRANT  EXECUTE ON FUNCTION  fn_audit_log()                            TO modvault_app;
GRANT  EXECUTE ON FUNCTION  fn_reviews_rating_rollup()                TO modvault_app;
GRANT  EXECUTE ON PROCEDURE pr_set_user_role(uuid, user_role_enum)    TO modvault_app;
GRANT  EXECUTE ON PROCEDURE pr_refresh_reports()                      TO modvault_app;
GRANT SELECT (user_id, username, email, role, is_active, created_at, updated_at) ON users TO modvault_app;

GRANT SELECT ON games, tags, mods, mod_versions, reviews, mod_tags, mod_dependencies,
                loadouts, loadout_mods, compatibility_matrix, audit_log,
                mod_catalog_view, mod_ratings_view, loadout_summary_view,
                loadout_health_view, mod_conflict_summary_view, mv_game_leaderboard
      TO modvault_app;

GRANT INSERT, UPDATE, DELETE ON loadouts, loadout_mods, reviews, compatibility_matrix,
                                mod_dependencies, mod_tags
      TO modvault_app;

GRANT INSERT, UPDATE ON mods, mod_versions, tags TO modvault_app;
ALTER TABLE loadouts ENABLE ROW LEVEL SECURITY;

CREATE POLICY loadouts_select ON loadouts FOR SELECT
    USING (is_public OR user_id = fn_current_user_id() OR fn_current_role() = 'admin');
CREATE POLICY loadouts_insert ON loadouts FOR INSERT
    WITH CHECK (user_id = fn_current_user_id());
CREATE POLICY loadouts_update ON loadouts FOR UPDATE
    USING (user_id = fn_current_user_id())
    WITH CHECK (user_id = fn_current_user_id());
CREATE POLICY loadouts_delete ON loadouts FOR DELETE
    USING (user_id = fn_current_user_id());
ALTER TABLE loadout_mods ENABLE ROW LEVEL SECURITY;

CREATE POLICY loadout_mods_select ON loadout_mods FOR SELECT
    USING (EXISTS (SELECT 1 FROM loadouts l WHERE l.loadout_id = loadout_mods.loadout_id));
CREATE POLICY loadout_mods_insert ON loadout_mods FOR INSERT
    WITH CHECK (EXISTS (SELECT 1 FROM loadouts l
                        WHERE l.loadout_id = loadout_mods.loadout_id AND l.user_id = fn_current_user_id()));
CREATE POLICY loadout_mods_update ON loadout_mods FOR UPDATE
    USING (EXISTS (SELECT 1 FROM loadouts l
                   WHERE l.loadout_id = loadout_mods.loadout_id AND l.user_id = fn_current_user_id()))
    WITH CHECK (EXISTS (SELECT 1 FROM loadouts l
                        WHERE l.loadout_id = loadout_mods.loadout_id AND l.user_id = fn_current_user_id()));
CREATE POLICY loadout_mods_delete ON loadout_mods FOR DELETE
    USING (EXISTS (SELECT 1 FROM loadouts l
                   WHERE l.loadout_id = loadout_mods.loadout_id AND l.user_id = fn_current_user_id()));
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;

CREATE POLICY reviews_select ON reviews FOR SELECT USING (true);
CREATE POLICY reviews_insert ON reviews FOR INSERT
    WITH CHECK (user_id = fn_current_user_id());
CREATE POLICY reviews_update ON reviews FOR UPDATE
    USING (user_id = fn_current_user_id())
    WITH CHECK (user_id = fn_current_user_id());
CREATE POLICY reviews_delete ON reviews FOR DELETE
    USING (user_id = fn_current_user_id());
ALTER TABLE compatibility_matrix ENABLE ROW LEVEL SECURITY;

CREATE POLICY compatibility_matrix_select ON compatibility_matrix FOR SELECT USING (true);
CREATE POLICY compatibility_matrix_insert ON compatibility_matrix FOR INSERT
    WITH CHECK (fn_current_role() IN ('curator', 'admin'));
CREATE POLICY compatibility_matrix_update ON compatibility_matrix FOR UPDATE
    USING (fn_current_role() IN ('curator', 'admin'))
    WITH CHECK (fn_current_role() IN ('curator', 'admin'));
CREATE POLICY compatibility_matrix_delete ON compatibility_matrix FOR DELETE
    USING (fn_current_role() IN ('curator', 'admin'));
ALTER TABLE mod_dependencies ENABLE ROW LEVEL SECURITY;

CREATE POLICY mod_dependencies_select ON mod_dependencies FOR SELECT USING (true);
CREATE POLICY mod_dependencies_insert ON mod_dependencies FOR INSERT
    WITH CHECK (fn_current_role() IN ('curator', 'admin'));
CREATE POLICY mod_dependencies_update ON mod_dependencies FOR UPDATE
    USING (fn_current_role() IN ('curator', 'admin'))
    WITH CHECK (fn_current_role() IN ('curator', 'admin'));
CREATE POLICY mod_dependencies_delete ON mod_dependencies FOR DELETE
    USING (fn_current_role() IN ('curator', 'admin'));
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY audit_log_select ON audit_log FOR SELECT
    USING (fn_current_role() = 'admin');
