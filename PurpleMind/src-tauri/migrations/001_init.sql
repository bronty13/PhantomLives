-- PurpleMind initial schema.
--
-- A mindmap is a `maps` row plus its `nodes` and `edges`. This maps
-- directly onto React Flow's node/edge model, so cross-links beyond a
-- strict parent/child tree are representable. Positions are stored in
-- flow coordinates; the per-map viewport remembers the last pan/zoom.
--
-- IMMUTABLE once shipped (CLAUDE.md). Schema changes go in a NEW
-- migration (002_*.sql) — never edit this file's bytes.

-- App-wide key/value settings (e.g. the export output directory override).
-- Single-row-per-key avoids a forest of one-row tables. (Backup settings
-- live separately in backup-settings.json next to the DB.)
CREATE TABLE IF NOT EXISTS app_settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

INSERT OR IGNORE INTO app_settings (key, value)
VALUES ('export_dir', ''),              -- empty = default ~/Downloads/PurpleMind/
       ('schema_version_intro', '1');

-- One row per mindmap.
CREATE TABLE IF NOT EXISTS maps (
    id            TEXT PRIMARY KEY,
    title         TEXT NOT NULL,
    created_at    TEXT NOT NULL,
    updated_at    TEXT NOT NULL,
    viewport_x    REAL NOT NULL DEFAULT 0,
    viewport_y    REAL NOT NULL DEFAULT 0,
    viewport_zoom REAL NOT NULL DEFAULT 1
);

-- Nodes belong to a map; deleting a map cascades to its nodes.
CREATE TABLE IF NOT EXISTS nodes (
    id         TEXT PRIMARY KEY,
    map_id     TEXT NOT NULL REFERENCES maps(id) ON DELETE CASCADE,
    label      TEXT NOT NULL DEFAULT '',
    x          REAL NOT NULL,
    y          REAL NOT NULL,
    color      TEXT,                    -- nullable; NULL = brand default
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_nodes_map ON nodes(map_id);

-- Edges connect two nodes within a map. Deleting either endpoint (or the
-- map) cascades the edge away.
CREATE TABLE IF NOT EXISTS edges (
    id        TEXT PRIMARY KEY,
    map_id    TEXT NOT NULL REFERENCES maps(id) ON DELETE CASCADE,
    source_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    target_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_edges_map ON edges(map_id);
CREATE INDEX IF NOT EXISTS idx_edges_source ON edges(source_id);
CREATE INDEX IF NOT EXISTS idx_edges_target ON edges(target_id);
