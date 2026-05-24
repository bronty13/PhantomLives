-- Phase 4.3 — per-file rotation overrides.
--
-- A bundle commonly mixes correctly-oriented files with sideways /
-- upside-down ones (iPhone clips recorded landscape-but-portrait,
-- scanned photos imported upside-down, etc.). The previous per-batch
-- rotation dropdown couldn't express "rotate file 3 by 90°, leave
-- file 4 alone, rotate file 5 by 180°" — Robert's real workflow.
--
-- Store the override on bundle_files itself rather than a sidecar
-- overrides table so a single SELECT in the processing pipeline picks
-- it up, and a CASCADE on bundle delete carries the overrides away.
--
-- 0 = no rotation (default), 90 = 90° clockwise, 180 = 180°,
-- 270 = 90° counter-clockwise. Enforced via CHECK so a typo in
-- application code surfaces at the DB layer instead of producing a
-- silently-no-op ffmpeg invocation.

-- SQLite ALTER TABLE doesn't support adding a column with a CHECK
-- constraint that references the column itself, so we do this as an
-- ADD COLUMN followed by a defensive CHECK enforced at write time
-- (validation lives in Rust — `set_bundle_file_rotation`).
ALTER TABLE bundle_files
    ADD COLUMN rotation_degrees INTEGER NOT NULL DEFAULT 0;
