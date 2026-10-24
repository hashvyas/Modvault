-- =============================================================================
-- ModVault: A Mod Repository and Compatibility Intelligence System
-- PostgreSQL DDL  --  schema.sql
--
-- This file defines the complete database structure.
-- No sample data, triggers, stored procedures, or indexes are included here.
-- Tables are created in foreign-key dependency order so every referenced
-- table already exists when a referencing table is created.
--
-- HOW TO RUN
--   Do not run this file alone. It is included by database/run_all.sql.
--   Rebuild everything with:  python scripts/db_reset.py
-- =============================================================================

SET client_encoding = 'UTF8';


-- =============================================================================
-- SECTION 0 -- EXTENSIONS
-- =============================================================================

-- pgvector is required for the mods.embedding VECTOR(384) column.
CREATE EXTENSION IF NOT EXISTS vector;

-- pgcrypto provides gen_random_uuid() on PostgreSQL < 13.
-- On PostgreSQL 13+ it is built-in, but enabling the extension is harmless.
CREATE EXTENSION IF NOT EXISTS pgcrypto;


-- =============================================================================
-- SECTION 1 -- ENUM TYPE DEFINITIONS
--
-- Enum values are inferred from the project abstract, ER diagram, and
-- common conventions in mod-hosting platforms (e.g. Nexus Mods).
-- Each enum is commented to document the rationale for its values.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- user_role_enum
-- Represents the access level / permission tier of a registered user.
--   modder   - a regular user who can upload and manage mods
--   curator  - a trusted reviewer who can verify compatibility reports
--   admin    - platform administrator with full access
-- ASSUMPTION: Three roles cover the project abstract's mention of
--             "role-based access for modders and curators". An admin tier
--             is added as a sensible operational necessity.
-- -----------------------------------------------------------------------------
CREATE TYPE user_role_enum AS ENUM (
    'modder',
    'curator',
    'admin'
);

-- -----------------------------------------------------------------------------
-- dep_type_enum
-- Describes the nature of a mod dependency relationship.
--   required   - the dependent mod cannot function without the required mod
--   optional   - the required mod enhances but is not mandatory
--   conflicts  - the two mods are known to conflict with each other
--   recommends - the author recommends (but does not require) the other mod
-- ASSUMPTION: Standard dependency semantics drawn from package-manager
--             conventions (npm, Nexus Mods FOMOD, etc.).
-- -----------------------------------------------------------------------------
CREATE TYPE dep_type_enum AS ENUM (
    'required',
    'optional',
    'conflicts',
    'recommends'
);

-- -----------------------------------------------------------------------------
-- dep_source_enum
-- Tracks where the dependency information originated.
--   manual   - entered manually by the mod author
--   nexus    - imported/synced from the Nexus Mods API
--   inferred - detected automatically by the platform (e.g. via triggers)
-- ASSUMPTION: The schema stores nexus_mod_id / nexus_version_id columns,
--             implying Nexus Mods integration. A manual entry path and an
--             automated inference path are also natural for the stated goals.
-- -----------------------------------------------------------------------------
CREATE TYPE dep_source_enum AS ENUM (
    'manual',
    'nexus',
    'inferred'
);

-- -----------------------------------------------------------------------------
-- compat_status_enum
-- Records the known compatibility state between two mod versions
-- (stored in compatibility_matrix).
--   compatible   - the two versions are confirmed to work together
--   incompatible - the two versions are confirmed to conflict
--   unknown      - no compatibility data is available yet
--   partial      - works together only under specific conditions
-- ASSUMPTION: "partial" is included because real-world modding often
--             surfaces conditional compatibility (e.g. load-order dependent).
-- -----------------------------------------------------------------------------
CREATE TYPE compat_status_enum AS ENUM (
    'compatible',
    'incompatible',
    'unknown',
    'partial'
);


-- =============================================================================
-- SECTION 2 -- BASE TABLES (no foreign-key dependencies)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- users
-- Registered platform accounts. role drives RBAC throughout the system.
-- -----------------------------------------------------------------------------
CREATE TABLE users (
    user_id       UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    username      VARCHAR(50)     NOT NULL,
    email         VARCHAR(255)    NOT NULL,
    password_hash TEXT            NOT NULL,
    role          user_role_enum  NOT NULL DEFAULT 'modder',
    is_active     BOOLEAN         NOT NULL DEFAULT TRUE,   -- inactive users cannot log in
    created_at    TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    -- Usernames and e-mail addresses must be unique across the platform.
    CONSTRAINT uq_users_username UNIQUE (username),
    CONSTRAINT uq_users_email    UNIQUE (email)
);

-- -----------------------------------------------------------------------------
-- games
-- Supported game titles that mods can be authored for.
-- -----------------------------------------------------------------------------
CREATE TABLE games (
    game_id        UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name           VARCHAR(255) NOT NULL,
    domain          VARCHAR(100),            -- Nexus Mods URL domain (e.g. "skyrimspecialedition")
    nexus_game_id   VARCHAR(100),            -- External identifier; nullable - may not be on Nexus
    current_version VARCHAR(50),             -- Latest game version, e.g. "1.6.1170"
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    -- A game name should be unique on the platform.
    CONSTRAINT uq_games_name   UNIQUE (name),
    -- Loadout manifests resolve the game by domain, so it must be unique.
    CONSTRAINT uq_games_domain UNIQUE (domain)
);

-- -----------------------------------------------------------------------------
-- tags
-- Flat taxonomy tags that can be applied to mods (e.g. "armor", "quest").
-- -----------------------------------------------------------------------------
CREATE TABLE tags (
    tag_id UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name   VARCHAR(100) NOT NULL,
    slug   VARCHAR(100) NOT NULL,            -- URL-safe identifier, e.g. "new-lands"

    CONSTRAINT uq_tags_name UNIQUE (name),
    CONSTRAINT uq_tags_slug UNIQUE (slug)
);


-- =============================================================================
-- SECTION 3 -- TABLES THAT DEPEND ON BASE TABLES
-- =============================================================================

-- -----------------------------------------------------------------------------
-- mods
-- A mod record represents a single modification authored for a specific game.
-- embedding stores a 384-dimensional pgvector embedding of the mod summary
-- (Xenova/all-MiniLM-L6-v2), enabling semantic / similarity search.
-- search_tsv is a generated full-text vector used by keyword search.
-- author_id is NULL for mods imported from Nexus; nexus_author keeps the
-- original author name.
-- -----------------------------------------------------------------------------
CREATE TABLE mods (
    mod_id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id         UUID
                          REFERENCES users(user_id) ON DELETE SET NULL,
    nexus_author      VARCHAR(255),         -- Original Nexus author name
    game_id           UUID         NOT NULL
                          REFERENCES games(game_id) ON DELETE RESTRICT,
    nexus_mod_id      VARCHAR(100),         -- Nullable: mod may originate outside Nexus
    name              VARCHAR(255) NOT NULL,
    summary           TEXT,                 -- Human-readable description; used for embedding
    category          VARCHAR(100),         -- e.g. "Weapons", "Quests", "Textures"
    download_count    INTEGER      NOT NULL DEFAULT 0,
    endorsement_count INTEGER      NOT NULL DEFAULT 0,
    is_featured       BOOLEAN      NOT NULL DEFAULT FALSE,
    rating_avg        NUMERIC(3,2) NOT NULL DEFAULT 0,   -- maintained by trigger
    rating_count      INTEGER      NOT NULL DEFAULT 0,   -- maintained by trigger
    search_tsv        TSVECTOR GENERATED ALWAYS AS (
                          setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
                          setweight(to_tsvector('english', coalesce(category, '')), 'B') ||
                          setweight(to_tsvector('english', coalesce(summary, '')), 'C')
                      ) STORED,
    embedding         VECTOR(384),          -- pgvector semantic embedding (nullable until generated)
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_mods_download_count    CHECK (download_count >= 0),
    CONSTRAINT chk_mods_endorsement_count CHECK (endorsement_count >= 0),

    -- A Nexus mod id is unique within its game.
    CONSTRAINT uq_mods_game_nexus_mod UNIQUE (game_id, nexus_mod_id)
);

-- -----------------------------------------------------------------------------
-- loadouts
-- A named collection of mods assembled by a user for a particular game.
-- nexus_collection_id / nexus_revision_id support optional Nexus Collections sync.
-- -----------------------------------------------------------------------------
CREATE TABLE loadouts (
    loadout_id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id              UUID         NOT NULL
                             REFERENCES users(user_id) ON DELETE CASCADE,
    game_id              UUID         NOT NULL
                             REFERENCES games(game_id) ON DELETE RESTRICT,
    name                 VARCHAR(255) NOT NULL,
    description          TEXT,
    game_version         VARCHAR(50),         -- NULL means "not set"
    is_public            BOOLEAN      NOT NULL DEFAULT FALSE,
    nexus_collection_id  VARCHAR(100),        -- Nullable: not all loadouts are Nexus Collections
    nexus_revision_id    VARCHAR(100),        -- Nullable: only set when synced to Nexus
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);


-- =============================================================================
-- SECTION 4 -- TABLES THAT DEPEND ON MODS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- mod_versions
-- Each row represents a distinct release of a mod (semantic version).
-- is_primary flags the version that should be considered "current" by default.
-- -----------------------------------------------------------------------------
CREATE TABLE mod_versions (
    version_id       UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    mod_id           UUID         NOT NULL
                         REFERENCES mods(mod_id) ON DELETE CASCADE,
    semver           VARCHAR(20)  NOT NULL,   -- e.g. "1.4.2"
    nexus_version_id VARCHAR(100),            -- Nullable: Nexus file ID
    changelog        TEXT,                    -- Release notes (optional)
    supported_game_versions TEXT[]  NOT NULL DEFAULT '{}',  -- empty means "any game version"
    is_primary       BOOLEAN      NOT NULL DEFAULT FALSE,
    uploaded_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    -- A mod cannot have two versions with the same semver string.
    CONSTRAINT uq_mod_versions_mod_semver UNIQUE (mod_id, semver)
);

-- -----------------------------------------------------------------------------
-- reviews
-- User-authored ratings and written reviews for a mod (not a specific version).
-- rating is constrained to the conventional 1-5 scale.
-- -----------------------------------------------------------------------------
CREATE TABLE reviews (
    review_id  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID        NOT NULL
                   REFERENCES users(user_id) ON DELETE CASCADE,
    mod_id     UUID        NOT NULL
                   REFERENCES mods(mod_id) ON DELETE CASCADE,
    rating     SMALLINT    NOT NULL,
    body       TEXT,                         -- Written review body (optional)
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- One review per user per mod is a natural business rule.
    CONSTRAINT uq_reviews_user_mod UNIQUE (user_id, mod_id),

    -- Rating must fall in the standard 1-5 star range.
    CONSTRAINT chk_reviews_rating CHECK (rating BETWEEN 1 AND 5)
);

-- -----------------------------------------------------------------------------
-- mod_tags
-- Many-to-many join between mods and tags.
-- Composite primary key preserves the relational schema design.
-- -----------------------------------------------------------------------------
CREATE TABLE mod_tags (
    mod_id UUID NOT NULL REFERENCES mods(mod_id) ON DELETE CASCADE,
    tag_id UUID NOT NULL REFERENCES tags(tag_id) ON DELETE CASCADE,

    PRIMARY KEY (mod_id, tag_id)
);


-- =============================================================================
-- SECTION 5 -- TABLES THAT DEPEND ON MOD_VERSIONS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- mod_dependencies
-- Records a dependency from one mod version onto another mod (any version
-- satisfying version_constraint).
--
-- dependent_version_id -> mod_versions.version_id
--     The version that *has* the dependency.
-- required_mod_id -> mods.mod_id
--     The mod that is depended upon. Version resolution uses version_constraint.
--     Pointing to a mod (not a specific version) is intentional -- the
--     constraint string (e.g. ">=1.2.0") allows flexible version matching at
--     the application layer.
--
-- ASSUMPTION: Linking required_mod_id to mods rather than mod_versions matches
--             the ER diagram and is consistent with how FOMOD/NMM handle
--             dependency declarations (mod-level, not version-level target).
-- -----------------------------------------------------------------------------
CREATE TABLE mod_dependencies (
    dep_id                UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    dependent_version_id  UUID            NOT NULL
                              REFERENCES mod_versions(version_id) ON DELETE CASCADE,
    required_mod_id       UUID            NOT NULL
                              REFERENCES mods(mod_id) ON DELETE RESTRICT,
    version_constraint    VARCHAR(50),    -- e.g. ">=1.2.0", "^2.0"; NULL = any version
    dep_type              dep_type_enum   NOT NULL DEFAULT 'required',
    source                dep_source_enum NOT NULL DEFAULT 'manual',

    -- A version should not declare a duplicate dependency on the same required mod.
    CONSTRAINT uq_mod_dependencies_version_mod
        UNIQUE (dependent_version_id, required_mod_id)
);

-- -----------------------------------------------------------------------------
-- loadout_mods
-- Associates specific mod versions with a loadout, along with load order
-- position and enabled/disabled state.
-- -----------------------------------------------------------------------------
CREATE TABLE loadout_mods (
    id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    loadout_id  UUID    NOT NULL
                    REFERENCES loadouts(loadout_id) ON DELETE CASCADE,
    version_id  UUID    NOT NULL
                    REFERENCES mod_versions(version_id) ON DELETE RESTRICT,
    position    INTEGER NOT NULL DEFAULT 0,
    enabled     BOOLEAN NOT NULL DEFAULT TRUE,

    -- A given version can appear only once in a loadout.
    CONSTRAINT uq_loadout_mods_loadout_version UNIQUE (loadout_id, version_id),

    -- Load order position must be non-negative.
    CONSTRAINT chk_loadout_mods_position CHECK (position >= 0)
);

-- -----------------------------------------------------------------------------
-- compatibility_matrix
-- Stores pairwise compatibility assessments between two mod versions.
-- verified_by optionally links to the curator who confirmed the status.
-- conflict_detail holds freeform structured data (e.g. affected files, notes).
--
-- ASSUMPTION: UUID values have no semantic ordering, so enforcing
--             version_a_id < version_b_id via CHECK is not meaningful.
--             Instead, trigger trg_compat_canonicalise_pair canonicalises
--             pair order (always store lower UUID as A) so that (A,B) and
--             (B,A) are not stored as separate rows.
--             The UNIQUE constraint on (version_a_id, version_b_id) prevents
--             exact duplicates of the same ordered pair.
--
-- Self-comparison (version_a_id = version_b_id) is explicitly forbidden.
-- -----------------------------------------------------------------------------
CREATE TABLE compatibility_matrix (
    compat_id       UUID               PRIMARY KEY DEFAULT gen_random_uuid(),
    version_a_id    UUID               NOT NULL
                        REFERENCES mod_versions(version_id) ON DELETE CASCADE,
    version_b_id    UUID               NOT NULL
                        REFERENCES mod_versions(version_id) ON DELETE CASCADE,
    status          compat_status_enum NOT NULL DEFAULT 'unknown',
    conflict_detail JSONB,                      -- Nullable; populated for incompatible/partial
    verified_by     UUID
                        REFERENCES users(user_id) ON DELETE SET NULL,
    updated_at      TIMESTAMPTZ        NOT NULL DEFAULT NOW(),

    -- Prevent a version from being compared against itself.
    CONSTRAINT chk_compat_no_self_compare
        CHECK (version_a_id <> version_b_id),

    -- Prevent duplicate (A,B) pairs. Pair order is canonicalised by
    -- trg_compat_canonicalise_pair.
    CONSTRAINT uq_compat_version_pair
        UNIQUE (version_a_id, version_b_id)
);


-- =============================================================================
-- SECTION 6 -- AUDIT LOG
-- =============================================================================

-- -----------------------------------------------------------------------------
-- audit_log
-- Append-only history written by trigger function fn_audit_log() on every
-- INSERT / UPDATE / DELETE of audited tables. trg_audit_log_immutable blocks
-- UPDATE and DELETE. old_row / new_row omit password_hash, embedding and
-- search_tsv. changed_by is the app session user (app.user_id).
-- -----------------------------------------------------------------------------
CREATE TABLE audit_log (
    audit_id    BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name  TEXT        NOT NULL,
    operation   CHAR(1)     NOT NULL,
    row_pk      UUID,
    old_row     JSONB,                       -- NULL for INSERT
    new_row     JSONB,                       -- NULL for DELETE
    changed_by  UUID
                    REFERENCES users(user_id) ON DELETE SET NULL,
    changed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_audit_log_operation CHECK (operation IN ('I', 'U', 'D'))
);
