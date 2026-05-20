-- Phase 0: personas + app_settings.
-- Personas are the single most important entity in Molly. They drive
-- color theming and act as a filter across the whole app.

CREATE TABLE IF NOT EXISTS personas (
    code              TEXT PRIMARY KEY,        -- short identifier, e.g. "CoC"
    name              TEXT NOT NULL,           -- display name, e.g. "Curse Of Curves"
    description       TEXT NOT NULL DEFAULT '',
    primary_color     TEXT NOT NULL,           -- "#RRGGBB"
    secondary_color   TEXT NOT NULL,
    tint_color        TEXT NOT NULL,
    accent_color      TEXT NOT NULL,
    text_color        TEXT NOT NULL,
    sort_order        INTEGER NOT NULL DEFAULT 0,
    archived          INTEGER NOT NULL DEFAULT 0,
    created_at        TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at        TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Single-row key/value table for app-wide settings (theme prefs, last
-- active persona, etc.). Avoids a forest of single-row tables.
CREATE TABLE IF NOT EXISTS app_settings (
    key     TEXT PRIMARY KEY,
    value   TEXT NOT NULL
);

-- Backup-related settings live in OS preferences (UserDefaults on Mac,
-- Tauri store on Windows) rather than the DB, since the backup must run
-- before the DB is necessarily writable. See backup.rs::Settings.

-- Default persona seed. Colors picked to be cute and to recolor the UI
-- recognizably for each persona. Updatable from Settings.
INSERT OR IGNORE INTO personas
    (code, name, description, primary_color, secondary_color, tint_color, accent_color, text_color, sort_order)
VALUES
    ('CoC', 'Curse Of Curves',     'Baby-pink dreamy persona.',                            '#FFC0CB', '#FFE4F0', '#FFF0F6', '#E5527A', '#5B2540', 1),
    ('PoA', 'Princess of Addiction','Red & black bratty princess persona.',                 '#C8102E', '#1A1A1A', '#FFE1E1', '#FF4D4D', '#1A1A1A', 2),
    ('Sa',  'Sheer Attraction',    'Tan/cream soft-glam persona.',                          '#D2B48C', '#F5E9D7', '#FBF5EA', '#8B6F47', '#3A2F22', 3);
