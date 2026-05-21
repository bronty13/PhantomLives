-- Phase 1.4.0: per-customer sales transactions. Unlike customer_history
-- (append-only, no edit/delete), sales are full-CRUD — Sallie can edit a
-- price, correct a date, or delete an erroneous entry. The two streams
-- are interleaved in the UI by timestamp.
--
-- Design choices:
-- * `unit_price_cents` snapshots `products.price_cents` at sale time so
--   later price changes don't retroactively rewrite history.
-- * `total_cents` is stored independently (not computed) so the user can
--   apply line-level discounts: editing the total back-solves unit_price
--   only on user action, not automatically.
-- * `product_id` FK uses ON DELETE RESTRICT — historical sales must stay
--   attached to the product they came from. Archive products instead of
--   deleting them when they go out of rotation.
CREATE TABLE IF NOT EXISTS customer_sales (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_uid     TEXT    NOT NULL REFERENCES customers(uid) ON DELETE CASCADE,
    product_id       INTEGER NOT NULL REFERENCES products(id)   ON DELETE RESTRICT,
    sale_date        TEXT    NOT NULL DEFAULT (datetime('now')),
    quantity         REAL    NOT NULL DEFAULT 1,
    unit_price_cents INTEGER NOT NULL DEFAULT 0,
    total_cents      INTEGER NOT NULL DEFAULT 0,
    notes            TEXT    NOT NULL DEFAULT '',
    created_at       TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at       TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS customer_sales_by_customer
    ON customer_sales(customer_uid, sale_date DESC);
