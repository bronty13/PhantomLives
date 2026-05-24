-- Phase 5 follow-up — central processing log.
--
-- One row per significant event during media processing — every job
-- lifecycle transition (claimed / running / done / failed), plus
-- ad-hoc info entries for things like watermark cache misses or
-- DeepFilterNet skip-due-to-missing-binary. The UI surfaces these on
-- the Edit tab and exports them as a text file when composing the
-- return bundle to Molly (Phase 11).
--
-- Scoping:
--   - bundle_uid is nullable so app-wide events (worker startup,
--     migration apply) can also be logged.
--   - job_id is nullable for the same reason + for log entries
--     attached to a bundle but not a specific job.
--   - Both reference their parent table with ON DELETE SET NULL so
--     pruning history doesn't drop log entries the user may still
--     want to inspect.
--
-- Levels follow the standard info/warn/error trio; CHECK enforces.

CREATE TABLE IF NOT EXISTS processing_log (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp     TEXT NOT NULL DEFAULT (datetime('now')),
    bundle_uid    TEXT REFERENCES bundles(uid) ON DELETE SET NULL,
    job_id        INTEGER REFERENCES jobs(id) ON DELETE SET NULL,
    kind          TEXT,                                       -- 'process_video' / 'transcribe_video' / 'lifecycle' / etc.
    level         TEXT NOT NULL CHECK(level IN ('info','warn','error')) DEFAULT 'info',
    message       TEXT NOT NULL,
    subject       TEXT,                                       -- file the event is about, when applicable
    details       TEXT                                        -- optional payload (stderr tail, JSON, etc.)
);

CREATE INDEX IF NOT EXISTS idx_log_bundle ON processing_log(bundle_uid, timestamp);
CREATE INDEX IF NOT EXISTS idx_log_job    ON processing_log(job_id);
CREATE INDEX IF NOT EXISTS idx_log_time   ON processing_log(timestamp);
