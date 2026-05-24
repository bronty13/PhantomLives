-- Phase 0: app-wide key/value settings table. Bundle ingest +
-- bundle_files + posting_targets + bundle_postings + dropbox_mappings +
-- transcripts + jobs / job_runs all land in their own migrations
-- (002-009) per SideMolly/PLAN.md §6.
--
-- Single-row key/value avoids a forest of one-row tables.
CREATE TABLE IF NOT EXISTS app_settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- Initial Phase 0 seed: where to watch for new bundle ZIPs. Default is
-- the convention path from PLAN.md §4 (~/Downloads/Molly bundles/).
-- Frontend can override; persistence is per-key.
INSERT OR IGNORE INTO app_settings (key, value)
VALUES ('bundle_watch_dir', ''),       -- empty = use default at runtime
       ('schema_version_intro', '1');
