-- Phase 14 PR2: Global content tags + per-bundle tagging.
--
-- Mirrors the Notes tag pattern (migration 023): a single table of tag
-- definitions with renameable + recolourable built-ins, plus a many-to-many
-- link table from bundles. Tag definitions are global (not persona-scoped)
-- so the same chip can show up on a CoC bundle and a PoA bundle.
--
-- Default seed leans on a pastel-ish palette so the chips look cute in
-- the bundle forms without further user editing. All 8 defaults are
-- is_builtin=1 — Sallie can rename + recolour them but not delete (same
-- contract as notes built-in tags).

CREATE TABLE IF NOT EXISTS content_tags_def (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL UNIQUE,
    color       TEXT NOT NULL,                  -- hex '#RRGGBB'
    sort_order  INTEGER NOT NULL DEFAULT 0,
    is_builtin  INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS bundle_tag_links (
    bundle_uid  TEXT NOT NULL REFERENCES bundles(uid) ON DELETE CASCADE,
    tag_id      INTEGER NOT NULL REFERENCES content_tags_def(id) ON DELETE CASCADE,
    PRIMARY KEY (bundle_uid, tag_id)
);
CREATE INDEX IF NOT EXISTS bundle_tag_links_by_tag ON bundle_tag_links(tag_id);

INSERT OR IGNORE INTO content_tags_def (name, color, sort_order, is_builtin) VALUES
    ('tits',      '#FCA5A5', 1, 1),  -- soft coral
    ('pantyhose', '#DDD6FE', 2, 1),  -- lilac
    ('panties',   '#F9A8D4', 3, 1),  -- bubble-gum pink
    ('face',      '#FBA17C', 4, 1),  -- peach
    ('ass',       '#FDA4AF', 5, 1),  -- rose
    ('feet',      '#A7F3D0', 6, 1),  -- mint
    ('flats',     '#BAE6FD', 7, 1),  -- sky
    ('heels',     '#FCA5A5', 8, 1);  -- cherry-blossom
