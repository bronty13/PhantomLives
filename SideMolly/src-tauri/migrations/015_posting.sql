-- Phase 7 — posting primitives.
--
-- Two tables for the per-bundle posting checklist + the user's own
-- platform list (independent of Molly; decision #12 in PLAN.md §12).
--
--   posting_targets   — the platforms the user posts to. Each row
--                       has a name, URL template (with {uid}/{title}/
--                       {persona} variables), a kind that filters
--                       which bundle types show this target
--                       (content/custom/fansite/any), and presentation
--                       fields (color, icon, position) for the per-
--                       bundle Post tab cards.
--
--   bundle_postings   — one row per (bundle, target) pair, tracking
--                       state (pending/scheduled/posted/skipped),
--                       the URL the user actually posted to, any
--                       free-text body override, and notes. UPSERT on
--                       (bundle_uid, target_id) so toggling state is
--                       a no-allocation roundtrip.
--
-- No seed rows — the user adds their own platforms via Settings →
-- Platforms (decision #12: SideMolly's platform list is independent
-- from Molly's).

CREATE TABLE IF NOT EXISTS posting_targets (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    name          TEXT NOT NULL UNIQUE,
    url_template  TEXT NOT NULL DEFAULT '',
    persona_code  TEXT,                                      -- nullable
    color         TEXT NOT NULL DEFAULT '#888888',
    icon          TEXT NOT NULL DEFAULT '🎯',
    position      INTEGER NOT NULL DEFAULT 100,
    kind          TEXT NOT NULL DEFAULT 'any'
                  CHECK(kind IN ('content','custom','fansite','any')),
    enabled       INTEGER NOT NULL DEFAULT 1,
    created_at    TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_posting_targets_position ON posting_targets(position);

CREATE TABLE IF NOT EXISTS bundle_postings (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    bundle_uid     TEXT NOT NULL REFERENCES bundles(uid) ON DELETE CASCADE,
    target_id      INTEGER NOT NULL REFERENCES posting_targets(id) ON DELETE CASCADE,
    state          TEXT NOT NULL DEFAULT 'pending'
                   CHECK(state IN ('pending','scheduled','posted','skipped')),
    posted_at      TEXT,
    posted_url     TEXT,
    body_override  TEXT,
    notes          TEXT,
    created_at     TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at     TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(bundle_uid, target_id)
);

CREATE INDEX IF NOT EXISTS idx_bundle_postings_bundle ON bundle_postings(bundle_uid);
