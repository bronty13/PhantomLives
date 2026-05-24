-- Phase 4 follow-up — widen processed_files.op_kind to accept video ops.
--
-- Phase 3 (migration 005) defined op_kind with a narrow CHECK list of
-- image-only op kinds ('watermark', 'strip_exif', etc.). Phase 4 video
-- processing emits op_kind values like 'video_watermark_strip',
-- 'video_clean', 'video_watermark_strip_rename' — produced by
-- VideoOpsInput::op_kind() — and the CHECK constraint was rejecting
-- every dispatch_process_video DB insert. Symptom: all video jobs
-- reached ffmpeg success but failed at the processed_files insert with
-- "CHECK constraint failed: op_kind IN (...)" (caught 2026-05-24).
--
-- SQLite can't ALTER an existing CHECK, so we rebuild the table without
-- one. op_kind is internal — both image and video paths construct it
-- in Rust (see images.rs ImageOpsInput::op_kind, bundles.rs
-- VideoOpsInput::op_kind), so the DB CHECK was redundant safety.
-- Validation stays in Rust where new op kinds get added.

PRAGMA foreign_keys = OFF;

CREATE TABLE processed_files_new (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    bundle_file_id  INTEGER NOT NULL REFERENCES bundle_files(id) ON DELETE CASCADE,
    op_kind         TEXT NOT NULL,
    output_path     TEXT NOT NULL,
    output_sha256   TEXT NOT NULL DEFAULT '',
    params_json     TEXT NOT NULL DEFAULT '{}',
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(bundle_file_id, op_kind)
);

INSERT INTO processed_files_new
    (id, bundle_file_id, op_kind, output_path, output_sha256, params_json, created_at)
SELECT id, bundle_file_id, op_kind, output_path, output_sha256, params_json, created_at
FROM processed_files;

DROP TABLE processed_files;
ALTER TABLE processed_files_new RENAME TO processed_files;

CREATE INDEX IF NOT EXISTS idx_processed_files_bundle_file ON processed_files(bundle_file_id);

PRAGMA foreign_keys = ON;
