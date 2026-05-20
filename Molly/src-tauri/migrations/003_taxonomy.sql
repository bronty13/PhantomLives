-- Phase 1: customer taxonomy — products (what they buy) + interests
-- (what they like). Both are simple typed-color lists, editable from
-- Settings. A customer references many of each via the join tables in
-- 004_customers.sql.
CREATE TABLE IF NOT EXISTS products (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL UNIQUE,
    color       TEXT NOT NULL,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    archived    INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS interests (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL UNIQUE,
    color       TEXT NOT NULL,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    archived    INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Default products from spec — phone/cam/customs + physical merch.
INSERT OR IGNORE INTO products (name, color, sort_order) VALUES
    ('Phone',                 '#FFB6C1', 10),
    ('Cam',                   '#FF8FB1', 20),
    ('Customs',               '#E5527A', 30),
    ('Physical — Panties',    '#D46BAA', 40),
    ('Physical — Pantyhose',  '#B85C9C', 50),
    ('Physical — Shoes Flats','#9C4A85', 60),
    ('Physical — Heels',      '#7A3868', 70);

-- Default interests from spec.
INSERT OR IGNORE INTO interests (name, color, sort_order) VALUES
    ('Feet',        '#F472B6', 10),
    ('Pantyhose',   '#EC4899', 20),
    ('Panties',     '#DB2777', 30),
    ('Humiliation', '#9D174D', 40);
