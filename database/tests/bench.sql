-- =============================================================================
-- ModVault: A Mod Repository and Compatibility Intelligence System
-- Index benchmarks  --  tests/bench.sql
--
-- PURPOSE
--   Measures what the indexes buy on a large catalogue. Everything runs in one
--   BEGIN ... ROLLBACK, so the 50,000 synthetic mods, the dropped indexes and
--   every other change disappear at the end.
--
--   Data: 50,000 synthetic mods in a "Bench Game", each with a random
--   normalized 384-dim embedding, a 5-word summary from a 48-word vocabulary,
--   one primary version and 2 random required dependencies (~100,000 rows).
--   A 40-mod loadout gets a few compatibility rows.
--
--   Four queries, each run with EXPLAIN (ANALYZE, BUFFERS) twice: with the
--   index, then with the relevant index dropped inside the same transaction:
--     1. vector top 10            idx_mods_embedding_hnsw (HNSW)
--     2. full-text search         idx_mods_search_tsv (GIN)
--     3. reverse dependency       idx_mod_dependencies_required_mod (B-tree)
--     4. health check, 40 mods    idx_mod_dependencies_dependent_version and
--                                 uq_mod_dependencies_version_mod (B-tree; both
--                                 serve dependent_version_id lookups)
--   Each query runs once (as a count) before its measured run to warm the cache.
--
--   Results go into docs/benchmarks.md by hand.
--
-- NOTES
--   * Needs a superuser (local modvault_owner is one): the load sets
--     session_replication_role = replica to skip triggers (audit rows,
--     single-primary check) while inserting synthetic rows.
--   * The HNSW and GIN indexes are dropped before the load and rebuilt after
--     it: one bulk build is much faster than 50,000 incremental inserts.
--   * Takes about a minute or two.
--
-- HOW TO RUN (after run_all.sql)
--   psql "postgresql://modvault_owner:modvault_owner_dev@localhost:5432/modvault" -v ON_ERROR_STOP=1 -f database/tests/bench.sql
-- =============================================================================

SET client_encoding = 'UTF8';
\timing on

BEGIN;
SET LOCAL maintenance_work_mem = '512MB';
SET LOCAL session_replication_role = replica;

DROP INDEX idx_mods_embedding_hnsw;
DROP INDEX idx_mods_search_tsv;

INSERT INTO games (name, domain) VALUES ('Bench Game', 'bench-game');

CREATE TEMP TABLE bench_words ON COMMIT DROP AS
SELECT ARRAY['menu', 'interface', 'armor', 'weapon', 'weather', 'lantern', 'quest', 'dragon',
             'texture', 'mesh', 'lighting', 'shadow', 'combat', 'magic', 'spell', 'perk',
             'skill', 'crafting', 'settlement', 'farm', 'animal', 'crop', 'mine', 'cave',
             'dungeon', 'city', 'village', 'road', 'map', 'compass', 'inventory', 'dialogue',
             'voice', 'music', 'sound', 'fix', 'patch', 'framework', 'script', 'plugin',
             'performance', 'camera', 'horse', 'boat', 'tree', 'grass', 'water', 'snow'] AS w;

-- One row per synthetic mod; ids chosen up front so versions and dependencies can refer to them.
CREATE TEMP TABLE bench_mods ON COMMIT DROP AS
SELECT i, gen_random_uuid() AS mod_id, gen_random_uuid() AS version_id
FROM   generate_series(1, 50000) AS i;

INSERT INTO mods (mod_id, game_id, nexus_mod_id, nexus_author, name, summary, category, download_count, embedding)
SELECT b.mod_id,
       (SELECT game_id FROM games WHERE domain = 'bench-game'),
       'bench-' || b.i,
       'bench',
       'Bench Mod ' || b.i,
       (SELECT string_agg(w.w[1 + floor(random() * 48)::int], ' ')
        FROM bench_words w, generate_series(1, 5) AS k WHERE b.i > 0),
       'Bench',
       floor(random() * 100000)::int,
       -- The b.i > 0 reference makes the subquery run per row (a fresh vector each time).
       (SELECT l2_normalize(array_agg(random() - 0.5)::vector)
        FROM generate_series(1, 384) AS d WHERE b.i > 0)
FROM   bench_mods b;

INSERT INTO mod_versions (version_id, mod_id, semver, is_primary)
SELECT version_id, mod_id, '1.0.0', TRUE FROM bench_mods;

INSERT INTO mod_dependencies (dependent_version_id, required_mod_id, dep_type)
SELECT b.version_id, t.mod_id, 'required'
-- random() in the subquery's select list: one draw per (mod, k), then a plain equi-join.
FROM  (SELECT version_id, i, 1 + floor(random() * 50000)::int AS target_i
       FROM bench_mods, generate_series(1, 2) AS k) b
JOIN   bench_mods t ON t.i = b.target_i
WHERE  t.i <> b.i
ON CONFLICT DO NOTHING;

-- A 40-mod loadout (mods 1..40) with a compatibility row for 10 of its pairs.
INSERT INTO loadouts (loadout_id, user_id, game_id, name)
SELECT 'bbbbbbbb-0000-0000-0000-000000000001', (SELECT user_id FROM users ORDER BY username LIMIT 1),
       (SELECT game_id FROM games WHERE domain = 'bench-game'), 'Bench 40-mod loadout';
INSERT INTO loadout_mods (loadout_id, version_id, position)
SELECT 'bbbbbbbb-0000-0000-0000-000000000001', version_id, i - 1 FROM bench_mods WHERE i <= 40;
INSERT INTO compatibility_matrix (version_a_id, version_b_id, status, conflict_detail)
SELECT least(a.version_id, b.version_id), greatest(a.version_id, b.version_id),
       (ARRAY['compatible', 'incompatible', 'partial']::compat_status_enum[])[1 + a.i % 3],
       '{"reason": "bench"}'
FROM   bench_mods a JOIN bench_mods b ON b.i = a.i + 1
WHERE  a.i <= 10;

SET LOCAL session_replication_role = origin;

CREATE INDEX idx_mods_embedding_hnsw ON mods USING hnsw (embedding vector_cosine_ops);
CREATE INDEX idx_mods_search_tsv ON mods USING gin (search_tsv);
ANALYZE mods;
ANALYZE mod_versions;
ANALYZE mod_dependencies;
ANALYZE loadout_mods;
ANALYZE compatibility_matrix;

-- Data set size. Expected: about 50,045 mods and 100,000+ dependencies.
SELECT (SELECT count(*) FROM mods) AS mods,
       (SELECT count(*) FROM mod_versions) AS versions,
       (SELECT count(*) FROM mod_dependencies) AS dependencies;

-- Fixed inputs for the queries, as psql variables.
SELECT (SELECT l2_normalize(array_agg(random() - 0.5)::vector) FROM generate_series(1, 384))::text AS qvec,
       (SELECT mod_id FROM bench_mods WHERE i = 777) AS dep_target \gset

\timing off


-- -----------------------------------------------------------------------------
-- 1. Vector top 10  (idx_mods_embedding_hnsw)
-- -----------------------------------------------------------------------------
\echo '=== 1. vector top 10: WITH index'
SELECT count(*) AS warm_up FROM (SELECT mod_id FROM mods ORDER BY embedding <=> :'qvec'::vector LIMIT 10) t;
EXPLAIN (ANALYZE, BUFFERS)
SELECT mod_id, name FROM mods ORDER BY embedding <=> :'qvec'::vector LIMIT 10;

DROP INDEX idx_mods_embedding_hnsw;
\echo '=== 1. vector top 10: WITHOUT index'
SELECT count(*) AS warm_up FROM (SELECT mod_id FROM mods ORDER BY embedding <=> :'qvec'::vector LIMIT 10) t;
EXPLAIN (ANALYZE, BUFFERS)
SELECT mod_id, name FROM mods ORDER BY embedding <=> :'qvec'::vector LIMIT 10;


-- -----------------------------------------------------------------------------
-- 2. Full-text search  (idx_mods_search_tsv)
-- -----------------------------------------------------------------------------
\echo '=== 2. full-text search: WITH index'
SELECT count(*) FROM mods WHERE search_tsv @@ websearch_to_tsquery('english', 'weather lantern');
EXPLAIN (ANALYZE, BUFFERS)
SELECT mod_id, name, ts_rank_cd(search_tsv, q) AS rank
FROM   mods, websearch_to_tsquery('english', 'weather lantern') AS q
WHERE  search_tsv @@ q
ORDER  BY rank DESC
LIMIT  10;

DROP INDEX idx_mods_search_tsv;
\echo '=== 2. full-text search: WITHOUT index'
SELECT count(*) FROM mods WHERE search_tsv @@ websearch_to_tsquery('english', 'weather lantern');
EXPLAIN (ANALYZE, BUFFERS)
SELECT mod_id, name, ts_rank_cd(search_tsv, q) AS rank
FROM   mods, websearch_to_tsquery('english', 'weather lantern') AS q
WHERE  search_tsv @@ q
ORDER  BY rank DESC
LIMIT  10;


-- -----------------------------------------------------------------------------
-- 3. Reverse dependency lookup  (idx_mod_dependencies_required_mod)
--    "Which mods depend on this mod?"
-- -----------------------------------------------------------------------------
\echo '=== 3. reverse dependency lookup: WITH index'
SELECT count(*) FROM mod_dependencies WHERE required_mod_id = :'dep_target';
EXPLAIN (ANALYZE, BUFFERS)
SELECT m.name, d.dep_type
FROM   mod_dependencies d
JOIN   mod_versions v ON v.version_id = d.dependent_version_id
JOIN   mods m         ON m.mod_id = v.mod_id
WHERE  d.required_mod_id = :'dep_target';

DROP INDEX idx_mod_dependencies_required_mod;
\echo '=== 3. reverse dependency lookup: WITHOUT index'
SELECT count(*) FROM mod_dependencies WHERE required_mod_id = :'dep_target';
EXPLAIN (ANALYZE, BUFFERS)
SELECT m.name, d.dep_type
FROM   mod_dependencies d
JOIN   mod_versions v ON v.version_id = d.dependent_version_id
JOIN   mods m         ON m.mod_id = v.mod_id
WHERE  d.required_mod_id = :'dep_target';


-- -----------------------------------------------------------------------------
-- 4. Health check on a 40-mod loadout
--    (idx_mod_dependencies_dependent_version + uq_mod_dependencies_version_mod)
--    The function's inner plan is not shown (Function Scan); the time is the
--    whole health check.
-- -----------------------------------------------------------------------------
\echo '=== 4. health check, 40-mod loadout: WITH index'
SELECT count(*) FROM fn_check_loadout_compatibility('bbbbbbbb-0000-0000-0000-000000000001');
EXPLAIN (ANALYZE, BUFFERS)
SELECT severity, count(*) FROM fn_check_loadout_compatibility('bbbbbbbb-0000-0000-0000-000000000001') GROUP BY severity;

DROP INDEX idx_mod_dependencies_dependent_version;
ALTER TABLE mod_dependencies DROP CONSTRAINT uq_mod_dependencies_version_mod;
\echo '=== 4. health check, 40-mod loadout: WITHOUT index'
SELECT count(*) FROM fn_check_loadout_compatibility('bbbbbbbb-0000-0000-0000-000000000001');
EXPLAIN (ANALYZE, BUFFERS)
SELECT severity, count(*) FROM fn_check_loadout_compatibility('bbbbbbbb-0000-0000-0000-000000000001') GROUP BY severity;

ROLLBACK;
