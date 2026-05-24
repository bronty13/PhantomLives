-- Phase 1: catalog of ingested Molly bundles.
--
-- A bundle is identified by its UID (matches the outer-zip filename
-- minus `.zip`). Re-ingesting the same UID UPSERTs the row in place;
-- user-side state (postings, notes, etc.) lands on a sibling table in
-- later phases and never gets clobbered by re-import.
--
-- verify_status: did hashes.json line up with re-hashed bytes?
--   'pending'  — row created but verification not yet attempted
--   'verified' — every inner-zip entry hashed clean
--   'failed'   — one or more divergent hashes; user can re-publish + re-import
-- verify_error: free-text detail on the divergence (relative path + sha).
--
-- manifest_source: which parser populated manifest_json?
--   'manifest_json' — new contract (Phase 2's Molly PR adds it to the ZIP)
--   'molly_log'     — fallback line-based parse of Molly.log (for pre-PR bundles)
--
-- bundle_state: workflow state. Phase 1 just tracks 'new'; the runners
-- in Phases 8/9/10 flip to 'in_progress' / 'shipped' / 'archived'.
CREATE TABLE IF NOT EXISTS bundles (
    uid                TEXT PRIMARY KEY,
    bundle_type        TEXT NOT NULL CHECK(bundle_type IN ('content','custom','fansite')),
    persona_code       TEXT,
    title              TEXT NOT NULL DEFAULT '',
    source_zip_path    TEXT NOT NULL,
    source_zip_sha256  TEXT NOT NULL DEFAULT '',
    ingested_at        TEXT NOT NULL DEFAULT (datetime('now')),
    verify_status      TEXT NOT NULL CHECK(verify_status IN ('pending','verified','failed')) DEFAULT 'pending',
    verify_error       TEXT,
    manifest_source    TEXT NOT NULL CHECK(manifest_source IN ('manifest_json','molly_log')) DEFAULT 'molly_log',
    manifest_json      TEXT NOT NULL DEFAULT '{}',
    bundle_state       TEXT NOT NULL CHECK(bundle_state IN ('new','in_progress','shipped','archived')) DEFAULT 'new',
    created_at         TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at         TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_bundles_ingested ON bundles(ingested_at DESC);
CREATE INDEX IF NOT EXISTS idx_bundles_persona  ON bundles(persona_code);
CREATE INDEX IF NOT EXISTS idx_bundles_state    ON bundles(bundle_state);
