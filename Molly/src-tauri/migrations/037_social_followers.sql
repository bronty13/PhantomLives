-- v1.25.0 — Per-platform daily FOLLOWER COUNT tracking.
--
-- Sallie types each platform's follower number each day; Molly shows
-- history, a line graph, trend, and a forecast (ETA to a goal).
--
-- SNAPSHOT semantics — NOT increments like social_post_drops. One
-- absolute follower number per (persona, platform, day), written by
-- UPSERT: the latest write for a given day wins. Editing today re-saves;
-- entering a past date backfills. A missing day is a GAP (unknown), NOT
-- zero — do not aggregate with COUNT(*). Counts are persona-scoped like
-- the piggy bank; the "ALL" view combines across personas in the read
-- layer (each persona's latest snapshot), never here.

-- 1) Per-platform optional follower GOAL (milestone target, e.g. 10000).
--    Column on social_platforms, mirroring how migration 035 added
--    daily_goal. 0 means "no goal set" → no forecast ETA, no celebration.
ALTER TABLE social_platforms ADD COLUMN follower_goal INTEGER NOT NULL DEFAULT 0;

-- 2) The daily snapshot table. UNIQUE(persona, platform, date) powers the
--    UPSERT. NOTE: SQLite treats NULL as distinct in UNIQUE, so this does
--    not constrain NULL-persona rows — that's intentional: we NEVER write
--    a NULL persona here (the Rust upsert rejects it). "ALL" is a read-time
--    aggregation only. Do not "fix" this into an ON CONFLICT on NULL.
CREATE TABLE IF NOT EXISTS social_follower_counts (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    persona_code   TEXT REFERENCES personas(code) ON DELETE CASCADE,
    platform_id    INTEGER NOT NULL REFERENCES social_platforms(id) ON DELETE CASCADE,
    count_date     TEXT NOT NULL,                          -- YYYY-MM-DD, local
    follower_count INTEGER NOT NULL,                       -- absolute snapshot, >= 0
    source         TEXT NOT NULL DEFAULT 'manual',         -- future: 'api', 'import'
    recorded_at    TEXT NOT NULL DEFAULT (datetime('now')),-- UTC ISO 8601
    UNIQUE(persona_code, platform_id, count_date)
);

CREATE INDEX IF NOT EXISTS social_follower_counts_by_persona_platform_date
    ON social_follower_counts(persona_code, platform_id, count_date);
CREATE INDEX IF NOT EXISTS social_follower_counts_by_platform_date
    ON social_follower_counts(platform_id, count_date);
