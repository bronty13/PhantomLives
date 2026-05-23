-- Phase 15 PR4: Dark mode toggle.
--
-- Default 'light' per user's explicit ask. 'system' follows the OS
-- `prefers-color-scheme` media query. The setting lives in
-- app_settings; the frontend reads it on App mount and writes it from
-- the Settings tab.

INSERT OR IGNORE INTO app_settings (key, value) VALUES
    ('ui.theme', 'light');
