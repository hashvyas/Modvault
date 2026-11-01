# ModVault

[![db](https://github.com/hashvyas/Modvault/actions/workflows/db.yml/badge.svg)](https://github.com/hashvyas/Modvault/actions/workflows/db.yml)
[![Web Application CI](https://github.com/hashvyas/Modvault/actions/workflows/app.yml/badge.svg)](https://github.com/hashvyas/Modvault/actions/workflows/app.yml)

ModVault checks a game mod loadout before you launch the game. Pick a game, build an ordered list of mod versions, and ModVault reports which mods miss a dependency, which pairs conflict, which load in the wrong order and which do not support your game version. Find mods with hybrid search that understands meaning ("make the menus look better"), not only keywords.

Seeded with 45 real mods (15 each for Skyrim Special Edition, Fallout 4 and Stardew Valley) from the Nexus Mods API. Built for the PES University DBMS mini project.

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

Prerequisites: PostgreSQL 18 with pgvector 0.8+, Python 3.11+, Node.js 24. Create the owner role and database once:

```bash
psql -U postgres -c "CREATE ROLE modvault_owner LOGIN SUPERUSER PASSWORD 'modvault_owner_dev';"
psql -U postgres -c "CREATE DATABASE modvault OWNER modvault_owner ENCODING 'UTF8';"
```

Create a `.env` file in the repo root:

```bash
DATABASE_URL=postgresql://modvault_owner:modvault_owner_dev@localhost:5432/modvault
APP_DATABASE_URL=postgresql://modvault_app:modvault_app_dev@localhost:5432/modvault
JWT_SECRET=<at least 32 characters, e.g. from: openssl rand -hex 32>
ADMIN_PASSWORD=<password for the seeded admin account>
CURATOR_PASSWORD=<password for the seeded curator account>
```

The seed creates the `admin` and `curator` accounts with the passwords you choose here. Then run these three commands from the repo root:

```bash
python scripts/db_reset.py                                        # schema, logic, RLS and seed
npm --prefix scripts ci && npm --prefix scripts run embed         # 384-dim embeddings for the 45 mods
npm --prefix web ci && npm --prefix web run build && npm --prefix web run start
```

Open http://localhost:3000 and register an account. Add `--with-tests` to `db_reset.py` to run the SQL tests too, then run `python scripts/db_reset.py` again for clean seed data.

To deploy to Neon and Render, see [`docs/deploy.md`](docs/deploy.md).

## Development

Run these from `web/`:

| Command | What it does |
|---|---|
| `npm run dev` | Dev server with Turbopack on http://localhost:3000 |
| `npm run lint` | ESLint |
| `npm run typecheck` | `tsc --noEmit` |
| `npm run build && npm run start` | Production build and server |
| `npm run test:e2e` | Playwright end-to-end tests (starts `npm run start` itself, so build first) |
| `npm run cache-model` | Pre-download the embedding model |

The SQL tests live in `database/tests/` and run through `python scripts/db_reset.py --with-tests`. CI (`.github/workflows/`) runs both suites on PostgreSQL 18 with pgvector.

To refresh the seed data from Nexus Mods, set `NEXUS_API_KEY` in `.env`, install `scripts/nexus/requirements.txt` and run `python scripts/nexus/pull.py`, then `python scripts/nexus/generate_seed.py`. The hand-curated inputs are in `data/curated/`.

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

Measured with `database/tests/bench.sql` on 2026-11-01 (method in [`docs/benchmarks.md`](docs/benchmarks.md)): 50,000 synthetic mods, `EXPLAIN (ANALYZE, BUFFERS)`, median of 3 runs.

| Query | With index (ms) | Without index (ms) | Speed-up | Plan node with index | Plan node without index |
|---|---|---|---|---|---|
| Vector top 10 (`ORDER BY embedding <=> q LIMIT 10`) | 0.88 (0.82 to 0.99) | 52.07 (27.03 to 68.40) | 59x | Index Scan using `idx_mods_embedding_hnsw` (HNSW) | Seq Scan on mods + top-N heapsort |
| Full-text search (`search_tsv @@ 'weather lantern'`, top 10 by `ts_rank_cd`) | 1.58 (1.44 to 1.65) | 51.14 (22.49 to 72.49) | 32x | Bitmap Index Scan on `idx_mods_search_tsv` (GIN) | Seq Scan on mods |
| Reverse dependency lookup (mods that require one mod) | 0.17 (0.15 to 0.28) | 5.80 (5.31 to 6.80) | 34x | Bitmap Index Scan on `idx_mod_dependencies_required_mod` (B-tree) | Seq Scan on mod_dependencies |
| Health check, 40-mod loadout (`fn_check_loadout_compatibility`) | 4.15 (3.91 to 4.39) | 14.96 (14.53 to 16.46) | 3.6x | Index Scan using `idx_mod_dependencies_dependent_version` (B-tree, 40 loops) | Seq Scan on mod_dependencies (101,484 rows) |
