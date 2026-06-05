# Purple Tree

A cross-platform (macOS + Windows) disk-space analyzer and file-cleanup
utility — a TreeSize / WinDirStat / DaisyDisk equivalent. Built with Electron
+ React, mirroring the `PurplePDF/` subproject conventions.

## What it does

- **Scan** any folder and see per-folder size aggregation as a sortable tree.
- **Treemap** visualization — nested rectangles sized by bytes; click to drill
  down, breadcrumb to navigate back.
- **Sortable detail list** of the current folder (size / name / files / date),
  with select-and-delete.
- **Duplicate finder** — size → partial-hash → full-hash (xxhash), with
  select-and-trash.
- **Large & old files** — filtered view (≥ N MB and/or not opened in N months).
- **Size heat shading** — rows in Explorer and Large & Old are tinted by relative size so space hogs stand out instantly. Color is customizable in Settings.
- **Resizable columns** — drag the Name column header edge to resize; hover any truncated name or path for a full-path tooltip.
- **Smart cache cleanup** — curated, per-platform safe-to-clear locations;
  always trash, never permanent; nothing selected by default; sizes shown
  before any action.
- **Export** scan results to CSV / HTML / JSON.
- **Snapshots** — save a scan to disk for later comparison.

Deletions go to the **Trash / Recycle Bin** by default (recoverable). A guarded
**permanent delete** can be enabled in Settings; both paths run through a
protected-path guard that refuses to touch filesystem roots, OS system folders,
the home root, and the app's own data directories.

## Architecture

| Piece | Where | Notes |
|---|---|---|
| Crawl engine | `src/main/scan/scanWorker.ts` | Node `worker_thread`; iterative `opendir`/`lstat` DFS. |
| In-memory tree | `src/main/scan/tree.ts` | Structure-of-Arrays (typed arrays); ~70 B/node. Transferred zero-copy. |
| Controller | `src/main/scan/scanController.ts` | Owns workers + trees; renderer pulls windowed slices, never the whole tree. |
| Treemap layout | `src/main/scan/treemap.ts` | d3-hierarchy squarified, computed in main; painted on canvas. |
| Duplicates | `src/main/dup/*` | Pure staged pipeline (`dupePipeline.ts`) + `xxhash-wasm`. |
| Safety guard | `src/main/safety/protectedPaths.ts` | Pure, unit-tested; enforced in main. |
| Backup | `src/main/backup/backupService.ts` | Launch-time auto-backup per the PhantomLives standard. |

The renderer never touches `fs`; everything funnels through the `purpleTree`
contextBridge API (`src/preload/index.ts`).

## Build & run

```sh
./build-app.sh                # build + install to /Applications + relaunch
./build-app.sh --no-open      # build + install, no relaunch
./build-app.sh --no-install   # build only (dist/)
npm run dev                   # electron-vite dev server
npm test                      # vitest (53 unit + 1 worker integration test)
npm run typecheck             # tsc against node + web tsconfigs
npm run dist:mac              # universal2 DMG (needs Apple Developer ID env)
npm run dist:win              # Windows NSIS installer
```

First clone: run `scripts/install-git-hooks.sh` for the auto-version-bump
pre-commit hook.

## Default locations

- Exported reports: `~/Downloads/Purple Tree/`
- Auto-backups: `~/Downloads/Purple Tree backup/`
- Prefs + snapshots: `~/Library/Application Support/Purple Tree/`

## Platform notes

- **macOS Full Disk Access:** a user-picked folder scans without prompting. To
  scan `~/Library`, other users' homes, or a whole volume, grant Purple Tree
  **Full Disk Access** in System Settings → Privacy & Security (no entitlement
  auto-grants it).
- **Hard-link de-duplication** in folder totals is macOS/Linux only (Windows
  inode numbers are unreliable).
- **WizTree-style MFT turbo mode** (Windows, admin-only) is future work; v1 uses
  portable, permission-respecting traversal.
