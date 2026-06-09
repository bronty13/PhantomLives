# Changelog

All notable changes to PurpleAttic are documented here. This project follows
release-hygiene conventions from the repo root `CLAUDE.md`.

## [0.6.1] — 2026-06-09

Fixes to the 0.6.0 preflight, from first use.

### Fixed
- **Photos Automation could never be granted** ("nothing to grant under
  Automation; the error never clears"). The app sent Apple Events without an
  `NSAppleEventsUsageDescription` in its Info.plist, so macOS never showed the
  consent prompt and never listed PurpleAttic under Automation. Added the usage
  string (the `com.apple.security.automation.apple-events` entitlement was
  already present for hardened runtime) — the "PurpleAttic wants to control
  Photos" prompt now appears and the grant sticks.
- **False low-space warning on the Cryptomator vault.** The vault is a macFUSE
  volume, which doesn't report the `volumeAvailableCapacityForImportantUsage`
  resource key, so free space read as 0/absent despite ample room.
  `FreeSpaceCheck.freeBytes` now uses `statfs()` (what `df` uses), which reports
  correctly on APFS/HFS *and* macFUSE.

## [0.6.0] — 2026-06-09

Run-cleanly hardening: a permissions preflight, a "Photos Archive" subfolder on
physical destinations, and a free-space sanity check.

### Added
- **Permissions preflight (hard gate).** New `PermissionsService` (app) checks
  the three macOS grants a clean run needs — **Full Disk Access** (probed via
  the shared `Permissions.fullDiskAccessLikely` Core helper), **Photos
  Automation** (Apple Events → Photos, via `AEDeterminePermissionToAutomateTarget`),
  and **Photos Library** (PhotoKit). The Archive pane shows a per-grant panel
  with inline *Grant…* / *Settings…* buttons, and **Dry Run + Run Archive stay
  disabled until all three are granted** (`AppState.runArchive` also refuses as
  defense-in-depth). This closes the failure mode where a missing Automation
  grant sent osxphotos into the "AppleScript export failed 10 consecutive times,
  restarting Photos app" loop.
- **Archive subfolder.** New editable `archiveSubfolder` on the profile (default
  **"Photos Archive"**). You pick a drive *root* (e.g. `/Volumes/PRO-G40`) and the
  archive is nested under `<drive>/Photos Archive/…` so the drive root stays
  tidy. Applies to the **primary + mirrors**; the **Cryptomator vault is exempt**
  (archive written at the vault root). Threaded through `ExportPlan`,
  `ExportEngine` (mirror/verify/cloud), and the `ArchiveIndex`/`PurgePlanner`
  purge path. Empty subfolder = opt-out (archive at the base, pre-0.6 behavior).
- **Free-space sanity check (warning).** New `FreeSpaceCheck` estimates the
  archive footprint from the library's originals size and compares it against
  each destination volume's free space; the Archive pane shows a non-blocking
  warning when a volume looks too small or isn't mounted.
- **`pattic doctor`** now also reports Full Disk Access (and notes the
  Automation requirement); **`pattic plan`** shows the composed archive roots.

### Changed
- `ArchiveProfile` now decodes **every** key with `decodeIfPresent` + defaults,
  so a pre-0.6 `profile.json` (no `archiveSubfolder`) loads cleanly instead of
  failing — it defaults to "Photos Archive".
- `primaryDestination` / `mirrorDestinations` now mean the **drive/volume base**;
  the archive lives in `archiveSubfolder` beneath each. Validation checks the
  base (drive) is mounted. Starter profile destinations are now drive roots.
- Tests: 54 total (+15 — archive-root composition, profile-migration decoding,
  free-space estimate/sufficiency/mount-boundary).

## [0.5.1] — 2026-06-09

Docs only.

### Added
- `HANDOFF.md` — architecture snapshot (safety model, Core/CLI/App module split,
  data flow, topology, gotchas). Registered PurpleAttic in the root `CLAUDE.md`.
- `USER_MANUAL.md` — Vortex first-run walkthrough, pane-by-pane reference, the
  purge workflow, output locations, troubleshooting, and the `pattic` CLI.

## [0.5.0] — 2026-06-09

Phase D: the **scheduler** — a launchd agent that runs the archive on a cadence.

### Added
- **`ArchiveSchedule`** — daily/weekly cadence + time (Codable, persisted in
  settings with backward-compatible decoding). `nextRun(after:)` and
  `calendarKeys` are unit-tested.
- **`LaunchAgentPlist`** — pure builder for the launchd plist (StartCalendar
  Interval, `RunAtLoad` false so it only fires on schedule, Background
  ProcessType, log paths). Unit-tested incl. XML escaping.
- **`SchedulerService`** (app target) — writes the agent to
  `~/Library/LaunchAgents/com.bronty13.PurpleAttic.archive.plist` and loads it
  via `launchctl bootstrap gui/<uid>` (with bootout/retry); `runNow` kickstarts;
  `isLoaded`/`lastRunDate` for status. The agent runs the **bundled `pattic
  export`** — which has no purge path, so automated runs can never delete.
- **Schedule pane** — enable + daily/weekly + time pickers, Apply, live status
  (loaded?, next run, last run), Run Now, Reveal Log, and notes (run on the
  originals Mac; grant Full Disk Access to bundled pattic; purge is never
  automated).
- Tests: 39 total (+8 — schedule keys, plist fields, next-run, escaping).
  The launchctl bootstrap/print/kickstart/bootout sequence was smoke-tested live.

### Notes
- The scheduler archives only. Purge remains manual (Purge pane), OFF by default.

## [0.4.0] — 2026-06-09

Phase C: the **guarded purge** — wired but gated behind `purgeEnabled` (default
OFF) and multiple safety checks. Removes aged, un-pinned photos from Photos
*only* after they're verified in the archive.

### Added
- **`PhotoMetadataQuery`** — reads candidate metadata via `osxphotos query
  --to-date <cutoff> --json` (osxphotos is the source because it reads
  **keywords**, which PhotoKit can't). Decodes uuid/date/favorite/albums/
  keywords/original_filename/original_filesize/ismissing/intrash.
- **`ArchiveIndex`** — filename → byte-size index of an archive's `originals/`
  tree. Verification matches on **filename AND exact size**, independent of the
  osxphotos folder template.
- **`PurgePlanner`** — applies `RetentionPolicy` to the candidates and verifies
  each against the primary + mirrors. A photo is **deletable only when present +
  size-matched in the primary AND ≥1 mirror** (the ≥2-copy gate). Skips trashed
  and unparseable-date records. Pure `plan(...)` is unit-tested.
- **`PhotoKitPurger`** (app target only — never Core/CLI) — the sole deletion
  path: maps osxphotos UUIDs → `PHAsset`s and calls `deleteAssets`, which shows
  macOS's own confirmation. Deletions go to Recently Deleted (30 days).
- **Purge pane** — "Preview Eligible Photos" (read-only: eligible / verified /
  unverified counts, freed space, date range, a sample list) and a guarded
  "Delete N Verified Photos…" button. Delete requires: purge enabled, verified
  candidates, an in-app confirmation, and the macOS confirmation.
- Tests: 31 total (+9 — eligibility, ≥2-copy verification, size-mismatch,
  pinning, trashed/undated skips, index matching).

### Safety
- Purge ships **OFF**. The CLI still has no purge path at all. Unverified
  candidates (e.g. originals not on this Mac) are never deleted.

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
