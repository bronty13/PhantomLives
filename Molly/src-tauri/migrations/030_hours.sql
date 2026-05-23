-- Phase 15 PR2: Hours tracker + reward milestones.
--
-- Sessions are clock-in/clock-out intervals. duration_ms is denormalised
-- on stop so dashboard rollups (today / week / month) are a single SUM
-- without re-computing per-row. start_ms is a unix epoch milliseconds
-- so client + Rust can both compare cheaply.
--
-- A SINGLE in-progress session is allowed at a time; the convention is
-- "if any row has duration_ms IS NULL, you're clocked in". UI enforces
-- the one-at-a-time invariant; the schema permits multiple to recover
-- gracefully if state ever drifts.
--
-- Reward milestones are global (not persona-scoped — that was the user's
-- explicit ask). Total hours = SUM(duration_ms across ALL sessions) +
-- the running clock if any. Multiple goals allowed (100h, 150h, 250h…).
-- Hitting a goal is computed at render time from total_hours >= hours_goal.

CREATE TABLE IF NOT EXISTS clock_sessions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    persona_code    TEXT REFERENCES personas(code) ON DELETE SET NULL,
    start_ms        INTEGER NOT NULL,                -- unix epoch ms
    duration_ms     INTEGER,                         -- NULL = still running
    notes           TEXT NOT NULL DEFAULT '',
    created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS clock_sessions_by_start ON clock_sessions(start_ms DESC);
CREATE INDEX IF NOT EXISTS clock_sessions_open
    ON clock_sessions(id) WHERE duration_ms IS NULL;

CREATE TABLE IF NOT EXISTS reward_milestones (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    hours_goal      REAL NOT NULL CHECK (hours_goal > 0),
    label           TEXT NOT NULL,
    sort_order      INTEGER NOT NULL DEFAULT 0,
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS reward_milestones_by_goal ON reward_milestones(hours_goal);
