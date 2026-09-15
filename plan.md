# CRASHLOG (ModVault) — Execution Plan

DBMS Level 3 Mini Project. Mod repository with conflict detection and compatibility tracking.
Stack: PostgreSQL + pgvector, Next.js. Data source: Nexus Mods API.

## Current state (as of this plan)

Done:
- `schema.sql` — 12 tables, 4 enums, all constraints, FK dependency order correct.
- `indexes.sql` — 9 indexes on FK and lookup columns.
- `views.sql` — 3 views: `mod_catalog_view`, `mod_ratings_view`, `loadout_summary_view`.

Scaffolded only (comments, no logic):
- `functions.sql` — 10 functions planned, 0 implemented.
- `triggers.sql` — 8 triggers planned, 0 attached.
- `transactions.sql` — BEGIN/COMMIT blocks outlined, 0 written.
- `seed.sql` — table-by-table placeholders, 0 rows.
- `queries.sql` — 7 query slots, 0 written.
- `ddl_demo.sql` — ALTER TABLE plan outlined, 0 executed.

Not started:
- Next.js app (no app code exists yet, database folder only).
- Auth (role-based, against `users` table).
- pgvector semantic search (mods.embedding column exists in schema, nothing populates or queries it yet).

## Open decision — resolve before Phase 2

`functions.sql` plans `fn_refresh_mv_mod_ratings`, refreshing a materialized view `mv_mod_ratings`.
`triggers.sql` plans a trigger calling that refresh on every review insert/update/delete.
`views.sql` only created a plain view `mod_ratings_view` — not materialized.

Pick one:
- **A. Materialized view.** Convert `mod_ratings_view` to `mv_mod_ratings` (materialized), keep the refresh trigger as designed. Matches what's already written in functions.sql/triggers.sql. Adds refresh-lock complexity; `REFRESH MATERIALIZED VIEW CONCURRENTLY` needs a unique index on the view.
- **B. Plain view (default assumption for this plan).** Drop `fn_refresh_mv_mod_ratings` and its trigger from the plan. Simpler, always live, no refresh logic. Ratings view recomputes on every query, fine at seed-data scale.

This plan proceeds under **B** unless you say otherwise. Swap to A by re-adding the function/trigger pair in Phase 2.

## Phase 1 — Seed data (real Nexus pull)

Source: real mods/mod_versions data pulled from the Nexus Mods API. Everything else (users, reviews, loadouts, compatibility_matrix) is hand-authored on top of it.

Scope: 2–3 games, ~15–20 mods each (45–60 mods total). Endpoints, per the AUP-scoped mods/mod-files/collections decision already locked in schema-decisions.md:

1. `GET /v1/games/{domain}.json` — resolve numeric game_id per game. 3 calls.
2. `GET /v1/games/{domain}/mods/latest_added.json` (or `trending.json`) — batch of mod summaries per game. 3 calls.
3. `GET /v1/games/{domain}/mods/{mod_id}.json` — full mod detail per kept mod. ~45–60 calls.
4. `GET /v1/games/{domain}/mods/{mod_id}/files.json` — becomes `mod_versions` rows. ~45–60 calls.

Total: ~100–130 requests. Nexus limits: 20,000/24h, 500/hour. Well inside budget in one run.

Steps:
1. Generate a personal API key (nexusmods.com/users/myaccount?tab=api).
2. Pick game domain slugs (e.g. `skyrimspecialedition`, `fallout4`, `stardewvalley`).
3. Write a pull script, headers include `Application-Name` and `Application-Version` per the AUP. Dump raw JSON to disk before writing any SQL, so a bad response doesn't cost a re-pull.
4. From the cached JSON, generate `INSERT INTO mods ...` and `INSERT INTO mod_versions ...` statements for `seed.sql`.
5. Hand-author: `users` (a handful of modder/curator/admin accounts), `games` (rows matching the 2–3 pulled games), `tags` + `mod_tags`, `mod_dependencies` (a few real-looking chains between the pulled mods), `reviews`, `loadouts` + `loadout_mods`, `compatibility_matrix` (some compatible/incompatible/partial pairs — this is where "conflict detection" gets something to detect).

Estimate: half a day, most of it the pull script and JSON-to-SQL step.

## Phase 2 — Functions

Implement the 10 planned functions in `functions.sql`, in the order the file already lists them:

1. `fn_compat_canonicalise_pair` — order-independent (A,B) pair storage for compatibility_matrix.
2. `fn_mod_version_single_primary` — enforce one `is_primary = true` per mod.
3. `fn_refresh_mv_mod_ratings` — only if Decision A above; otherwise drop.
4. `fn_set_updated_at` — generic `updated_at` bump, reusable across tables.
5. `fn_loadout_mods_auto_position` — auto-increment load-order position on insert.
6. `fn_audit_log` — generic row-change logger, feeds `audit_log`.
7. `fn_get_mod_dependency_tree` — recursive walk over `mod_dependencies`.
8. `fn_check_loadout_compatibility` — cross-references `loadout_mods` against `compatibility_matrix`. This is the core "conflict detection" feature.
9. `fn_mod_stats` — aggregate counts/ratings for a mod.
10. `fn_search_mods_by_tag` — tag-based lookup, precursor to the semantic search in Phase 7.

Test each against Phase 1's seed data as you write it, not at the end.

Estimate: 1–2 days.

## Phase 3 — Triggers

Attach the 8 planned triggers in `triggers.sql` to their Phase 2 functions:
- `trg_compat_canonicalise_pair`
- `trg_mod_version_single_primary`
- `trg_refresh_mv_mod_ratings` (only if Decision A)
- `trg_mods_updated_at` (and equivalents on other tables with `updated_at`)
- `trg_loadout_mods_position`
- `trg_audit_users`, `trg_audit_mods`, `trg_audit_compat`

Verify each fires correctly against seed data: insert a duplicate compat pair and confirm canonicalisation, insert a second `is_primary` version and confirm the old one flips, etc.

Estimate: half a day, given functions are already tested.

## Phase 4 — Transactions

Write the BEGIN/COMMIT/ROLLBACK blocks in `transactions.sql`. Each block should exercise trigger behavior under a transaction boundary — e.g. a loadout batch-add that rolls back cleanly if one mod version conflicts, a compatibility_matrix batch update.

Estimate: half a day.

## Phase 5 — Queries

Write the 7 demo queries in `queries.sql` against seeded data — these are your "look, the schema answers real questions" proof points. Draw from: conflict detection across a loadout, dependency tree resolution, top-rated mods per game, curator-verified compatibility pairs.

Estimate: a few hours.

## Phase 6 — DDL demo

Run the `ddl_demo.sql` ALTER TABLE / ADD CONSTRAINT / DROP demos last, since they mutate the schema everything above depends on. Confirm nothing upstream breaks after each alteration.

Estimate: a few hours.

## Phase 7 — Application layer

1. Scaffold Next.js app, connect to the Phase 1–6 database.
2. Auth against `users.role` (modder/curator/admin), role-gated routes.
3. Core pages: mod browse/detail, loadout builder (surfaces `fn_check_loadout_compatibility`), compatibility matrix view.
4. pgvector semantic search: generate embeddings for `mods.embedding` (needs an embedding provider — OpenAI or similar; separate rate limit/cost to plan for once you're here) and wire up similarity search using `fn_search_mods_by_tag` as a fallback/hybrid.
5. Wire audit_log to an admin-only activity view.

Estimate: the largest phase, budget several days minimum depending on how much UI polish is in scope.

## Sequencing summary

Seed data → functions → triggers → transactions → queries → DDL demo → app layer.
Each DB phase depends on the seed data existing and the prior phase's objects being in place. Don't start the app layer until Phase 6 is done — the app has nothing real to call against otherwise.
