-- Phase 15 PR1: Reddit ops — subreddits, post log, captions.
--
-- All three tables are persona-scoped (persona_code references personas).
-- NULL persona_code means "global / not yet assigned" — kept available
-- for future cross-persona moves but the default UI always sets it.
--
-- Subreddit categories reuse the existing content_tags_def taxonomy so
-- the same color-coded chips show up on bundles, clips, and now subs.
-- The HTML reference set used 5 categories not yet in the seed; we add
-- them here as built-in (Sallie can rename/recolor but not delete).
-- Pastel-ish hexes picked to complement the existing 8 body-part tags.

INSERT OR IGNORE INTO content_tags_def (name, color, sort_order, is_builtin) VALUES
    ('bbw',           '#F472B6',  9, 1),  -- hot pink
    ('hairy',         '#86EFAC', 10, 1),  -- mint
    ('fetish',        '#A5B4FC', 11, 1),  -- periwinkle
    ('redhead',       '#FB923C', 12, 1),  -- amber
    ('general curvy', '#FBCFE8', 13, 1);  -- baby pink

CREATE TABLE IF NOT EXISTS subreddits (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    persona_code    TEXT REFERENCES personas(code) ON DELETE SET NULL,
    name            TEXT NOT NULL,                       -- without leading "r/"
    tag_id          INTEGER REFERENCES content_tags_def(id) ON DELETE SET NULL,
    verified        INTEGER NOT NULL DEFAULT 0 CHECK (verified IN (0, 1)),
    karma_req       TEXT NOT NULL DEFAULT '',            -- e.g. "50+", "100+"
    rotation        TEXT NOT NULL DEFAULT 'fresh'
                    CHECK (rotation IN ('fresh', 'soon', 'wait')),
    last_posted_at  TEXT,                                -- ISO date YYYY-MM-DD
    notes           TEXT NOT NULL DEFAULT '',
    starred         INTEGER NOT NULL DEFAULT 0 CHECK (starred IN (0, 1)),
    sort_order      INTEGER NOT NULL DEFAULT 0,
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);
-- Allow same name across personas, forbid same name twice for one persona.
CREATE UNIQUE INDEX IF NOT EXISTS subreddits_unique_name_per_persona
    ON subreddits(persona_code, LOWER(name));
CREATE INDEX IF NOT EXISTS subreddits_by_persona  ON subreddits(persona_code);
CREATE INDEX IF NOT EXISTS subreddits_by_rotation ON subreddits(rotation);
CREATE INDEX IF NOT EXISTS subreddits_by_tag      ON subreddits(tag_id);

CREATE TABLE IF NOT EXISTS subreddit_posts (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    persona_code    TEXT REFERENCES personas(code) ON DELETE SET NULL,
    -- Nullable so a post can be logged ad-hoc against a sub that hasn't
    -- been added to the tracker yet. UI sets it whenever possible.
    subreddit_id    INTEGER REFERENCES subreddits(id) ON DELETE SET NULL,
    -- Snapshot of the sub's name at post time so display survives
    -- subreddit row deletion or rename.
    subreddit_name  TEXT NOT NULL,
    tag_id          INTEGER REFERENCES content_tags_def(id) ON DELETE SET NULL,
    posted_date     TEXT NOT NULL,                       -- ISO date YYYY-MM-DD
    notes           TEXT NOT NULL DEFAULT '',
    created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS subreddit_posts_by_date    ON subreddit_posts(posted_date);
CREATE INDEX IF NOT EXISTS subreddit_posts_by_persona ON subreddit_posts(persona_code, posted_date);
CREATE INDEX IF NOT EXISTS subreddit_posts_by_sub     ON subreddit_posts(subreddit_id);

CREATE TABLE IF NOT EXISTS captions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    persona_code    TEXT REFERENCES personas(code) ON DELETE SET NULL,
    text            TEXT NOT NULL,
    tag_id          INTEGER REFERENCES content_tags_def(id) ON DELETE SET NULL,
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS captions_by_persona ON captions(persona_code);
CREATE INDEX IF NOT EXISTS captions_by_tag     ON captions(tag_id);

-- 33 default subreddits for CoC ("Curse of Curves" = the HTML's "Curves"
-- persona). The tag_id is resolved at insert time via subquery against
-- content_tags_def so Sallie's recolours / renames don't break referential
-- integrity. PoA + Sa start empty.
INSERT INTO subreddits (persona_code, name, tag_id, verified, karma_req, rotation, last_posted_at, notes, starred) VALUES
  ('CoC', 'SFWredheads',          (SELECT id FROM content_tags_def WHERE name='redhead'),       0, '50+',  'fresh', NULL, 'SFW only',                    0),
  ('CoC', 'thickredheads',        (SELECT id FROM content_tags_def WHERE name='redhead'),       0, '50+',  'fresh', NULL, '',                            0),
  ('CoC', 'armpitfetish',         (SELECT id FROM content_tags_def WHERE name='fetish'),        0, '100+', 'fresh', NULL, 'Fetish-specific only',        0),
  ('CoC', 'bbwtits',              (SELECT id FROM content_tags_def WHERE name='bbw'),           0, '50+',  'fresh', NULL, '',                            0),
  ('CoC', 'bigbelliesandhangers', (SELECT id FROM content_tags_def WHERE name='bbw'),           0, '50+',  'fresh', NULL, '',                            0),
  ('CoC', 'tortas',               (SELECT id FROM content_tags_def WHERE name='general curvy'), 0, '50+',  'fresh', NULL, 'Latina-leaning — check fit',  0),
  ('CoC', 'bbwchubbyasses',       (SELECT id FROM content_tags_def WHERE name='bbw'),           0, '50+',  'fresh', NULL, '',                            0),
  ('CoC', 'redheadsinblack',      (SELECT id FROM content_tags_def WHERE name='redhead'),       0, '50+',  'fresh', NULL, 'Outfit/aesthetic focused',    0),
  ('CoC', 'redheadmilfs',         (SELECT id FROM content_tags_def WHERE name='redhead'),       0, '100+', 'fresh', NULL, '',                            0),
  ('CoC', 'chubbywomen',          (SELECT id FROM content_tags_def WHERE name='general curvy'), 0, '50+',  'fresh', NULL, '',                            0),
  ('CoC', 'bbwselfies',           (SELECT id FROM content_tags_def WHERE name='bbw'),           0, '50+',  'fresh', NULL, 'Selfie format works best',    0),
  ('CoC', 'bbw',                  (SELECT id FROM content_tags_def WHERE name='bbw'),           0, '100+', 'fresh', NULL, 'High traffic — competitive',  1),
  ('CoC', 'lovebbw',              (SELECT id FROM content_tags_def WHERE name='bbw'),           0, '50+',  'fresh', NULL, '',                            0),
  ('CoC', 'bbw_nude',             (SELECT id FROM content_tags_def WHERE name='bbw'),           0, '100+', 'fresh', NULL, 'Verify req. likely',          0),
  ('CoC', 'bbw_worldwide',        (SELECT id FROM content_tags_def WHERE name='bbw'),           0, '50+',  'fresh', NULL, '',                            0),
  ('CoC', 'onlysfansbbwluv',      (SELECT id FROM content_tags_def WHERE name='bbw'),           0, '50+',  'fresh', NULL, 'Promo-friendly',              0),
  ('CoC', 'chubby',               (SELECT id FROM content_tags_def WHERE name='general curvy'), 0, '50+',  'fresh', NULL, '',                            0),
  ('CoC', 'bbwtummy',             (SELECT id FROM content_tags_def WHERE name='bbw'),           0, '50+',  'fresh', NULL, 'Tummy-focused',               0),
  ('CoC', 'thickpawglovers',      (SELECT id FROM content_tags_def WHERE name='general curvy'), 0, '50+',  'fresh', NULL, '',                            0),
  ('CoC', 'bigboobsunlimited',    (SELECT id FROM content_tags_def WHERE name='bbw'),           0, '50+',  'fresh', NULL, '',                            0),
  ('CoC', 'bbwleggings',          (SELECT id FROM content_tags_def WHERE name='bbw'),           0, '50+',  'fresh', NULL, 'Leggings content',            0),
  ('CoC', 'bbwchubbytits',        (SELECT id FROM content_tags_def WHERE name='bbw'),           0, '50+',  'fresh', NULL, '',                            0),
  ('CoC', 'big_girl_big_boobs',   (SELECT id FROM content_tags_def WHERE name='bbw'),           0, '50+',  'fresh', NULL, '',                            0),
  ('CoC', 'heavyknockers',        (SELECT id FROM content_tags_def WHERE name='bbw'),           0, '50+',  'fresh', NULL, '',                            0),
  ('CoC', 'bbwsoftworld',         (SELECT id FROM content_tags_def WHERE name='bbw'),           0, '50+',  'fresh', NULL, 'Softer aesthetic',            0),
  ('CoC', 'tigerstripes',         (SELECT id FROM content_tags_def WHERE name='general curvy'), 0, '50+',  'fresh', NULL, 'Stretch mark focused',        0),
  ('CoC', 'fupaluv',              (SELECT id FROM content_tags_def WHERE name='bbw'),           0, '50+',  'fresh', NULL, '',                            0),
  ('CoC', 'bbwperfection',        (SELECT id FROM content_tags_def WHERE name='bbw'),           0, '50+',  'fresh', NULL, '',                            0),
  ('CoC', 'stretchmarks',         (SELECT id FROM content_tags_def WHERE name='general curvy'), 0, '50+',  'fresh', NULL, 'Warm captions work well',     0),
  ('CoC', 'panthose',             (SELECT id FROM content_tags_def WHERE name='fetish'),        0, '50+',  'fresh', NULL, 'Pantyhose fetish',            0),
  ('CoC', 'hairypussyonly',       (SELECT id FROM content_tags_def WHERE name='hairy'),         0, '100+', 'fresh', NULL, '',                            0),
  ('CoC', 'hairypie',             (SELECT id FROM content_tags_def WHERE name='hairy'),         0, '100+', 'fresh', NULL, '',                            0),
  ('CoC', 'bbwhairypussyworld',   (SELECT id FROM content_tags_def WHERE name='hairy'),         0, '100+', 'fresh', NULL, 'Verify likely',               0);
