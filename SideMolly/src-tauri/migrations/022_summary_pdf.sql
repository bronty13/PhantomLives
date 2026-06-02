-- v0.26.0 — SideMollySummary PDF + configurable thumbnail count.
--
-- Two changes:
--
-- (a) The export-thumbnail selection (bundle_export_thumbs) was hard-capped at
--     10 by `CHECK(position BETWEEN 1 AND 10)` in migration 004. The count is
--     now user-configurable (default 30) and drives BOTH the summary PDF's
--     thumbnail grid and the post-bundle's artifacts/thumbnails payload. SQLite
--     can't ALTER a CHECK in place, so we rebuild the table widening the CHECK
--     to `position >= 1` (the cap is now enforced in app code, not the schema).
--     Same table-rebuild recipe as migrations 007/010/016/018: foreign_keys
--     OFF, CREATE _new, copy, DROP, RENAME, recreate index, foreign_keys ON.
--     Nothing references bundle_export_thumbs, so no dependent FKs to preserve.
--     Every other column/constraint is copied verbatim from migration 004.
--
-- (b) summary_settings: a one-row singleton holding the configurable
--     thumbnail count (default 30). Mirrors auto_assembly_settings (mig 011).

PRAGMA foreign_keys = OFF;

CREATE TABLE bundle_export_thumbs_new (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    bundle_uid      TEXT NOT NULL REFERENCES bundles(uid) ON DELETE CASCADE,
    bundle_file_id  INTEGER NOT NULL REFERENCES bundle_files(id) ON DELETE CASCADE,
    position        INTEGER NOT NULL CHECK(position >= 1),
    thumbnail_path  TEXT NOT NULL,
    UNIQUE(bundle_uid, position),
    UNIQUE(bundle_uid, bundle_file_id)
);

INSERT INTO bundle_export_thumbs_new
    (id, bundle_uid, bundle_file_id, position, thumbnail_path)
SELECT id, bundle_uid, bundle_file_id, position, thumbnail_path
FROM bundle_export_thumbs;

DROP TABLE bundle_export_thumbs;
ALTER TABLE bundle_export_thumbs_new RENAME TO bundle_export_thumbs;

CREATE INDEX IF NOT EXISTS idx_bundle_export_thumbs_bundle ON bundle_export_thumbs(bundle_uid);

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS summary_settings (
    id          INTEGER PRIMARY KEY CHECK(id = 1),
    thumb_count INTEGER NOT NULL DEFAULT 30,
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);
INSERT OR IGNORE INTO summary_settings (id) VALUES (1);
