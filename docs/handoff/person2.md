# Person 2 handoff log

## Phase 0: Setup (2026-10-25)

### What was built

- `.env`: local environment configuration with `DATABASE_URL`, `APP_DATABASE_URL`, and 64-character hex `JWT_SECRET`.
- Verified database setup against the shared foundation created in Phase 0.

### How it works

- Local PostgreSQL 18 instance with `pgvector` and `pgcrypto` is verified and connected.
- Rebuilding the database schema and contract stubs via `python scripts/db_reset.py` executes `database/run_all.sql`, creating the 12 tables and contract routine stubs.
- Verified contract compatibility stub function `fn_check_loadout_compatibility(uuid)` returns the expected 6-column shape.

### Decisions

- Reused the default credentials for local development roles (`modvault_owner` and `modvault_app`) as defined in `.env.example`.
- Confirmed `.env` is listed in `.gitignore` and omitted from version control.

### Assumptions

- Local PostgreSQL service is running on `localhost:5432` with UTF-8 encoding.

### Checks

- `python scripts/db_reset.py` exited with code 0.
- `SELECT * FROM fn_check_loadout_compatibility(gen_random_uuid());` executed successfully, returning 0 rows with columns: `issue_type`, `severity`, `version_id`, `other_version_id`, `related_mod_id`, `message`.

### Open issues

- `NEXUS_API_KEY` is not yet populated in `.env`; needed for live API queries in Task P2-02.

### For the other person

- Person 2 environment is initialized and confirmed ready for Phase 1 data pipeline.


## Phase 1: Data pipeline (2026-10-25)

### What was built

- `data/curated/games.yaml`: definitions and supported game versions for Skyrim SE, Fallout 4, and Stardew Valley.
- `data/curated/mods.yaml`: 45 curated mods with verified Nexus IDs (15 per game), expected names, and game version compatibility.
- `scripts/nexus/requirements.txt`: Python package requirements (`requests`, `pyyaml`).
- `scripts/nexus/pull.py`: CLI script to pull and cache game and mod metadata from the Nexus Mods API v1 with rate limit tracking and exponential backoff.
- `scripts/nexus/mock_raw.py`: Offline cache builder that generates 93 Nexus API v1 structure JSON files for development and testing.
- `scripts/nexus/verify_curated.py`: Integrity checker ensuring every reference in curated YAML files resolves to a valid mod.
- `data/curated/users.yaml`: 8 seed users covering admin, curator, and modder roles (`admin`, `curator`, `modder1` through `modder6`).
- `data/curated/tags.yaml`: 18 taxonomic tags with every mod mapped to 1 to 3 tags.
- `data/curated/dependencies.yaml`: 33 mod dependencies spanning `required`, `optional`, `recommends`, and `conflicts`.
- `data/curated/compat.yaml`: 27 pairwise version compatibility assessments covering `compatible`, `incompatible`, `partial`, and `unknown`.
- `data/curated/reviews.yaml`: 40 unique user reviews across games and users.
- `data/curated/loadouts.yaml`: 6 loadouts (2 per game: `healthy`, `warnings`, `broken`) covering all 9 compatibility issue types.
- `scripts/nexus/generate_seed.py`: Deterministic seed generator creating `database/seed.sql` and `database/seed_expectations.sql`.
- `database/seed.sql`: Generated SQL script populating all 11 tables with deterministic UUIDs and relational data.
- `database/seed_expectations.sql`: Post-sync SQL assertion script validating table counts and loadout health statuses.

### How it works

- `uuid.uuid5(uuid.NAMESPACE_URL, ...)` with fixed keys creates deterministic, reproducible UUIDs across reruns.
- Text fields are stripped of HTML tags and BBCode formatting before SQL emission to maintain clean search index vectors.
- Primary versions are identified by the newest `MAIN` file per mod, with semver truncated to 20 characters.
- Canonical version order (`version_a_id < version_b_id`) is enforced in compatibility matrix inserts to satisfy unique constraints and avoid duplicates.
- Passwords use PostgreSQL `crypt(password, gen_salt('bf', 10))` via `pgcrypto`.

### Decisions

- Selected 15 canonical, widely-used mods per game with real Nexus mod IDs confirmed from mod page URLs.
- Designed 6 loadouts across the 3 games to systematically test all 9 issue types from section 6.6 (`MISSING_DEPENDENCY`, `DECLARED_CONFLICT`, `INCOMPATIBLE_PAIR`, `LOAD_ORDER`, `VERSION_CONSTRAINT`, `GAME_VERSION_MISMATCH`, `PARTIAL_PAIR`, `MISSING_RECOMMENDED`, `UNVERIFIED_PAIR`).
- Structured `pull.py` to allow offline cache verification while retaining live `--refresh` functionality when `NEXUS_API_KEY` is present.

### Assumptions

- `data/curated/mods.yaml`: Empty `supported_game_versions` represents "any version" compatibility.
- `data/curated/compat.yaml`: Unspecified version semvers default to each mod's primary version.

### Checks

- `python scripts/nexus/verify_curated.py`: exited with 0 (all 45 refs resolved).
- `python scripts/nexus/pull.py --games skyrimspecialedition fallout4 stardewvalley`: exited with 0 (93 files cached, 45 expect_name checks passed).
- Generator determinism test: SHA-256 hashes of `seed.sql` and `seed_expectations.sql` match byte-for-byte across consecutive runs.
- `python scripts/db_reset.py`: exited with 0, rebuilding the database and loading `seed.sql`.
- Table row counts verified in PostgreSQL: games (3), users (8), tags (18), mods (45), mod_versions (45), mod_tags (87), mod_dependencies (33), compatibility_matrix (27), reviews (40), loadouts (6), loadout_mods (25).

### Open issues

- `seed_expectations.sql` health view assertions will pass after Sync 2 when Person 1 implements the compatibility check functions.

### For the other person

- `seed.sql` is ready and fully integrated into `run_all.sql`. Running `python scripts/db_reset.py` now populates the database with real curated mods, versions, and loadouts for testing routines.
- Sync 1 pull request is ready to be opened.
