-- v0.27.0 — global Edit defaults.
--
-- The Edit tab's image/video op toggles (watermark, strip EXIF/metadata,
-- rename) were hard-coded in the React component. This singleton makes the
-- starting toggle states user-configurable (Settings → Edit defaults), GLOBAL
-- (not per-persona). Rename now defaults ON. Mirrors the other singleton
-- settings tables (auto_assembly_settings mig 011, summary_settings mig 022).
CREATE TABLE IF NOT EXISTS edit_defaults (
    id                    INTEGER PRIMARY KEY CHECK(id = 1),
    image_watermark       INTEGER NOT NULL DEFAULT 1,
    image_strip_exif      INTEGER NOT NULL DEFAULT 1,
    image_rename          INTEGER NOT NULL DEFAULT 1,
    video_watermark       INTEGER NOT NULL DEFAULT 1,
    video_strip_metadata  INTEGER NOT NULL DEFAULT 1,
    video_rename          INTEGER NOT NULL DEFAULT 1,
    updated_at            TEXT NOT NULL DEFAULT (datetime('now'))
);
INSERT OR IGNORE INTO edit_defaults (id) VALUES (1);
