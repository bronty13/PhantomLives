-- Phase 3 image ops: per-persona watermark configuration + per-output
-- audit trail for every processed file.
--
-- watermark_profiles: keyed on persona_code so a bundle's watermark
-- comes from its persona binding. Defaults seeded for the three known
-- PhantomLives personas (CoC / PoA / Sa) per PLAN.md §12 decision #24
-- (full-name-no-spaces text). Bundles with personaCode=NULL fall
-- through to the '' row (which can be edited in Settings to set a
-- generic default).
--
-- processed_files: one row per (bundle_file, op_combination). UPSERT
-- semantics — re-running the same op replaces. CASCADE on
-- bundle_files.id so deleting a bundle wipes the audit trail.

CREATE TABLE IF NOT EXISTS watermark_profiles (
    persona_code    TEXT PRIMARY KEY,
    text            TEXT NOT NULL DEFAULT '',
    opacity_percent INTEGER NOT NULL DEFAULT 20
                    CHECK(opacity_percent BETWEEN 0 AND 100),
    position        TEXT NOT NULL DEFAULT 'bottom-right'
                    CHECK(position IN (
                        'top-left','top-center','top-right',
                        'middle-left','middle-center','middle-right',
                        'bottom-left','bottom-center','bottom-right'
                    )),
    font_size_pct   REAL NOT NULL DEFAULT 4.0,
    margin_pct      REAL NOT NULL DEFAULT 2.5,
    enabled         INTEGER NOT NULL DEFAULT 1,
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Seed PhantomLives' three personas per decisions #24 (CurseOfCurves /
-- PrincessOfAddiction / SheerAttraction — no spaces). Generic '' row
-- catches persona-less bundles + serves as the editable default.
INSERT OR IGNORE INTO watermark_profiles (persona_code, text)
VALUES
    ('',    ''),
    ('CoC', 'CurseOfCurves'),
    ('PoA', 'PrincessOfAddiction'),
    ('Sa',  'SheerAttraction');

CREATE TABLE IF NOT EXISTS processed_files (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    bundle_file_id  INTEGER NOT NULL REFERENCES bundle_files(id) ON DELETE CASCADE,
    op_kind         TEXT NOT NULL CHECK(op_kind IN (
        'watermark', 'strip_exif', 'rename',
        'watermark_strip', 'watermark_strip_rename'
    )),
    output_path     TEXT NOT NULL,
    output_sha256   TEXT NOT NULL DEFAULT '',
    params_json     TEXT NOT NULL DEFAULT '{}',
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(bundle_file_id, op_kind)
);

CREATE INDEX IF NOT EXISTS idx_processed_files_bundle_file ON processed_files(bundle_file_id);
