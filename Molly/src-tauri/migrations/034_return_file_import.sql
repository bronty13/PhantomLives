-- v1.20.0 — Import SideMolly's "return file" (post-bundle) into Molly.
--
-- A return file is the <UID>-post.zip SideMolly drops at
-- ~/Downloads/Molly post-bundles/ after Robert (Sallie's collaborator)
-- posts a published bundle to its targets. Importing it closes the
-- round-trip: per-target posting facts are written back into Molly, and
-- the source bundle is flagged for cleanup 3 days later so the on-disk
-- ZIP doesn't linger.
--
-- Schema additions:
--   - bundles.completed_at, bundles.delete_after  — import outcome flags
--   - bundle_postings        — one row per (bundle, posting target)
--   - bundle_posting_files   — per-file rows; clip_id is the writeback target
--   - return_file_imports    — idempotency log keyed by source sha256

ALTER TABLE bundles ADD COLUMN completed_at TEXT;
ALTER TABLE bundles ADD COLUMN delete_after TEXT;

-- One row per target SideMolly posted (or planned to post) for a bundle.
-- target_id mirrors SideMolly's posting_targets.name (stable across imports).
-- Re-importing the same return file UPSERTs on (bundle_uid, target_id) so
-- restated postings overwrite without duplicates.
CREATE TABLE IF NOT EXISTS bundle_postings (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    bundle_uid    TEXT    NOT NULL REFERENCES bundles(uid) ON DELETE CASCADE,
    target_id     TEXT    NOT NULL,
    target_name   TEXT    NOT NULL,
    state         TEXT    NOT NULL CHECK (state IN ('pending','scheduled','posted','skipped')),
    posted_at     TEXT,
    posted_url    TEXT,
    body_override TEXT,
    notes         TEXT,
    fansite_day   INTEGER,                                       -- 1..31, FanSite only
    imported_at   TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE (bundle_uid, target_id, fansite_day)
);

CREATE INDEX IF NOT EXISTS bundle_postings_by_bundle ON bundle_postings(bundle_uid);
CREATE INDEX IF NOT EXISTS bundle_postings_by_clip_lookup ON bundle_postings(target_id);

-- Per-file rows attached to a posting. clip_id is resolved by filename match
-- against clips.title / clips.external_clip_id; NULL when no match was found
-- (the file still gets recorded so the result UI can surface unmatched files).
CREATE TABLE IF NOT EXISTS bundle_posting_files (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    posting_id  INTEGER NOT NULL REFERENCES bundle_postings(id) ON DELETE CASCADE,
    relpath     TEXT    NOT NULL,
    clip_id     TEXT    REFERENCES clips(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS bundle_posting_files_by_posting ON bundle_posting_files(posting_id);
CREATE INDEX IF NOT EXISTS bundle_posting_files_by_clip    ON bundle_posting_files(clip_id);

-- Idempotency log: each successful return-file import lands one row keyed by
-- the source ZIP's sha256. Re-importing the same file short-circuits with a
-- was_duplicate=true result and does no DB writes.
CREATE TABLE IF NOT EXISTS return_file_imports (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    bundle_uid     TEXT    NOT NULL REFERENCES bundles(uid) ON DELETE CASCADE,
    source_path    TEXT    NOT NULL,
    source_sha256  TEXT    NOT NULL UNIQUE,
    imported_at    TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS return_file_imports_by_bundle ON return_file_imports(bundle_uid);
