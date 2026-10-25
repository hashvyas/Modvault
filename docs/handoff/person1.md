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

## Phase 1: Indexes and triggers (2026-10-25)

### What was built

- `database/indexes.sql`: 7 new indexes on top of the existing 9 (16 total). HNSW on `mods.embedding` (vector search), GIN on `mods.search_tsv` (full-text), GIN on `mod_versions.supported_game_versions` (array containment), B-tree on `mod_dependencies.required_mod_id` (reverse dependency lookup), two on `audit_log` (by table and time, by user), and the partial unique index `uq_mod_versions_one_primary`.
- `database/functions.sql`, section 1: 8 trigger functions: `fn_compat_canonicalise_pair`, `fn_mod_version_single_primary`, `fn_set_updated_at`, `fn_loadout_mods_auto_position`, `fn_loadout_mods_game_check`, `fn_reviews_rating_rollup`, `fn_audit_log`, `fn_audit_log_immutable`. Section 2: the real one-line bodies of `fn_current_user_id` and `fn_current_role` (see Decisions).
- `database/triggers.sql`: rewritten. 18 `CREATE TRIGGER` statements. The obsolete `mv_mod_ratings` refresh outline is gone.
- `database/tests/fixtures.sql` (new): 2 games, 3 users (one per role, password `fixture-pass`), 6 mods, 8 versions, 5 dependencies (every dep_type), 4 matrix rows (one per status), 2 loadouts with 5 rows. Fixed UUIDs (`a...` games, `b...` users, `c...` mods, `d...` versions, `e...` loadouts).
- `database/tests/test_triggers.sql` (new): 9 trigger tests: the 7 from P1-02, plus test 8 (changing `old_row` on an audit row raises FORBIDDEN) and test 9 (deleting a user with audit history succeeds, their audit rows get `changed_by` NULL, `old_row` and `new_row` stay the same).

### How it works

- Pair canonicalisation: a BEFORE row trigger rewrites `NEW` (swaps A and B when A > B). Concept: BEFORE trigger that changes the row before it is written. The existing unique constraint then catches (A, B) and (B, A) as the same pair.
- Single primary: BEFORE INSERT OR UPDATE OF is_primary. When the new row is primary, it first sets `is_primary = false` on the mod's other versions, so the partial unique index never sees two primaries. Concept: `UPDATE OF <column>` trigger plus a partial unique index as a hard backstop.
- `fn_set_updated_at`: one generic function attached to users, mods, loadouts, compatibility_matrix. Concept: trigger function reuse.
- Auto position: BEFORE INSERT on loadout_mods. Position 0 means "append": it becomes `max(position) + 1`, or stays 0 for an empty loadout.
- Game check: BEFORE INSERT OR UPDATE on loadout_mods. Looks up the loadout's game and the version's mod game. If they differ it raises `MODVAULT:GAME_MISMATCH: <mod> is made for a different game than this loadout`. Missing rows are left to the foreign keys.
- Rating rollup: AFTER row trigger on reviews. Recomputes `rating_avg` (rounded to 2 places, same as `mod_ratings_view`) and `rating_count` for only the affected mod ids: NEW on insert, OLD on delete, both on update. SECURITY DEFINER because review authors will not have UPDATE on mods. Concept: trigger-maintained denormalised cache.
- Audit: one function `fn_audit_log` on 8 tables, the primary key column name passed as a trigger argument (`TG_ARGV[0]`). It turns OLD and NEW into JSONB with `to_jsonb`, removes `password_hash`, `embedding`, `search_tsv`, and writes `changed_by = fn_current_user_id()`. An UPDATE whose only changes are in `updated_at`, `rating_avg`, `rating_count`, `embedding`, `search_tsv` is skipped. Concept: generic AFTER row trigger, SECURITY DEFINER with pinned `search_path`.
- Immutable audit log: BEFORE UPDATE OR DELETE on audit_log raises `MODVAULT:FORBIDDEN`. Concept: append-only table enforced by trigger.
- Tests: each check is `BEGIN; DO $$ ... ASSERT ... $$; ROLLBACK;`. Expected errors are caught in a nested `BEGIN ... EXCEPTION` block and the message is matched against `MODVAULT:<CODE>: %`.
- Test 9 step by step: insert a temporary user, set `app.user_id` to that user, edit a fixture loadout (one audit row with `changed_by` = that user), switch `app.user_id` to the fixture admin, delete the user, then compare the audit row before and after. Only `changed_by` changes, to NULL. Concept: a foreign-key `ON DELETE SET NULL` action is an UPDATE, so BEFORE UPDATE triggers on the referencing table see it.

### Decisions

- `fn_current_user_id` and `fn_current_role` got their real bodies now instead of in P1-03. Reason: `fn_audit_log` uses `fn_current_user_id()` and test 5 asserts `changed_by` equals the session user, which cannot pass with the NULL stub. The bodies are exactly the section 6.1 one-liners, so nothing in Phase 2 changes. Alternative rejected: reading `current_setting` directly in `fn_audit_log`, which duplicates the contract helper.
- The audit skip check compares rows before hiding columns. Reason: if `password_hash` were hidden first, a password change would look like "nothing changed" and not be logged. Now it is logged, but without the hash.
- `audit_log` lets one kind of UPDATE through: `changed_by` set to NULL with nothing else changed. Reason: `changed_by` has `ON DELETE SET NULL`, which PostgreSQL runs as an UPDATE on audit_log. Without the exception, any user who ever changed anything could never be deleted. Covered by test 9. Test 8 shows that any other UPDATE, for example changing `old_row`, still raises FORBIDDEN. Alternative rejected: changing the FK to `NO ACTION` (would need a `schema.sql` change, which is frozen).
- Game check compares game ids only when both are found, so a missing loadout or version gives the normal foreign-key error, not a misleading GAME_MISMATCH.
- Fixture names start with `FX` / `Fixture` and use domains `fx-game-a`, `fx-game-b`, so they never hit the unique name and domain constraints once Person 2's real seed is loaded.
- Test 4 also checks an UPDATE that moves a review to another mod (both mods refreshed) and a DELETE of the last review (cache back to 0). Small addition beyond the spec, because those are the two branches most likely to be wrong.

### Assumptions

- `database/functions.sql`, section 2 header: session helpers filled in Phase 1 instead of P1-03.
- `database/functions.sql`, `fn_audit_log_immutable`: the FK `SET NULL` update on `changed_by` is allowed.
- "`\di` lists 16 indexes" means the 16 indexes defined in `indexes.sql`. `\di` itself shows 41, because it also lists primary-key, unique-constraint and materialized-view indexes.

### Checks

- `python scripts/db_reset.py`: exit code 0, 16 `CREATE INDEX` from indexes.sql, 18 `CREATE TRIGGER`.
- `psql ... -f database/tests/fixtures.sql`: exit code 0. Produces 33 audit rows.
- `pg_indexes` query: 16 indexes from indexes.sql (all 9 old plus the 7 new names).
- `psql ... -v ON_ERROR_STOP=1 -f database/tests/test_triggers.sql`: exit code 0, `PASS 1` to `PASS 9`, zero failed assertions.

### Open issues

- Auto position is not safe under two concurrent inserts into the same loadout (both can read the same max). Marked with a `shortcut:` comment. Fine for one user editing their own loadout.
- Position 0 always means "append" when rows exist, so an explicit insert at position 0 into a non-empty loadout goes to the end. That is the spec rule. Reordering goes through `pr_apply_load_order` or an UPDATE, which the trigger does not touch.
- `fixtures.sql` is not yet run by `db_reset.py` or CI. Phase 5 (P1-11) wires it in.
- A user cannot delete themselves while `app.user_id` is set to their own id. The delete cascades to their loadouts and reviews, the audit trigger writes rows with `changed_by` = that user, and the foreign key to the already-deleted user fails. Test 9 avoids this by switching to the admin before the delete. Revisit if a "delete my account" feature is added: run the delete with `app.user_id` cleared or set to an admin.

### For the other person

- `fn_current_user_id()` and `fn_current_role()` now work. Set `app.user_id` and `app.role` with `set_config(..., true)` at the start of every app transaction, otherwise audit rows get `changed_by = NULL`. `app.user_id` must be a real user id (it is a foreign key in audit_log).
- Adding a version of a mod from another game to a loadout now fails with `MODVAULT:GAME_MISMATCH: ...`. Show the human text.
- Inserting into `loadout_mods` without a position appends to the end.
- `mods.rating_avg` / `rating_count` are maintained by trigger. Do not write them from the app or seed.
- Setting `is_primary = true` on a version automatically demotes the old primary.
- `audit_log` cannot be updated or deleted (FORBIDDEN). Deleting a user is fine and keeps their audit rows with `changed_by` NULL, but never delete a user while `app.user_id` is that same user (see Open issues).

## Phase 2: Core SQL logic (2026-10-25)

### What was built

- `database/functions.sql`: real bodies for 10 contract functions. Auth: `fn_register_user`, `fn_authenticate`. Search: `fn_search_mods_hybrid`, `fn_search_mods_by_tag`. Mods: `fn_get_mod_dependency_tree`, `fn_mod_stats`, `fn_semver_satisfies`. Loadouts: `fn_check_loadout_compatibility`, `fn_loadout_health_score`, `fn_suggest_load_order`. `fn_export_loadout` and all procedures are still stubs (Phase 3).
- `database/tests/test_auth.sql` (new): 5 checks. Register then log in, failed logins (wrong password, unknown user, NULL, inactive user), DUPLICATE for username and email, INVALID_INPUT for 5 bad inputs, 18 semver cases.
- `database/tests/test_health.sql` (new): 12 checks. One loadout per issue type (9), a clean loadout scoring 100, a disabled conflicting mod, and score formula / result order / unknown ids.
- `database/tests/test_graph.sql` (new): 7 checks. 3-level dependency chain, conflicts not followed, A to B to A cycle, load order on a shuffled loadout, load order with a cycle, `fn_mod_stats` counts, tag AND match.
- `database/tests/test_search.sql` (new): 4 checks with hand-made 384-dim one-hot vectors. Keyword only, vector only, fused rank, game filter / limit cap / empty input.

### How it works

- `fn_register_user` (PL/pgSQL, SECURITY DEFINER): checks the username regex, `@` in the email, password length, then inserts with `crypt(pw, gen_salt('bf', 10))`. A `unique_violation` is caught in an `EXCEPTION` block and turned into `MODVAULT:DUPLICATE`. `GET STACKED DIAGNOSTICS ... CONSTRAINT_NAME` tells a duplicate username from a duplicate email. Concept: exception handling, error translation.
- `fn_authenticate` (SQL, SECURITY DEFINER): `LEFT JOIN users` from a one-row table, so there is always exactly one row to run `crypt` on. When the username is unknown, `crypt` runs against a fixed dummy cost-10 hash, so a missing user takes as long as a wrong password. Concept: timing-safe login, SECURITY DEFINER so the app role never reads `password_hash`.
- `fn_semver_satisfies` (PL/pgSQL, IMMUTABLE): pulls the digit groups out with `regexp_matches(..., '\d+', 'g')` into a `numeric[]`, pads both sides with zeros to the same length (at least 3), and compares the arrays. PostgreSQL compares arrays element by element, so `{1,10,0} > {1,9,0}`. The operator is read with `regexp_match`. Concept: array comparison.
- `fn_check_loadout_compatibility` (one SQL function): CTE `lm` = enabled loadout rows with version, mod and loadout game version. CTE `deps` = every dependency of an `lm` version, `LEFT JOIN`ed to the loadout's version of the target mod (NULL when absent). CTE `pairs` = matrix rows with both versions in the loadout. Then one CTE per issue type reads from these three. They are combined with `UNION ALL` and ordered by severity, issue_type, message. `DECLARED_CONFLICT` uses `DISTINCT ON (least(a, b), greatest(a, b))` so a conflict declared from both sides is one row. `UNVERIFIED_PAIR` pairs `a.version_id < b.version_id` (the canonical matrix order from the Phase 1 trigger) and `LEFT JOIN`s the matrix. Concept: CTE pipeline, anti-join with LEFT JOIN ... IS NULL, DISTINCT ON.
- `fn_loadout_health_score` (PL/pgSQL): NOT_FOUND for an unknown loadout, otherwise `count(*) FILTER (WHERE severity = ...)` over the check function. Concept: aggregate FILTER.
- `fn_get_mod_dependency_tree`: `WITH RECURSIVE`. The anchor is the version at depth 0. Each step joins `mod_dependencies` (required, optional, recommends) to the primary version of the target mod and appends it to `path`. It stops when the next version is already in `path` or depth reaches 10. Concept: recursive CTE with cycle guard.
- `fn_suggest_load_order`: builds the edges between loadout versions, then a recursive CTE walks every path from every version (the `path` array stops cycles). A version's depth is its longest walk. `ROW_NUMBER() OVER (ORDER BY depth, position, mod name) - 1` gives positions 0 to n-1. Concept: longest path by recursive CTE, window function.
- `fn_mod_stats`: scalar subqueries for versions, dependent mods, and conflicts (declared conflicts in either direction plus incompatible matrix pairs).
- `fn_search_mods_by_tag`: `GROUP BY mod_id HAVING count(DISTINCT slug) = number of slugs asked for`. Concept: relational division.
- `fn_search_mods_hybrid`: CTE `sem` takes the 50 nearest embeddings (`ORDER BY embedding <=> p_embedding LIMIT 50`, which can use the HNSW index) and numbers them. CTE `kw` takes the 50 best `ts_rank_cd` matches of `websearch_to_tsquery`. `FULL OUTER JOIN` keeps mods found by either half. The score is the RRF sum `1/(60 + rank)` of both halves. Concept: Reciprocal Rank Fusion, FULL OUTER JOIN.

### Decisions

- `fn_semver_satisfies` and `fn_loadout_health_score` are PL/pgSQL, not SQL like their stubs. The language is not part of the signature. Semver needs several steps, and the score needs RAISE.
- Semver uses `numeric[]` instead of `int[]` so a long build number cannot overflow. Both sides are padded to the same length, so `1.2.0.1` is not equal to `1.2.0`.
- In `fn_search_mods_hybrid`, `ROW_NUMBER` is applied after `LIMIT 50` in an inner query. Numbering first would force a full sort of all mods and skip the HNSW index.
- A blank query is passed to `websearch_to_tsquery` as NULL. An empty string works too, but prints a "no lexemes" NOTICE on every vector-only search.
- `p_limit` NULL means 50, negative means 0, and above 50 is cut to 50.
- `fn_mod_stats.dependent_count` counts distinct other mods with a non-conflict dependency. A conflict is not a dependent.
- `UNVERIFIED_PAIR` skips two versions of the same mod in one loadout. That pair is not a compatibility question.
- `DUPLICATE` says whether the username or the email is taken, so the sign-up form can point at the right field.

### Assumptions

- `database/functions.sql`, `fn_semver_satisfies`: a constraint with no digits (for example `>=abc`) is treated as satisfied.
- `database/functions.sql`, `fn_check_loadout_compatibility`, CTE `version_constraint`: version constraints on `conflicts` rows are not checked.
- `database/functions.sql`, `fn_suggest_load_order` header: disabled rows are ordered too, so `pr_apply_load_order` can renumber every row.

### Checks

- `psql ... -f database/tests/test_auth.sql`: exit 0, PASS 1 to 5 (18 semver cases).
- `psql ... -f database/tests/test_health.sql`: exit 0, PASS 1 to 12.
- `psql ... -f database/tests/test_graph.sql`: exit 0, PASS 1 to 7.
- `psql ... -f database/tests/test_search.sql`: exit 0, PASS 1 to 4.
- `psql ... -f database/tests/test_triggers.sql`: still exit 0, PASS 1 to 9.
- Clean build: a scratch database got `run_all.sql`, `fixtures.sql` and all five test files. All exited 0, then the scratch database was dropped. (`db_reset.py` itself was not run this phase; see Open issues.)
- Contract: a `pg_proc` dump of every `fn_` / `pr_` routine (name, arguments, result, SECURITY DEFINER) before and after the phase is identical, 29 routines.
- Sync 1 has not landed (`seed.sql` is still comments only), so the real-seed health check was not run.

### Open issues

- `python scripts/db_reset.py` was not run during this phase. The clean build was checked in a scratch database instead. Run it once before committing.
- `fn_suggest_load_order` walks every dependency path, which grows fast in dense graphs. Marked with a `shortcut:` comment. Fine for loadouts of tens of mods.
- `UNVERIFIED_PAIR` gives n(n-1)/2 info rows for a loadout with no matrix data (780 for 40 mods). That is the spec rule. The UI should group or collapse info rows.
- A query made only of stopwords (for example "the") still prints the "no lexemes" NOTICE. Harmless.

### For the other person

- Working now: `fn_register_user`, `fn_authenticate`, `fn_search_mods_hybrid`, `fn_search_mods_by_tag`, `fn_get_mod_dependency_tree`, `fn_mod_stats`, `fn_semver_satisfies`, `fn_check_loadout_compatibility`, `fn_loadout_health_score`, `fn_suggest_load_order`. Still stubs until Phase 3: `fn_export_loadout` and all `pr_` procedures.
- `fn_register_user` errors: `MODVAULT:INVALID_INPUT: ...` (username, email or password) and `MODVAULT:DUPLICATE: username is already taken` / `MODVAULT:DUPLICATE: email is already registered`.
- `fn_authenticate` returns zero rows for every failure, including inactive accounts. Show one generic "wrong username or password" message.
- `fn_search_mods_hybrid`: pass a NULL embedding for keyword-only search, and a NULL or empty query for vector-only search. The limit is capped at 50. `semantic_rank` / `keyword_rank` are NULL when that half did not find the mod, so the "Meaning" / "Keyword" badges can key on them.
- `fn_loadout_health_score` raises `MODVAULT:NOT_FOUND` for an unknown loadout. `fn_check_loadout_compatibility` returns zero rows instead.
- There can be many info rows (`UNVERIFIED_PAIR`). Collapse them in the UI.
