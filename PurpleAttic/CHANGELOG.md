# Changelog

All notable changes to PurpleAttic are documented here. This project follows
release-hygiene conventions from the repo root `CLAUDE.md`.

## [0.12.0] — 2026-06-11

Fix purge verification rejecting ~all photos (the `--exiftool` size delta).

### Fixed
- **The ≥2-copy purge gate verified almost nothing** — a real preview marked only **368 of
  66,279** eligible photos "deletable" and skipped 65,911, making purge useless. Root cause:
  verification matched each photo's archived file against the **Photos `original_filesize`**,
  but the export embeds metadata via **`osxphotos --exiftool`**, so every archived original is
  a few hundred bytes **larger** than its pre-export size — the exact-size check failed for
  67,122 of the present files (only files exiftool happened not to resize matched).
- **New verification model:** a candidate is verified when its filename is present in the
  primary **and** a mirror holds a **byte-identical** copy (the primary/mirror size-sets for
  that name intersect). This proves two *consistent* copies exist — the real intent of the
  gate — without depending on the pre-export size. After the fix, the same library verifies
  **65,627 of 66,279** (the 652 still skipped are the shared/"Shared with You" items excluded
  from the archive in 0.10, which correctly have no archived copy and must never be deleted).
  Validated end-to-end against the live 68,151-record library + both mounted drives.
- Tests: 100 total (regression: exiftool-resized file still verifies; primary/mirror size
  disagreement → unverified; name-absent → unverified).

### Note
The ideal long-term correlation is osxphotos' export DB (uuid → archived path), noted in
HANDOFF; the name + cross-copy-consistency model is the robust, version-independent fix shipped
now. The 30-day Recently Deleted net and the independently-verified complete archive remain
backstops.

## [0.11.0] — 2026-06-11

Fix the purge preview crashing on osxphotos' non-standard JSON.

### Fixed
- **Purge preview failed with "Couldn't parse osxphotos JSON: …isn't in the correct
  format"** on a real library. Root cause: `osxphotos query --json` emits **non-standard
  JSON literals** — `Infinity` / `-Infinity` / `NaN` (in a video's audio-waveform
  `energyValues`, and unset scores). Python tolerates them; Swift's JSON parser rejects
  them outright, so the entire preview (and thus any purge) was impossible. `PhotoMetadataQuery`
  now runs a single-pass, **string-aware** sanitizer over the osxphotos output that rewrites
  those bare literals to `null` **only in value position** — a keyword / album / caption that
  literally contains "Infinity" or "NaN" is left byte-for-byte intact (backslash-escaped quotes
  handled). Validated end-to-end: a 727 MB / 68,151-record real query that previously failed
  now decodes cleanly. None of the rewritten fields are ones the retention logic reads.
- Tests: 98 total (+5 — value-position rewrite, negative-number/normal-value safety, literals
  inside strings preserved, escaped-quote string tracking, full-record decode round-trip).

## [0.10.0] — 2026-06-11

Stop chasing ghosts — exclude "Shared with You" + shared-album items.

### Added
- **`excludeSharedAndSyndicated` (on by default).** The export now passes osxphotos
  **`--not-syndicated --not-shared`**, skipping **"Shared with You"** (Messages /
  syndication) items and **shared-album** items. These aren't your originals and have
  **no downloadable master**, so they otherwise linger forever as bogus "missing"
  originals — exactly the false gap that sent a multi-hour download chase after photos
  that could never come down. New Settings toggle (Source card); `ExportPlan` emits the
  flags only when enabled. Old profiles decode with it **on**. Your own iCloud **Shared
  Library** photos are unaffected (that's `--shared-library`, which you do own).
- Tests: 93 total (+4 — flags present-by-default / disabled, migration defaults).

### Why
The first production download-missing run left "3 missing" that no tool — osxphotos
(AppleScript or PhotoKit) or Photos' own Export Unmodified Original — could fetch.
Diagnosis: all three were **shared/syndicated** content (a texted pasta photo
`syndicated=True`, a shared video `shared=True`), not owned originals. osxphotos counts
them as "missing" because they have no master. Excluding them makes the missing count
reflect only photos you actually own. Incident: 2026-06-11, Vortex.

## [0.9.0] — 2026-06-10

PhotoKit download path — make `--download-missing` reliable (stop killing Photos).

### Added
- **`usePhotoKitForDownload` (on by default).** When download-missing is enabled,
  PurpleAttic now passes osxphotos `--use-photokit`, fetching missing originals from
  iCloud via **PhotoKit** instead of the default AppleScript path. A new Settings
  toggle (shown only when download-missing is on) exposes it; `ExportPlan` emits
  `--use-photokit` only alongside `--download-missing`. Old profiles decode with it
  **on**.
- Tests: 89 total (+5 — PhotoKit flag present-by-default / disabled / absent-without-
  download-missing, and migration defaults).

### Why
The default osxphotos download path drives Photos over **AppleScript**; on a slow or
**indeterminate (`incloud=None`)** iCloud asset that request **times out**, and
osxphotos' retry loop **terminates Photos** (`killall`) and re-tries — which on a real
run wedged both Photos and the export with **0 of 44 stragglers downloaded** (and was
the cause of a separate "Photos not responding" hang). `--use-photokit` requests the
original directly and needs no Photos-Automation grant. Incident: 2026-06-10, Vortex.

## [0.8.0] — 2026-06-10

"NEW PHOTOS TO REVIEW" — stage each incremental run's new items for review.

### Added
- **New-photo review staging (on by default).** On an **incremental** run, the
  items newly added to the archive (originals + JPEG, with sidecars) are also
  copied into a dated batch folder under **"NEW PHOTOS TO REVIEW"** (default
  `~/Downloads/PurpleAttic/NEW PHOTOS TO REVIEW/<timestamp>/`), so just-arrived
  photos can be handed off (to keep) or deleted after review — without touching
  the backup set. New `ReviewStaging` (Core) snapshots each export pass's files
  before the run and copies the set-difference afterwards. **Skipped on the
  first/baseline run** (everything is "new" then, so nothing is duplicated) and
  whenever a pass adds nothing. Re-exported edits of existing photos keep their
  path and are not re-staged.
- Profile gains `reviewNewItems` (default true) + `reviewFolderPath` (nil →
  default); Settings → **New-photo review** card (toggle + folder). The run
  report and log show the staged count + batch path; `pattic plan` shows the
  setting. Old profiles decode with the feature **on**.
- Tests: 84 total (+6 — set-difference, snapshot/copy round-trip, profile defaults).

## [0.7.0] — 2026-06-10

The three post-first-run enhancements: live progress, graceful errors, mount guard.

### Added
- **Live progress dashboard.** The Archive pane now shows a **phase stepper**
  (Export HEIC → Export JPEG → Mirror → Verify → Cloud) with per-phase state
  (pending/running/done/failed/skipped) + elapsed, total elapsed, the current
  file being copied (rsync) / files checked (verify), and a live count of files
  written during each export pass (polled, since osxphotos' own progress is
  TTY-only and silent when piped). Replaces the bare "Running…" spinner for
  these multi-hour runs. New `RunProgress` + `RunProgressTracker` in Core;
  `ExportEngine(onProgress:)` streams snapshots; `AppState.progress` publishes them.
- **Graceful error handling.** The benign exiftool *metadata-embed* failures
  (Bad/Truncated MakerNotes, "Not a valid HEIC/JPEG/PNG", Bad ExifIFD, "Error
  reading image data") no longer flood the log as scary "❌️ Error" lines. New
  `OsxphotosLine.classify` reclassifies them as a counted **"sidecar-only"**
  notice (the image + `.xmp` are archived; only the in-file embed was skipped),
  suppresses the per-file/retry spam, keeps genuine export failures distinct, and
  lists the affected photos in the run report. The run summary carries
  `metadataEmbedSkips`.
- **Mirror/vault mount guard.** New `VolumeReadiness` — before copying, each
  mirror base must exist and (for a `/Volumes/*` path) be a genuinely mounted
  separate volume. An unmounted drive is **skipped with a warning** instead of
  the engine creating the folder on the **boot disk** and rsyncing hundreds of GB
  there. (Found as a risk in 0.6.2.)

### Changed
- Mirror/verify are now reported as aggregate phases across all configured
  mirrors (N ok / skipped / failed), and a failed/skipped mirror is no longer
  verified.
- Tests: 78 total (+16 — line classification, volume readiness, progress tracker).

## [0.6.5] — 2026-06-10

Third cloud-copy fix — the vault rsync also can't create temp files (`--inplace`).

### Fixed
- **Cloud copy to the Cryptomator vault still aborted (`mkstempat`/`utimensat:
  No such file or directory`)** after the 0.6.4 chown fix — this time ~24k files
  in, on a duplicate-named file (`_MG_4667 (1).JPG`). openrsync writes each file
  to a temp name then renames it, and that temp-file creation fails on the
  macFUSE/Cryptomator volume for some names. The vault copy now adds `--inplace`
  (write directly to the final file, no temp/rename). Verified by re-copying the
  exact folder that failed (1,044 files, exit 0). Combined with 0.6.3
  (`.DS_Store` exclude) and 0.6.4 (`--no-owner --no-group --no-perms`), all three
  openrsync↔Cryptomator incompatibilities are handled. The APFS mirror keeps
  atomic temp-then-rename writes (only the FUSE vault needs `--inplace`). 62 tests.

## [0.6.4] — 2026-06-10

Second cloud-copy fix — the vault rsync also can't preserve owner/group/perms.

### Fixed
- **Cloud copy to the Cryptomator vault still aborted (`fchownat: Function not
  implemented`).** With 0.6.3 the copy got past `.DS_Store` and transferred the
  first file, then died because rsync `-a` preserves owner/group/perms and the
  macFUSE/Cryptomator volume doesn't implement `chown`/`chmod`. The cloud copy
  now adds `--no-owner --no-group --no-perms` (content + timestamps still
  transfer; perms are moot inside an encrypted container). The **on-disk mirror
  keeps `-a`** (APFS supports those). Verified against the live vault. Mirror +
  verify remain confirmed (verify: 350,513 files match). 61 tests.

## [0.6.3] — 2026-06-10

Cloud-copy fix found by the first end-to-end run (mirror + verify now confirmed).

### Fixed
- **Cloud copy to a Cryptomator vault aborted on `.DS_Store`.** With the 0.6.2
  rsync flags, mirror (→ APFS) and verify both succeeded (verify: 350,500 files
  match — the openrsync fix is confirmed), but the cloud rsync to the macFUSE
  Cryptomator vault died at the first file: openrsync copies each file to a temp
  name then renames it into place, and that `renameat` fails on the FUSE volume
  ("renameat: No such file or directory") for `.DS_Store`, aborting the whole
  transfer (exit 1, 0 files copied). `ExportEngine.rsyncCopyArgs` now excludes
  `.DS_Store` and `.osxphotos_export.db*` from every copy (mirror + cloud).
  Verified end-to-end against the live vault. These are dotfiles, which
  `VerifyService` and `ArchiveIndex` already skip (`.skipsHiddenFiles`), so
  excluding them creates no verify discrepancies and they were never archive
  content. (59 tests.)

## [0.6.2] — 2026-06-10

Critical mirror/cloud fix found by the first full run.

### Fixed
- **Mirror, verify, and cloud all failed on stock macOS.** The engine hard-coded
  rsync's `--info=progress2`, but macOS's default rsync is **openrsync** (reports
  "2.6.9 compatible"), which rejects that flag and aborts in 0.1s with a usage
  error. Result: the mirror copied nothing, **verify then reported every primary
  file as a discrepancy** (349k false positives — an empty mirror, not real
  corruption), and the cloud copy failed identically. The exports themselves were
  fine. `ExportEngine.rsyncCopyArgs` now picks flags the available rsync supports
  — `--info=progress2` only for a real rsync 3.x (e.g. Homebrew), otherwise plain
  `-ahv` which every rsync understands. Tested across openrsync / rsync 3.x /
  classic 2.6.9 / empty-banner. (58 tests.)

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
