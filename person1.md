# ModVault: Person 1 Plan (database)

Branch: `p1-database`. This file is the full spec for Person 1's coding agent. Person 2 has a matching file. Sections 1 to 6 are identical in both files.


## 0. Instructions for the agent

You are the coding agent for Person 1. Your branch is `p1-database`. Person 2 works in parallel on a separate branch with a separate agent and a separate plan file. Read this whole file before writing any code.

1. Phase 0 runs on `main` before any branch exists. You run it. When Phase 0 is done, the human pushes `main` and creates `p1-database` and `p2-app`. All later phases run on `p1-database`.
2. Run phases in order, and tasks inside a phase in order. Do not skip ahead. Each task lists Files, Steps and Done when.
3. A task is complete only when every "Done when" check passes. Run the checks yourself and show the output to the human.
4. A phase is complete only when every task in it is complete and the phase exit checks pass.
5. At the end of each phase, stop and give the human a summary: what you built, check output, assumptions made. The human commits and pushes. Commit message format: `p1-phase-<N>: <phase title>`, for example `p1-phase-2: core SQL logic`. Do not start the next phase until the human confirms the push.
6. Only edit files your person owns (section 4). If you need a change in a file you do not own, stop and tell the human what change you need and why.
7. Never change a signature in the contract (section 6). Function bodies change. Names, arguments, return columns and types do not.
8. Never invent Nexus mod IDs, API fields or library APIs. If unsure, check the official docs or ask the human.
9. When a task is ambiguous, pick the option closest to this spec, write the assumption in a code comment starting with `-- ASSUMPTION:` or `// ASSUMPTION:`, and list it in the phase summary.
10. Stop and ask the human before: deleting files you do not own, changing `schema.sql` after Phase 0, using any paid service, or committing secrets
11. Every command runs in PowerShell on Windows 11 from the repo root.
12. Keep a handoff log at `docs/handoff/person<N>.md`. This file belongs to you only, so it never causes a merge conflict. At the end of every phase, before the phase summary, append one entry with these parts, in plain language a student can follow without reading the code. Header: phase number, phase title, date. What was built: each file created or changed, with one or two sentences on what it does. How it works: the logic of the main functions, triggers, pages or scripts, step by step, with the SQL or code concept each one demonstrates (for example recursive CTE, row-level trigger, savepoint, RLS policy). Decisions: every choice made during the phase, the reason for it, and the alternatives rejected and why. Assumptions: every `ASSUMPTION:` comment written in this phase, with its location. Checks: the "Done when" and exit check commands run, and a short summary of their output. Open issues: anything unfinished, fragile or worth revisiting. For the other person: anything the other person needs to know or wait for, such as a new function, a changed behavior or a sync point. Never rewrite or delete earlier entries. If a later phase reverses an earlier decision, add a new entry stating the change and the reason.


## 1. Project summary

ModVault is a mod compatibility checker. A user picks a game and builds a loadout (an ordered list of mod versions). ModVault reports, before the game launches, which mods miss a dependency, which pairs conflict, which load in the wrong order, and which do not support the chosen game version. Users find mods with hybrid semantic search.

Course: PES University DBMS Level 3 Mini Project. Required features: triggers, stored procedures and functions, views, transactions, role-based authentication.

Core design rule: business logic lives in PostgreSQL. The web app calls SQL functions and procedures and renders results. No ORM.


## 2. Fixed technical decisions

Do not revisit these.

| Area | Decision |
|---|---|
| Database | PostgreSQL 18 with extensions `vector` (pgvector) and `pgcrypto` |
| Local DB | Native PostgreSQL 18 on Windows with pgvector 0.8.0 or newer, already installed on both machines. No Docker for local development |
| DB roles | `modvault_owner` owns all objects and runs migrations and seed. `modvault_app` is the web app login, not owner, subject to Row-Level Security |
| Session context | Every app transaction sets `app.user_id` and `app.role` with `set_config(..., true)`. Policies, audit and procedures read these |
| Passwords | bcrypt through pgcrypto: `crypt(pw, gen_salt('bf', 10))`. Checked inside a `SECURITY DEFINER` function. `modvault_app` has no SELECT on `users.password_hash` |
| Web app | Next.js latest stable, App Router, TypeScript strict, in folder `web/` |
| UI | Tailwind CSS + shadcn/ui. Dark theme default |
| DB driver | `pg` (node-postgres). Parameterized SQL only. No ORM, no query builder |
| Validation | `zod` on every server action and route handler input |
| Session | JWT signed with `jose` (HS256), httpOnly cookie `modvault_session`, 7 days |
| Embeddings | `Xenova/all-MiniLM-L6-v2` through `@huggingface/transformers`, mean pooling, normalized, 384 dimensions. Same library and model for seeding and for live queries |
| Search | Hybrid: pgvector cosine (HNSW) + full-text `tsvector` (GIN), fused with Reciprocal Rank Fusion, k = 60 |
| Drag and drop | `@dnd-kit/core` + `@dnd-kit/sortable` |
| Graph view | `@xyflow/react` |
| Data source | Nexus Mods API v1, base `https://api.nexusmods.com` |
| Games | `skyrimspecialedition`, `fallout4`, `stardewvalley` |
| Seed size | 15 curated mods per game, 45 total |
| Data scripts | Python 3.11+ with `requests` and `pyyaml` |
| Tests | SQL tests with `DO` blocks and `ASSERT`. Web end-to-end smoke test with Playwright |
| CI | GitHub Actions, two workflow files |
| Hosting | Neon (PostgreSQL) + Render (Docker web service running the Next.js standalone build) |


## 3. Environment

`.env.example` (copy to `.env`, never commit `.env`):

```bash
DATABASE_URL=postgresql://modvault_owner:modvault_owner_dev@localhost:5432/modvault
APP_DATABASE_URL=postgresql://modvault_app:modvault_app_dev@localhost:5432/modvault
JWT_SECRET=replace-with-64-random-hex-chars
NEXUS_API_KEY=replace-with-your-personal-key
```

Both development machines run Windows 11 with PostgreSQL 18 installed natively. All commands run in PowerShell from the repo root. Helper scripts are Python, not shell scripts, so the same script runs on both machines and in CI.

Verified on Person 1's machine: PostgreSQL 18.6, pgvector 0.8.6, pgcrypto 1.4, Python 3.12.10, pip 26.2.1, Node.js 24.11.0, npm 11.16.0, Git 2.52.0.

One-time setup per machine (the human runs this, not the agent). The owner is a superuser in local dev because it creates extensions and the `modvault_app` role. In PowerShell:

```bash
psql -U postgres -c "CREATE ROLE modvault_owner LOGIN SUPERUSER PASSWORD 'modvault_owner_dev';"
psql -U postgres -c "CREATE DATABASE modvault OWNER modvault_owner ENCODING 'UTF8';"
```

Check versions before Phase 0. Server must be 18, pgvector 0.8.0 or newer:

```bash
psql "postgresql://modvault_owner:modvault_owner_dev@localhost:5432/modvault" -c "SHOW server_version;" -c "SELECT default_version FROM pg_available_extensions WHERE name = 'vector';"
```

Encoding: the Windows console uses code page 437. Mod names contain non-ASCII characters. Every SQL file the project runs starts with `SET client_encoding = 'UTF8';`, and every file is saved as UTF-8 without BOM.

Reset and rebuild the database (drops all data):

```bash
python scripts/db_reset.py
```

Run a SQL file manually:

```bash
psql "postgresql://modvault_owner:modvault_owner_dev@localhost:5432/modvault" -v ON_ERROR_STOP=1 -f database/<file>.sql
```


## 4. Repo layout and ownership

Each path has one owner. Phase 0 creates the shared skeleton.

```bash
modvault/
  .env.example                     # Phase 0
  .gitignore                       # Phase 0 (.env, data/raw/, node_modules/, .next/)
  README.md                        # Final merge, both
  scripts/db_reset.py              # Phase 0
  database/
    run_all.sql                    # Phase 0, then P1
    schema.sql                     # Phase 0, then frozen (P1 only, with human approval)
    indexes.sql                    # P1
    functions.sql                  # Phase 0 stubs, then P1
    triggers.sql                   # P1
    views.sql                      # P1
    rls.sql                        # P1
    seed.sql                       # P2 (generated, never hand-edited)
    seed_expectations.sql          # P2 (generated)
    transactions.sql               # P1
    queries.sql                    # P1
    ddl_demo.sql                   # P1
    tests/                         # P1
  scripts/nexus/                   # P2
  scripts/embed.ts                 # P2
  scripts/package.json             # P2
  data/raw/                        # P2, gitignored
  data/curated/                    # P2
  web/                             # P2
  docs/benchmarks.md               # P1
  docs/er-diagram.png              # P1
  docs/screenshots/                # P2
  .github/workflows/db.yml         # P1
  .github/workflows/app.yml        # P2
  docs/handoff/person1.md          # P1
  docs/handoff/person2.md          # P2
```

Build order inside `run_all.sql`:

```bash
\ir schema.sql
\ir indexes.sql
\ir functions.sql
\ir triggers.sql
\ir views.sql
\ir rls.sql
\ir seed.sql
REFRESH MATERIALIZED VIEW mv_game_leaderboard;
```

`transactions.sql`, `queries.sql`, `ddl_demo.sql`, `seed_expectations.sql` and `tests/run_tests.sql` run after `run_all.sql`, one at a time.


## 5. Target schema

12 tables. All primary keys are `UUID DEFAULT gen_random_uuid()` except `audit_log`. All timestamps are `TIMESTAMPTZ NOT NULL DEFAULT NOW()` unless noted.

Enums (unchanged from the repo):

```bash
user_role_enum:     'modder', 'curator', 'admin'
dep_type_enum:      'required', 'optional', 'conflicts', 'recommends'
dep_source_enum:    'manual', 'nexus', 'inferred'
compat_status_enum: 'compatible', 'incompatible', 'unknown', 'partial'
```

Changes against the current `schema.sql` are marked NEW or CHANGED. Everything else stays as written in the repo.

```bash
-- users
user_id        UUID PK
username       VARCHAR(50)  NOT NULL UNIQUE
email          VARCHAR(255) NOT NULL UNIQUE
password_hash  TEXT NOT NULL
role           user_role_enum NOT NULL DEFAULT 'modder'
is_active      BOOLEAN NOT NULL DEFAULT TRUE              -- NEW
created_at     TIMESTAMPTZ
updated_at     TIMESTAMPTZ                                -- NEW

-- games
game_id         UUID PK
name            VARCHAR(255) NOT NULL UNIQUE
domain          VARCHAR(100) UNIQUE                       -- CHANGED: add UNIQUE
nexus_game_id   VARCHAR(100)
current_version VARCHAR(50)                               -- NEW
created_at      TIMESTAMPTZ

-- tags (unchanged)

-- mods
mod_id            UUID PK
author_id         UUID NULL REFERENCES users ON DELETE SET NULL   -- CHANGED: nullable, SET NULL
nexus_author      VARCHAR(255)                                    -- NEW: original Nexus author name
game_id           UUID NOT NULL REFERENCES games ON DELETE RESTRICT
nexus_mod_id      VARCHAR(100)
name              VARCHAR(255) NOT NULL
summary           TEXT
category          VARCHAR(100)
download_count    INTEGER NOT NULL DEFAULT 0 CHECK (>= 0)         -- NEW
endorsement_count INTEGER NOT NULL DEFAULT 0 CHECK (>= 0)         -- NEW
is_featured       BOOLEAN NOT NULL DEFAULT FALSE                  -- NEW
rating_avg        NUMERIC(3,2) NOT NULL DEFAULT 0                 -- NEW, maintained by trigger
rating_count      INTEGER NOT NULL DEFAULT 0                      -- NEW, maintained by trigger
search_tsv        TSVECTOR GENERATED ALWAYS AS (
                    setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
                    setweight(to_tsvector('english', coalesce(category, '')), 'B') ||
                    setweight(to_tsvector('english', coalesce(summary, '')), 'C')
                  ) STORED                                        -- NEW
embedding         VECTOR(384)                                     -- CHANGED: was 1536
created_at        TIMESTAMPTZ
updated_at        TIMESTAMPTZ                                     -- NEW
UNIQUE (game_id, nexus_mod_id)                                    -- NEW

-- mod_versions
version_id              UUID PK
mod_id                  UUID NOT NULL REFERENCES mods ON DELETE CASCADE
semver                  VARCHAR(20) NOT NULL
nexus_version_id        VARCHAR(100)
changelog               TEXT
supported_game_versions TEXT[] NOT NULL DEFAULT '{}'      -- NEW, empty means "any"
is_primary              BOOLEAN NOT NULL DEFAULT FALSE
uploaded_at             TIMESTAMPTZ
UNIQUE (mod_id, semver)

-- loadouts
loadout_id          UUID PK
user_id             UUID NOT NULL REFERENCES users ON DELETE CASCADE
game_id             UUID NOT NULL REFERENCES games ON DELETE RESTRICT
name                VARCHAR(255) NOT NULL
description         TEXT                                  -- NEW
game_version        VARCHAR(50)                           -- NEW, NULL means "not set"
is_public           BOOLEAN NOT NULL DEFAULT FALSE
nexus_collection_id VARCHAR(100)
nexus_revision_id   VARCHAR(100)
created_at          TIMESTAMPTZ
updated_at          TIMESTAMPTZ                           -- NEW

-- reviews, mod_tags, mod_dependencies, loadout_mods, compatibility_matrix: unchanged

-- audit_log (NEW, table 12)
audit_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY
table_name  TEXT NOT NULL
operation   CHAR(1) NOT NULL CHECK (operation IN ('I', 'U', 'D'))
row_pk      UUID
old_row     JSONB
new_row     JSONB
changed_by  UUID REFERENCES users ON DELETE SET NULL
changed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
```

Also update `mod_catalog_view` in `views.sql` to `LEFT JOIN users` and show `coalesce(u.username, m.nexus_author) AS author_name`, because `author_id` is now nullable.


## 6. Contract

Phase 0 writes every object below as a stub with the exact signature. P1 fills the bodies. P2 calls them. Signatures are frozen.

### 6.1 Session helpers

```bash
fn_current_user_id() RETURNS uuid    -- NULLIF(current_setting('app.user_id', true), '')::uuid
fn_current_role()    RETURNS text    -- coalesce(NULLIF(current_setting('app.role', true), ''), 'anonymous')
```

### 6.2 Functions

```bash
-- Auth (SECURITY DEFINER, SET search_path = public, pg_temp)
fn_register_user(p_username text, p_email text, p_password text) RETURNS uuid
fn_authenticate(p_username text, p_password text)
  RETURNS TABLE(user_id uuid, username text, role user_role_enum)

-- Search
fn_search_mods_hybrid(p_query text, p_embedding vector(384), p_game_id uuid, p_limit int)
  RETURNS TABLE(mod_id uuid, name text, summary text, game_id uuid,
                semantic_rank int, keyword_rank int, score float8)
fn_search_mods_by_tag(VARIADIC p_tags text[]) RETURNS SETOF mods

-- Mods
fn_get_mod_dependency_tree(p_version_id uuid)
  RETURNS TABLE(version_id uuid, mod_id uuid, mod_name text, parent_version_id uuid,
                depth int, dep_type dep_type_enum, path uuid[])
fn_mod_stats(p_mod_id uuid)
  RETURNS TABLE(version_count int, dependent_count int, conflict_count int,
                rating_avg numeric, rating_count int, download_count int)
fn_semver_satisfies(p_installed text, p_constraint text) RETURNS boolean

-- Loadouts
fn_check_loadout_compatibility(p_loadout_id uuid)
  RETURNS TABLE(issue_type text, severity text, version_id uuid, other_version_id uuid,
                related_mod_id uuid, message text)
fn_loadout_health_score(p_loadout_id uuid) RETURNS int
fn_suggest_load_order(p_loadout_id uuid) RETURNS TABLE(version_id uuid, suggested_position int)
fn_export_loadout(p_loadout_id uuid) RETURNS jsonb
```

### 6.3 Procedures

No procedure runs COMMIT or ROLLBACK. The caller owns the transaction.

```bash
pr_publish_mod(p_game_id uuid, p_name text, p_summary text, p_category text, p_semver text,
               p_tags text[], p_embedding vector(384), INOUT p_mod_id uuid DEFAULT NULL)
pr_add_mod_to_loadout(p_loadout_id uuid, p_version_id uuid)
pr_apply_load_order(p_loadout_id uuid)
pr_import_loadout(p_manifest jsonb, INOUT p_loadout_id uuid DEFAULT NULL, INOUT p_skipped int DEFAULT NULL)
pr_promote_version(p_version_id uuid)
pr_upsert_compatibility(p_version_a uuid, p_version_b uuid, p_status compat_status_enum, p_detail jsonb)
pr_set_user_role(p_user_id uuid, p_role user_role_enum)        -- SECURITY DEFINER, admin only
pr_refresh_reports()                                            -- SECURITY DEFINER, admin only
```

### 6.4 Views

```bash
mod_catalog_view            -- existing, updated for nullable author
mod_ratings_view            -- existing, plain view, live
loadout_summary_view        -- existing
loadout_health_view         -- NEW: loadout_id, error_count, warning_count, info_count, score, status
mod_conflict_summary_view   -- NEW: mod_id, mod_name, incompatible_pairs, partial_pairs,
                            --      declared_conflicts, dependent_mods
mv_game_leaderboard         -- NEW, materialized: game_id, mod_id, mod_name, rating_count, rating_avg,
                            --      bayes_score, download_count, rank_in_game
                            --      UNIQUE INDEX (game_id, mod_id)
```

### 6.5 Error format

Every custom error uses `RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'MODVAULT:<CODE>: <human text>'`.

Codes: `NOT_FOUND`, `FORBIDDEN`, `GAME_MISMATCH`, `DUPLICATE`, `INVALID_MANIFEST`, `INVALID_INPUT`.

The web app parses the code with the regex `^MODVAULT:([A-Z_]+): (.*)$` and shows the human text.

### 6.6 Health check issue types

Only enabled rows of `loadout_mods` count. Disabled mods are ignored everywhere.

| issue_type | severity | Rule | related_mod_id |
|---|---|---|---|
| MISSING_DEPENDENCY | error | A `required` dependency of a loadout version has no version of the required mod in the loadout | required mod |
| DECLARED_CONFLICT | error | A `conflicts` dependency points to a mod present in the loadout. Report each pair once | conflicting mod |
| INCOMPATIBLE_PAIR | error | `compatibility_matrix` status `incompatible` for two loadout versions | NULL |
| LOAD_ORDER | warning | A present `required` dependency has a higher position than the mod needing it | required mod |
| VERSION_CONSTRAINT | warning | A present dependency fails `fn_semver_satisfies(installed semver, version_constraint)` | required mod |
| GAME_VERSION_MISMATCH | warning | `loadouts.game_version` is set, `supported_game_versions` is not empty, and the game version is not in the array | NULL |
| PARTIAL_PAIR | warning | Matrix status `partial`. Message includes `conflict_detail->>'reason'` when present | NULL |
| MISSING_RECOMMENDED | info | An `optional` or `recommends` dependency is absent | recommended mod |
| UNVERIFIED_PAIR | info | Two loadout versions with no matrix row or status `unknown` | NULL |

Score: `GREATEST(0, 100 - 25 * errors - 10 * warnings)`. Info issues do not change the score.
Status: `broken` if any error, else `warnings` if any warning, else `healthy`.
Order results by severity (error, warning, info), then issue_type, then message.

### 6.7 Loadout manifest format

`fn_export_loadout` returns this. `pr_import_loadout` accepts it.

```bash
{
  "format": "modvault-loadout/1",
  "name": "Stable Skyrim UI",
  "description": "optional",
  "game_domain": "skyrimspecialedition",
  "game_version": "1.6.1170",
  "mods": [
    { "nexus_mod_id": "12345", "semver": "5.2.0", "position": 0, "enabled": true }
  ]
}
```

Import rules: `format` must match, else `INVALID_MANIFEST`. The new loadout belongs to `fn_current_user_id()`. Resolve game by domain. Resolve each mod by `(game_id, nexus_mod_id)`, then version by `semver`, falling back to the primary version. Each mod insert runs in its own `BEGIN ... EXCEPTION WHEN others` block. A failing or unresolved entry increments `p_skipped` and does not abort the import.


## 7. Phases

| Phase | Title | Tasks |
|---|---|---|
| 0 | Shared foundation (DONE 2026-10-24) | T0-01, T0-02, T0-03, T0-04 |
| 1 | Indexes and triggers | P1-01, P1-02 |
| 2 | Core SQL logic | P1-03, P1-04, P1-05, P1-06 |
| 3 | Procedures, views and security | P1-07, P1-08, P1-09 |
| 4 | Demonstration SQL | P1-10 |
| 5 | Tests, CI and benchmarks | P1-11, P1-12 |
| 6 | Final merge | together |

### Phase 0: Shared foundation (DONE 2026-10-24)

Status: complete. All tasks and exit checks passed. Do not redo this phase. Details are in `docs/handoff/person1.md`.

Goal: Create the skeleton, final schema, contract stubs and run order on `main`, so both people branch from the same base.

Depends on: Nothing. Runs on `main` before branching.

#### T0-01 Skeleton

Files: `.env.example`, `.gitignore`, `scripts/db_reset.py`.

Steps:
1. `db_reset.py` (Python standard library only): read `DATABASE_URL` from `.env` in the repo root, or from the environment when set (CI). Exit with a clear message when missing. Find `psql` on PATH, falling back to `C:\Program Files\PostgreSQL\18\bin`. Run `pg_isready -d <url>`. Run `DROP SCHEMA public CASCADE; CREATE SCHEMA public;` as owner, then `database/run_all.sql` with `-v ON_ERROR_STOP=1`. Set `PGCLIENTENCODING=UTF8` in the child process environment. Resolve paths relative to the script so it runs from any folder. Exit non-zero on any failure. Flag `--with-tests` also runs `database/tests/run_tests.sql`.
2. Add `SET client_encoding = 'UTF8';` as the first statement of every SQL file.
3. Keep the name "ModVault" in SQL file headers. Fix every "HOW TO RUN" header to point at `run_all.sql` and `scripts/db_reset.py`.

Done when: the version check in section 3 passes and `pg_isready -d "$DATABASE_URL"` reports accepting connections.

#### T0-02 Schema

Files: `database/schema.sql`, `database/views.sql` (only the `mod_catalog_view` fix).

Steps: apply section 5 exactly. Keep existing comments where still true. Fix the header of `seed.sql` to say mods and versions come from the Nexus API and other rows are curated.

Done when: `schema.sql` runs on an empty database with no errors and `\dt` lists 12 tables.

#### T0-03 Contract stubs

Files: `database/functions.sql`.

Steps:
1. Remove the `audit_log` CREATE TABLE plan and the `fn_refresh_mv_mod_ratings` plan from this file.
2. Write every function and procedure from section 6 with the exact signature. Function stubs return no rows, NULL, `false`, `0` or `'{}'::jsonb` as fits the return type. Procedure stubs do nothing.
3. Write stub views from section 6.4 in `views.sql` with the right column names and types, using `WHERE false` bodies. `mv_game_leaderboard` gets its unique index.

Done when: running `schema.sql`, `functions.sql`, `views.sql` in order succeeds and `SELECT * FROM fn_check_loadout_compatibility(gen_random_uuid());` returns zero rows with the 6 contract columns.

#### T0-04 Run order

Files: `database/run_all.sql`, empty placeholders for `indexes.sql` additions, `triggers.sql`, `rls.sql`, `seed.sql` (comment only).

Done when: `python scripts/db_reset.py` finishes with exit code 0.

#### Phase 0 exit checks

- `python scripts/db_reset.py` exits with code 0 on a clean database.
- `\dt` lists 12 tables.
- Every function, procedure and view in section 6 exists with its exact signature.
- After the commit, the human pushes `main` and creates `p1-database` and `p2-app`.

### Phase 1: Indexes and triggers

Goal: All indexes, trigger functions and triggers in place and tested on fixtures.

Depends on: Phase 0 on `main`.

Before P1-01, create `database/tests/fixtures.sql`. Contents: 2 games, 3 users (one per role), 6 mods, 8 versions, dependencies covering every dep_type, 4 matrix rows (one per status), 2 loadouts. Load it after `run_all.sql` for local testing.

#### P1-01 Indexes

Files: `database/indexes.sql`.

Keep the existing 9 indexes. Add:

```bash
CREATE INDEX idx_mods_embedding_hnsw ON mods USING hnsw (embedding vector_cosine_ops);
CREATE INDEX idx_mods_search_tsv ON mods USING gin (search_tsv);
CREATE INDEX idx_mod_versions_supported ON mod_versions USING gin (supported_game_versions);
CREATE INDEX idx_mod_dependencies_required_mod ON mod_dependencies (required_mod_id);
CREATE INDEX idx_audit_log_table_time ON audit_log (table_name, changed_at DESC);
CREATE INDEX idx_audit_log_changed_by ON audit_log (changed_by);
CREATE UNIQUE INDEX uq_mod_versions_one_primary ON mod_versions (mod_id) WHERE is_primary;
```

Done when: `python scripts/db_reset.py` passes and `\di` lists all 16 indexes.

#### P1-02 Trigger functions and triggers

Files: `database/functions.sql` (trigger functions section), `database/triggers.sql`.

| Trigger | Table and timing | Behavior |
|---|---|---|
| `trg_compat_canonicalise_pair` | compatibility_matrix, BEFORE INSERT OR UPDATE, row | If `version_a_id > version_b_id`, swap them |
| `trg_mod_version_single_primary` | mod_versions, BEFORE INSERT OR UPDATE OF is_primary, row | When NEW.is_primary is true, set `is_primary = false` on other versions of the same mod first |
| `trg_<table>_updated_at` | users, mods, loadouts, compatibility_matrix, BEFORE UPDATE, row | `NEW.updated_at = NOW()`. One function `fn_set_updated_at` |
| `trg_loadout_mods_position` | loadout_mods, BEFORE INSERT, row | When NEW.position is 0 and rows exist, set it to `max(position) + 1` for the loadout |
| `trg_loadout_mods_game_check` | loadout_mods, BEFORE INSERT OR UPDATE, row | Raise `GAME_MISMATCH` if the version's mod game differs from the loadout game |
| `trg_reviews_rating_rollup` | reviews, AFTER INSERT OR UPDATE OR DELETE, row | Recompute `rating_avg` and `rating_count` for affected mod ids only (both OLD and NEW mod on UPDATE). Function is SECURITY DEFINER |
| `trg_audit_<table>` | users, mods, mod_versions, mod_dependencies, compatibility_matrix, loadouts, loadout_mods, reviews, AFTER INSERT OR UPDATE OR DELETE, row | Call `fn_audit_log(<pk column name>)` |
| `trg_audit_log_immutable` | audit_log, BEFORE UPDATE OR DELETE, row | Raise `FORBIDDEN` |

`fn_audit_log` rules:
- SECURITY DEFINER, `SET search_path = public, pg_temp`.
- Primary key column name comes from `TG_ARGV[0]`.
- Build JSON with `to_jsonb(OLD)` and `to_jsonb(NEW)`, then remove keys `password_hash`, `embedding`, `search_tsv`.
- On UPDATE, skip the insert when the only changed keys are in `updated_at`, `rating_avg`, `rating_count`, `embedding`, `search_tsv`.
- `changed_by = fn_current_user_id()`.

Tests in `database/tests/test_triggers.sql`, each check wrapped in `BEGIN ... ROLLBACK`:
1. Insert pair (B, A) where A < B. Stored row is (A, B). Inserting (A, B) after it violates the unique constraint.
2. Promote a second version. Old primary is false, new is true, exactly one primary.
3. Insert into loadout_mods with a mod from another game. Raises `GAME_MISMATCH`.
4. Insert three reviews. `mods.rating_avg` and `rating_count` equal `mod_ratings_view`.
5. Update a user's email. Newest audit row has no `password_hash` key and `changed_by` equals the session user id.
6. `DELETE FROM audit_log` raises `FORBIDDEN`.
7. Two inserts into one loadout without position get positions 0 and 1.

Done when: `tests/test_triggers.sql` runs with zero failed assertions.

#### Phase 1 exit checks

- `database/tests/fixtures.sql` exists and loads after `run_all.sql`.
- `\di` lists 16 indexes.
- `tests/test_triggers.sql` passes with zero failed assertions.

### Phase 2: Core SQL logic

Goal: Auth, semver, health check engine, graph functions and hybrid search implemented behind the frozen contract.

Depends on: Phase 1.

#### P1-03 Auth, helpers, semver

Files: `database/functions.sql`.

1. `fn_current_user_id`, `fn_current_role` per section 6.1.
2. `fn_register_user`: validate username `^[a-zA-Z0-9_]{3,50}$`, email contains `@`, password length at least 8, else `INVALID_INPUT`. Duplicate username or email raises `DUPLICATE`. Role is always `modder`.
3. `fn_authenticate`: return the row when `password_hash = crypt(p_password, password_hash)` and `is_active`. Otherwise zero rows. Same timing path for unknown user (compare against a fixed dummy hash).
4. `fn_semver_satisfies`: strip a leading `v`, take numeric parts with `regexp_matches(..., '\d+', 'g')`, pad to 3 ints, compare as `int[]`. Support `*`, `=x`, `>=x`, `>x`, `<=x`, `<x`, `^x` (same major, at least x), and plain `x` (treated as `>=x`). NULL or empty constraint returns true. Unparseable installed version returns true.

Done when: `tests/test_auth.sql` passes: register then authenticate succeeds, wrong password returns zero rows, duplicate username raises `DUPLICATE`, and at least 12 semver cases pass including `('1.10.0', '>=1.9')`, `('2.0.0', '^1.0')` false, `('v1.2', '=1.2.0')` true.

#### P1-04 Health check engine

Files: `database/functions.sql`.

1. `fn_check_loadout_compatibility`: one SQL function (`LANGUAGE sql STABLE`). Start with CTE `lm` (enabled loadout rows joined to versions, mods, loadout). One CTE per issue type from section 6.6. `UNION ALL`. Order per 6.6. Messages use mod names, for example `SkyUI requires SKSE64, which is not in this loadout`.
2. `fn_loadout_health_score` per 6.6.
3. Raise `NOT_FOUND` for an unknown loadout id in the score function. The check function returns zero rows for unknown ids.

Done when: `tests/test_health.sql` builds one fixture loadout per issue type and asserts each issue appears exactly once with the right severity, a clean loadout returns zero error and warning rows with score 100, and a disabled conflicting mod produces no issue.

#### P1-05 Dependency tree, load order, stats, tag search

Files: `database/functions.sql`.

1. `fn_get_mod_dependency_tree`: recursive CTE. Root row is the given version at depth 0 with NULL parent and NULL dep_type. Each step follows `mod_dependencies` of types required, optional, recommends to the primary version of the required mod. Stop when the next version is already in `path`. Max depth 10.
2. `fn_suggest_load_order`: edges inside the loadout from a mod to each present dependency (required, optional, recommends). Compute each version's longest dependency chain length with a recursive CTE and a path cycle guard. Sort by depth ascending, then current position, then mod name. Return positions 0 to n-1.
3. `fn_mod_stats`: `conflict_count` = declared conflicts in either direction + incompatible matrix pairs touching any version of the mod.
4. `fn_search_mods_by_tag`: mods having every given tag slug (AND match).

Done when: `tests/test_graph.sql` passes: a 3-level chain returns depths 0, 1, 2, a cycle A to B to A terminates, and load order on a shuffled loadout puts dependencies before dependents.

#### P1-06 Hybrid search

Files: `database/functions.sql`.

1. CTE `sem`: when `p_embedding` is not NULL, top 50 mods with non-NULL embedding by `embedding <=> p_embedding`, rank with `ROW_NUMBER()`.
2. CTE `kw`: when `trim(p_query)` is not empty, top 50 mods where `search_tsv @@ websearch_to_tsquery('english', p_query)`, ranked by `ts_rank_cd` descending.
3. `FULL OUTER JOIN` on mod_id. `score = coalesce(1.0 / (60 + sem.rank), 0) + coalesce(1.0 / (60 + kw.rank), 0)`.
4. Optional `p_game_id` filter applied inside both CTEs. Order by score descending. Limit `p_limit`, capped at 50.

Done when: `tests/test_search.sql` passes with hand-made 384-dim vectors: a keyword-only query returns keyword hits with NULL semantic_rank, a vector-only query returns semantic hits, and a mod appearing in both ranks above a mod appearing in one.

#### Phase 2 exit checks

- `tests/test_auth.sql`, `tests/test_health.sql`, `tests/test_graph.sql`, `tests/test_search.sql` all pass.
- No contract signature changed (compare against the Phase 0 stubs).
- If Sync 1 has landed, the health check runs on real seed loadouts without errors.

### Phase 3: Procedures, views and security

Goal: All procedures, new views, roles and Row-Level Security done. This phase unblocks Person 2.

Depends on: Phase 2.

#### P1-07 Procedures

Files: `database/functions.sql`.

1. `pr_publish_mod`: requires a logged-in user (else `FORBIDDEN`). Inserts mods (author = current user), one primary mod_version, tags by slug (create missing tags). All inside the caller's transaction.
2. `pr_add_mod_to_loadout`: loadout must exist and be visible (else `NOT_FOUND`). If another version of the same mod is in the loadout, update that row's `version_id` in place (keeps position). Else insert. Game mismatch surfaces from the trigger.
3. `pr_apply_load_order`: update positions from `fn_suggest_load_order` in one statement.
4. `pr_import_loadout`: per section 6.7.
5. `pr_promote_version`: `SELECT ... FOR UPDATE` on all versions of the mod, then set the target primary.
6. `pr_upsert_compatibility`: role must be curator or admin, else `FORBIDDEN`. `INSERT ... ON CONFLICT (version_a_id, version_b_id) DO UPDATE`, with the pair ordered first (so the conflict target matches the canonical order). `verified_by = fn_current_user_id()`.
7. `pr_set_user_role`, `pr_refresh_reports`: role must be admin, else `FORBIDDEN`. Refresh uses `REFRESH MATERIALIZED VIEW CONCURRENTLY mv_game_leaderboard`.
8. `fn_export_loadout`: per 6.7, mods ordered by position.

Done when: `tests/test_procedures.sql` passes: export then import gives an equal mod list, an import with one bad entry returns `p_skipped = 1`, a modder calling `pr_upsert_compatibility` raises `FORBIDDEN`, a curator call writes a row with `verified_by` set.

#### P1-08 Views

Files: `database/views.sql`.

1. `loadout_health_view`: for every loadout, `LATERAL` call to the check function, aggregate counts, score and status.
2. `mod_conflict_summary_view` per 6.4.
3. `mv_game_leaderboard`: Bayesian score `(C * m + rating_count * rating_avg) / (C + rating_count)` with `C = 5` and `m` = average rating across reviews in the same game. `RANK() OVER (PARTITION BY game_id ORDER BY bayes_score DESC, download_count DESC)`. Keep rows with rank at most 20.

Done when: all views return rows on fixture data and `REFRESH MATERIALIZED VIEW CONCURRENTLY mv_game_leaderboard` succeeds.

#### P1-09 Roles and Row-Level Security

Files: `database/rls.sql`.

1. Create role `modvault_app` inside a `DO` block only when missing, `LOGIN PASSWORD 'modvault_app_dev'`. Comment: production changes the password with `ALTER ROLE`.
2. `GRANT USAGE ON SCHEMA public`. `GRANT EXECUTE` on all functions and procedures.
3. Column-level grant on users: `GRANT SELECT (user_id, username, email, role, is_active, created_at, updated_at) ON users`. Do not grant table-level SELECT on users (a column REVOKE does not override a table grant).
4. `GRANT SELECT` on all other tables and views. `GRANT INSERT, UPDATE, DELETE` on loadouts, loadout_mods, reviews, compatibility_matrix, mod_dependencies, mod_tags. `GRANT INSERT, UPDATE` on mods, mod_versions, tags. No direct write grant on users or audit_log.
5. Enable RLS and write policies:

| Table | SELECT | INSERT, UPDATE, DELETE |
|---|---|---|
| loadouts | `is_public` or owner or admin | owner only |
| loadout_mods | parent loadout visible | parent loadout owned |
| reviews | everyone | owner only |
| compatibility_matrix | everyone | role curator or admin |
| mod_dependencies | everyone | role curator or admin |
| audit_log | role admin | none |

Done when: `tests/test_rls.sql` passes. It runs `SET ROLE modvault_app`, sets user A, confirms user B's private loadout returns zero rows, confirms `SELECT password_hash FROM users` raises permission denied, and confirms a modder cannot insert into compatibility_matrix.

#### Phase 3 exit checks

- `tests/test_procedures.sql` and `tests/test_rls.sql` pass.
- `REFRESH MATERIALIZED VIEW CONCURRENTLY mv_game_leaderboard` succeeds.
- The human opens the Sync 2 pull request (section 8).

### Phase 4: Demonstration SQL

Goal: Transactions, query catalogue and DDL demo written and runnable on seed data.

Depends on: Phase 3 and Sync 1 (needs real seed).

#### P1-10 Transactions, queries, DDL demo

Files: `database/transactions.sql`, `database/queries.sql`, `database/ddl_demo.sql`.

1. `transactions.sql`: fill the 7 outlined sections. Each section has a scenario comment, the SQL, and the expected output as a comment. Sections 3, 4, 5 and 7 need two sessions: write them as `-- SESSION A` and `-- SESSION B` steps with a numbered timeline. Section 5 shows a `could not serialize access` error and a retry.
2. `queries.sql`: fill every slot in sections 1 to 7 against seed data. One comment line per query on what it proves. 2.5 uses `search_tsv`.
3. `ddl_demo.sql`: wrap the file in `BEGIN; ... ROLLBACK;`. Demo add columns (users.bio, users.avatar_url, mod_versions.file_size_bytes, mod_versions.checksum_sha256, compatibility_matrix.notes), widen a varchar, rename `mods.summary` to `description` and back, add and drop a CHECK constraint. After ROLLBACK, a query against `information_schema.columns` proves the schema is unchanged.

Done when: each file runs on seeded data with `ON_ERROR_STOP=1` (the single-session parts), and the schema check after the DDL demo shows zero new columns.

#### Phase 4 exit checks

- `transactions.sql` (single-session parts), `queries.sql` and `ddl_demo.sql` run with `ON_ERROR_STOP=1`.
- The schema check after the DDL demo shows zero new columns.

### Phase 5: Tests, CI and benchmarks

Goal: Automated SQL tests in CI, measured index performance and the ER diagram.

Depends on: Phase 4.

#### P1-11 Test runner and DB CI

Files: `database/tests/run_tests.sql`, `.github/workflows/db.yml`.

1. `run_tests.sql` includes every test file with `\ir`.
2. Workflow on push and pull request: service `pgvector/pgvector:pg18` with owner credentials from section 3, install a PostgreSQL 18 client on the runner, run `python scripts/db_reset.py` with `DATABASE_URL` set to the service, then `tests/fixtures.sql` inside a throwaway database copy or after seed, then `run_tests.sql`, `queries.sql`, `ddl_demo.sql`, and the single-session parts of `transactions.sql`.

Done when: the workflow passes on GitHub.

#### P1-12 Benchmarks and ER diagram

Files: `docs/benchmarks.md`, `docs/er-diagram.png`, `database/tests/bench.sql`.

1. `bench.sql`: inside `BEGIN ... ROLLBACK`, insert 50,000 synthetic mods with random normalized 384-dim vectors using `generate_series`. Run `EXPLAIN (ANALYZE, BUFFERS)` for: vector top 10, full-text search, reverse dependency lookup, health check on a 40-mod loadout. Repeat each with the relevant index dropped inside the same transaction.
2. `benchmarks.md`: table of query, with index ms, without index ms, plan node used.
3. ER diagram from the final schema with matplotlib, dark GitHub-style theme.

Done when: `benchmarks.md` has real numbers from a local run.

#### Phase 5 exit checks

- `.github/workflows/db.yml` passes on GitHub.
- `docs/benchmarks.md` holds real numbers.
- `docs/er-diagram.png` matches the final schema.
- The human opens the Sync 3 pull request for Person 1.

### Phase 6: Final merge (both people together)

Goal: one working `main` with both tracks, documented and tagged.

Depends on: both people finished Phase 5.

Steps:
1. Person 1's Sync 3 pull request merges first. Then Person 2 merges `main` into `p2-app`, fixes conflicts or breakages, and merges its pull request.
2. Fresh clone of `main` on one machine. Run `python scripts/db_reset.py --with-tests`, `npm --prefix scripts run embed`, then start the web app.
3. Run the full demo script in section 9.
4. Write `README.md` together: pitch, architecture diagram, ER diagram, feature list, 3-command setup, demo accounts, screenshots, benchmark table, live link.
5. Fill the real numbers into the resume bullets in section 10.
6. The human tags `v1.0.0`.

#### Phase 6 exit checks

- Both CI workflows pass on `main`.
- A fresh clone reaches a working demo with the README steps alone.
- Commit message: `phase-6: final merge and v1.0.0`.


## 8. Sync points and final merge

Code reaches `main` only through pull requests with green CI. Each person commits and pushes to their own branch at the end of every phase. Only the sync points below open pull requests into `main`.

| Sync | Trigger | Pull request content | After merge |
|---|---|---|---|
| 1 | Person 2 finishes Phase 1 | `scripts/nexus/`, `data/curated/`, `database/seed.sql`, `database/seed_expectations.sql` | Person 1 merges `main` into `p1-database` and switches tests from fixtures to real seed where useful |
| 2 | Person 1 finishes Phase 3 | Person 1 Phases 1 to 3 | Person 2 merges `main` into `p2-app`. `seed_expectations.sql` must pass. If a loadout status is wrong, Person 2 fixes the YAML, not the SQL |
| 3 | Both finish Phase 5 | Person 1 remainder first, then Person 2 remainder | Phase 6 runs on `main` |

Both people run `python scripts/db_reset.py` after every sync.


## 9. Demo script (evaluation and end-to-end test)

1. Search "make the menus look better". A UI mod appears with a Meaning badge.
2. Open the broken Skyrim loadout. Score and errors show.
3. Click "Add" on the missing dependency, then "Auto-sort". Status improves.
4. Log in as `curator`, mark a pair in the loadout incompatible on the heatmap. The loadout turns broken.
5. Log in as `admin`, open the audit log, find the curator's change with a diff.
6. Log in as `modder2`, confirm `modder1`'s private loadout is not visible.
7. In psql, run transaction section 4 in two sessions and the DDL demo.
8. Show `docs/benchmarks.md`.


## 10. Resume bullets (fill real numbers in Phase 6)

- Built ModVault, a full-stack mod compatibility checker (PostgreSQL, pgvector, Next.js) seeded with 45 real mods from the Nexus Mods API, detecting 9 classes of loadout problems through a single SQL health engine.
- Implemented hybrid semantic search inside PostgreSQL by fusing pgvector HNSW similarity with full-text ranking (RRF), cutting query time from X ms to Y ms on 50k rows.
- Enforced security in the database layer with Row-Level Security, pgcrypto bcrypt, SECURITY DEFINER auth and an append-only trigger-based audit log, verified by SQL tests and Playwright in GitHub Actions CI.
