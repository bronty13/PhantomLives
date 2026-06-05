# Purple Tree — Architecture Handoff

Read this before non-trivial changes. Purple Tree is an Electron app
(electron-vite + React 18 + TS) in the PhantomLives monorepo, mirroring
`PurplePDF/` conventions.

## Mental model

- **Main process** (`src/main/`) owns everything stateful: it spawns the scan
  worker, holds the finalized scan tree(s) in memory, and answers windowed
  slice queries over IPC. The renderer never receives the whole tree.
- **Scan worker** (`src/main/scan/scanWorker.ts`) is a Node `worker_thread`
  (electron-vite emits it as a separate `out/main/scanWorker.js` via a second
  rollup input — see `electron.vite.config.ts`). It crawls the filesystem and
  posts a finalized Structure-of-Arrays tree back, transferred zero-copy.
- **Renderer** (`src/renderer/`) is a thin React view. All FS access goes
  through `window.purpleTree` (`src/preload/index.ts`).

## Key flows

- **Scan:** `App.chooseFolder` → `api.startScan` → `scanController.startScan`
  spawns the worker with a `SharedArrayBuffer` cancel flag → worker DFS builds a
  `TreeBuilder` → `finalize()` rolls up aggregates (reverse-index post-order,
  valid because parentId < childId) → transfers `SerializedTree` →
  controller wraps it in a `Tree` (typed-array *views* over the transferred
  buffers — no copy) keyed by `scanId`.
- **Slices:** the renderer calls `getChildren` / `getTopFiles` / `getTreemap` /
  `getBreadcrumb` with the `scanId`; the controller answers from the in-memory
  `Tree`.
- **Treemap:** `computeTreemap` (main) builds a depth/budget-bounded
  d3-hierarchy, lays it out squarified, returns flat `RectNode[]`; the renderer
  paints them on one `<canvas>` and hit-tests for clicks.
- **Duplicates / cache / delete / export / backup / snapshots:** each is a
  `src/main/<area>/` module wired to an IPC handler in `src/main/index.ts`.

## SoA tree (`src/main/scan/tree.ts`)

- `TreeBuilder` grows typed arrays (double-and-copy), prepends children (O(1)),
  and `finalize()` packs names into one UTF-8 buffer + offsets so the *entire*
  tree is transferable.
- Flag bits in `src/shared/types.ts`: dir / symlink / perm-denied /
  crossed-mount / hard-link-dup. Hard-link repeats keep their real `selfSize`
  for display but contribute 0 to folder totals (du-correct).
- `Tree` is the read-side: `getChildren`, `getTopFiles`, `getBreadcrumb`,
  `path(id)` (walks ancestors), `flatten` (export), `collectFiles` (dup input).

## Safety (`src/main/safety/`)

- `protectedPaths.isProtected` is **pure and the most security-critical code** —
  enforced in main inside the delete handlers, never trusting the renderer. It
  realpath-resolves first (`deleteService`) then blocks roots / system dirs /
  home root / app data+backup dirs / non-absolute paths. Heavily table-tested.

## Gotchas

- **ESM-only deps** (`d3-hierarchy`, `xxhash-wasm`) must be **excluded from
  `externalizeDepsPlugin`** in `electron.vite.config.ts` so Vite bundles them as
  CJS — otherwise the CJS main bundle throws `ERR_REQUIRE_ESM` at launch. (This
  bit us once during bring-up.) CJS deps (jszip, electron-store/-updater) stay
  externalized.
- **Worker path:** `scanController.workerPath()` resolves `scanWorker.js` next to
  `index.js` in `out/main/`. If a future change relocates the worker, update
  this and confirm the emitted filename after `npm run build`.
- **macOS Full Disk Access** is a TCC user grant keyed to the app's cdhash —
  *not* an entitlement. This is why `install.sh` pins the app to
  `/Applications` (stable cdhash). Scanning protected locations without FDA
  yields `EPERM`, handled as perm-skips.
- **Windows hard-link dedup** is disabled (`ino` unreliable).
- **Snapshots** are regenerable (a function of the FS), so they don't *require*
  the backup machinery; but prefs do, and the backup zips the whole data dir, so
  snapshots ride along.

## Tests

`npm test` — 53 unit tests (protectedPaths, dupePipeline, tokens, report, tree,
backup) + 1 integration test that spawns the **built** worker against a temp
tree (`tests/integration/scanWorker.test.ts`, skipped if not built).

## Not yet click-tested in the GUI

The scan→treemap→delete UI path is exercised by the worker integration test and
the slice-query unit tests, but has not been driven through the live GUI by
automation. Manual smoke before release: scan `~/Downloads`, drill the treemap,
trash a file, run the duplicate finder, and exercise Settings → Backup.

## v1.5.0 additions

- **`heatBg(fraction, hex)`** in `src/renderer/src/features/common/format.ts`:
  maps a 0–1 size fraction + hex color → `rgba()` background. Uses a `0.7`
  power curve so mid-sized items are visible; max alpha 0.38.
- **`useColumnResize(defaultWidth, min)`** in
  `src/renderer/src/features/common/useColumnResize.ts`: drag-to-resize hook.
  Records start-X/W on mousedown, listens to window mousemove/mouseup, updates
  width state. Shared by `DetailList` and `LargeOldFilesView`.
- **Custom hover tooltips** (`path-tooltip`, `tip-name`, `tip-path` CSS classes):
  fixed-position React tooltip rendered from `onMouseEnter`/`onMouseMove`/
  `onMouseLeave` handlers on name/path cells. Bypasses Electron's slow native
  `title` tooltip. Used in both `DetailList` and `LargeOldFilesView`.
- **`heatmapColor` pref**: new field in `Preferences` (prefs.ts), default
  `#7c3aed`. Migration v4. Exposed in Settings → General → Appearance with a
  native color picker and five preset swatches.
- **Vite entry-point invalidation**: Vite only re-compiles the full renderer
  module graph when the entry-point (`src/renderer/src/App.tsx`) is dirty.
  Always `touch src/renderer/src/App.tsx` before `npm run dist:mac` when only
  non-entry files changed, or changes will not appear in the bundle.

## Future work

- WizTree-style **MFT turbo mode** (Windows, admin) as an alternate tree
  populator behind the same `ScanEvent` protocol.
- Snapshot **diff/compare** visualization; user-authored cache presets; live FS
  watch; perceptual image near-duplicate detection.
