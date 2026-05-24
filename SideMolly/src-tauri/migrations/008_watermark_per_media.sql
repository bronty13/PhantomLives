-- Phase 4.2 — split watermark_profiles.enabled into per-media kind toggles.
--
-- The original single `enabled` column treated images and videos the
-- same: either both watermarked or neither. Robert's actual workflow
-- needs the opposite default per kind (videos = always watermarked,
-- images = usually unwatermarked because the cropping/text-overlay
-- shop work that comes after a still photo would defeat the watermark
-- anyway). Splitting the flag lets each persona enable/disable
-- independently.
--
-- Default policy (per Robert's spec 2026-05-24):
--   image_enabled = 0   (off — most photos get hand-edited downstream)
--   video_enabled = 1   (on — videos go to platforms direct and need
--                        provenance burn-in)
--
-- Migration semantics for existing rows:
--   * video_enabled <- old enabled value (preserves whatever the user
--     had configured — almost certainly =1 since that was the
--     practical default).
--   * image_enabled <- 0 (force off, matching the new default policy).
--
-- SQLite can't conditionally rename a column, so we ALTER TABLE ADD
-- COLUMN and migrate the data in-place rather than the table-rebuild
-- dance migration 007 needed.

ALTER TABLE watermark_profiles
    ADD COLUMN image_enabled INTEGER NOT NULL DEFAULT 0;
ALTER TABLE watermark_profiles
    ADD COLUMN video_enabled INTEGER NOT NULL DEFAULT 1;

-- Carry forward existing intent: whatever was in `enabled` becomes the
-- video flag; image flag stays at its DEFAULT 0.
UPDATE watermark_profiles SET video_enabled = enabled;

-- Keep `enabled` for one migration as a fallback so a Phase 4.1 build
-- pointed at a 4.2 DB doesn't immediately crash; loader code now
-- reads image_enabled / video_enabled exclusively. Phase 5 can drop
-- the column.
