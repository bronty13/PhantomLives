-- Phase 12: background jobs runner.
--
-- Generic recurring-task registry + append-only run history. Initial
-- only registered kind is 'atw_repost' (a chromiumoxide-driven port of
-- the standalone atw-repost-bot/repost.js daemon). The runner ticks
-- every 60s from a tauri::async_runtime::spawn alongside the existing
-- backup + bundle-purge launch tasks.
--
-- DELIBERATELY NOT overloaded into the existing schedules/occurrences
-- system — that's reminder-centric (materialize "tasks due today" into
-- a calendar grid), this is task-execution-centric (fire a Tauri
-- command at cadence X, log success/failure rows).

CREATE TABLE IF NOT EXISTS background_jobs (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    kind             TEXT    NOT NULL,                       -- e.g. 'atw_repost'
    name             TEXT    NOT NULL,                       -- human label, editable
    enabled          INTEGER NOT NULL DEFAULT 1,
    cadence_seconds  INTEGER NOT NULL,                       -- e.g. 14400 = 4h
    params_json      TEXT    NOT NULL DEFAULT '{}',          -- per-kind knobs
    last_run_at      TEXT,                                   -- last successful OR failed start
    next_run_at      TEXT,                                   -- denormalized for runner SELECT
    created_at       TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at       TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS background_jobs_due
    ON background_jobs(enabled, next_run_at);

CREATE TABLE IF NOT EXISTS background_job_runs (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id        INTEGER NOT NULL REFERENCES background_jobs(id) ON DELETE CASCADE,
    started_at    TEXT    NOT NULL DEFAULT (datetime('now')),
    finished_at   TEXT,
    status        TEXT    NOT NULL CHECK (status IN ('running','success','failed','cancelled')),
    summary       TEXT    NOT NULL DEFAULT '',               -- human-readable headline
    log_excerpt   TEXT    NOT NULL DEFAULT ''                -- last ~100 log lines for debugging
);
CREATE INDEX IF NOT EXISTS background_job_runs_by_job
    ON background_job_runs(job_id, started_at DESC);
