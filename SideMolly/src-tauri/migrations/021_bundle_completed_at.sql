-- v0.25.0 — Inbox completion lifecycle.
--
-- A processed bundle can be marked "complete" to drop out of the Inbox's
-- default Active view. This is orthogonal to the (currently unused)
-- bundle_state workflow enum: completion is a user-driven archival flag with
-- a timestamp, not a workflow stage. "complete" <=> completed_at IS NOT NULL.
-- Reactivating clears it back to NULL. The timestamp also drives the
-- "Completed <date>" readout and date filtering in the Inbox toolbar.
--
-- Nullable (NULL = active), so a plain ALTER TABLE ADD COLUMN suffices — no
-- table rebuild. The immutability guard still hashes this file like any other.
ALTER TABLE bundles ADD COLUMN completed_at TEXT;
CREATE INDEX IF NOT EXISTS idx_bundles_completed ON bundles(completed_at);
