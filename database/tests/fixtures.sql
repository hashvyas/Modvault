-- =============================================================================
-- ModVault: A Mod Repository and Compatibility Intelligence System
-- Test fixtures  --  tests/fixtures.sql
--
-- PURPOSE
--   Small, hand-made data set for the SQL tests: 2 games, 3 users (one per
--   role), 6 mods, 8 versions, dependencies covering every dep_type, 4
--   compatibility rows (one per status), 2 loadouts.
--
--   Fixed UUIDs, so tests can refer to rows directly:
--     a...0N  games      b...0N  users      c...0N  mods
--     d...0N  versions   e...0N  loadouts
--   Game names, domains and usernames start with "fx" / "Fixture" so they never
--   clash with the real seed.
--
-- HOW TO RUN (after run_all.sql)
--   python scripts/db_reset.py
--   psql "postgresql://modvault_owner:modvault_owner_dev@localhost:5432/modvault" -v ON_ERROR_STOP=1 -f database/tests/fixtures.sql
-- =============================================================================

SET client_encoding = 'UTF8';

BEGIN;

INSERT INTO games (game_id, name, domain, current_version) VALUES
    ('a0000000-0000-0000-0000-000000000001', 'Fixture Game A', 'fx-game-a', '1.6.1170'),
    ('a0000000-0000-0000-0000-000000000002', 'Fixture Game B', 'fx-game-b', '1.10.163');

-- Password for all three: fixture-pass
INSERT INTO users (user_id, username, email, password_hash, role) VALUES
    ('b0000000-0000-0000-0000-000000000001', 'fx_modder',  'fx_modder@example.com',  crypt('fixture-pass', gen_salt('bf', 10)), 'modder'),
    ('b0000000-0000-0000-0000-000000000002', 'fx_curator', 'fx_curator@example.com', crypt('fixture-pass', gen_salt('bf', 10)), 'curator'),
    ('b0000000-0000-0000-0000-000000000003', 'fx_admin',   'fx_admin@example.com',   crypt('fixture-pass', gen_salt('bf', 10)), 'admin');

INSERT INTO mods (mod_id, game_id, nexus_mod_id, nexus_author, name, summary, category) VALUES
    ('c0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'fx-1', 'fx author', 'FX Script Extender', 'Script extender required by many mods',  'Utilities'),
    ('c0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'fx-2', 'fx author', 'FX SkyUI',           'Menu and inventory interface overhaul',  'User Interface'),
    ('c0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'fx-3', 'fx author', 'FX Unofficial Patch', 'Fixes thousands of bugs',               'Patches'),
    ('c0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'fx-4', 'fx author', 'FX Alternate UI',    'Another interface overhaul',             'User Interface'),
    ('c0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000002', 'fx-5', 'fx author', 'FX F4 Script Extender', 'Script extender for game B',           'Utilities'),
    ('c0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000002', 'fx-6', 'fx author', 'FX Armorsmith',      'Armor crafting framework',               'Gameplay');

INSERT INTO mod_versions (version_id, mod_id, semver, supported_game_versions, is_primary) VALUES
    ('d0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', '2.2.6',  '{1.6.1170}', TRUE),
    ('d0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000002', '5.2.0',  '{}',         TRUE),
    ('d0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000002', '5.1.0',  '{}',         FALSE),
    ('d0000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-000000000003', '4.3.0',  '{}',         TRUE),
    ('d0000000-0000-0000-0000-000000000005', 'c0000000-0000-0000-0000-000000000004', '1.0.0',  '{}',         TRUE),
    ('d0000000-0000-0000-0000-000000000006', 'c0000000-0000-0000-0000-000000000005', '0.6.23', '{1.10.163}', TRUE),
    ('d0000000-0000-0000-0000-000000000007', 'c0000000-0000-0000-0000-000000000006', '2.0.0',  '{}',         TRUE),
    ('d0000000-0000-0000-0000-000000000008', 'c0000000-0000-0000-0000-000000000006', '1.0.0',  '{}',         FALSE);

-- required, recommends, conflicts, optional all appear.
INSERT INTO mod_dependencies (dependent_version_id, required_mod_id, version_constraint, dep_type) VALUES
    ('d0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001', '>=2.2', 'required'),
    ('d0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000003', NULL,    'recommends'),
    ('d0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000004', NULL,    'conflicts'),
    ('d0000000-0000-0000-0000-000000000005', 'c0000000-0000-0000-0000-000000000001', NULL,    'optional'),
    ('d0000000-0000-0000-0000-000000000007', 'c0000000-0000-0000-0000-000000000005', '>=0.6', 'required');

-- One row per status. The incompatible row is given in (B, A) order on purpose.
INSERT INTO compatibility_matrix (version_a_id, version_b_id, status, conflict_detail, verified_by) VALUES
    ('d0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000004', 'compatible',   NULL, 'b0000000-0000-0000-0000-000000000002'),
    ('d0000000-0000-0000-0000-000000000005', 'd0000000-0000-0000-0000-000000000002', 'incompatible', '{"reason": "both replace the inventory menu"}', 'b0000000-0000-0000-0000-000000000002'),
    ('d0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000004', 'unknown',      NULL, NULL),
    ('d0000000-0000-0000-0000-000000000006', 'd0000000-0000-0000-0000-000000000007', 'partial',      '{"reason": "needs the F4SE build for 1.10.163"}', 'b0000000-0000-0000-0000-000000000002');

INSERT INTO loadouts (loadout_id, user_id, game_id, name, game_version, is_public) VALUES
    ('e0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'FX private game A loadout', '1.6.1170', FALSE),
    ('e0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000002', 'FX public game B loadout',  NULL,       TRUE);

INSERT INTO loadout_mods (loadout_id, version_id, position) VALUES
    ('e0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 0),
    ('e0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002', 1),
    ('e0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000004', 2),
    ('e0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000006', 0),
    ('e0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000007', 1);

COMMIT;
