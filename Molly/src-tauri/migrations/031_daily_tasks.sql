-- Phase 15 PR3: Daily to-do list.
--
-- The HTML "Today" panel auto-resets at midnight. We store each task
-- with the date it belongs to (TEXT YYYY-MM-DD), so previous-day tasks
-- stay queryable for history without polluting today's view. The UI
-- always filters by `for_date = <today>` and the auto-reset is a
-- frontend concept (no destructive purge — just stop showing).
--
-- done_at is set when complete; toggles back to NULL on undo.

CREATE TABLE IF NOT EXISTS daily_tasks (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    persona_code    TEXT REFERENCES personas(code) ON DELETE SET NULL,
    for_date        TEXT NOT NULL,                    -- ISO YYYY-MM-DD
    text            TEXT NOT NULL,
    category        TEXT NOT NULL DEFAULT 'other'
                    CHECK (category IN ('reddit','youtube','content','admin','other')),
    done_at         TEXT,                             -- ISO datetime or NULL
    sort_order      INTEGER NOT NULL DEFAULT 0,
    created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS daily_tasks_by_date    ON daily_tasks(for_date);
CREATE INDEX IF NOT EXISTS daily_tasks_by_persona ON daily_tasks(persona_code, for_date);
