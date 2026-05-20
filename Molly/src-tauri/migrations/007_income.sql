-- Phase 4: income tracking.
--
-- Two flavors:
--   * income_adhoc — one-off sales tied to a specific date earned.
--   * income_site  — monthly totals per (year, month, site). The Site
--                    Income Wizard walks every site grouped by persona
--                    and accepts one dollar amount per cell.
CREATE TABLE IF NOT EXISTS income_adhoc (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    date_earned     TEXT NOT NULL,           -- ISO date YYYY-MM-DD
    amount          REAL NOT NULL DEFAULT 0,
    persona_code    TEXT REFERENCES personas(code) ON DELETE SET NULL,  -- null = unassigned
    source_label    TEXT NOT NULL DEFAULT '',
    note            TEXT NOT NULL DEFAULT '',
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS income_adhoc_by_date    ON income_adhoc(date_earned);
CREATE INDEX IF NOT EXISTS income_adhoc_by_persona ON income_adhoc(persona_code);

CREATE TABLE IF NOT EXISTS income_site (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    year            INTEGER NOT NULL,
    month           INTEGER NOT NULL,         -- 1-12
    site_id         INTEGER NOT NULL REFERENCES sites(id) ON DELETE CASCADE,
    amount          REAL NOT NULL DEFAULT 0,
    note            TEXT NOT NULL DEFAULT '',
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (year, month, site_id)
);
CREATE INDEX IF NOT EXISTS income_site_by_period ON income_site(year, month);
