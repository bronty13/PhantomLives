-- Phase 6 follow-up — drop the brackets from the default folder template.
--
-- v0.13.0 shipped with default `[{date}] - {title}` (e.g.
--   `[2026-05-22] - and before too soon it was JUNE`).
-- Robert prefers the unbracketed `{date} {title}` form
--   `2025-12-31 Mary Poppins`
-- which sorts the same in Finder but doesn't visually fight the title.
--
-- Update only the rows still on the v0.13.0 default — any user who
-- already customized the template keeps their value.

UPDATE dropbox_settings
   SET template = '{date} {title}',
       updated_at = datetime('now')
 WHERE template = '[{date}] - {title}';
