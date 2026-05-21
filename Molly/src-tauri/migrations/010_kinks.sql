-- Phase 1.1: third customer taxonomy — kinks. Same shape as products /
-- interests in 003_taxonomy.sql; ordering matters at the catalog level
-- via sort_order (mirrors MasterClipper's ClipCategory). No seed rows —
-- the Settings → Kinks tab includes a "Seed from ~/Downloads/kinks.json"
-- button for bulk imports.
CREATE TABLE IF NOT EXISTS kinks (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL UNIQUE,
    color       TEXT NOT NULL,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    archived    INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS customer_kinks (
    customer_uid  TEXT NOT NULL REFERENCES customers(uid) ON DELETE CASCADE,
    kink_id       INTEGER NOT NULL REFERENCES kinks(id) ON DELETE CASCADE,
    PRIMARY KEY (customer_uid, kink_id)
);
