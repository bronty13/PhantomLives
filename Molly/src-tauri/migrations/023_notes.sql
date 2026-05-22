-- Phase 13: Notes — Apple-Notes-style organiser. Folders (unlimited
-- nesting via self-referencing parent_id) hold notes. Notes carry a
-- TipTap HTML body + a denormalised plaintext extract used for the
-- regex Find feature. Many-to-many tags with user-editable colours.
-- Per-note overrides for font + paper colour fall back to app-wide
-- defaults stored in app_settings (key 'notes.defaultFont', 'notes.
-- defaultPaperColor'). Attachments mirror the MollysLog pattern.

CREATE TABLE IF NOT EXISTS note_folders (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    parent_id   INTEGER REFERENCES note_folders(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS note_folders_by_parent ON note_folders(parent_id, sort_order);

CREATE TABLE IF NOT EXISTS notes (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    folder_id       INTEGER REFERENCES note_folders(id) ON DELETE CASCADE,
    title           TEXT NOT NULL DEFAULT 'Untitled',
    content_html    TEXT NOT NULL DEFAULT '',
    content_text    TEXT NOT NULL DEFAULT '',   -- plaintext, for Find scanning
    font_family     TEXT,                        -- NULL = use app default
    paper_color     TEXT,                        -- NULL = use app default
    sort_order      INTEGER NOT NULL DEFAULT 0,
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now')),
    last_edited_at  TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS notes_by_folder ON notes(folder_id, sort_order);
CREATE INDEX IF NOT EXISTS notes_by_updated ON notes(updated_at DESC);

CREATE TABLE IF NOT EXISTS note_tags_def (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL UNIQUE,
    color       TEXT NOT NULL,                   -- hex like '#f9a8d4'
    sort_order  INTEGER NOT NULL DEFAULT 0,
    is_builtin  INTEGER NOT NULL DEFAULT 0,      -- built-ins are recolour/rename-able but not delete-able
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS note_tag_links (
    note_id  INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    tag_id   INTEGER NOT NULL REFERENCES note_tags_def(id) ON DELETE CASCADE,
    PRIMARY KEY (note_id, tag_id)
);
CREATE INDEX IF NOT EXISTS note_tag_links_by_tag ON note_tag_links(tag_id);

CREATE TABLE IF NOT EXISTS note_attachments (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    note_id         INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    filename        TEXT NOT NULL,           -- on-disk filename (UUID-prefixed)
    original_name   TEXT NOT NULL,           -- what the user dragged in
    mime            TEXT NOT NULL DEFAULT '',
    size_bytes      INTEGER NOT NULL DEFAULT 0,
    created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS note_attachments_by_note ON note_attachments(note_id);

-- Seed the six default tags. Soft, pretty colours from the persona
-- palette. Renameable + recolourable by the user but not deletable.
INSERT OR IGNORE INTO note_tags_def (name, color, sort_order, is_builtin) VALUES
    ('ideas',         '#f9a8d4', 1, 1),  -- pink
    ('plans',         '#a5b4fc', 2, 1),  -- indigo
    ('roadmap',       '#86efac', 3, 1),  -- mint
    ('promo',         '#fcd34d', 4, 1),  -- butter
    ('content',       '#fda4af', 5, 1),  -- rose
    ('bettereveryday','#c4b5fd', 6, 1);  -- lavender

-- App-wide defaults live in app_settings. Seeded here so the Notes
-- view can render immediately on first launch without a save.
INSERT OR IGNORE INTO app_settings (key, value) VALUES
    ('notes.defaultFont',        'Paper Daisy'),
    ('notes.defaultPaperColor',  '#fdfcf8');
