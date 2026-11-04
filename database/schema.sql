

SET client_encoding = 'UTF8';
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TYPE user_role_enum AS ENUM (
    'modder',
    'curator',
    'admin'
);
CREATE TYPE dep_type_enum AS ENUM (
    'required',
    'optional',
    'conflicts',
    'recommends'
);
CREATE TYPE dep_source_enum AS ENUM (
    'manual',
    'nexus',
    'inferred'
);
CREATE TYPE compat_status_enum AS ENUM (
    'compatible',
    'incompatible',
    'unknown',
    'partial'
);
CREATE TABLE users (
    user_id       UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    username      VARCHAR(50)     NOT NULL,
    email         VARCHAR(255)    NOT NULL,
    password_hash TEXT            NOT NULL,
    role          user_role_enum  NOT NULL DEFAULT 'modder',
    is_active     BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_users_username UNIQUE (username),
    CONSTRAINT uq_users_email    UNIQUE (email)
);
CREATE TABLE games (
    game_id        UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name           VARCHAR(255) NOT NULL,
    domain          VARCHAR(100),
    nexus_game_id   VARCHAR(100),
    current_version VARCHAR(50),
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_games_name   UNIQUE (name),
    CONSTRAINT uq_games_domain UNIQUE (domain)
);
CREATE TABLE tags (
    tag_id UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name   VARCHAR(100) NOT NULL,
    slug   VARCHAR(100) NOT NULL,

    CONSTRAINT uq_tags_name UNIQUE (name),
    CONSTRAINT uq_tags_slug UNIQUE (slug)
);
CREATE TABLE mods (
    mod_id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id         UUID
                          REFERENCES users(user_id) ON DELETE SET NULL,
    nexus_author      VARCHAR(255),
    game_id           UUID         NOT NULL
                          REFERENCES games(game_id) ON DELETE RESTRICT,
    nexus_mod_id      VARCHAR(100),
    name              VARCHAR(255) NOT NULL,
    summary           TEXT,
    category          VARCHAR(100),
    download_count    INTEGER      NOT NULL DEFAULT 0,
    endorsement_count INTEGER      NOT NULL DEFAULT 0,
    is_featured       BOOLEAN      NOT NULL DEFAULT FALSE,
    rating_avg        NUMERIC(3,2) NOT NULL DEFAULT 0,
    rating_count      INTEGER      NOT NULL DEFAULT 0,
    search_tsv        TSVECTOR GENERATED ALWAYS AS (
                          setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
                          setweight(to_tsvector('english', coalesce(category, '')), 'B') ||
                          setweight(to_tsvector('english', coalesce(summary, '')), 'C')
                      ) STORED,
    embedding         VECTOR(384),
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_mods_download_count    CHECK (download_count >= 0),
    CONSTRAINT chk_mods_endorsement_count CHECK (endorsement_count >= 0),
    CONSTRAINT uq_mods_game_nexus_mod UNIQUE (game_id, nexus_mod_id)
);
CREATE TABLE loadouts (
    loadout_id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id              UUID         NOT NULL
                             REFERENCES users(user_id) ON DELETE CASCADE,
    game_id              UUID         NOT NULL
                             REFERENCES games(game_id) ON DELETE RESTRICT,
    name                 VARCHAR(255) NOT NULL,
    description          TEXT,
    game_version         VARCHAR(50),
    is_public            BOOLEAN      NOT NULL DEFAULT FALSE,
    nexus_collection_id  VARCHAR(100),
    nexus_revision_id    VARCHAR(100),
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
CREATE TABLE mod_versions (
    version_id       UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    mod_id           UUID         NOT NULL
                         REFERENCES mods(mod_id) ON DELETE CASCADE,
    semver           VARCHAR(20)  NOT NULL,
    nexus_version_id VARCHAR(100),
    changelog        TEXT,
    supported_game_versions TEXT[]  NOT NULL DEFAULT '{}',
    is_primary       BOOLEAN      NOT NULL DEFAULT FALSE,
    uploaded_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_mod_versions_mod_semver UNIQUE (mod_id, semver)
);
CREATE TABLE reviews (
    review_id  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID        NOT NULL
                   REFERENCES users(user_id) ON DELETE CASCADE,
    mod_id     UUID        NOT NULL
                   REFERENCES mods(mod_id) ON DELETE CASCADE,
    rating     SMALLINT    NOT NULL,
    body       TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_reviews_user_mod UNIQUE (user_id, mod_id),
    CONSTRAINT chk_reviews_rating CHECK (rating BETWEEN 1 AND 5)
);
CREATE TABLE mod_tags (
    mod_id UUID NOT NULL REFERENCES mods(mod_id) ON DELETE CASCADE,
    tag_id UUID NOT NULL REFERENCES tags(tag_id) ON DELETE CASCADE,

    PRIMARY KEY (mod_id, tag_id)
);
CREATE TABLE mod_dependencies (
    dep_id                UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    dependent_version_id  UUID            NOT NULL
                              REFERENCES mod_versions(version_id) ON DELETE CASCADE,
    required_mod_id       UUID            NOT NULL
                              REFERENCES mods(mod_id) ON DELETE RESTRICT,
    version_constraint    VARCHAR(50),
    dep_type              dep_type_enum   NOT NULL DEFAULT 'required',
    source                dep_source_enum NOT NULL DEFAULT 'manual',
    CONSTRAINT uq_mod_dependencies_version_mod
        UNIQUE (dependent_version_id, required_mod_id)
);
CREATE TABLE loadout_mods (
    id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    loadout_id  UUID    NOT NULL
                    REFERENCES loadouts(loadout_id) ON DELETE CASCADE,
    version_id  UUID    NOT NULL
                    REFERENCES mod_versions(version_id) ON DELETE RESTRICT,
    position    INTEGER NOT NULL DEFAULT 0,
    enabled     BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_loadout_mods_loadout_version UNIQUE (loadout_id, version_id),
    CONSTRAINT chk_loadout_mods_position CHECK (position >= 0)
);
CREATE TABLE compatibility_matrix (
    compat_id       UUID               PRIMARY KEY DEFAULT gen_random_uuid(),
    version_a_id    UUID               NOT NULL
                        REFERENCES mod_versions(version_id) ON DELETE CASCADE,
    version_b_id    UUID               NOT NULL
                        REFERENCES mod_versions(version_id) ON DELETE CASCADE,
    status          compat_status_enum NOT NULL DEFAULT 'unknown',
    conflict_detail JSONB,
    verified_by     UUID
                        REFERENCES users(user_id) ON DELETE SET NULL,
    updated_at      TIMESTAMPTZ        NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_compat_no_self_compare
        CHECK (version_a_id <> version_b_id),
    CONSTRAINT uq_compat_version_pair
        UNIQUE (version_a_id, version_b_id)
);
CREATE TABLE audit_log (
    audit_id    BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name  TEXT        NOT NULL,
    operation   CHAR(1)     NOT NULL,
    row_pk      UUID,
    old_row     JSONB,
    new_row     JSONB,
    changed_by  UUID
                    REFERENCES users(user_id) ON DELETE SET NULL,
    changed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_audit_log_operation CHECK (operation IN ('I', 'U', 'D'))
);
