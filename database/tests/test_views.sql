

SET client_encoding = 'UTF8';
BEGIN;
DO $$
BEGIN
    ASSERT EXISTS (SELECT 1 FROM mod_catalog_view),          'mod_catalog_view is empty';
    ASSERT EXISTS (SELECT 1 FROM mod_ratings_view),          'mod_ratings_view is empty';
    ASSERT EXISTS (SELECT 1 FROM loadout_summary_view),      'loadout_summary_view is empty';
    ASSERT EXISTS (SELECT 1 FROM loadout_health_view),       'loadout_health_view is empty';
    ASSERT EXISTS (SELECT 1 FROM mod_conflict_summary_view), 'mod_conflict_summary_view is empty';
    ASSERT EXISTS (SELECT 1 FROM mv_game_leaderboard),       'mv_game_leaderboard is empty';
    RAISE NOTICE 'PASS 1 every view has rows';
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE
    l uuid;
BEGIN
    ASSERT NOT EXISTS (
        SELECT 1 FROM loadout_health_view h
        WHERE h.score <> fn_loadout_health_score(h.loadout_id)
           OR h.error_count + h.warning_count + h.info_count
              <> (SELECT count(*) FROM fn_check_loadout_compatibility(h.loadout_id))
           OR h.status <> CASE WHEN h.error_count > 0 THEN 'broken'
                               WHEN h.warning_count > 0 THEN 'warnings' ELSE 'healthy' END),
        'loadout_health_view disagrees with the health functions';

    INSERT INTO loadouts (user_id, game_id, name)
    VALUES ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'FX empty')
    RETURNING loadout_id INTO l;
    ASSERT (SELECT score = 100 AND status = 'healthy' AND error_count = 0 FROM loadout_health_view
            WHERE loadout_id = l), 'empty loadout is not healthy with score 100';
    RAISE NOTICE 'PASS 2 loadout_health_view matches the functions';
END $$;
ROLLBACK;
BEGIN;
DO $$
BEGIN
    ASSERT (SELECT (incompatible_pairs, partial_pairs, declared_conflicts, dependent_mods) = (1, 0, 1, 0)
            FROM mod_conflict_summary_view WHERE mod_id = 'c0000000-0000-0000-0000-000000000002'),
        'FX SkyUI conflict counts are wrong';
    ASSERT (SELECT dependent_mods FROM mod_conflict_summary_view
            WHERE mod_id = 'c0000000-0000-0000-0000-000000000001') = 2, 'FX Script Extender dependents wrong';
    RAISE NOTICE 'PASS 3 mod_conflict_summary_view counts';
END $$;
ROLLBACK;
BEGIN;
INSERT INTO reviews (user_id, mod_id, rating) VALUES
    ('b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000005', 5),
    ('b0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000005', 5),
    ('b0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000006', 2);
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_game_leaderboard;
DO $$
BEGIN
    ASSERT (SELECT bayes_score FROM mv_game_leaderboard WHERE mod_id = 'c0000000-0000-0000-0000-000000000005') = 4.2857,
        'F4SE bayes_score is wrong';
    ASSERT (SELECT bayes_score FROM mv_game_leaderboard WHERE mod_id = 'c0000000-0000-0000-0000-000000000006') = 3.6667,
        'Armorsmith bayes_score is wrong';
    ASSERT (SELECT rank_in_game FROM mv_game_leaderboard WHERE mod_id = 'c0000000-0000-0000-0000-000000000005') = 1,
        'F4SE should rank first in game B';
    ASSERT (SELECT max(rank_in_game) FROM mv_game_leaderboard) <= 20, 'rank above 20 kept';
    RAISE NOTICE 'PASS 4 leaderboard scores and refresh';
END $$;
ROLLBACK;
