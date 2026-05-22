-- Phase 11: site credentials (sub-credentials per site).
--
-- A single site can have multiple logins (e.g. a CoC store + a PoA
-- store on the same C4S account, or alt accounts on OnlyFans). Pulled
-- in from the deferred list because the user asked for it day one.
--
-- Cleanest schema is a child table; existing sites.username data is
-- backfilled into a "default" primary credential row per site.
-- sites.username STAYS in the schema for backwards-compat (existing
-- read paths like Molly Helper's "Copy user" button continue working
-- unchanged); the new credentials table is the source of truth going
-- forward, and changes to the primary credential's username are
-- mirrored back to sites.username by the data layer.

CREATE TABLE IF NOT EXISTS site_credentials (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    site_id              INTEGER NOT NULL REFERENCES sites(id) ON DELETE CASCADE,
    label                TEXT    NOT NULL DEFAULT 'default',   -- e.g. 'CoC store', 'PoA store', 'backup'
    username             TEXT    NOT NULL DEFAULT '',
    password_encrypted   TEXT,                                  -- base64 of versioned AES-GCM blob; NULL = no password set
    password_dek_version INTEGER,                               -- which DEK generation wrote this; lets future re-key migrations identify stale rows
    password_updated_at  TEXT,
    is_primary           INTEGER NOT NULL DEFAULT 0,            -- exactly one per site
    sort_order           INTEGER NOT NULL DEFAULT 0,
    created_at           TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at           TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS site_credentials_by_site
    ON site_credentials(site_id, sort_order);

-- Backfill: every existing site gets a primary credential row carrying
-- the legacy sites.username. New sites created post-019 should also
-- create a primary row via the data layer (data/sites.ts INSERT helper
-- is wrapped to do this).
INSERT INTO site_credentials (site_id, label, username, is_primary, sort_order)
SELECT id, 'default', COALESCE(username, ''), 1, 0
FROM sites;
