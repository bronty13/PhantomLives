-- Phase 1: sites table. Sites are organized by persona but the same
-- site name (e.g. NiteFlirt) can recur under different personas with
-- different usernames. The `login_group` column lets us mark sites that
-- share credentials (e.g. OnlyFans CoC ↔ PoA) so the UI can hint at it.
CREATE TABLE IF NOT EXISTS sites (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    persona_code    TEXT NOT NULL REFERENCES personas(code) ON DELETE CASCADE,
    name            TEXT NOT NULL,                -- display name, e.g. "NiteFlirt"
    short_code      TEXT NOT NULL,                -- e.g. "nf", "c4s"
    url             TEXT NOT NULL,
    username        TEXT NOT NULL DEFAULT '',
    note            TEXT NOT NULL DEFAULT '',     -- free-form ("Alice", "shared OF login")
    color           TEXT NOT NULL,                -- #RRGGBB
    login_group     TEXT,                         -- nullable; rows with same value share credentials
    sort_order      INTEGER NOT NULL DEFAULT 0,
    archived        INTEGER NOT NULL DEFAULT 0,
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS sites_by_persona ON sites(persona_code, sort_order);
CREATE INDEX IF NOT EXISTS sites_by_login_group ON sites(login_group);

-- ---- CoC seed (5 sites) -------------------------------------------------
INSERT OR IGNORE INTO sites
    (persona_code, name, short_code, url, username, note, color, login_group, sort_order)
VALUES
    ('CoC', 'Clips4Sale',     'c4s', 'https://www.clips4sale.com/account/login', 'curseofcurves',              '',                              '#FF8FB8', NULL,        10),
    ('CoC', 'NiteFlirt',      'nf',  'https://www.niteflirt.com',                'Curse of curves',            '',                              '#E55A8A', NULL,        20),
    ('CoC', 'ManyVids',       'mv',  'https://www.manyvids.com',                 'TheCurseOfCurves',           '',                              '#FF99CC', NULL,        30),
    ('CoC', 'All Things Worn','atw', 'https://www.allthingsworn.com',            'curseofcurvesllc@gmail.com', '',                              '#D46BAA', NULL,        40),
    ('CoC', 'OnlyFans',       'of',  'https://onlyfans.com',                     'Curseofcurvesllc@gmail.com', 'Shared login — switch to CoC store after sign-in.', '#00AFF0', 'of-shared', 50);

-- ---- PoA seed (13 sites) ------------------------------------------------
INSERT OR IGNORE INTO sites
    (persona_code, name, short_code, url, username, note, color, login_group, sort_order)
VALUES
    ('PoA', 'Clips4Sale',                 'c4s',  'https://clips4sale.com',             'Princessaddiction',                       '',                                                      '#C8102E', NULL,        10),
    ('PoA', 'IWantClips',                 'iwc',  'https://iwantclips.com',             'Princessofrealaddiction@gmail.com',        '',                                                      '#9B1D3A', NULL,        20),
    ('PoA', 'NiteFlirt',                  'nf',   'https://www.niteflirt.com',          'PrincessOfAddiction',                      '',                                                      '#7D1431', NULL,        30),
    ('PoA', 'LoyalFans',                  'lf',   'https://loyalfans.com',              'Princessofrealaddiction@gmail.com',        '',                                                      '#5E0F25', NULL,        40),
    ('PoA', 'OnlyFans',                   'of',   'https://onlyfans.com',               'Curseofcurvesllc@gmail.com',               'Shared login — switch to PoA store after sign-in.',     '#00AFF0', 'of-shared', 50),
    ('PoA', 'FeetFinder',                 'ff',   'https://www.feetfinder.com',         'amazingsallie@yahoo.com',                  '',                                                      '#FF4D4D', NULL,        60),
    ('PoA', 'MyFreeCams',                 'mfc',  'https://www.myfreecams.com',         'Curseofcurves',                            '',                                                      '#3A0A18', NULL,        70),
    ('PoA', 'Imgur',                      'img',  'https://imgur.com',                  'imagine',                                  '',                                                      '#B33A66', NULL,        80),
    ('PoA', 'Talktome',                   'ttm',  'https://www.talktome.com',           'playfuldesiremfc@hotmail.com',             '',                                                      '#A22E58', NULL,        90),
    ('PoA', 'NiteFlirt — Alice',          'nfa',  'https://www.niteflirt.com',          'cute alice',                               'Alice persona on NF.',                                  '#E45B7E', NULL,        100),
    ('PoA', 'NiteFlirt — Taylor',         'nft',  'https://www.niteflirt.com',          'TaylorThe18yrTease',                       'Taylor persona on NF.',                                 '#D24F71', NULL,        110),
    ('PoA', 'NiteFlirt — sluttysecrets',  'nfs',  'https://www.niteflirt.com',          'sluttysecrets',                            'sluttysecrets persona on NF.',                          '#BF4264', NULL,        120);

-- Sa has no preloaded sites per spec; will be added from the UI.
