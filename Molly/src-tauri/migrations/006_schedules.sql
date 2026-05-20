-- Phase 3: scheduling engine + reminders.
--
-- Two tables: `schedules` (the rule/recurrence) and `occurrences` (the
-- materialized instances we tick off). `cadence_json` holds the cadence
-- shape (see src/lib/cadence.ts). We never expose cron strings to the
-- user; the wizard speaks human ("every Mon + Thu", "10 days before
-- next month") and serializes to JSON here.
CREATE TABLE IF NOT EXISTS schedules (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    name            TEXT NOT NULL,
    persona_code    TEXT REFERENCES personas(code) ON DELETE SET NULL,  -- null = applies across personas
    cadence_json    TEXT NOT NULL,
    lead_time_days  INTEGER NOT NULL DEFAULT 0,
    notes           TEXT NOT NULL DEFAULT '',
    active          INTEGER NOT NULL DEFAULT 1,
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS occurrences (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    schedule_id       INTEGER NOT NULL REFERENCES schedules(id) ON DELETE CASCADE,
    due_at            TEXT NOT NULL,             -- ISO date 'YYYY-MM-DD'
    completed_at      TEXT,                       -- ISO datetime when checked off; null = pending
    completion_note   TEXT NOT NULL DEFAULT '',
    attachment_path   TEXT,                       -- path relative to app_data_dir
    created_at        TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (schedule_id, due_at)
);

CREATE INDEX IF NOT EXISTS occurrences_by_due ON occurrences(due_at);
CREATE INDEX IF NOT EXISTS occurrences_pending ON occurrences(completed_at) WHERE completed_at IS NULL;

-- ---------------------------------------------------------------------------
-- Default schedules from spec.
-- ---------------------------------------------------------------------------
-- 1) Fan Site Posting — CoC: monthly, fires 10 days before the start of
--    next month. ("monthly_days_before_next" with daysBefore=10.)
INSERT OR IGNORE INTO schedules (id, name, persona_code, cadence_json, notes, active) VALUES
    (1, 'Fan Site Posting — CoC',  'CoC', '{"kind":"monthly_days_before_next","daysBefore":10}', 'Plan + queue next month''s posts for CoC.', 1),
    (2, 'Fan Site Posting — PoA',  'PoA', '{"kind":"monthly_days_before_next","daysBefore":10}', 'Plan + queue next month''s posts for PoA.', 1),
    (3, 'Income update',           NULL,  '{"kind":"monthly_days_after_eom","daysAfter":3}',     'Enter site income for the month that just ended.', 1),
    (4, 'CoC content release',     'CoC', '{"kind":"weekly","days":[1,4]}',                       'Weekly content drops: Mondays and Thursdays.', 1),
    (5, 'PoA content release',     'PoA', '{"kind":"weekly","days":[3,5]}',                       'Weekly content drops: Wednesdays and Fridays.', 1);
