

SET client_encoding = 'UTF8';
BEGIN;
DO $$
BEGIN
    INSERT INTO mod_dependencies (dependent_version_id, required_mod_id, dep_type)
    VALUES ('d0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000003', 'required');

    ASSERT (SELECT array_agg(depth ORDER BY depth)
            FROM fn_get_mod_dependency_tree('d0000000-0000-0000-0000-000000000005')) = ARRAY[0, 1, 2],
        'chain depths are not 0, 1, 2';
    ASSERT (SELECT parent_version_id IS NULL AND dep_type IS NULL
            FROM fn_get_mod_dependency_tree('d0000000-0000-0000-0000-000000000005') WHERE depth = 0),
        'root row must have NULL parent and dep_type';
    ASSERT (SELECT version_id = 'd0000000-0000-0000-0000-000000000004'
                   AND parent_version_id = 'd0000000-0000-0000-0000-000000000001'
                   AND dep_type = 'required'
                   AND path = ARRAY['d0000000-0000-0000-0000-000000000005', 'd0000000-0000-0000-0000-000000000001',
                                    'd0000000-0000-0000-0000-000000000004']::uuid[]
            FROM fn_get_mod_dependency_tree('d0000000-0000-0000-0000-000000000005') WHERE depth = 2),
        'depth 2 row is wrong';
    RAISE NOTICE 'PASS 1 dependency chain depths 0, 1, 2';
END $$;
ROLLBACK;
DO $$
BEGIN
    ASSERT (SELECT array_agg(version_id ORDER BY version_id)
            FROM fn_get_mod_dependency_tree('d0000000-0000-0000-0000-000000000002')) =
           ARRAY['d0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002',
                 'd0000000-0000-0000-0000-000000000004']::uuid[],
        'tree of SkyUI must be d1, d2, d4 (no conflicting d5)';
    ASSERT (SELECT count(*) FROM fn_get_mod_dependency_tree('d0000000-0000-0000-0000-000000000003')) = 1,
        'version without dependencies must give only the root';
    ASSERT (SELECT count(*) FROM fn_get_mod_dependency_tree(gen_random_uuid())) = 0,
        'unknown version returned rows';
    RAISE NOTICE 'PASS 2 conflicts not followed';
END $$;
BEGIN;
DO $$
BEGIN
    INSERT INTO mod_dependencies (dependent_version_id, required_mod_id, dep_type)
    VALUES ('d0000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-000000000002', 'required');

    ASSERT (SELECT count(*) FROM fn_get_mod_dependency_tree('d0000000-0000-0000-0000-000000000004')) = 3,
        'cycle tree must be d4, d2, d1';
    ASSERT (SELECT count(*) FROM fn_get_mod_dependency_tree('d0000000-0000-0000-0000-000000000004')
            WHERE version_id = 'd0000000-0000-0000-0000-000000000004') = 1,
        'cycle start appears more than once';
    RAISE NOTICE 'PASS 3 cycle terminates';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    l uuid;
BEGIN
    INSERT INTO mod_dependencies (dependent_version_id, required_mod_id, dep_type)
    VALUES ('d0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000003', 'required');
    INSERT INTO loadouts (user_id, game_id, name)
    VALUES ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'FX shuffled')
    RETURNING loadout_id INTO l;
    INSERT INTO loadout_mods (loadout_id, version_id, position) VALUES
        (l, 'd0000000-0000-0000-0000-000000000002', 0),
        (l, 'd0000000-0000-0000-0000-000000000004', 5),
        (l, 'd0000000-0000-0000-0000-000000000001', 9);

    ASSERT (SELECT array_agg(version_id ORDER BY suggested_position) FROM fn_suggest_load_order(l)) =
           ARRAY['d0000000-0000-0000-0000-000000000004', 'd0000000-0000-0000-0000-000000000001',
                 'd0000000-0000-0000-0000-000000000002']::uuid[],
        'suggested order is not d4, d1, d2';
    ASSERT (SELECT array_agg(suggested_position ORDER BY suggested_position) FROM fn_suggest_load_order(l)) = ARRAY[0, 1, 2],
        'positions are not 0 to n-1';
    ASSERT NOT EXISTS (
        SELECT 1
        FROM   fn_suggest_load_order(l) a
        JOIN   mod_dependencies d ON d.dependent_version_id = a.version_id AND d.dep_type <> 'conflicts'
        JOIN   mod_versions v ON v.mod_id = d.required_mod_id
        JOIN   fn_suggest_load_order(l) b ON b.version_id = v.version_id
        WHERE  b.suggested_position > a.suggested_position),
        'a dependency is placed after its dependent';
    RAISE NOTICE 'PASS 4 load order puts dependencies first';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    l uuid;
BEGIN
    INSERT INTO mod_dependencies (dependent_version_id, required_mod_id, dep_type)
    VALUES ('d0000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-000000000002', 'required');
    INSERT INTO loadouts (user_id, game_id, name)
    VALUES ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'FX cycle')
    RETURNING loadout_id INTO l;
    INSERT INTO loadout_mods (loadout_id, version_id, position) VALUES
        (l, 'd0000000-0000-0000-0000-000000000002', 0),
        (l, 'd0000000-0000-0000-0000-000000000004', 1);
    ASSERT (SELECT array_agg(suggested_position ORDER BY suggested_position) FROM fn_suggest_load_order(l)) = ARRAY[0, 1],
        'cycle loadout does not return positions 0 and 1';
    RAISE NOTICE 'PASS 5 load order survives a cycle';
END $$;
ROLLBACK;
DO $$
DECLARE
    s record;
BEGIN
    SELECT * INTO s FROM fn_mod_stats('c0000000-0000-0000-0000-000000000002');
    ASSERT s.version_count = 2 AND s.dependent_count = 0 AND s.conflict_count = 1, 'SkyUI stats wrong';
    SELECT * INTO s FROM fn_mod_stats('c0000000-0000-0000-0000-000000000004');
    ASSERT s.conflict_count = 1, 'Alternate UI conflict_count wrong';
    SELECT * INTO s FROM fn_mod_stats('c0000000-0000-0000-0000-000000000001');
    ASSERT s.version_count = 1 AND s.dependent_count = 2 AND s.conflict_count = 0, 'Script Extender stats wrong';
    ASSERT (SELECT count(*) FROM fn_mod_stats(gen_random_uuid())) = 0, 'unknown mod returned a row';
    RAISE NOTICE 'PASS 6 mod stats';
END $$;
BEGIN;
DO $$
BEGIN
    INSERT INTO tags (tag_id, name, slug) VALUES
        ('f0000000-0000-0000-0000-000000000001', 'FX UI',    'fx-ui'),
        ('f0000000-0000-0000-0000-000000000002', 'FX Menus', 'fx-menus');
    INSERT INTO mod_tags (mod_id, tag_id) VALUES
        ('c0000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000001'),
        ('c0000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000002'),
        ('c0000000-0000-0000-0000-000000000004', 'f0000000-0000-0000-0000-000000000001');

    ASSERT (SELECT array_agg(mod_id ORDER BY mod_id) FROM fn_search_mods_by_tag('fx-ui')) =
           ARRAY['c0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000004']::uuid[],
        'single tag must match SkyUI and Alternate UI';
    ASSERT (SELECT array_agg(mod_id) FROM fn_search_mods_by_tag('fx-ui', 'fx-menus')) =
           ARRAY['c0000000-0000-0000-0000-000000000002']::uuid[],
        'two tags must match only SkyUI';
    ASSERT (SELECT count(*) FROM fn_search_mods_by_tag('fx-ui', 'fx-no-such-tag')) = 0,
        'unknown tag must match nothing';
    RAISE NOTICE 'PASS 7 tag search is an AND match';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    s record;
BEGIN
    INSERT INTO mod_dependencies (dependent_version_id, required_mod_id, dep_type)
    VALUES ('d0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000004', 'conflicts');
    INSERT INTO compatibility_matrix (version_a_id, version_b_id, status)
    VALUES ('d0000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000005', 'incompatible');

    SELECT * INTO s FROM fn_mod_stats('c0000000-0000-0000-0000-000000000002');
    ASSERT s.version_count = 2 AND s.conflict_count = 1,
        format('SkyUI: expected 2 versions and 1 conflicting mod, got %s and %s', s.version_count, s.conflict_count);
    SELECT * INTO s FROM fn_mod_stats('c0000000-0000-0000-0000-000000000004');
    ASSERT s.conflict_count = 1, format('Alternate UI: expected 1 conflicting mod, got %s', s.conflict_count);
    RAISE NOTICE 'PASS 8 conflict_count counts distinct conflicting mods';
END $$;
ROLLBACK;
