# Person 1 handoff log

## Phase 0: Shared foundation (2026-10-24)

### What was built

- `.env.example`: the four settings both people need (owner and app database URLs, JWT secret, Nexus key). Copy it to `.env`, which is never committed.
- `.gitignore`: ignores `.env`, `data/raw/`, `node_modules/`, `.next/`.
- `scripts/db_reset.py`: rebuilds the database from scratch. It drops schema `public` and runs `database/run_all.sql`. `--with-tests` also runs `database/tests/run_tests.sql`.
- `database/schema.sql`: the final 12-table schema from section 5. `users` gets `is_active` and `updated_at`. `games` gets `current_version` and a unique `domain`. `mods` gets a nullable `author_id` (SET NULL), `nexus_author`, counters, `is_featured`, rating cache columns, the generated `search_tsv`, a 384-dim `embedding`, `updated_at` and `UNIQUE (game_id, nexus_mod_id)`. `mod_versions` gets `supported_game_versions`. `loadouts` gets `description`, `game_version` and `updated_at`. The new `audit_log` is table 12.
- `database/functions.sql`: stubs for all 21 contract routines (13 functions, 8 procedures) with the exact section 6 signatures. Removed the old `audit_log` table plan and the `fn_refresh_mv_mod_ratings` plan. The trigger-function plans stay as comments for Phase 1.
- `database/views.sql`: `mod_catalog_view` now uses `LEFT JOIN users` and shows `author_name`. Added stubs for `loadout_health_view`, `mod_conflict_summary_view` and the materialized view `mv_game_leaderboard` with its unique index.
- `database/run_all.sql`: the build order from section 4.
- `database/rls.sql`: placeholder (comment and `SET` only).
- `database/indexes.sql`, `triggers.sql`, `seed.sql`, `queries.sql`, `transactions.sql`, `ddl_demo.sql`: added `SET client_encoding = 'UTF8';` and fixed the DEPENDENCY / HOW TO RUN headers to point at `run_all.sql` and `scripts/db_reset.py`. The `seed.sql` header now says it is generated: mods and versions come from the Nexus API, and all other rows are curated.

### How it works

- `db_reset.py`: reads `DATABASE_URL` from the environment, falling back to `.env`. It finds `psql` and `pg_isready` on PATH, falling back to `C:\Program Files\PostgreSQL\18\bin`. It sets `PGCLIENTENCODING=UTF8` for the child processes. Then it runs `pg_isready`, `DROP SCHEMA public CASCADE; CREATE SCHEMA public;` and `run_all.sql` with `ON_ERROR_STOP=1`. Every path is resolved from the script's own location, so it works from any folder. Any failing step prints a message and exits with code 1.
- `run_all.sql` uses `\ir` (include relative to this file) so the build order lives in one place.
- `search_tsv` is a generated stored column, meaning PostgreSQL computes it on every insert or update. It weights name A, category B and summary C, so name matches rank highest in `ts_rank_cd`.
- Contract stubs: SQL-language functions return `SELECT <typed NULLs> WHERE false` (zero rows of the right shape), or `NULL`, `false`, `0` or `'{}'::jsonb` for scalar results. Procedures are PL/pgSQL `BEGIN NULL; END`. The auth functions, `pr_set_user_role` and `pr_refresh_reports` are already `SECURITY DEFINER` with `SET search_path = public, pg_temp`, so later phases only replace the bodies.
- The stub views use typed `NULL` columns with `WHERE false`, so their column names and types are fixed now. `mv_game_leaderboard` has `UNIQUE INDEX (game_id, mod_id)`, which `REFRESH ... CONCURRENTLY` needs later.

### Decisions

- `mods.updated_at`, `users.updated_at` and `loadouts.updated_at` are `NOT NULL DEFAULT NOW()`, following the section 5 rule for all timestamps. A nullable "never updated" value was rejected because it conflicts with that rule.
- Constraints are named (`uq_games_domain`, `uq_mods_game_nexus_mod`, `chk_mods_*`, `chk_audit_log_operation`), following the existing `uq_` / `chk_` naming in `schema.sql`.
- The stubs for `fn_current_user_id` and `fn_current_role` return NULL. The real one-liners are task P1-03, and the plan says not to skip ahead.
- `pr_set_user_role` and `pr_refresh_reports` also get `SET search_path = public, pg_temp`. The contract only says SECURITY DEFINER, but every SECURITY DEFINER routine should pin its search_path. This is not part of the signature.
- `triggers.sql` still has its old outline, including the obsolete `mv_mod_ratings` refresh section. Phase 1 (P1-02) rewrites that file, so it was left alone apart from the header.

### Assumptions

- `database/views.sql`, VIEW 1 header: `author_name` replaces `author_username` instead of sitting beside it.
- `database/views.sql`, VIEW 4 header: in `loadout_health_view` the counts are bigint and `score` is int.
- `database/views.sql`, VIEW 5 header: in `mod_conflict_summary_view` the counts are bigint.
- `database/views.sql`, VIEW 6 header: in `mv_game_leaderboard`, `rating_count` and `download_count` are int, `rating_avg` and `bayes_score` are numeric, and `rank_in_game` is bigint.

### Checks

- Section 3 version check: server 18.6, pgvector 0.8.6. `pg_isready`: accepting connections.
- `schema.sql` on an empty schema, then `\dt`: 12 tables.
- `schema.sql`, `functions.sql`, `views.sql` in order, then `SELECT * FROM fn_check_loadout_compatibility(gen_random_uuid());`: 0 rows with the 6 contract columns.
- `python scripts/db_reset.py` run from another folder: exit code 0.
- `db_reset.py` against a dead port: clear message and exit code 1.
- `pg_proc` dump: all 13 functions and 8 procedures match section 6 exactly. View and materialized-view columns match 6.4. The unique index on `mv_game_leaderboard` exists.

### Open issues

- `db_reset.py --with-tests` fails with a clear message until `database/tests/run_tests.sql` exists (Phase 5).
- `triggers.sql` still has the stale `mv_mod_ratings` outline (rewritten in Phase 1).

### For the other person

- `mod_catalog_view` now has `author_name` (username, else Nexus author) instead of `author_username`.
- All contract routines exist as stubs. They return no rows, NULL, `false`, `0` or `'{}'` until Phases 2 and 3 fill the bodies. You can wire calls against them now.
- `seed.sql` is yours from here on. It must be UTF-8 without BOM and start with `SET client_encoding = 'UTF8';`. Mods need `author_id` NULL plus `nexus_author`, and `(game_id, nexus_mod_id)` must be unique.
- After every sync, run `python scripts/db_reset.py`.
