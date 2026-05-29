-- v1.21.0 — Social-hub piggy-bank tracker.
--
-- The Reddit page becomes a "Social" hub with per-platform daily-post
-- goals and a streak counter ("posted consistently for N days"). Each
-- "+1" tap from Sallie is a coin drop into the piggy bank for that
-- (persona, platform, date).
--
-- Reddit's existing `subreddit_posts` log keeps working untouched; the
-- piggy-bank's Reddit count is the UNION of social_post_drops (generic
-- one-tap drops) plus subreddit_posts (subreddit-specific marks).
-- Both contribute to the daily Reddit goal.

-- 1) Per-platform daily goal. Default 1, then backfill the four seeded
--    platforms with Sallie's preferred cadence.
ALTER TABLE social_platforms ADD COLUMN daily_goal INTEGER NOT NULL DEFAULT 1;

UPDATE social_platforms SET daily_goal = 10 WHERE id = 1; -- Reddit
UPDATE social_platforms SET daily_goal = 3  WHERE id = 2; -- X (Twitter)
UPDATE social_platforms SET daily_goal = 2  WHERE id = 3; -- Instagram
UPDATE social_platforms SET daily_goal = 2  WHERE id = 4; -- TikTok

-- 2) The coin-drop log. One row per +1 tap; counts are aggregated.
CREATE TABLE IF NOT EXISTS social_post_drops (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    persona_code  TEXT REFERENCES personas(code) ON DELETE SET NULL,
    platform_id   INTEGER NOT NULL REFERENCES social_platforms(id) ON DELETE CASCADE,
    posted_date   TEXT NOT NULL,                       -- YYYY-MM-DD, local
    posted_at     TEXT NOT NULL DEFAULT (datetime('now'))  -- UTC ISO 8601, for ordering / undo
);

CREATE INDEX IF NOT EXISTS social_post_drops_by_persona_date
    ON social_post_drops(persona_code, posted_date);
CREATE INDEX IF NOT EXISTS social_post_drops_by_platform_date
    ON social_post_drops(platform_id, posted_date);
CREATE INDEX IF NOT EXISTS social_post_drops_by_posted_at
    ON social_post_drops(posted_at);
