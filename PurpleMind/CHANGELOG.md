# Changelog

All notable changes to PurpleMind are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
semantic versioning.

## [0.1.0] — 2026-06-04

Initial release. A cross-platform (macOS + Windows) mindmap studio built on the
Molly/SideMolly stack (Tauri 2 + React 19 + TypeScript + Tailwind + SQLite).

### Added

- **Maps** — create, rename, and delete named mindmaps; the sidebar lists them
  newest-first and remembers the last pan/zoom per map.
- **Infinite canvas editor** (React Flow) — add nodes (toolbar, `＋ Child`, or
  double-click the canvas), edit labels inline, drag to move, connect nodes by
  dragging between handles, delete with ⌫/Delete, pan/zoom, minimap, and
  fit-to-view.
- **Auto-layout** — one-click `✨ Tidy` arranges the map as a left-to-right
  tidy tree.
- **Per-node colours** — a swatch palette tints selected nodes.
- **Export** — PNG, SVG, PDF, a PurpleMind `.json` document, and a Markdown
  outline. Exports default to `~/Downloads/PurpleMind/` (configurable).
- **Import** — open a PurpleMind `.json` or a Markdown outline into a brand-new
  map (auto-arranged when positions aren't supplied).
- **Auto-backup-on-launch** — zips the app-data directory into
  `~/Downloads/PurpleMind backup/` on launch (14-day retention, 5-minute
  debounce, never blocks launch), plus the full Settings → Backup UI
  (toggle / location / retention / Run Now / Test / Restore / Reveal).
- **Light/dark/auto theme** with a soft purple aesthetic.
- Cross-platform release workflow (`release-purplemind.yml`) building a macOS
  `.dmg` and a Windows `.exe` from a `purplemind-v*` tag, with a signed updater
  feed.

### Notes

- The migration `001_init.sql` is frozen by the `migration_immutability`
  guardrail test; schema changes ship as new migrations.
- Releases are unsigned until Apple Developer ID + Windows code-sign certs are
  wired (Gatekeeper/SmartScreen warn on first launch).
