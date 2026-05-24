-- Phase 4.5 — accept new job kinds for the Auto-Assembly pipeline.
--
-- Phase 4's `jobs.kind` CHECK was narrow (`'process_video'` only).
-- Phase 4.5 adds three new kinds — `render_title`, `normalize_video`,
-- `assemble_master` — that compose into a master MP4 (title card →
-- xfade-chained per-video normalize+watermark+audio → fade-to-black).
--
-- SQLite can't ALTER a CHECK constraint in place, and rather than
-- rewrite the table on every new kind, we drop the CHECK entirely
-- and validate at the Rust dispatcher layer (which already routes by
-- kind, so an unknown kind surfaces as a clear runtime error rather
-- than a confusing DB constraint failure). Same approach we took in
-- migration 007 for processed_files.op_kind.

PRAGMA foreign_keys = OFF;

CREATE TABLE jobs_new (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    kind                TEXT NOT NULL,
    params_json         TEXT NOT NULL DEFAULT '{}',
    bundle_uid          TEXT REFERENCES bundles(uid) ON DELETE CASCADE,
    source_in_zip_path  TEXT,
    status              TEXT NOT NULL CHECK(status IN ('pending','running','done','failed'))
                          DEFAULT 'pending',
    attempts            INTEGER NOT NULL DEFAULT 0,
    last_error          TEXT,
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT INTO jobs_new
    (id, kind, params_json, bundle_uid, source_in_zip_path, status,
     attempts, last_error, created_at, updated_at)
SELECT id, kind, params_json, bundle_uid, source_in_zip_path, status,
       attempts, last_error, created_at, updated_at
FROM jobs;

DROP TABLE jobs;
ALTER TABLE jobs_new RENAME TO jobs;

CREATE INDEX IF NOT EXISTS idx_jobs_status_created ON jobs(status, created_at);
CREATE INDEX IF NOT EXISTS idx_jobs_bundle        ON jobs(bundle_uid);

PRAGMA foreign_keys = ON;
