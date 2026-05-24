-- Phase 8 / Phase 10 — extend bundle_postings with per-platform asset
-- selection (Content runner) and fansite-day binding (FanSite runner).
--
-- Both columns are nullable + JSON-blob respectively so existing rows
-- from Phase 7 round-trip cleanly without backfill.
--
--   selected_assets_json — JSON array of {kind, path, label} the
--                          user selected to ship to this platform
--                          (Content runner; null = "use all/default"
--                          in non-Content contexts). Phase 8 only
--                          surfaces this for content bundles.
--
--   fansite_day          — 1..=31 day-of-month for FanSite bundles
--                          (Phase 10). One bundle_postings row per
--                          (bundle, target, day) so the FanSite
--                          calendar can track each day independently.
--                          NULL for Content / Custom postings.

ALTER TABLE bundle_postings
    ADD COLUMN selected_assets_json TEXT NOT NULL DEFAULT '[]';

ALTER TABLE bundle_postings
    ADD COLUMN fansite_day INTEGER;

-- Replace the old (bundle_uid, target_id) uniqueness with a tuple
-- including fansite_day so a FanSite bundle can have N rows for the
-- same target (one per day). SQLite can't ALTER constraints in place,
-- so we rebuild the table.
--
-- (Phase 7's UNIQUE(bundle_uid, target_id) was correct for Content +
--  Custom — neither type has per-day state.)

PRAGMA foreign_keys = OFF;

CREATE TABLE bundle_postings_new (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    bundle_uid     TEXT NOT NULL REFERENCES bundles(uid) ON DELETE CASCADE,
    target_id      INTEGER NOT NULL REFERENCES posting_targets(id) ON DELETE CASCADE,
    state          TEXT NOT NULL DEFAULT 'pending'
                   CHECK(state IN ('pending','scheduled','posted','skipped')),
    posted_at             TEXT,
    posted_url            TEXT,
    body_override         TEXT,
    notes                 TEXT,
    selected_assets_json  TEXT NOT NULL DEFAULT '[]',
    fansite_day           INTEGER,
    created_at            TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at            TEXT NOT NULL DEFAULT (datetime('now')),
    -- Composite key includes the day so per-day FanSite rows coexist.
    UNIQUE(bundle_uid, target_id, fansite_day)
);

INSERT INTO bundle_postings_new
    (id, bundle_uid, target_id, state, posted_at, posted_url,
     body_override, notes, selected_assets_json, fansite_day,
     created_at, updated_at)
SELECT id, bundle_uid, target_id, state, posted_at, posted_url,
       body_override, notes, selected_assets_json, fansite_day,
       created_at, updated_at
FROM bundle_postings;

DROP TABLE bundle_postings;
ALTER TABLE bundle_postings_new RENAME TO bundle_postings;

CREATE INDEX IF NOT EXISTS idx_bundle_postings_bundle ON bundle_postings(bundle_uid);
CREATE INDEX IF NOT EXISTS idx_bundle_postings_fansite
    ON bundle_postings(bundle_uid, fansite_day);

PRAGMA foreign_keys = ON;
