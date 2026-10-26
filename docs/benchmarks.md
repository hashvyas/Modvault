# ModVault index benchmarks

Measured with `database/tests/bench.sql` on 2026-10-25. The script loads 50,000 synthetic mods into a seeded database and runs each query with `EXPLAIN (ANALYZE, BUFFERS)`. It runs each query twice: once with the index, then again with the relevant index dropped inside the same transaction. Everything ends in `ROLLBACK`.

## Results

Execution time is the median of 3 full runs, with the range of the 3 runs in brackets. Each measured query runs after one warm-up run.

| Query | With index (ms) | Without index (ms) | Speed-up | Plan node with index | Plan node without index |
|---|---|---|---|---|---|
| Vector top 10 (`ORDER BY embedding <=> q LIMIT 10`) | 1.00 (0.95 to 1.16) | 53.29 (29.43 to 73.19) | 53x | Index Scan using `idx_mods_embedding_hnsw` (HNSW) | Seq Scan on mods + top-N heapsort |
| Full-text search (`search_tsv @@ 'weather lantern'`, top 10 by `ts_rank_cd`) | 1.54 (1.53 to 1.63) | 52.13 (29.14 to 64.56) | 34x | Bitmap Index Scan on `idx_mods_search_tsv` (GIN) | Seq Scan on mods |
| Reverse dependency lookup (mods that require one mod) | 0.15 (0.13 to 0.41) | 5.69 (4.97 to 6.15) | 37x | Bitmap Index Scan on `idx_mod_dependencies_required_mod` (B-tree) | Seq Scan on mod_dependencies |
| Health check, 40-mod loadout (`fn_check_loadout_compatibility`) | 4.17 (3.93 to 4.24) | 14.40 (13.37 to 15.80) | 3.5x | Index Scan using `idx_mod_dependencies_dependent_version` (B-tree, 40 loops) | Seq Scan on mod_dependencies (101,482 rows) |

For the health check, "without index" drops both indexes that serve `dependent_version_id` lookups: `idx_mod_dependencies_dependent_version` and the unique constraint index `uq_mod_dependencies_version_mod`. With only one dropped, the planner just uses the other. `fn_check_loadout_compatibility` is a `LANGUAGE sql STABLE` function, so PostgreSQL inlines it and its inner plan appears in the `EXPLAIN` output.

## What the numbers say

- **Vector search:** without HNSW, PostgreSQL computes the cosine distance to all 50,045 embeddings and sorts them. HNSW visits a small neighbourhood of the graph instead, so the time stays about 1 ms however large the table grows. HNSW is approximate: it can occasionally miss a true neighbour, the usual trade for this speed.
- **Full-text search:** the GIN index goes straight to the rows containing both terms (about 400 of 50,045 per run). Without it, every row's `search_tsv` is tested.
- **Reverse dependency lookup:** a lookup touching 2 rows out of 101,482. The B-tree finds them directly; a sequential scan reads the whole table.
- **Health check:** the smallest gain, because most of its work (pair checks, sorting, message formatting) runs over the 40 loadout rows, not the large tables. The index matters for the 40 dependency lookups. It replaces one full scan of 101,482 rows with 40 probes of about 2 rows each.
- **Noise:** the "without index" times vary more between runs (29 to 73 ms) than the indexed ones, because a full scan depends on how much of the table is in the cache. Each run also generates new random data. The indexed times are stable.

## Data set

| Table | Rows |
|---|---|
| mods | 50,045 (50,000 synthetic + 45 seed) |
| mod_versions | 51,793 |
| mod_dependencies | 101,482 |
| compatibility_matrix | 37 |

Synthetic mods have:
- a random normalized 384-dim embedding (`l2_normalize` of 384 uniform values);
- a 5-word summary drawn from a 48-word vocabulary;
- one primary version;
- 2 random `required` dependencies.

The 40-mod loadout uses the first 40 synthetic mods and has 10 compatibility rows.

## Environment

- PostgreSQL 18.6 (x86_64-windows), pgvector 0.8.6, default server settings. The script sets `maintenance_work_mem = 512MB` locally for the index builds.
- Windows 11, Intel Core i5-11400H (6 cores, 12 threads), 16 GB RAM. Person 1's development laptop.
- HNSW index with default parameters (`m = 16`, `ef_construction = 64`, `hnsw.ef_search = 40`).

## Reproduce

```bash
python scripts/db_reset.py
psql "postgresql://modvault_owner:modvault_owner_dev@localhost:5432/modvault" -v ON_ERROR_STOP=1 -f database/tests/bench.sql
```

Each run takes about 25 seconds and leaves the database unchanged. Read the `Execution Time` line under each `=== ...` heading. The script needs a superuser, because it sets `session_replication_role = replica` to skip triggers during the bulk load. The local `modvault_owner` is a superuser.
