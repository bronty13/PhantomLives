# Changelog

All notable changes to PurpleMind are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
semantic versioning.

## [0.2.0] — 2026-06-04

The "real mindmap" release — maps now read like MindNode instead of a generic
node graph.

### Added

- **Per-branch colors** — each top-level branch off the root gets its own hue
  from a palette; descendants and connectors inherit it. Coloring a top-level
  topic recolors its whole branch; coloring a deeper node overrides just that
  node. (Derived from structure — no stored color needed.)
- **Tiered node styles** — a prominent central **root** card, filled pastel
  **topic** boxes, and **leaf items** rendered as text on a branch-colored
  underline.
- **Tapered branch connectors** — filled ribbons in the branch color, thick at
  the parent and thin toward the child (custom `BranchEdge`).
- **Bilateral layout** — `✨ Tidy` (and imported maps) now fan the branches out
  to *both* sides of the central root, balanced by branch size (MindNode-style),
  with connectors routing cleanly from each side.
- **Collapsible branches** — a fold toggle on any node with children hides/shows
  its subtree (stored `collapsed`); hidden nodes drop out of layout and export.
- **Keyboard-tree editing** — `Tab` = child · `Enter` = sibling · `Space` = edit
  label · `Esc` = cancel · arrows = navigate (←parent, →first child, ↑/↓
  siblings).
- **Per-node emoji icons** — pick from a curated set (toolbar 😀); shown before
  the label.
- **Checkboxes & notes** — toolbar ☑ adds/removes a checkbox on the selection
  (click it to mark done, with strikethrough); 📝 attaches a note (shown as a
  📝 indicator you can click to view/edit). Checkboxes export to Markdown as
  `- [x]`/`- [ ]`.
- **Reopen last map on launch** — the most recently opened map is restored on
  startup instead of the welcome screen.
- **Drag-to-reparent** — drop a node onto another to make it the new parent
  (guards against cycles); ✨ Tidy re-flows.
- **Search / filter** — a toolbar search box highlights matching nodes and dims
  the rest; Enter cycles through matches; ⌘/Ctrl+F focuses it.
- **Tidy keyboard shortcut** — ⌘/Ctrl+Shift+L.
- **Mermaid mindmap export** — export the map as a Markdown file containing a
  `mermaid` mindmap diagram that renders visually in GitHub / Obsidian / VS Code
  (alongside the plain bullet outline).
- **Copy to clipboard** — copy the map as a Mermaid mindmap or as a Markdown
  outline (uses Tauri's clipboard plugin; works on macOS + Windows).

### Changed

- JSON export/import (doc format v2) and Markdown now carry icon, checkbox,
  note, and collapsed state.
- Minimap node colors follow the new branch colors.

### Migrations

- **002_node_items** adds `checked` / `note` / `collapsed` / `icon` to `nodes`
  (additive; 001 stays frozen). Guarded by `migration_immutability`.

## [0.1.0] — 2026-06-04

Initial release. A cross-platform (macOS + Windows) mindmap studio built on the
Molly/SideMolly stack (Tauri 2 + React 19 + TypeScript + Tailwind + SQLite).

### Added

- **Maps** — create, rename, and delete named mindmaps; the sidebar lists them
  newest-first and remembers the last pan/zoom per map.
- **Infinite canvas editor** (React Flow) — add nodes (toolbar, `＋ Child`, or
  double-click the canvas), edit labels inline, drag to move, connect nodes by
  dragging between handles, delete with ⌫/Delete, pan/zoom, minimap, and
  fit-to-view. **Unlimited nesting depth** — a newly added node becomes the
  selection, so repeatedly clicking `＋ Child` chains node → child →
  grandchild → … as deep as you like.
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
