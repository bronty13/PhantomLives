# SideMolly — User Manual

> **Phase 0 placeholder.** Content lands as features ship.

SideMolly is a workbench for Molly bundles. When Molly publishes a bundle
(content, custom, or fan-site), drop the resulting ZIP into SideMolly and
work through three stages — **edit**, **process**, **post** — then send a
post-bundle back to Molly to record what actually happened.

## What works in Phase 0

- The app installs and launches.
- Sidebar shows three tabs: **Inbox** (placeholder), **Settings**, and
  **Manual** (this file).
- **Settings → Backup** is fully wired:
  - Toggle auto-backup-on-launch (default **on**, 5-minute debounce)
  - Set a custom backup folder (or fall back to `~/Downloads/SideMolly backup/`)
  - Set retention days (0 = keep forever, default 14)
  - **Run Backup Now**
  - **Recent backups** list with per-row Test / Restore / Reveal actions
  - Last-backup timestamp + status line

## What's coming

See [PLAN.md](PLAN.md) §11 for the 13-phase plan. The first real feature
(bundle ingest + verify + Inbox) lands in Phase 1.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘+S / Ctrl+S | Toggle the sidebar |
