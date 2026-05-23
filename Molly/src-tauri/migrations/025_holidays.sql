-- Phase 14 PR1: Holidays on the Calendar.
--
-- Define recurring holidays once (either as a fixed Month/Day or as the
-- "Nth weekday of Month" — Memorial Day, MLK Day, etc.). Calendar view
-- resolves them to concrete ISO dates per visible month and renders as
-- themed pills (red/white/blue for 4th of July, red/green for Christmas,
-- etc.). Disabling instead of deleting preserves the seeded defaults so
-- a user can come back later.

CREATE TABLE IF NOT EXISTS holidays (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    name            TEXT NOT NULL,
    kind            TEXT NOT NULL CHECK (kind IN ('fixed', 'nth_weekday')),
    month           INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
    day             INTEGER,  -- for 'fixed': 1..31
    weekday         INTEGER,  -- for 'nth_weekday': 0=Sun .. 6=Sat
    nth             INTEGER,  -- 1..4, or -1 = last
    color_primary   TEXT NOT NULL,        -- hex "#RRGGBB"
    color_secondary TEXT,                 -- optional second band for striped pills
    color_text      TEXT NOT NULL,        -- hex "#RRGGBB" — readable over primary
    emoji           TEXT,                 -- optional single-glyph icon
    enabled         INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
    source          TEXT NOT NULL DEFAULT 'custom' CHECK (source IN ('us_default', 'custom')),
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_holidays_month ON holidays(month);

-- Display toggle. Default ON so the seed set lights up immediately.
INSERT OR IGNORE INTO app_settings (key, value) VALUES
    ('calendar.holidaysEnabled', '1');

-- US extended default set. Color choices lean on commonly-associated
-- pairings (red+green for Christmas, red+white+blue treatment for
-- patriotic holidays — frontend renders a two-color gradient when a
-- secondary is present; the white stripe comes from a CSS overlay).
INSERT INTO holidays (name, kind, month, day, weekday, nth, color_primary, color_secondary, color_text, emoji, source) VALUES
    ('New Year''s Day',       'fixed',       1,  1, NULL, NULL, '#D4AF37', '#C0C0C0', '#1A1A1A', '🎉', 'us_default'),
    ('MLK Day',               'nth_weekday', 1,  NULL, 1,  3,   '#6B46C1', '#D4AF37', '#FFFFFF', '✊',  'us_default'),
    ('Valentine''s Day',      'fixed',       2, 14, NULL, NULL, '#E11D48', '#FBCFE8', '#FFFFFF', '💝', 'us_default'),
    ('Presidents'' Day',      'nth_weekday', 2,  NULL, 1,  3,   '#B91C1C', '#1E3A8A', '#FFFFFF', '🇺🇸', 'us_default'),
    ('St. Patrick''s Day',    'fixed',       3, 17, NULL, NULL, '#16A34A', '#FBBF24', '#FFFFFF', '🍀', 'us_default'),
    ('Mother''s Day',         'nth_weekday', 5,  NULL, 0,  2,   '#EC4899', '#FBCFE8', '#FFFFFF', '💐', 'us_default'),
    ('Memorial Day',          'nth_weekday', 5,  NULL, 1, -1,   '#B91C1C', '#1E3A8A', '#FFFFFF', '🇺🇸', 'us_default'),
    ('Father''s Day',         'nth_weekday', 6,  NULL, 0,  3,   '#2563EB', '#FCD34D', '#FFFFFF', '👔', 'us_default'),
    ('Juneteenth',            'fixed',       6, 19, NULL, NULL, '#B91C1C', '#16A34A', '#FFFFFF', '✊🏿', 'us_default'),
    ('Independence Day',      'fixed',       7,  4, NULL, NULL, '#B91C1C', '#1E3A8A', '#FFFFFF', '🎆', 'us_default'),
    ('Labor Day',             'nth_weekday', 9,  NULL, 1,  1,   '#B91C1C', '#1E3A8A', '#FFFFFF', '🇺🇸', 'us_default'),
    ('Columbus Day',          'nth_weekday', 10, NULL, 1,  2,   '#7C2D12', '#FBBF24', '#FFFFFF', '🧭', 'us_default'),
    ('Halloween',             'fixed',      10, 31, NULL, NULL, '#EA580C', '#1A1A1A', '#FFFFFF', '🎃', 'us_default'),
    ('Veterans Day',          'fixed',      11, 11, NULL, NULL, '#B91C1C', '#1E3A8A', '#FFFFFF', '🎖️', 'us_default'),
    ('Thanksgiving',          'nth_weekday', 11, NULL, 4,  4,   '#C2410C', '#92400E', '#FFFFFF', '🦃', 'us_default'),
    ('Christmas Eve',         'fixed',      12, 24, NULL, NULL, '#DC2626', '#15803D', '#FFFFFF', '🎄', 'us_default'),
    ('Christmas Day',         'fixed',      12, 25, NULL, NULL, '#DC2626', '#15803D', '#FFFFFF', '🎁', 'us_default'),
    ('New Year''s Eve',       'fixed',      12, 31, NULL, NULL, '#D4AF37', '#C0C0C0', '#1A1A1A', '🥂', 'us_default');
