-- =============================================================================
-- ModVault: A Mod Repository and Compatibility Intelligence System
-- Roles and Row-Level Security  --  rls.sql
--
-- PURPOSE
--   Creates the modvault_app login role (the web app), its grants, and the
--   Row-Level Security policies. modvault_owner owns every object and is not
--   subject to RLS; modvault_app is.
--
--   Policies read the session context set by the app in every transaction:
--     fn_current_user_id()  <- app.user_id
--     fn_current_role()     <- app.role ('anonymous' when unset)
--
--   This file demonstrates:
--     * CREATE ROLE inside a DO block (idempotent)
--     * Column-level GRANT (users.password_hash is never readable)
--     * ALTER TABLE ... ENABLE ROW LEVEL SECURITY
--     * CREATE POLICY ... USING / WITH CHECK
--
-- DEPENDENCY
--   Included by database/run_all.sql, after views.sql.
--
-- HOW TO RUN
--   Do not run this file alone. It is included by database/run_all.sql.
--   Rebuild everything with:  python scripts/db_reset.py
-- =============================================================================

SET client_encoding = 'UTF8';


-- =============================================================================
-- SECTION 1 -- ROLE
-- Roles belong to the cluster, not the schema, so db_reset.py does not drop it.
-- =============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'modvault_app') THEN
        -- Development password. Production changes it with ALTER ROLE modvault_app PASSWORD '...'.
        CREATE ROLE modvault_app LOGIN PASSWORD 'modvault_app_dev';
    END IF;
END $$;


-- =============================================================================
-- SECTION 2 -- GRANTS
-- =============================================================================

GRANT USAGE ON SCHEMA public TO modvault_app;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO modvault_app;

-- Column list, not a table grant: a column REVOKE would not override a table
-- grant, and password_hash must stay unreadable.
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

-- No write grant on users or audit_log: users change through SECURITY DEFINER
-- routines (fn_register_user, pr_set_user_role), audit rows through fn_audit_log.


-- =============================================================================
-- SECTION 3 -- ROW-LEVEL SECURITY
-- FOR ALL policies cover SELECT too, so each table with a stricter write rule
-- gets one SELECT policy and one write policy per command.
-- =============================================================================

-- loadouts: read public, own or (admin) any; write own only.
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

-- loadout_mods: follow the parent loadout. The subquery on loadouts is itself
-- filtered by the loadouts policies.
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

-- reviews: everyone reads; authors write their own.
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;

CREATE POLICY reviews_select ON reviews FOR SELECT USING (true);
CREATE POLICY reviews_insert ON reviews FOR INSERT
    WITH CHECK (user_id = fn_current_user_id());
CREATE POLICY reviews_update ON reviews FOR UPDATE
    USING (user_id = fn_current_user_id())
    WITH CHECK (user_id = fn_current_user_id());
CREATE POLICY reviews_delete ON reviews FOR DELETE
    USING (user_id = fn_current_user_id());

-- compatibility_matrix: everyone reads; curators and admins write.
ALTER TABLE compatibility_matrix ENABLE ROW LEVEL SECURITY;

CREATE POLICY compatibility_matrix_select ON compatibility_matrix FOR SELECT USING (true);
CREATE POLICY compatibility_matrix_insert ON compatibility_matrix FOR INSERT
    WITH CHECK (fn_current_role() IN ('curator', 'admin'));
CREATE POLICY compatibility_matrix_update ON compatibility_matrix FOR UPDATE
    USING (fn_current_role() IN ('curator', 'admin'))
    WITH CHECK (fn_current_role() IN ('curator', 'admin'));
CREATE POLICY compatibility_matrix_delete ON compatibility_matrix FOR DELETE
    USING (fn_current_role() IN ('curator', 'admin'));

-- mod_dependencies: everyone reads; curators and admins write.
ALTER TABLE mod_dependencies ENABLE ROW LEVEL SECURITY;

CREATE POLICY mod_dependencies_select ON mod_dependencies FOR SELECT USING (true);
CREATE POLICY mod_dependencies_insert ON mod_dependencies FOR INSERT
    WITH CHECK (fn_current_role() IN ('curator', 'admin'));
CREATE POLICY mod_dependencies_update ON mod_dependencies FOR UPDATE
    USING (fn_current_role() IN ('curator', 'admin'))
    WITH CHECK (fn_current_role() IN ('curator', 'admin'));
CREATE POLICY mod_dependencies_delete ON mod_dependencies FOR DELETE
    USING (fn_current_role() IN ('curator', 'admin'));

-- audit_log: admins read; nobody writes through the app role (no policy and
-- no grant). fn_audit_log is SECURITY DEFINER and runs as the owner.
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY audit_log_select ON audit_log FOR SELECT
    USING (fn_current_role() = 'admin');
