# PurpleMind — architecture handoff

A snapshot for the next developer (or future me) opening this cold. PurpleMind
is a Tauri 2 mindmap app modelled on SideMolly; if something here is unclear,
SideMolly is the reference sibling.

## 30-second mental model

`App.tsx` owns the map list + which view is showing (editor vs. settings) and a
fixed-width `Sidebar`. Selecting a map mounts `MapEditorView`, which wraps a
React Flow canvas in a `ReactFlowProvider`. The editor reads/writes the graph
through thin `data/*.ts` wrappers over `tauri-plugin-sql` (SQLite
`purplemind.db`). The Rust side (`src-tauri/src`) is intentionally small: it
runs the SQL migrations, the launch-time backup, and an export sink that writes
files to `~/Downloads/PurpleMind/`.

## Repo layout

```
PurpleMind/
├── src/                         React 19 + TS frontend
│   ├── App.tsx                  map list + view routing + sidebar
│   ├── components/
│   │   ├── Sidebar.tsx          fixed-width nav (no NavigationSplitView)
│   │   ├── NodeCard.tsx         custom React Flow node (inline-edit label)
│   │   └── ExportMenu.tsx       export/import dropdown
│   ├── data/                    DB access (one module per concern)
│   │   ├── db.ts                Database.load singleton + newId/nowIso
│   │   ├── maps.ts nodes.ts edges.ts   CRUD
│   │   ├── appSettings.ts       key/value (export_dir override)
│   │   └── importMap.ts         build a new map from a parsed graph
│   ├── lib/                     PURE, unit-tested helpers
│   │   ├── graph.ts             MindGraph type + buildForest (spanning forest)
│   │   ├── autoLayout.ts        tidy tree layout            (+ .test)
│   │   ├── markdownOutline.ts   tree ↔ indented bullets     (+ .test)
│   │   ├── mapSerialize.ts      PurpleMind .json (de)serialize (+ .test)
│   │   ├── exportImage.ts       html-to-image + jsPDF render (DOM, not unit-tested)
│   │   └── base64.ts            encoding helpers
│   ├── state/uiTheme.ts         light/dark/auto (pm-theme)
│   ├── views/                   MapEditorView, WelcomeView, SettingsView, BackupSettings
│   └── styles/index.css         purple CSS-var theme + React Flow overrides
├── src-tauri/
│   ├── src/lib.rs               Builder, migrations vec, command handlers, guardrail tests
│   ├── src/backup.rs            auto-backup (ported from SideMolly)
│   ├── src/export.rs            save_export / export_dir commands
│   ├── src/fsutil.rs            downloads_subdir / reveal_in_file_browser
│   ├── migrations/001_init.sql  maps / nodes / edges / app_settings (IMMUTABLE)
│   ├── capabilities/default.json ACL
│   └── tauri.conf.json          identifier com.phantomlives.purplemind, devUrl :1422
├── build-app.sh install.sh run-tests.sh
└── README.md USER_MANUAL.md CHANGELOG.md
```

## Data model (`001_init.sql`)

`maps(id, title, created_at, updated_at, viewport_{x,y,zoom})`,
`nodes(id, map_id→maps, label, x, y, color, …)`,
`edges(id, map_id→maps, source_id→nodes, target_id→nodes)` — all FK
`ON DELETE CASCADE`, so deleting a map (or a node) cleans up its children. This
mirrors React Flow's node/edge model directly. **The file is frozen** by
`migration_immutability` — schema changes go in a new `002_*.sql` and append a
hash to `EXPECTED_MIGRATION_HASHES`.

## Tauri command surface

| Command | Module | Purpose |
|---|---|---|
| `run_backup_now` / `list_backups` / `test_backup` / `restore_backup` / `reveal_backup_dir` / `reveal_path` / `get_backup_settings` / `set_backup_settings` | `backup` | Backup management (Settings UI). |
| `export_dir` / `save_export` | `export` | Resolve default dir; write a base64 export payload to `~/Downloads/PurpleMind/`. |

IPC structs are `#[serde(rename_all = "camelCase")]`; the `camel_case_contract`
test fails the build if a new boundary struct leaks snake_case.

## Frontend patterns

- **Graph state** lives in React Flow's `useNodesState`/`useEdgesState`. Edits
  update local state *and* persist via `data/*` (label on commit, position on
  `onNodeDragStop`, edges on `onConnect`/`onEdgesDelete`, viewport debounced on
  `onMoveEnd`). `touchMap` bumps `updated_at` so the sidebar reorders.
- **Pure logic** (layout, outline, serialize) is isolated in `lib/` with no
  React/Tauri imports so it stays Vitest-friendly. `buildForest` is the shared
  tree-derivation both layout and the Markdown outline rely on.
- **Export** renders in the webview (`exportImage.ts` for PNG/SVG/PDF, pure
  serializers for JSON/Markdown), base64-encodes, and hands bytes to Rust
  `save_export` — one place owns directory creation + filename sanitisation.
- **Import** picks a file (dialog plugin), reads it (fs plugin), parses, and
  calls `importGraph` to create a fresh map with new ids + auto-layout.

## Testing

`./run-tests.sh` → `cargo test --lib` (18 tests) + `pnpm test` (14 tests). Add a
Vitest case for any new pure helper and a `camel_case_contract` case for any new
IPC struct.

## Release

Tag `purplemind-v<x.y.z>` → `release-purplemind.yml` builds macOS + Windows,
signs the updater bundles (when `PURPLEMIND_TAURI_SIGNING_*` secrets exist),
composes `purplemind-latest.json`, and flips the draft to published. Keep the
version synced across `package.json`, `Cargo.toml`, and `tauri.conf.json`.

## Known follow-ups

- Ship a real PurpleMind app icon (currently a placeholder copied from
  SideMolly).
- Code-signing + notarization (macOS) and an EV/SmartScreen story (Windows).
- Out-of-scope-for-v1 niceties: per-node icons/notes, collapsible branches,
  Tab/Enter keyboard-tree editing.
