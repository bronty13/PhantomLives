-- Phase 1c — 10 random thumbnails per bundle, marked for inclusion in
-- the Phase 11 post-bundle ZIP that goes back to Molly.
--
-- Why a separate table (vs. a flag on bundle_files):
--   - Keeps the 10-row cap clean (one row per export slot).
--   - Lets a future "regenerate selection" feature swap the picks
--     without touching the per-file thumbnail_path on bundle_files.
--   - Position 1..10 surfaces ordering for the eventual Molly UI.
--
-- bundle_file_id is a CASCADE FK so deleting a bundle wipes its
-- export-thumb rows; deleting a single bundle_file does the same.

CREATE TABLE IF NOT EXISTS bundle_export_thumbs (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    bundle_uid      TEXT NOT NULL REFERENCES bundles(uid) ON DELETE CASCADE,
    bundle_file_id  INTEGER NOT NULL REFERENCES bundle_files(id) ON DELETE CASCADE,
    position        INTEGER NOT NULL CHECK(position BETWEEN 1 AND 10),
    thumbnail_path  TEXT NOT NULL,
    UNIQUE(bundle_uid, position),
    UNIQUE(bundle_uid, bundle_file_id)
);

CREATE INDEX IF NOT EXISTS idx_bundle_export_thumbs_bundle ON bundle_export_thumbs(bundle_uid);
