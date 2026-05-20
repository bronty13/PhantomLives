-- Phase 4: expense tracking.
--
-- `expenses` is the canonical journal — both one-off and the
-- materialized rows from recurring expenses land here. `excluded` +
-- `exclusion_amount` lets the user mark "this $100 was 30% personal,
-- 70% business" without losing the original total.
CREATE TABLE IF NOT EXISTS expenses (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    actual_date         TEXT NOT NULL,           -- when the charge hit
    effective_date      TEXT NOT NULL,           -- when it applies for reporting
    description         TEXT NOT NULL DEFAULT '',
    note                TEXT NOT NULL DEFAULT '',
    attachment_path     TEXT,                     -- relative to app_data_dir
    amount              REAL NOT NULL DEFAULT 0,
    persona_code        TEXT REFERENCES personas(code) ON DELETE SET NULL,
    excluded            INTEGER NOT NULL DEFAULT 0,    -- 1 = fully excluded from reporting
    exclusion_amount    REAL,                          -- nullable; if set and excluded=0, partial exclusion
    recurring_id        INTEGER REFERENCES expenses_recurring(id) ON DELETE SET NULL,
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS expenses_by_effective ON expenses(effective_date);
CREATE INDEX IF NOT EXISTS expenses_by_actual    ON expenses(actual_date);
CREATE INDEX IF NOT EXISTS expenses_by_persona   ON expenses(persona_code);
CREATE INDEX IF NOT EXISTS expenses_by_recurring ON expenses(recurring_id);

-- Recurring expenses use the same Cadence engine as schedules
-- (`src/lib/cadence.ts`). On launch + every 30 min the materializer
-- writes rows into `expenses` for any new effective dates between the
-- recurring expense's anchor and today.
CREATE TABLE IF NOT EXISTS expenses_recurring (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    description     TEXT NOT NULL,
    amount          REAL NOT NULL DEFAULT 0,
    persona_code    TEXT REFERENCES personas(code) ON DELETE SET NULL,
    cadence_json    TEXT NOT NULL,
    anchor_date     TEXT NOT NULL,            -- inclusive start of materialization
    last_material   TEXT,                      -- last effective_date we materialized
    note            TEXT NOT NULL DEFAULT '',
    active          INTEGER NOT NULL DEFAULT 1,
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Uniqueness on (recurring_id, effective_date) so re-running the
-- materializer is a no-op for any already-stamped occurrence.
CREATE UNIQUE INDEX IF NOT EXISTS expenses_recurring_unique
    ON expenses(recurring_id, effective_date)
    WHERE recurring_id IS NOT NULL;
