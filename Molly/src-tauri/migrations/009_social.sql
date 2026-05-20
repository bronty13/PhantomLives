-- Phase 7: social promotion tracker.
--
-- Two tables for v1:
--   * social_platforms — the venues (Reddit, X, Instagram, …). Editable
--     from Settings → Platforms; each carries a display color + emoji.
--   * social_promos — the actual promo posts. Each row points at a
--     platform and a persona, optionally links to a clip, and carries
--     the post URL plus title/body + rich-text notes.
--
-- v2 (deferred) — add a social_promo_metrics table for views/likes/DMs
-- snapshots over time so we can correlate promos with revenue.

CREATE TABLE IF NOT EXISTS social_platforms (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL UNIQUE,
    short_code  TEXT NOT NULL,
    icon        TEXT NOT NULL DEFAULT '📣',
    color       TEXT NOT NULL,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    archived    INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS social_promos (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    persona_code    TEXT REFERENCES personas(code) ON DELETE SET NULL,
    platform_id     INTEGER NOT NULL REFERENCES social_platforms(id) ON DELETE CASCADE,
    handle          TEXT NOT NULL DEFAULT '',          -- e.g. "u/curseofcurves" or "@coc"
    posted_at       TEXT NOT NULL,                      -- ISO datetime
    url             TEXT NOT NULL DEFAULT '',
    title           TEXT NOT NULL DEFAULT '',
    body            TEXT NOT NULL DEFAULT '',
    clip_id         TEXT REFERENCES clips(id) ON DELETE SET NULL,
    notes_html      TEXT NOT NULL DEFAULT '',
    archived        INTEGER NOT NULL DEFAULT 0,
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS social_promos_by_posted   ON social_promos(posted_at);
CREATE INDEX IF NOT EXISTS social_promos_by_persona  ON social_promos(persona_code);
CREATE INDEX IF NOT EXISTS social_promos_by_platform ON social_promos(platform_id);
CREATE INDEX IF NOT EXISTS social_promos_by_clip     ON social_promos(clip_id);

-- Default platforms — the four most relevant for content-creator
-- promo work. All editable from Settings → Platforms.
INSERT OR IGNORE INTO social_platforms (id, name, short_code, icon, color, sort_order) VALUES
    (1, 'Reddit',    'rdt', '🐶', '#FF4500', 10),
    (2, 'X',         'x',   '✖️', '#000000', 20),
    (3, 'Instagram', 'ig',  '📸', '#E1306C', 30),
    (4, 'TikTok',    'tt',  '🎵', '#69C9D0', 40);
