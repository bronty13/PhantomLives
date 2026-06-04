-- Adds per-node "item" attributes for the richer mindmap model:
--   checked   — NULL = no checkbox, 0 = unchecked, 1 = checked
--   note      — optional free-text note attached to the node
--   collapsed — 1 = this node's subtree is folded away in the editor
--   icon      — optional emoji shown before the label
--
-- Additive ALTERs only (001 stays frozen, per CLAUDE.md). A fresh install runs
-- 001 then 002; an existing install runs only 002 — both land at the same end
-- state.

ALTER TABLE nodes ADD COLUMN checked   INTEGER;
ALTER TABLE nodes ADD COLUMN note      TEXT;
ALTER TABLE nodes ADD COLUMN collapsed INTEGER NOT NULL DEFAULT 0;
ALTER TABLE nodes ADD COLUMN icon      TEXT;
