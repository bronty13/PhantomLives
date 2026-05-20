-- Phase 2: clips imported from MasterClipper.
--
-- The PK is MasterClipper's stable UID (format YYYY-MM-DD-#####, generated
-- by `MasterClipper/Sources/MasterClipper/Services/IDGeneratorService.swift`).
-- Re-importing the same CSV is therefore a clean UPSERT — duplicates can't
-- accumulate. Editable Molly-side notes live in `molly_notes_html`, separate
-- from the imported `notes` column so re-import doesn't clobber them.
CREATE TABLE IF NOT EXISTS clips (
    id                  TEXT PRIMARY KEY,           -- MasterClipper UID
    external_clip_id    TEXT NOT NULL DEFAULT '',
    persona_code        TEXT REFERENCES personas(code) ON DELETE SET NULL,
    title               TEXT NOT NULL DEFAULT '',
    status              TEXT NOT NULL DEFAULT '',
    content_date        TEXT,                       -- ISO date (YYYY-MM-DD) or null
    go_live_date        TEXT,                       -- ISO date or 'YYYY-MM-DD HH:MM' string
    length              TEXT NOT NULL DEFAULT '',   -- e.g. "5:32"
    price               TEXT NOT NULL DEFAULT '',
    categories          TEXT NOT NULL DEFAULT '',
    keywords            TEXT NOT NULL DEFAULT '',
    performers          TEXT NOT NULL DEFAULT '',
    notes               TEXT NOT NULL DEFAULT '',   -- imported from MC
    molly_notes_html    TEXT NOT NULL DEFAULT '',   -- editable on Molly side; preserved across re-imports
    imported_at         TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Calendar / dashboard hot paths: by date, by persona.
CREATE INDEX IF NOT EXISTS clips_by_go_live_date ON clips(go_live_date);
CREATE INDEX IF NOT EXISTS clips_by_persona     ON clips(persona_code);
-- Reuse detection: external_clip_id collisions across personas, and title hits.
CREATE INDEX IF NOT EXISTS clips_by_external_id ON clips(external_clip_id) WHERE external_clip_id != '';
CREATE INDEX IF NOT EXISTS clips_by_title       ON clips(title);

-- Tiny audit table for import runs; useful in the dashboard "recent imports" widget.
CREATE TABLE IF NOT EXISTS clip_imports (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    imported_at     TEXT NOT NULL DEFAULT (datetime('now')),
    source_file     TEXT NOT NULL DEFAULT '',
    rows_total      INTEGER NOT NULL DEFAULT 0,
    rows_inserted   INTEGER NOT NULL DEFAULT 0,
    rows_updated    INTEGER NOT NULL DEFAULT 0,
    rows_skipped    INTEGER NOT NULL DEFAULT 0,
    note            TEXT NOT NULL DEFAULT ''
);
