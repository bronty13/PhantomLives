-- v1.26.0 — Optional PREVIEW ASSETS on a Content bundle.
--
-- Sallie can attach two optional preview files to a Content bundle: a
-- static cover Thumbnail Image and an animated Teaser GIF. Like the
-- audio description (migration 017), these live ON the bundles row — not
-- in bundle_files — because they are single, slot-shaped attachments, not
-- ordered media deliverables. Each stores a relative path into
-- app_data/attachments/... and the SHA-256 captured at upload time, so
-- the deterministic bundle compose can verify the bytes haven't changed.
--
-- All four columns are nullable: a bundle with no preview assets simply
-- leaves them NULL, exactly like description_audio_relpath.

ALTER TABLE bundles ADD COLUMN thumbnail_relpath TEXT;
ALTER TABLE bundles ADD COLUMN thumbnail_sha256 TEXT;
ALTER TABLE bundles ADD COLUMN teaser_gif_relpath TEXT;
ALTER TABLE bundles ADD COLUMN teaser_gif_sha256 TEXT;
