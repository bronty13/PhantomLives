-- v0.22.0 — accept Molly's `youtube` bundle type.
--
-- Molly began emitting bundles with `"bundleType": "youtube"` (its first
-- YouTube workflow). SideMolly's `bundles.bundle_type` CHECK from
-- migration 002 only allowed ('content','custom','fansite'), so ingest
-- failed with `CHECK constraint failed: bundle_type IN (...)` and the
-- bundle never showed in the Inbox.
--
-- SQLite can't ALTER a CHECK constraint in place, so we rebuild the
-- table with the widened CHECK. Same table-rebuild recipe as migrations
-- 007/010/016: foreign_keys OFF, CREATE _new, copy, DROP, RENAME,
-- recreate indexes, foreign_keys ON. The 7 FK dependents
-- (bundle_files, bundle_export_thumbs, jobs, processing_log,
-- dropbox_copies, bundle_postings, posting_log) keep valid uid values
-- across the rebuild, so their foreign keys survive.
--
-- Every other column, default, and CHECK is copied verbatim from
-- migration 002_bundles.sql — only the bundle_type CHECK gains 'youtube'.

PRAGMA foreign_keys = OFF;

CREATE TABLE bundles_new (
    uid                TEXT PRIMARY KEY,
    bundle_type        TEXT NOT NULL CHECK(bundle_type IN ('content','custom','fansite','youtube')),
    persona_code       TEXT,
    title              TEXT NOT NULL DEFAULT '',
    source_zip_path    TEXT NOT NULL,
    source_zip_sha256  TEXT NOT NULL DEFAULT '',
    ingested_at        TEXT NOT NULL DEFAULT (datetime('now')),
    verify_status      TEXT NOT NULL CHECK(verify_status IN ('pending','verified','failed')) DEFAULT 'pending',
    verify_error       TEXT,
    manifest_source    TEXT NOT NULL CHECK(manifest_source IN ('manifest_json','molly_log')) DEFAULT 'molly_log',
    manifest_json      TEXT NOT NULL DEFAULT '{}',
    bundle_state       TEXT NOT NULL CHECK(bundle_state IN ('new','in_progress','shipped','archived')) DEFAULT 'new',
    created_at         TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at         TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT INTO bundles_new
    (uid, bundle_type, persona_code, title, source_zip_path,
     source_zip_sha256, ingested_at, verify_status, verify_error,
     manifest_source, manifest_json, bundle_state, created_at, updated_at)
SELECT uid, bundle_type, persona_code, title, source_zip_path,
       source_zip_sha256, ingested_at, verify_status, verify_error,
       manifest_source, manifest_json, bundle_state, created_at, updated_at
FROM bundles;

DROP TABLE bundles;
ALTER TABLE bundles_new RENAME TO bundles;

CREATE INDEX IF NOT EXISTS idx_bundles_ingested ON bundles(ingested_at DESC);
CREATE INDEX IF NOT EXISTS idx_bundles_persona  ON bundles(persona_code);
CREATE INDEX IF NOT EXISTS idx_bundles_state    ON bundles(bundle_state);

PRAGMA foreign_keys = ON;
