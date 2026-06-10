-- v1.31.0 — YouTube bundle visibility + ManyVids cross-post flags.
--
-- Two new per-bundle booleans, only meaningful for YouTube bundles (left at
-- their defaults and ignored for Content/Custom/FanSite):
--
--   make_private            — when 1, the video is uploaded private and goes
--                             live when Sallie publishes it, so NO go-live date
--                             is set (the form hides the date picker). When 0,
--                             a go-live date is required as before.
--   also_post_sfw_manyvids  — when 1, Robert should also post a SFW cut to
--                             ManyVids. Pure informational flag carried into
--                             the bundle's info.md / Molly.log.
--
-- Both are plain, never-cascading `ALTER TABLE ... ADD COLUMN`s (the same safe
-- move migrations 034/036/038 used). NOT NULL with a static DEFAULT so existing
-- rows backfill cleanly; new YouTube bundles get the Settings-configured
-- defaults written explicitly at create time (see create_bundle). The static
-- DEFAULT 1 for make_private matches the app-level "private by default" stance.

ALTER TABLE bundles ADD COLUMN make_private INTEGER NOT NULL DEFAULT 1;
ALTER TABLE bundles ADD COLUMN also_post_sfw_manyvids INTEGER NOT NULL DEFAULT 0;
