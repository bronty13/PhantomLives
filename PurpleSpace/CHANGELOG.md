# Changelog

All notable changes to Purple Space.

## 1.0.0 — 2026-06-11

Initial release.

- **Workspace**: nested page tree with drag & drop reorder/re-nest, hover
  actions (`+` add inside, `⋯` menu), rename, duplicate (deep copy of
  content + subtree), favorites section, trash (restore / delete forever /
  empty), quick switcher (`⌘P`/`⌘K`) with recents + fuzzy title match.
- **Editor**: BlockNote block editor — slash menu, drag handles, formatting
  toolbar, markdown-as-you-type shortcuts, headings/lists/check/toggle
  lists/quotes/dividers/tables, code blocks with shiki syntax highlighting,
  images/video/audio/files uploaded into Convex file storage. Autosave
  (400 ms debounce, flush on navigation). New pages drop the caret straight
  into the title.
- **Pages**: emoji icon picker, cover images (8 built-in gradients or
  uploaded image), serif display titles, breadcrumbs, per-page Markdown
  export (`⌘E`) to `~/Downloads/PurpleSpace/`.
- **Databases**: Notion-model tables (rows are pages). Properties: title,
  text, number, select, multi-select, date, checkbox, URL. Inline cell
  editing, create-tag-in-place pickers, property add/rename/retype/delete,
  single-key sorting, multi-rule filtering (contains / is / empty / </> /
  checked…), open-row-as-page with a property strip, Markdown table export.
- **Embedded Convex backend**: bundles the open-source
  `convex-local-backend` (pinned `precompiled-2026-06-09-b6aaa1a`), spawned
  on launch bound to `127.0.0.1:47800`, no account/docker/network.
  Per-install instance secret + derived admin key (`keygen admin-key`).
  Orphan adoption on same port; `install.sh` reaps orphans across upgrades
  so a stale binary is never adopted. Functions deploy via
  `scripts/deploy-functions.sh` (hot or temporary backend).
- **Backup standard**: auto-backup on launch (before the backend starts, so
  the SQLite file is quiescent) to `~/Downloads/Purple Space backup/`,
  5-minute debounce, 14-day retention (configurable, 0 = forever), never
  throws; Settings → Backup UI with Run Now / Test / Restore (restore
  relaunches the app), folder picker, archive list.
- **App**: light/dark/system themes (`⌘⇧L`), resizable + hideable sidebar
  (`⌘\`), window/sidebar/last-page state persistence, single-instance lock,
  code-generated app icon, install.sh with process-freshness proof.
- **Tests**: 37 vitest unit tests (backup zip/debounce/retention/restore
  safety, tree building/breadcrumbs/fractional ordering/cycle guards, db
  config parsing, sorting, all filter ops, cell text rendering, Markdown
  table export).
