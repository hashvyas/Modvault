-- =============================================================================
-- ModVault: A Mod Repository and Compatibility Intelligence System
-- Hybrid search tests  --  tests/test_search.sql
--
-- Hand-made 384-dim vectors: e(i) is 1 at dimension i and 0 elsewhere.
-- Game A embeddings set inside the test:
--   SkyUI (c2) = e(1)          Alternate UI (c4) = mostly e(1), a bit of e(2)
--   Unofficial Patch (c3) = e(3)   Script Extender (c1) = e(4)
--
-- Each check runs inside BEGIN ... ROLLBACK and leaves no data behind.
-- A failed ASSERT stops the run (ON_ERROR_STOP=1). Each passing check prints
-- a NOTICE starting with PASS.
--
-- HOW TO RUN (after run_all.sql and tests/fixtures.sql)
--   psql "postgresql://modvault_owner:modvault_owner_dev@localhost:5432/modvault" -v ON_ERROR_STOP=1 -f database/tests/test_search.sql
-- =============================================================================

SET client_encoding = 'UTF8';

-- Test helper, dropped with the session: weight a at dimension i plus weight b at dimension j.
CREATE FUNCTION pg_temp.fx_vec(i int, a float8 DEFAULT 1, j int DEFAULT NULL, b float8 DEFAULT 0)
RETURNS vector LANGUAGE sql IMMUTABLE AS $$
    SELECT ('[' || string_agg(CASE g WHEN i THEN a::text WHEN j THEN b::text ELSE '0' END, ',' ORDER BY g) || ']')::vector(384)
    FROM generate_series(1, 384) AS g
$$;

CREATE FUNCTION pg_temp.fx_set_embeddings()
RETURNS void LANGUAGE sql AS $$
    UPDATE mods SET embedding = CASE mod_id
        WHEN 'c0000000-0000-0000-0000-000000000002' THEN pg_temp.fx_vec(1)
        WHEN 'c0000000-0000-0000-0000-000000000004' THEN pg_temp.fx_vec(1, 0.9, 2, 0.436)
        WHEN 'c0000000-0000-0000-0000-000000000003' THEN pg_temp.fx_vec(3)
        WHEN 'c0000000-0000-0000-0000-000000000001' THEN pg_temp.fx_vec(4)
        ELSE pg_temp.fx_vec(5)
    END
    WHERE game_id IN ('a0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002');
$$;


-- 1. Keyword-only query: keyword hits only, semantic_rank NULL.
BEGIN;
DO $$
BEGIN
    PERFORM pg_temp.fx_set_embeddings();
    ASSERT (SELECT array_agg(mod_id ORDER BY mod_id)
            FROM fn_search_mods_hybrid('interface', NULL, 'a0000000-0000-0000-0000-000000000001', 10)) =
           ARRAY['c0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000004']::uuid[],
        'keyword search for "interface" must return SkyUI and Alternate UI';
    ASSERT (SELECT bool_and(semantic_rank IS NULL AND keyword_rank IS NOT NULL)
            FROM fn_search_mods_hybrid('interface', NULL, 'a0000000-0000-0000-0000-000000000001', 10)),
        'keyword-only rows must have NULL semantic_rank';
    RAISE NOTICE 'PASS 1 keyword-only search';
END $$;
ROLLBACK;


-- 2. Vector-only query: semantic hits only, nearest first.
BEGIN;
DO $$
BEGIN
    PERFORM pg_temp.fx_set_embeddings();
    ASSERT (SELECT count(*) FROM fn_search_mods_hybrid('', pg_temp.fx_vec(1), 'a0000000-0000-0000-0000-000000000001', 10)) = 4,
        'vector search must return the 4 game A mods';
    ASSERT (SELECT bool_and(keyword_rank IS NULL AND semantic_rank IS NOT NULL)
            FROM fn_search_mods_hybrid(NULL, pg_temp.fx_vec(1), 'a0000000-0000-0000-0000-000000000001', 10)),
        'vector-only rows must have NULL keyword_rank';
    ASSERT (SELECT array_agg(mod_id ORDER BY semantic_rank) FILTER (WHERE semantic_rank <= 2)
            FROM fn_search_mods_hybrid('   ', pg_temp.fx_vec(1), 'a0000000-0000-0000-0000-000000000001', 10)) =
           ARRAY['c0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000004']::uuid[],
        'nearest vectors must be SkyUI then Alternate UI';
    RAISE NOTICE 'PASS 2 vector-only search';
END $$;
ROLLBACK;


-- 3. A mod in both lists ranks above a mod in one list.
--    "script extender" hits Script Extender (keyword rank 1, semantic rank 3 or 4);
--    SkyUI is semantic rank 1 only.
BEGIN;
DO $$
DECLARE
    top record;
BEGIN
    PERFORM pg_temp.fx_set_embeddings();
    SELECT * INTO top FROM fn_search_mods_hybrid('script extender', pg_temp.fx_vec(1), 'a0000000-0000-0000-0000-000000000001', 10) LIMIT 1;
    ASSERT top.mod_id = 'c0000000-0000-0000-0000-000000000001', 'mod in both lists is not first';
    ASSERT top.semantic_rank IS NOT NULL AND top.keyword_rank IS NOT NULL, 'top row is not in both lists';
    ASSERT top.score = 1.0 / (60 + top.semantic_rank) + 1.0 / (60 + top.keyword_rank), 'score is not the RRF sum';
    ASSERT top.score > (SELECT score FROM fn_search_mods_hybrid('script extender', pg_temp.fx_vec(1),
                                          'a0000000-0000-0000-0000-000000000001', 10)
                        WHERE mod_id = 'c0000000-0000-0000-0000-000000000002'),
        'mod in both lists does not outscore the semantic-only top hit';
    RAISE NOTICE 'PASS 3 fused rank beats single list';
END $$;
ROLLBACK;


-- 4. Game filter, limit cap and empty input.
BEGIN;
DO $$
BEGIN
    PERFORM pg_temp.fx_set_embeddings();
    ASSERT (SELECT count(*) FROM fn_search_mods_hybrid('script extender', NULL, NULL, 10)
            WHERE mod_id = 'c0000000-0000-0000-0000-000000000005') = 1,
        'without a game filter the game B script extender must match';
    ASSERT (SELECT count(*) FROM fn_search_mods_hybrid('script extender', NULL, 'a0000000-0000-0000-0000-000000000001', 10)
            WHERE mod_id = 'c0000000-0000-0000-0000-000000000005') = 0,
        'game filter let a game B mod through';
    ASSERT (SELECT count(*) FROM fn_search_mods_hybrid('', pg_temp.fx_vec(1), NULL, 1000)) <= 50, 'limit not capped at 50';
    ASSERT (SELECT count(*) FROM fn_search_mods_hybrid('', pg_temp.fx_vec(1), NULL, 1)) = 1, 'limit 1 not applied';
    ASSERT (SELECT count(*) FROM fn_search_mods_hybrid('  ', NULL, NULL, 10)) = 0, 'empty search returned rows';
    RAISE NOTICE 'PASS 4 game filter, limit cap, empty input';
END $$;
ROLLBACK;
