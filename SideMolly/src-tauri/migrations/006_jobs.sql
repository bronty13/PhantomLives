-- Phase 4 — generic background job queue.
--
-- One row per enqueued job. Sequential worker (jobs.rs) polls every 2s,
-- claims the oldest 'pending' row by UPDATE ... WHERE status='pending'
-- LIMIT 1 (SQLite-friendly via a sub-SELECT), runs the dispatch, and
-- writes back 'done' or 'failed' + last_error.
--
-- kind is open-ended via CHECK so new job types (Phase 5 transcribe,
-- Phase 6 dropbox copy, Phase 11 post-bundle compose) can be added by
-- new migrations that ALTER the CHECK. For Phase 4 only 'process_video'
-- is shipped.
--
-- bundle_uid + source_in_zip_path are optional but populated when the
-- job operates on a specific bundle file — lets the JobsView surface
-- "what was this job working on?" without parsing params_json.

CREATE TABLE IF NOT EXISTS jobs (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    kind                TEXT NOT NULL CHECK(kind IN ('process_video')),
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

CREATE INDEX IF NOT EXISTS idx_jobs_status_created ON jobs(status, created_at);
CREATE INDEX IF NOT EXISTS idx_jobs_bundle        ON jobs(bundle_uid);

-- Per-attempt audit trail. A job can have multiple runs (one per retry).
-- log_path points at a file containing the captured stderr from the
-- subprocess; nullable when the job never spawned anything (e.g. setup
-- error before exec).
CREATE TABLE IF NOT EXISTS job_runs (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id      INTEGER NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    started_at  TEXT NOT NULL DEFAULT (datetime('now')),
    finished_at TEXT,
    exit_code   INTEGER,
    log_path    TEXT
);

CREATE INDEX IF NOT EXISTS idx_job_runs_job ON job_runs(job_id);
