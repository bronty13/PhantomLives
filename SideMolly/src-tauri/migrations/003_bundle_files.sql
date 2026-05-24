-- Phase 1: every file the inner ZIP carries, mirrored from hashes.json.
--
-- One row per entry in the inner zip. Captures the in-zip path
-- (canonical — used as the matching key against hashes.json), the
-- file's classification (video / image / audio / info / log / manifest),
-- and the sha256 the bundle's hashes.json claims for it. Phase 1
-- writes verify_match in the parent bundles.verify_status only —
-- per-file divergences go in bundles.verify_error.
--
-- Position + fansite_day_of_month are parsed out of the in-zip path
-- prefix conventions (Photos/00001_..., FanSite/DD_NN_...) so Phase 3+
-- views can sort without re-parsing.
--
-- working_path + thumbnail_path are Phase 3+ outputs of extract.rs and
-- the thumbnail generator; nullable here for now.
CREATE TABLE IF NOT EXISTS bundle_files (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    bundle_uid            TEXT NOT NULL REFERENCES bundles(uid) ON DELETE CASCADE,
    in_zip_path           TEXT NOT NULL,
    original_name         TEXT NOT NULL,
    kind                  TEXT NOT NULL CHECK(kind IN ('video','image','audio','info','log','manifest','other')),
    position              INTEGER NOT NULL DEFAULT 0,
    fansite_day_of_month  INTEGER,
    sha256                TEXT NOT NULL,
    size_bytes            INTEGER NOT NULL DEFAULT 0,
    working_path          TEXT,
    thumbnail_path        TEXT,
    UNIQUE(bundle_uid, in_zip_path)
);

CREATE INDEX IF NOT EXISTS idx_bundle_files_bundle ON bundle_files(bundle_uid);
CREATE INDEX IF NOT EXISTS idx_bundle_files_kind   ON bundle_files(kind);
