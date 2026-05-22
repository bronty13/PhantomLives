-- Phase 9: Content Bundler.
--
-- Sallie composes structured "bundles" of media + metadata in three flavors
-- (content / custom / fansite), then publishes each as a deterministic,
-- SHA-256 hashed two-layer ZIP delivered to ~/Downloads/Molly bundles/.
--
-- One parent table per bundle (with null-where-unused columns for the
-- per-type fields) plus four line-item tables. Picking columns-with-nulls
-- over a JSON blob keeps go-live-date filterable, lets the migration-smoke
-- test see every table, and matches the rest of Molly's schema style.
--
-- bundle_fan_days is defined before bundle_files so the latter's
-- fansite_day_id FK resolves cleanly during CREATE.

CREATE TABLE IF NOT EXISTS bundles (
    uid                       TEXT    PRIMARY KEY,           -- YYYY-MM-DD-####
    bundle_type               TEXT    NOT NULL CHECK (bundle_type IN ('content','custom','fansite')),
    persona_code              TEXT    REFERENCES personas(code) ON DELETE SET NULL,
    state                     TEXT    NOT NULL DEFAULT 'draft'
                                       CHECK (state IN ('draft','published','purged')),
    title                     TEXT    NOT NULL DEFAULT '',
    content_date              TEXT    NOT NULL,              -- YYYY-MM-DD
    go_live_date              TEXT,                          -- YYYY-MM-DD (content/custom)
    special_instructions      TEXT    NOT NULL DEFAULT '',

    -- Content-only fields.
    description_mode          TEXT,                          -- 'audio' | 'text' | null
    description_text          TEXT    NOT NULL DEFAULT '',
    description_audio_relpath TEXT,
    description_audio_sha256  TEXT,
    description_transcript    TEXT    NOT NULL DEFAULT '',   -- reserved for Phase 3 transcription

    -- Custom-only fields. Columns are declared now so PR2 (Custom + FanSite
    -- forms) doesn't have to ship another migration; nulls in PR1.
    delivery_kind             TEXT,                          -- 'site' | 'url' | null
    delivery_site_id          INTEGER REFERENCES sites(id) ON DELETE SET NULL,
    delivery_url              TEXT,
    delivery_recipient        TEXT    NOT NULL DEFAULT '',
    price_cents               INTEGER,
    handled_in_platform       INTEGER NOT NULL DEFAULT 0,

    -- FanSite-only fields.
    fansite_year              INTEGER,
    fansite_month             INTEGER,                       -- 1..12

    -- Publish output, stamped inside publish_bundle's transaction.
    published_at              TEXT,
    bundle_path               TEXT,                          -- ~/Downloads/Molly bundles/<UID>.zip
    bundle_size_bytes         INTEGER,
    outer_sha256              TEXT,
    inner_sha256              TEXT,

    created_at                TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS bundles_by_state_created ON bundles(state, created_at DESC);
CREATE INDEX IF NOT EXISTS bundles_by_persona       ON bundles(persona_code);
CREATE INDEX IF NOT EXISTS bundles_by_type          ON bundles(bundle_type, state);

-- One row per calendar day for a FanSite bundle. Holds the day's short
-- message; files for the day live in bundle_files with fansite_day_id set.
CREATE TABLE IF NOT EXISTS bundle_fan_days (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    bundle_uid    TEXT    NOT NULL REFERENCES bundles(uid) ON DELETE CASCADE,
    day_of_month  INTEGER NOT NULL CHECK (day_of_month BETWEEN 1 AND 31),
    message       TEXT    NOT NULL DEFAULT '',
    updated_at    TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE (bundle_uid, day_of_month)
);

-- Ordered media list. For content/custom bundles, fansite_day_id is NULL
-- and `position` is unique within the bundle (1..N). For fansite bundles,
-- fansite_day_id is set and `position` is unique within the day (1..N).
CREATE TABLE IF NOT EXISTS bundle_files (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    bundle_uid      TEXT    NOT NULL REFERENCES bundles(uid) ON DELETE CASCADE,
    fansite_day_id  INTEGER REFERENCES bundle_fan_days(id) ON DELETE CASCADE,
    position        INTEGER NOT NULL,
    relpath         TEXT    NOT NULL,                        -- attachments/bundles/<uid>/files/<uuid>_<orig>
    original_name   TEXT    NOT NULL,                        -- preserved across rename for ZIP-time renaming
    kind            TEXT    NOT NULL CHECK (kind IN ('video','image','audio')),
    size_bytes      INTEGER NOT NULL DEFAULT 0,
    sha256          TEXT    NOT NULL DEFAULT '',             -- hex-encoded, computed on upload
    created_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS bundle_files_by_bundle ON bundle_files(bundle_uid, position);
CREATE INDEX IF NOT EXISTS bundle_files_by_day    ON bundle_files(fansite_day_id, position);

-- Categories for content bundles. Stored UPPERCASE. PK enforces dedup
-- per bundle; `position` carries the user's drag-order.
CREATE TABLE IF NOT EXISTS bundle_categories (
    bundle_uid  TEXT    NOT NULL REFERENCES bundles(uid) ON DELETE CASCADE,
    name        TEXT    NOT NULL,                            -- stored UPPERCASE
    position    INTEGER NOT NULL,
    PRIMARY KEY (bundle_uid, name)
);

CREATE INDEX IF NOT EXISTS bundle_categories_by_position ON bundle_categories(bundle_uid, position);

-- Editable list of words the description validator flags as prohibited.
-- COLLATE NOCASE on the unique constraint makes case variants dedup.
CREATE TABLE IF NOT EXISTS bundle_prohibited_words (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    word        TEXT    NOT NULL UNIQUE COLLATE NOCASE,
    created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);

INSERT INTO bundle_prohibited_words (word) VALUES
    ('blackmail'),
    ('mommy'),
    ('addiction'),
    ('addicted')
ON CONFLICT(word) DO NOTHING;
