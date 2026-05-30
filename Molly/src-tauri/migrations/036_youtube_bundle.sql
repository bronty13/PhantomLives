-- v1.23.0 — YouTube bundle type.
--
-- Adds a 4th bundle flavor ("youtube"): title + persona + text/audio
-- description + 1..N video clips + go-live date + special instructions.
-- It's the Content bundle minus categories, with the file list locked to
-- video.
--
-- Why a new `bundle_kind` column instead of widening the existing
-- `bundle_type` CHECK ('content','custom','fansite'):
--
--   SQLite can't ALTER a CHECK constraint — relaxing it means rebuilding
--   the `bundles` table. But `bundles` is the parent of SIX FK-children
--   (bundle_fan_days, bundle_files, bundle_categories, bundle_tag_links,
--   bundle_postings, return_file_imports), all ON DELETE CASCADE. Inside a
--   tauri-plugin-sql migration foreign_keys is forced ON (sqlx default) and
--   the script runs in a transaction where `PRAGMA foreign_keys`,
--   `legacy_alter_table` and `defer_foreign_keys` are all no-ops — verified
--   empirically. So `DROP TABLE bundles` would cascade-delete every child
--   row. A full-cluster rebuild on Sallie's live DB is unacceptably risky.
--
--   Instead we add an UNCONSTRAINED discriminator column via a plain, never-
--   cascading `ALTER TABLE ... ADD COLUMN` (the same safe move migration 034
--   used for completed_at/delete_after). `bundle_kind` becomes the
--   authoritative type the app reads (Rust selects
--   COALESCE(bundle_kind, bundle_type) AS bundle_type). YouTube rows store
--   bundle_type='content' (keeps the legacy CHECK satisfied) +
--   bundle_kind='youtube'. This also permanently escapes the CHECK trap:
--   any future bundle type is now a zero-risk change.

ALTER TABLE bundles ADD COLUMN bundle_kind TEXT;

-- Backfill existing rows so the COALESCE read is a no-op for them.
UPDATE bundles SET bundle_kind = bundle_type WHERE bundle_kind IS NULL;

CREATE INDEX IF NOT EXISTS bundles_by_kind ON bundles(bundle_kind, state);
