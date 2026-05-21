-- Phase 1.3.0: per-customer immutable history log. Append-only audit
-- trail of free-text notes, each optionally carrying ONE attachment
-- stored inline as a SQLite BLOB (user's explicit choice for portability
-- in the auto-backup zip).
--
-- Notes:
-- * Immutability is enforced at the data-layer API surface — the
--   `customerHistory.ts` module only exports `addEntry()` + `listEntries()`,
--   no update/delete. A power user with SQL access can still mutate, but
--   the UX contract is "can't be edited, can't be deleted."
-- * Phase 3 sales transactions get a SEPARATE table (`customer_sales`) and
--   ARE editable; the two streams are interleaved in the UI by timestamp.
-- * Lists fetched via SELECT *without* `attachment_data` to keep memory
--   low (a year of attachments could otherwise blow up the row buffer).
--   Downloads stream the BLOB out by id through the
--   `download_history_attachment` Tauri command.
CREATE TABLE IF NOT EXISTS customer_history (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_uid        TEXT    NOT NULL REFERENCES customers(uid) ON DELETE CASCADE,
    ts                  TEXT    NOT NULL DEFAULT (datetime('now')),
    body                TEXT    NOT NULL DEFAULT '',
    -- Optional inline attachment. `attachment_size = 0` means no attachment.
    attachment_filename TEXT    NOT NULL DEFAULT '',
    attachment_mime     TEXT    NOT NULL DEFAULT '',
    attachment_size     INTEGER NOT NULL DEFAULT 0,
    attachment_data     BLOB
);

CREATE INDEX IF NOT EXISTS customer_history_by_customer
    ON customer_history(customer_uid, ts DESC);
