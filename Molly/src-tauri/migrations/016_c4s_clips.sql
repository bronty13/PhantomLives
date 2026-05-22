-- Phase 8: Clips4Sale (C4S) reference snapshot.
--
-- Each store (CoC / PoA) exports the full clip catalog as a pipe-delimited
-- CSV. Imports are atomic, store-scoped, **delete-and-reinsert** — this is
-- a snapshot, not relational state. No FK to personas (PoA's persona_code
-- in app data is 'PoA' even though the C4S Performers field says
-- 'PrincessOFAddiction'; we normalize on import). CHECK-locked to the two
-- shipped stores; widen only if Sallie ever adds a third storefront.
CREATE TABLE IF NOT EXISTS c4s_clips (
    clip_id              TEXT    NOT NULL,
    persona_code         TEXT    NOT NULL CHECK (persona_code IN ('CoC','PoA')),
    clip_status          TEXT    NOT NULL DEFAULT '',
    clip_tracking_tag    TEXT    NOT NULL DEFAULT '',
    clip_title           TEXT    NOT NULL DEFAULT '',
    clip_description     TEXT    NOT NULL DEFAULT '',
    categories           TEXT    NOT NULL DEFAULT '',   -- comma-joined as exported
    keywords             TEXT    NOT NULL DEFAULT '',
    clip_filename        TEXT    NOT NULL DEFAULT '',
    clip_thumbnail       TEXT    NOT NULL DEFAULT '',
    clip_preview         TEXT    NOT NULL DEFAULT '',
    performers           TEXT    NOT NULL DEFAULT '',
    price_cents          INTEGER,
    sales_count          INTEGER,
    income_6mo_cents     INTEGER,
    imported_at          TEXT    NOT NULL,             -- ISO 8601
    PRIMARY KEY (persona_code, clip_id)
);

CREATE INDEX IF NOT EXISTS c4s_clips_by_persona_status ON c4s_clips(persona_code, clip_status);
CREATE INDEX IF NOT EXISTS c4s_clips_by_title         ON c4s_clips(clip_title);

-- Per-import audit row, written inside the same transaction as the
-- overlay-replace. Drives the stale-data banner via `MAX(imported_at)`.
CREATE TABLE IF NOT EXISTS c4s_imports (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    persona_code  TEXT    NOT NULL,
    source_file   TEXT    NOT NULL DEFAULT '',
    row_count     INTEGER NOT NULL DEFAULT 0,
    imported_at   TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS c4s_imports_by_persona_time ON c4s_imports(persona_code, imported_at DESC);
