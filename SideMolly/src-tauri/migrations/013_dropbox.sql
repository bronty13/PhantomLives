-- Phase 6 — local Dropbox folder copy.
--
-- "Dropbox" here means the user's local Dropbox sync folder (~/Dropbox
-- by default). We never touch the Dropbox HTTP API — just write files
-- to a local path and let the Dropbox app sync them up. Locked-in
-- design decision #11 (PLAN.md §12).
--
-- Two tables:
--
--   dropbox_settings  — one row, app-wide config. Holds the absolute
--                       root path + the destination-folder template.
--                       Default template `[{date}] - {title}` is a
--                       flat layout — every bundle gets its own
--                       folder directly under root, named with the
--                       bundle's ingested date and title. Locked-in
--                       2026-05-24 (supersedes the original
--                       `{uid}_{persona}_{title}` decision; the date
--                       form is what Robert actually browses by).
--                       Template variables: {date} {title} {uid}
--                       {persona}.
--
--   dropbox_copies    — one row per (bundle_uid, source_path,
--                       dropbox_path) tuple. Records what we shipped,
--                       what we sha'd it as, and whether the post-
--                       copy verify succeeded. UNIQUE constraint makes
--                       the upsert flow trivial — re-running copy is
--                       a no-op when the source's sha hasn't changed.

CREATE TABLE IF NOT EXISTS dropbox_settings (
    id          INTEGER PRIMARY KEY CHECK(id = 1),
    root_path   TEXT NOT NULL DEFAULT '',      -- empty = unconfigured
    template    TEXT NOT NULL DEFAULT '[{date}] - {title}',
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT OR IGNORE INTO dropbox_settings (id) VALUES (1);

CREATE TABLE IF NOT EXISTS dropbox_copies (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    bundle_uid    TEXT NOT NULL REFERENCES bundles(uid) ON DELETE CASCADE,
    source_path   TEXT NOT NULL,
    dropbox_path  TEXT NOT NULL,
    sha256        TEXT NOT NULL,
    copied_at     TEXT NOT NULL DEFAULT (datetime('now')),
    verified      INTEGER NOT NULL DEFAULT 0,
    UNIQUE(bundle_uid, source_path, dropbox_path)
);

CREATE INDEX IF NOT EXISTS idx_dropbox_copies_bundle
    ON dropbox_copies(bundle_uid);
