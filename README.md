# ModVault

ModVault checks a game mod loadout before you launch the game. Pick a game, build an ordered list of mod versions, and ModVault reports which mods miss a dependency, which pairs conflict, which load in the wrong order and which do not support your game version. Find mods with hybrid search that understands meaning ("make the menus look better"), not only keywords.

Seeded with 45 real mods (15 each for Skyrim Special Edition, Fallout 4 and Stardew Valley) from the Nexus Mods API. Built for the PES University DBMS mini project.

Live demo: TBD

## Architecture

```
Browser ──► Next.js (App Router, server components and server actions)
              │  every query runs in withUser(): one transaction that sets
              │  app.user_id and app.role from the users table (set_config)
              ▼
            PostgreSQL 18 + pgvector + pgcrypto
              functions, procedures, views, triggers, Row-Level Security
```

- **Business logic lives in PostgreSQL.** The health check engine, hybrid search, dependency graph, load-order sort, import and export, publishing, compatibility edits, role changes and the audit log are SQL functions, procedures and triggers (`database/functions.sql`, `database/triggers.sql`).
- **Next.js calls them.** Pages read through functions and views. Writes go through procedures, except a few simple row edits on loadouts, loadout mods and reviews, which Row-Level Security guards. There is no ORM; every query is parameterized.
- **Two database roles.** `modvault_owner` owns the schema. The app logs in as `modvault_app`, which is subject to RLS and cannot read `users.password_hash`.
- **Embeddings.** `Xenova/all-MiniLM-L6-v2` (384 dimensions) runs in Node, both in the seed job (`scripts/embed.ts`) and for live search queries.

## ER diagram

![ModVault ER diagram](docs/er-diagram.png)

12 tables: users, games, tags, mods, mod_versions, mod_tags, mod_dependencies, compatibility_matrix, reviews, loadouts, loadout_mods and audit_log.

## Features

- **Loadout health check:** one SQL function detects 9 issue types: missing dependency, declared conflict, incompatible pair, load order, version constraint, game version mismatch, partial pair, missing recommended mod and unverified pair. Score is `100 - 25 x errors - 10 x warnings`, and the status is healthy, warnings or broken.
- **Loadout builder:** drag-and-drop order, version picker, enable toggle, one-click "Add" for a missing dependency, "Auto-sort" (dependencies before dependents), and JSON export and import.
- **Hybrid search:** pgvector HNSW cosine similarity fused with PostgreSQL full-text search by Reciprocal Rank Fusion (k = 60). Results show a Meaning badge, a Keyword badge, or both. You can also filter by tag.
- **Mod pages:** stats, versions with the primary marker, a React Flow dependency graph, the compatibility list, reviews and "Add to loadout".
- **Compatibility heatmap:** a grid of primary versions per game. Curators click a cell to record a status, a reason and conflicting files.
- **Security in the database:** Row-Level Security (21 policies), bcrypt passwords through pgcrypto, SECURITY DEFINER auth with a fixed `search_path`, and no PUBLIC execute on SECURITY DEFINER routines.
- **Database features:** 18 triggers, 8 stored procedures, 13 functions, 5 views and 1 materialized view (Bayesian leaderboard), 16 indexes, and 7 transaction demos (savepoints, isolation levels, `FOR UPDATE`, serialization failure and retry, deadlock).
- **Tests:** SQL tests with `ASSERT` for every function, trigger and policy, a Playwright end-to-end demo, and two GitHub Actions workflows.

## Run it on your machine

Prerequisites: PostgreSQL 18 with pgvector 0.8+, Python 3.11+, Node.js 24. Create the owner role and database once (section 3 of the plan):

```bash
psql -U postgres -c "CREATE ROLE modvault_owner LOGIN SUPERUSER PASSWORD 'modvault_owner_dev';"
psql -U postgres -c "CREATE DATABASE modvault OWNER modvault_owner ENCODING 'UTF8';"
```

Create a `.env` file in the repo root:

```bash
DATABASE_URL=postgresql://modvault_owner:modvault_owner_dev@localhost:5432/modvault
APP_DATABASE_URL=postgresql://modvault_app:modvault_app_dev@localhost:5432/modvault
JWT_SECRET=<at least 32 characters, e.g. from: openssl rand -hex 32>
ADMIN_PASSWORD=<pick one>
CURATOR_PASSWORD=<pick one>
MODDER_PASSWORD=<pick one>
```

The seed creates the `admin` and `curator` accounts, and `modder1` to `modder6` (sharing `MODDER_PASSWORD`), with the passwords you choose here. Then run these three commands from the repo root:

```bash
python scripts/db_reset.py                                        # schema, logic, RLS and seed
npm --prefix scripts ci && npm --prefix scripts run embed         # 384-dim embeddings for the 45 mods
npm --prefix web ci && npm --prefix web run build && npm --prefix web run start
```

Open http://localhost:3000 and register an account. Add `--with-tests` to `db_reset.py` to run the SQL tests too, then run `python scripts/db_reset.py` again for clean seed data.

## Screenshots

| | |
|---|---|
| ![Home](docs/screenshots/home.png) Home | ![Hybrid search](docs/screenshots/01-search-meaning.png) Hybrid search with Meaning badge |
| ![Game catalog](docs/screenshots/game-skyrim.png) Game catalog | ![Mod detail](docs/screenshots/mod-detail.png) Mod detail |
| ![Broken loadout](docs/screenshots/02-broken-loadout.png) Broken loadout diagnostics | ![Fixed loadout](docs/screenshots/03-fixed-loadout.png) After Add and Auto-sort |
| ![Heatmap](docs/screenshots/04-curator-heatmap.png) Curator heatmap | ![Audit diff](docs/screenshots/05-admin-audit-diff.png) Audit log diff |
| ![Private loadout hidden](docs/screenshots/06-private-loadout-hidden.png) RLS hides a private loadout | ![Loadouts](docs/screenshots/loadouts.png) Loadout manager |
| ![Publish](docs/screenshots/mod-publish.png) Publish a mod | ![Admin](docs/screenshots/admin.png) Admin dashboard |

## Benchmarks

From [`docs/benchmarks.md`](docs/benchmarks.md): 50,000 synthetic mods, `EXPLAIN (ANALYZE, BUFFERS)`, median of 3 runs.

| Query | With index (ms) | Without index (ms) | Speed-up | Plan node with index | Plan node without index |
|---|---|---|---|---|---|
| Vector top 10 (`ORDER BY embedding <=> q LIMIT 10`) | 1.00 (0.95 to 1.16) | 53.29 (29.43 to 73.19) | 53x | Index Scan using `idx_mods_embedding_hnsw` (HNSW) | Seq Scan on mods + top-N heapsort |
| Full-text search (`search_tsv @@ 'weather lantern'`, top 10 by `ts_rank_cd`) | 1.54 (1.53 to 1.63) | 52.13 (29.14 to 64.56) | 34x | Bitmap Index Scan on `idx_mods_search_tsv` (GIN) | Seq Scan on mods |
| Reverse dependency lookup (mods that require one mod) | 0.15 (0.13 to 0.41) | 5.69 (4.97 to 6.15) | 37x | Bitmap Index Scan on `idx_mod_dependencies_required_mod` (B-tree) | Seq Scan on mod_dependencies |
| Health check, 40-mod loadout (`fn_check_loadout_compatibility`) | 4.17 (3.93 to 4.24) | 14.40 (13.37 to 15.80) | 3.5x | Index Scan using `idx_mod_dependencies_dependent_version` (B-tree, 40 loops) | Seq Scan on mod_dependencies (101,482 rows) |
