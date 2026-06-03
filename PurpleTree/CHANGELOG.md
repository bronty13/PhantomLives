# Changelog

## [1.0.0] - 2026-06-03

Initial release. A cross-platform disk-space analyzer and file-cleanup utility.

- **Scanner**: Node worker-thread crawl (`opendir`/`lstat` iterative DFS) into a
  Structure-of-Arrays tree; throttled progress; cooperative cancel via an
  `Atomics` flag; zero-copy transfer of the finalized tree to the main process.
- Symlinks counted not followed; other volumes skipped by default; hard-link
  de-dup in folder totals (macOS/Linux); permission-denied dirs skipped, never
  crash.
- **Explorer**: lazy-expand folder tree, breadcrumb, squarified **treemap**
  (d3-hierarchy in main, canvas paint, drill-down), and a sortable detail list.
- **Duplicate finder**: size → 64 KB partial xxhash → full xxhash; select and
  trash.
- **Large & old files**: filter by size and last-access age.
- **Smart cache cleanup**: declarative per-platform presets; trash-only; never
  auto-selected; sizes shown before action.
- **Export** to CSV / HTML / JSON.
- **Deletion**: trash by default, opt-in guarded permanent delete; pure
  `protectedPaths` guard enforced in main (blocks roots, system folders, home
  root, app data dirs).
- **Snapshots**: save a scan to disk for later comparison.
- **Backup**: launch-time auto-backup of the app data dir with 5-minute
  debounce, 14-day retention, and a full Settings → Backup UI (run / test /
  restore), per the PhantomLives auto-backup standard.
- 53 unit tests + 1 built-worker integration test; universal-mac + win-nsis
  packaging via electron-builder; GitHub-published auto-update.
