# Changelog

## [1.0.1] - 2026-06-03

- Fix: a directory whose `readdir` fails mid-iteration — e.g. `ETIMEDOUT` on a
  network / cloud-backed mount (`~/Library/CloudStorage/…`, SMB, MacDroid) — no
  longer aborts the entire scan. The worker now catches `readdir`/`closedir`
  errors per-directory (like it already did for `opendir`/`lstat`), marks the
  directory permission-denied, and continues. A whole-disk scan that hit a timed-
  out Switch mount used to die with "Scan failed: ETIMEDOUT"; it now skips that
  one folder and finishes. Added a regression test (unreadable directory still
  completes the scan).

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
