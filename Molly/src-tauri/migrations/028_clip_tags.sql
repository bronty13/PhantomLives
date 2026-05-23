-- Phase 14 PR4: Clip tags (regular clips table only — c4s_clips is a
-- read-only snapshot, deliberately excluded).
--
-- Reuses the same `content_tags_def` taxonomy as bundles so tags stay
-- canonical across surfaces — a "panties" tag on a clip is the same
-- "panties" tag on a bundle. Many-to-many; cascades on both directions
-- so deleting a clip or a tag silently cleans up the join rows.

CREATE TABLE IF NOT EXISTS clip_tag_links (
    clip_id  TEXT NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
    tag_id   INTEGER NOT NULL REFERENCES content_tags_def(id) ON DELETE CASCADE,
    PRIMARY KEY (clip_id, tag_id)
);

CREATE INDEX IF NOT EXISTS clip_tag_links_by_tag ON clip_tag_links(tag_id);
