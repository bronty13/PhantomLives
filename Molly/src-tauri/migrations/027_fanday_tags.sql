-- Phase 14 PR3: Per-day FanSite tags.
--
-- Up through migration 026, bundle_tag_links carried one row per
-- (bundle_uid, tag_id) — fine for Content + Custom bundles, but
-- FanSite bundles needed per-day tagging so each post day can carry
-- its own theme set, not a single batch-wide blob.
--
-- This migration recreates the table with a nullable fan_day_id column:
--   - fan_day_id IS NULL → tag attaches to the whole bundle
--                          (Content + Custom; preserved from 026)
--   - fan_day_id IS NOT NULL → tag attaches only to that FanSite day
--
-- Partial unique indexes enforce one (bundle, tag) row at bundle level
-- and one (day, tag) row at day level without forbidding both shapes
-- on the same bundle.

CREATE TABLE bundle_tag_links_new (
    bundle_uid  TEXT NOT NULL REFERENCES bundles(uid) ON DELETE CASCADE,
    tag_id      INTEGER NOT NULL REFERENCES content_tags_def(id) ON DELETE CASCADE,
    fan_day_id  INTEGER REFERENCES bundle_fan_days(id) ON DELETE CASCADE
);

INSERT INTO bundle_tag_links_new (bundle_uid, tag_id, fan_day_id)
    SELECT bundle_uid, tag_id, NULL FROM bundle_tag_links;

DROP TABLE bundle_tag_links;
ALTER TABLE bundle_tag_links_new RENAME TO bundle_tag_links;

CREATE UNIQUE INDEX bundle_tag_links_bundle_level
    ON bundle_tag_links(bundle_uid, tag_id)
    WHERE fan_day_id IS NULL;

CREATE UNIQUE INDEX bundle_tag_links_day_level
    ON bundle_tag_links(fan_day_id, tag_id)
    WHERE fan_day_id IS NOT NULL;

CREATE INDEX bundle_tag_links_by_tag ON bundle_tag_links(tag_id);
CREATE INDEX bundle_tag_links_by_fanday
    ON bundle_tag_links(fan_day_id)
    WHERE fan_day_id IS NOT NULL;
