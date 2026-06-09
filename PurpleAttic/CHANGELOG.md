# Changelog

All notable changes to PurpleAttic are documented here. This project follows
release-hygiene conventions from the repo root `CLAUDE.md`.

## [0.3.0] — 2026-06-09

Phase B hardening: the **previews-only library guard** and **Cryptomator vault
unlock status**. Still no deletion engine.

### Added
- **`LibraryInspector`** — detects whether a Photos library is in "Optimize Mac
  Storage" mode (originals only in iCloud). Counts master files under
  `<library>/originals/` and reads `SELECT COUNT(*) FROM ZASSET` from the live
  `Photos.sqlite` (opened read-only + immutable). Flags the library when <90% of
  originals are on disk. Pure threshold (`isLikelyOptimized`) is unit-tested;
  reads degrade gracefully to "unreadable" without Full Disk Access.
  - The Archive pane shows a live status line ("⚠︎ Optimize Storage likely — X
    of Y originals on disk…") with a Recheck button, and a **real run on an
    optimized library now requires an explicit "Run Anyway" confirmation** (dry
    runs are unaffected). The engine logs the same INCOMPLETE-ARCHIVE warning.
- **`VaultStatus`** — reports whether the Cryptomator vault is `notConfigured` /
  `notMounted` / `ready` (mounted + writable). Settings shows a live indicator
  next to the vault path so you know whether the 3rd copy will run.
- Tests: 22 total (+8 — library threshold, path resolution, vault states).

## [0.2.0] — 2026-06-08

Phase B: the **SwiftUI GUI** wrapping `PurpleAtticCore`, plus the app bundle.

### Added
- **`PurpleAttic.app`** (SwiftUI macOS app, `PurpleAtticApp` target):
  - Manual `HStack` sidebar (PhantomLives pattern, not `NavigationSplitView`) +
    `WindowStateGuard`. Four panes: Archive, Settings, Backup, Purge.
  - **Archive** dashboard: Dry Run / Run Archive, a **live streaming log** (via a
    new `AtticLogger.sink`), the last-run summary, and banners for config issues
    / missing osxphotos. Runs the engine off the main thread.
  - **Settings**: full `ArchiveProfile` editor — source library, primary +
    mirror destinations, Cryptomator vault path, HEIC/JPEG toggles, folder
    template, and retention (keep window, keep albums, keep keywords, favorites).
    Shared JSON with the `pattic` CLI.
  - **Backup**: launch-time `BackupService` (zips `~/Library/Application
    Support/PurpleAttic/` → `~/Downloads/PurpleAttic backup/`, 14-day retention,
    5-min debounce, never throws) + the full Settings → Backup UI (toggle,
    retention, folder override, Run Now, recent-backups list). PhantomLives
    ship-blocker satisfied.
  - **Purge** pane: the guarded delete is **shipped disabled** — the
    `purgeEnabled` flag sits behind an affirmative confirmation, and the pane
    lays out every safety gate. No deletion engine yet (Phase C).
  - Sidebar toolchain readiness footer (osxphotos / exiftool / rsync).
- **Bundle infra**: `build-app.sh` (build → sign w/ Photos entitlements →
  install → relaunch + freshness proof), `install.sh` (force-kill + verify),
  `PurpleAttic.entitlements` (photos-library + apple-events), deterministic
  `Scripts/generate-icon.swift` (photo-into-archive-box icon). The `pattic` CLI
  is bundled inside the `.app`.

### Notes
- Built + installed + verified fresh (Developer-ID signed) at v0.2.x.
- Purge remains absent from both the CLI and the GUI's execution paths.

## [0.1.0] — 2026-06-08

Initial scaffold: the archival **engine** + the `pattic` CLI (the safe,
non-destructive half of PurpleAttic). The SwiftUI GUI and the guarded purge
stage come in later releases.

### Added
- **`PurpleAtticCore`** engine library:
  - `RetentionPolicy` — the pure, unit-tested keep/purge predicate. A photo is
    purge-eligible only when it is **both** older than `keepWindowDays`
    (default 365) **and** not pinned by a "Save" album, "save" keyword, or
    (optional) Favorite. Conservative by construction: when in doubt, keep.
  - `ArchiveProfile` / `ProfileStore` — Codable job description (library,
    destinations, formats, retention, purge toggle) persisted as JSON, shared
    by the CLI and the future GUI. Profiles are the reuse mechanism: a second
    Mac / iCloud account is just another profile with `purgeEnabled = false`.
  - `ExportPlan` — pure builder for the `osxphotos export …` argument vector
    (one pass for HEIC originals, one `--convert-to-jpeg` pass for the JPEG
    set). Always emits `--update` (incremental), `--sidecar XMP` + `--exiftool`
    (metadata embedded AND in sidecars), `--touch-file`, `--retry 3`.
  - `ExportEngine` — orchestrates export → rsync mirror (no `--delete`) →
    verify → Cryptomator-vault cloud copy, with a detailed log and a
    human-readable run report.
  - `VerifyService` — inventory (path + size) comparison of each mirror against
    the primary, with optional deep SHA-256. This is the evidence the future
    purge stage will require before deleting anything.
  - `AtticLogger` — timestamped, append-only logs under
    `~/Library/Logs/PurpleAttic/`; run reports under `~/Downloads/PurpleAttic/`.
  - `Tooling` — robust locator for `osxphotos` / `exiftool` / `rsync` that
    probes Homebrew + pipx locations (a Finder-launched app has a minimal PATH).
- **`pattic`** CLI: `doctor` (toolchain check), `init` (write a starter
  profile), `plan` (preview the osxphotos commands + retention, run nothing),
  `export` (run the archive; `--dry-run`, `--deep`). **The CLI never purges** —
  deletion is reserved for the guarded GUI.
- Tests: 14 passing (retention boundary/pinning cases, export-argv assertions).

### Notes
- Requires `osxphotos` (`pipx install osxphotos`) and `exiftool`
  (`brew install exiftool`) to run an export; `rsync` ships with macOS.
- Run host must have originals on disk ("Download Originals"); a host on
  "Optimize Mac Storage" should set `downloadMissingFromICloud: true`.
