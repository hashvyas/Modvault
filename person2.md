# ModVault: Person 2 Plan (data pipeline and web app)

Branch: `p2-app`. This file is the full spec for Person 2's coding agent. Person 1 has a matching file. Sections 1 to 6 are identical in both files.


## 0. Instructions for the agent

You are the coding agent for Person 2. Your branch is `p2-app`. Person 1 works in parallel on a separate branch with a separate agent and a separate plan file. Read this whole file before writing any code.

1. Do not start until Person 1's Phase 0 is on `main`. Then the human creates `p2-app` from `main`. All your phases run on `p2-app`.
2. Run phases in order, and tasks inside a phase in order. Do not skip ahead. Each task lists Files, Steps and Done when.
3. A task is complete only when every "Done when" check passes. Run the checks yourself and show the output to the human.
4. A phase is complete only when every task in it is complete and the phase exit checks pass.
5. At the end of each phase, stop and give the human a summary: what you built, check output, assumptions made. The human commits and pushes. Commit message format: `p2-phase-<N>: <phase title>`, for example `p2-phase-2: embeddings, web scaffold and auth`. Do not start the next phase until the human confirms the push.
6. Only edit files your person owns (section 4). If you need a change in a file you do not own, stop and tell the human what change you need and why.
7. Never change a signature in the contract (section 6). Function bodies change. Names, arguments, return columns and types do not.
8. Never invent Nexus mod IDs, API fields or library APIs. If unsure, check the official docs or ask the human.
9. When a task is ambiguous, pick the option closest to this spec, write the assumption in a code comment starting with `-- ASSUMPTION:` or `// ASSUMPTION:`, and list it in the phase summary.
10. Stop and ask the human before: deleting files you do not own, changing `schema.sql` after Phase 0, using any paid service, or committing secrets.
11. Every command runs in PowerShell on Windows 11 from the repo root.


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
| 0 | Setup | P2-00 |
| 1 | Data pipeline | P2-01, P2-02, P2-03, P2-04 |
| 2 | Embeddings, web scaffold and auth | P2-05, P2-06, P2-07 |
| 3 | Discovery pages | P2-08, P2-09 |
| 4 | Loadouts, curation and admin | P2-10, P2-11, P2-12 |
| 5 | Testing and deploy | P2-13, P2-14 |
| 6 | Final merge | together |

### Phase 0: Setup

Goal: Local environment ready on `p2-app` against the shared foundation.

Depends on: Person 1 Phase 0 pushed to `main`.

#### P2-00 Local setup

Files: `.env` (local only, never committed).

Steps:
1. Copy `.env.example` to `.env`. Fill `JWT_SECRET` with 64 random hex characters. Leave `NEXUS_API_KEY` for P2-02.
2. Run the one-time database setup from section 3 if not done yet.
3. Run `python scripts/db_reset.py`.

Done when: the reset exits with code 0 and `SELECT * FROM fn_check_loadout_compatibility(gen_random_uuid());` returns zero rows with the 6 contract columns.

#### Phase 0 exit checks

- `p2-app` exists and matches `main`.
- `python scripts/db_reset.py` exits with code 0.
- `.env` is listed in `.gitignore` and not committed.

### Phase 1: Data pipeline

Goal: Real Nexus data pulled, curated relationships written, deterministic `seed.sql` generated.

Depends on: Phase 0.

#### P2-01 Curated mod list

Files: `data/curated/games.yaml`, `data/curated/mods.yaml`.

Formats:

```bash
# games.yaml
- domain: skyrimspecialedition
  current_version: "1.6.1170"
  versions: ["1.5.97", "1.6.640", "1.6.1170"]

# mods.yaml (mod refs everywhere use "<domain>:<nexus_mod_id>")
- ref: skyrimspecialedition:<id>
  expect_name: SkyUI
  supported_game_versions:
    "<semver>": ["1.6.640", "1.6.1170"]
```

Steps: list 15 mods per game with real dependency relationships. Good anchors: SKSE64, Address Library, SkyUI, Unofficial Skyrim Special Edition Patch (Skyrim). F4SE, Mod Configuration Menu, Unofficial Fallout 4 Patch (Fallout 4). SMAPI, Content Patcher, Generic Mod Config Menu (Stardew). The human confirms each Nexus ID from the mod page URL. Do not guess IDs.

Done when: 45 entries exist and the human has confirmed the IDs.

#### P2-02 Nexus pull script

Files: `scripts/nexus/pull.py`, `scripts/nexus/requirements.txt`.

1. Headers on every request: `apikey: $NEXUS_API_KEY`, `Application-Name: modvault`, `Application-Version: 0.1.0`, `Accept: application/json`.
2. Calls: `GET /v1/games/{domain}.json` per game, `GET /v1/games/{domain}/mods/{id}.json` and `GET /v1/games/{domain}/mods/{id}/files.json` per mod.
3. Cache each response to `data/raw/{domain}/game.json`, `mod_{id}.json`, `files_{id}.json`. Skip any file already cached unless `--refresh`.
4. Sleep 1 second between calls. Read `X-RL-Hourly-Remaining` and stop with a clear message when it drops below 20. Retry 429 and 5xx with backoff, at most 3 times.
5. Fail loudly when a mod's `name` does not contain `expect_name` (case-insensitive).

```bash
python -m pip install -r scripts/nexus/requirements.txt
python scripts/nexus/pull.py --games skyrimspecialedition fallout4 stardewvalley
```

Done when: 93 JSON files exist in `data/raw/` and the name check passes for all 45 mods.

#### P2-03 Curated relationship data

Files: `data/curated/users.yaml`, `tags.yaml`, `dependencies.yaml`, `compat.yaml`, `reviews.yaml`, `loadouts.yaml`.

```bash
# users.yaml
- { username: admin, email: admin@modvault.dev, role: admin, password: "REDACTED" }

# tags.yaml
- { name: User Interface, slug: user-interface, mods: [skyrimspecialedition:<id>] }

# dependencies.yaml
- { mod: <ref>, requires: <ref>, type: required, constraint: ">=2.0.0", source: nexus }

# compat.yaml (versions default to primary, add a_semver or b_semver to pin)
- { a: <ref>, b: <ref>, status: incompatible, verified_by: curator,
    detail: { reason: "Both replace the same menu files", files: ["interface/hudmenu.swf"] } }

# reviews.yaml
- { user: modder1, mod: <ref>, rating: 5, body: "Required for every UI mod." }

# loadouts.yaml
- name: Broken Skyrim UI
  owner: modder1
  game: skyrimspecialedition
  game_version: "1.6.1170"
  is_public: true
  expected_status: broken
  mods: [<ref>, <ref>, <ref>]
  disabled: []
```

Requirements:
- Users: `admin`, `curator`, `modder1` to `modder6`.
- 15 to 20 tags, every mod has 1 to 3.
- Dependencies from each mod's Nexus requirements section use `source: nexus`. Add a few `conflicts`, `optional` and `recommends` rows with `source: manual`.
- 20 to 30 compat rows covering all four statuses.
- 40 reviews spread across mods and users.
- 6 loadouts: 2 per game, covering `healthy`, `warnings` and `broken`. Across all loadouts, every issue type in section 6.6 appears at least once.

Done when: every ref resolves to a mod in `mods.yaml`.

#### P2-04 Seed generator

Files: `scripts/nexus/generate_seed.py`, `database/seed.sql`, `database/seed_expectations.sql`.

1. UUIDs: `uuid.uuid5(uuid.NAMESPACE_URL, f"modvault:{kind}:{key}")`. Keys: game domain, mod ref, `ref@semver` for versions, username, tag slug. Reruns produce identical output.
2. Games from `game.json` (`name`, `id`, `domain_name`) plus `current_version` from YAML.
3. Mods from `mod_*.json`: `name`, `summary`, `author` to `nexus_author`, `mod_downloads` to `download_count`, `endorsement_count`, category name looked up from the game's `categories` list by `category_id`. `author_id` NULL. Strip HTML tags and BBCode from text.
4. Versions from `files_*.json`: keep files with `category_name` in `MAIN` or `OLD_VERSION`. Use `version` as semver (empty becomes `0.0.0`, truncate to 20 chars). Keep the newest file per semver. Newest MAIN file is primary. `uploaded_timestamp` to `uploaded_at`. File `description` (stripped) to `changelog`. `supported_game_versions` from YAML, default `{}`.
5. Dependencies apply to every version of the dependent mod.
6. Passwords: emit `crypt('<password>', gen_salt('bf', 10))`.
7. Write one `BEGIN; ... COMMIT;` with inserts in FK order: games, users, tags, mods, mod_versions, mod_tags, mod_dependencies, compatibility_matrix, reviews, loadouts, loadout_mods. Escape all strings with dollar quoting or doubled single quotes.
8. `seed_expectations.sql`: one `ASSERT` per loadout comparing `loadout_health_view.status` with `expected_status`, plus row-count asserts per table.

```bash
python scripts/nexus/generate_seed.py
```

Done when: `python scripts/db_reset.py` loads the seed with no errors, and running the generator twice gives byte-identical files. `seed_expectations.sql` passes only after Sync 2 (it needs P1's functions).

#### Phase 1 exit checks

- 93 cached JSON files exist in `data/raw/` (gitignored).
- `python scripts/db_reset.py` loads the seed with no errors.
- Running the generator twice gives byte-identical files.
- The human opens the Sync 1 pull request (section 8).

### Phase 2: Embeddings, web scaffold and auth

Goal: Every mod has an embedding, the Next.js app talks to the database through `withUser`, and login works for all roles.

Depends on: Phase 1.

#### P2-05 Embedding job

Files: `scripts/package.json`, `scripts/embed.ts`.

1. Load `pipeline('feature-extraction', 'Xenova/all-MiniLM-L6-v2')`. Call with `{ pooling: 'mean', normalize: true }`.
2. Text per mod: `` `${name}. ${category ?? ''}. ${summary ?? ''}` ``.
3. Select mods with `embedding IS NULL` using `DATABASE_URL` (owner). Update in batches of 16 inside one transaction. Pass vectors as the string `'[v1,v2,...]'` cast with `$1::vector`.
4. Print count embedded.
5. `scripts/package.json` defines `"embed": "tsx embed.ts"` and loads `.env` from the repo root.

```bash
npm --prefix scripts install
npm --prefix scripts run embed
```

Done when: `SELECT count(*) FROM mods WHERE embedding IS NULL` returns 0 and rerunning embeds 0 rows.

#### P2-06 Web scaffold

Files: `web/` (new Next.js app).

1. Create the app with TypeScript, App Router, Tailwind, ESLint, `src/` off, import alias `@/*`.
2. Install `pg`, `zod`, `jose`, `@huggingface/transformers`, `@dnd-kit/core`, `@dnd-kit/sortable`, `@xyflow/react`, and init shadcn/ui.
3. `next.config` with `output: 'standalone'` and `serverExternalPackages: ['@huggingface/transformers']`.
4. `web/lib/db.ts`: a `Pool` on `APP_DATABASE_URL`. Export `withUser(session | null, fn)`: get client, `BEGIN`, `SELECT set_config('app.user_id', $1, true), set_config('app.role', $2, true)` (empty strings for anonymous), run `fn(client)`, `COMMIT`, `ROLLBACK` on error, always release.
5. `web/lib/errors.ts`: parse `MODVAULT:<CODE>:` per section 6.5 into `{ code, message }`.
6. `web/lib/embed.ts`: module-level singleton pipeline, same options as P2-05. Export `embed(text): Promise<number[]>` and `toPgVector(v): string`.
7. Every DB call goes through `withUser`. No raw SQL string concatenation.

Done when: `npm run build` passes and a test page prints the row count from `mod_catalog_view` through `withUser`.

#### P2-07 Auth

Files: `web/lib/session.ts`, `web/middleware.ts`, `web/app/(auth)/login`, `web/app/(auth)/register`, logout server action.

1. Register calls `fn_register_user`, then logs in. Login calls `fn_authenticate`. Zero rows shows "Invalid username or password".
2. JWT payload `{ sub: user_id, username, role }`, HS256 with `JWT_SECRET`, cookie `modvault_session`, httpOnly, `secure` in production, `sameSite: 'lax'`, 7 days.
3. Middleware route rules:

| Path | Allowed |
|---|---|
| `/`, `/search`, `/games/**`, `/mods/**`, `/loadouts/[id]` when public | anyone |
| `/loadouts`, `/loadouts/new`, `/mods/new`, review actions | modder, curator, admin |
| `/curate/**`, matrix edits | curator, admin |
| `/admin/**` | admin |

4. Server actions re-check the role from the verified session. Never trust a role sent by the client.

Done when: each demo account reaches its allowed pages and gets redirected from the others.

#### Phase 2 exit checks

- `SELECT count(*) FROM mods WHERE embedding IS NULL` returns 0.
- `npm run build` passes in `web/`.
- Each demo account reaches its allowed pages and is redirected from the others.

### Phase 3: Discovery pages

Goal: Home, search, game browse, mod detail and publish pages working.

Depends on: Phase 2. Search and stats return real results only after Sync 2. Before Sync 2, build against the contract stubs and confirm empty states render.

#### P2-08 Search and browse

Files: `web/app/page.tsx`, `web/app/search/`, `web/app/games/[domain]/`.

1. Home: search bar, three game cards, featured mods, leaderboard strip from `mv_game_leaderboard`.
2. `/search?q=&game=`: embed `q`, call `fn_search_mods_hybrid`. Each result shows badges: "Meaning" when `semantic_rank` is set, "Keyword" when `keyword_rank` is set. Tag filter calls `fn_search_mods_by_tag` and intersects.
3. `/games/[domain]`: mod grid from `mod_catalog_view` joined to mods, sort by rating, downloads, newest, filter by category and tag, 24 per page.

Done when: searching "make the menus look better" returns a UI mod with a Meaning badge.

#### P2-09 Mod detail and publish

Files: `web/app/mods/[id]/`, `web/app/mods/new/`.

1. Header with stats from `fn_mod_stats`, tags, Nexus author, link to the Nexus page.
2. Versions table with supported game versions and primary marker. Curators get a "Make primary" button (`pr_promote_version`).
3. Dependency graph with React Flow from `fn_get_mod_dependency_tree`. Edge style by dep_type.
4. Compatibility list from `compatibility_matrix` for this mod's versions, colored by status, showing `conflict_detail`.
5. Reviews list and a review form (insert or update own review).
6. "Add to loadout" picker listing the user's loadouts for this game, calling `pr_add_mod_to_loadout`.
7. `/mods/new`: form, embed name + category + summary, call `pr_publish_mod`.

Done when: every section renders on a seeded Skyrim mod and publishing a new mod makes it findable in search.

#### Phase 3 exit checks

- Every page in P2-08 and P2-09 renders with no runtime errors.
- After Sync 2: searching "make the menus look better" returns a UI mod with a Meaning badge.

### Phase 4: Loadouts, curation and admin

Goal: Loadout builder with live health report, compatibility heatmap and admin tools.

Depends on: Phase 3 and Sync 2 (needs Person 1's procedures, views and RLS).

#### P2-10 Loadout builder

Files: `web/app/loadouts/`.

1. `/loadouts`: user's loadouts with status badges from `loadout_health_view`. "New loadout" form (name, game, game version, public toggle).
2. `/loadouts/[id]`, two panes:
   - Left: sortable list with dnd-kit. Each row shows mod name, version picker, enable toggle, remove. Dropping saves all positions in one server action (one transaction).
   - Right: health panel. Score ring, status, issues grouped by severity, info group collapsed by default.
3. Fix buttons: MISSING_DEPENDENCY row gets "Add <mod>" (primary version of `related_mod_id` through `pr_add_mod_to_loadout`). LOAD_ORDER rows and the panel header get "Auto-sort" (`pr_apply_load_order`).
4. Export button downloads `fn_export_loadout` JSON. Import page accepts a file and calls `pr_import_loadout`, then shows the skipped count.
5. After every change, refetch the health report.

Done when: on the seeded broken loadout, adding the missing dependency and auto-sorting moves the status from broken to healthy or warnings, and export then import gives an identical mod list.

#### P2-11 Compatibility heatmap

Files: `web/app/games/[domain]/compat/`.

1. Grid of primary versions for the game, cells colored by status (gray for no row).
2. Curators click a cell to open a dialog: status select, reason text, file list. Saves with `pr_upsert_compatibility`.
3. Everyone else sees read-only cells with a tooltip.

Done when: a curator marks a pair incompatible and the loadout holding both turns broken on reload.

#### P2-12 Admin

Files: `web/app/admin/`.

1. Audit log table: filter by table, operation, user, date range. 50 per page, newest first.
2. Row detail: side-by-side diff of `old_row` and `new_row` with changed keys highlighted.
3. "Refresh reports" button calls `pr_refresh_reports`.
4. Users table with role select calling `pr_set_user_role`.

Done when: the curator's change from P2-11 appears with the curator's username and a correct diff.

#### Phase 4 exit checks

- `seed_expectations.sql` passes.
- Demo script steps 1 to 6 (section 9) work by hand.

### Phase 5: Testing and deploy

Goal: End-to-end test in CI and a live deployment.

Depends on: Phase 4.

#### P2-13 End-to-end test and app CI

Files: `web/e2e/demo.spec.ts`, `web/playwright.config.ts`, `.github/workflows/app.yml`.

1. Playwright test runs the demo script from section 9, steps 1 to 6.
2. Workflow: service `pgvector/pgvector:pg18`, run `run_all.sql` and `seed_expectations.sql`, run `embed.ts`, then in `web/`: `npm ci`, lint, typecheck, build, start, Playwright.

Done when: the workflow passes on GitHub after Sync 2.

#### P2-14 Deploy

Files: `web/Dockerfile`, `docs/screenshots/`, `docs/deploy.md`.

Render builds this Dockerfile on its own servers. Nobody installs Docker locally.

1. Multi-stage Dockerfile on the standalone build. A build step downloads the embedding model into the image (`env.cacheDir` set to a folder copied into the final stage), so the first search has no download delay.
2. Neon: create a project on PostgreSQL 18 (the version used locally and in CI), create the database, enable `vector` and `pgcrypto`, run `run_all.sql`, change the `modvault_app` password, run `embed.ts` against it.
3. Render: Docker web service from `web/Dockerfile`, env vars `APP_DATABASE_URL`, `JWT_SECRET`.
4. Screenshots of every page into `docs/screenshots/`. Steps written in `docs/deploy.md`.

Done when: the live URL passes the demo script by hand.

#### Phase 5 exit checks

- `.github/workflows/app.yml` passes on GitHub.
- The live URL passes the demo script by hand.
- The human opens the Sync 3 pull request for Person 2.

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
