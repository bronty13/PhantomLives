-- Phase 1: customer tracker.
--
-- The customer UID format mirrors MasterClipper's IDGeneratorService
-- (`MasterClipper/Sources/MasterClipper/Services/IDGeneratorService.swift`):
-- `YYYY-MM-DD-#####` where the sequence resets daily. Generated client-
-- side from `src/lib/uid.ts`.
CREATE TABLE IF NOT EXISTS customers (
    uid              TEXT PRIMARY KEY,            -- e.g. "2026-05-20-00001"
    persona_code     TEXT REFERENCES personas(code) ON DELETE SET NULL,  -- nullable = "ALL"
    username         TEXT NOT NULL DEFAULT '',
    real_name        TEXT NOT NULL DEFAULT '',
    email1           TEXT NOT NULL DEFAULT '',
    email2           TEXT NOT NULL DEFAULT '',
    email3           TEXT NOT NULL DEFAULT '',
    email4           TEXT NOT NULL DEFAULT '',
    email5           TEXT NOT NULL DEFAULT '',
    notes_html       TEXT NOT NULL DEFAULT '',     -- Tiptap-serialized HTML
    archived         INTEGER NOT NULL DEFAULT 0,
    created_at       TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS customers_by_persona  ON customers(persona_code);
CREATE INDEX IF NOT EXISTS customers_by_username ON customers(username);

CREATE TABLE IF NOT EXISTS customer_products (
    customer_uid  TEXT NOT NULL REFERENCES customers(uid) ON DELETE CASCADE,
    product_id    INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    PRIMARY KEY (customer_uid, product_id)
);

CREATE TABLE IF NOT EXISTS customer_interests (
    customer_uid  TEXT NOT NULL REFERENCES customers(uid) ON DELETE CASCADE,
    interest_id   INTEGER NOT NULL REFERENCES interests(id) ON DELETE CASCADE,
    PRIMARY KEY (customer_uid, interest_id)
);
