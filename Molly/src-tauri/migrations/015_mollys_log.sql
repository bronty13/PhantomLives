-- Phase 1.7.0: Molly's Log — Star-Trek-Captain's-Log-style journal for
-- the creator. Same shape as customer_history (id + ts + body + inline
-- BLOB attachment) but global (no customer FK, no persona binding).
-- Full CRUD on entries; mirrors the 1.4.2 lift of audit-only on history
-- notes.
CREATE TABLE IF NOT EXISTS mollys_log (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    ts                  TEXT    NOT NULL DEFAULT (datetime('now')),
    body                TEXT    NOT NULL DEFAULT '',
    -- Optional inline attachment. attachment_size = 0 means no attachment.
    attachment_filename TEXT    NOT NULL DEFAULT '',
    attachment_mime     TEXT    NOT NULL DEFAULT '',
    attachment_size     INTEGER NOT NULL DEFAULT 0,
    attachment_data     BLOB,
    updated_at          TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS mollys_log_by_ts ON mollys_log(ts DESC);
