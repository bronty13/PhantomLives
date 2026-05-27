-- Phase 13 — posting_log (append-only audit trail).
--
-- `bundle_postings` holds only the *current* state of each
-- (bundle, target, day) cell. When a FanSite day is unwound and re-
-- posted, or the whole plan is reset to start fresh, that history is
-- lost. Robert needs a timestamped record of every posting action —
-- viewable in SideMolly and carried back to Molly in the post-bundle
-- (posting-log.json) so Molly can reconcile what actually went live.
--
-- This is append-only by convention: rows are INSERTed on each
-- posted / unposted / reset action, never UPDATEd. The target name is
-- snapshotted (not just the FK) so a row survives the target being
-- deleted or renamed later — Molly imports keyed on the name string.
--
--   action ∈ posted | unposted | reset
--     posted   — a (bundle, target, day) cell transitioned TO 'posted'
--     unposted — a cell transitioned AWAY from 'posted'
--     reset    — bulk unwind of a site (target_id set) or the whole
--                bundle (target_id NULL); one summary row per reset

CREATE TABLE IF NOT EXISTS posting_log (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    bundle_uid    TEXT NOT NULL REFERENCES bundles(uid) ON DELETE CASCADE,
    target_id     INTEGER REFERENCES posting_targets(id) ON DELETE SET NULL,
    target_name   TEXT NOT NULL DEFAULT '',   -- snapshot, survives target delete
    persona_code  TEXT,
    fansite_day   INTEGER,                     -- 1..=31 for FanSite, NULL otherwise
    title         TEXT,                        -- bundle title snapshot
    action        TEXT NOT NULL
                  CHECK(action IN ('posted','unposted','reset')),
    posted_url    TEXT,
    details       TEXT,                        -- free-text (e.g. "reset all sites")
    logged_at     TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_posting_log_bundle
    ON posting_log(bundle_uid, logged_at);
