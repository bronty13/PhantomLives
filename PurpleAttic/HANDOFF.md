# PurpleAttic — Architecture Handoff

Canonical architecture snapshot. Read this before non-trivial changes. For *what
changed when*, see `CHANGELOG.md`; for *how to use it*, see `README.md`.

## What it is

PurpleAttic exports the macOS **Photos** library to a plain-file archive the
user owns (so nothing is locked in a `.photoslibrary` bundle), keeps multiple
**verified** copies, and — once the user opts in — **purges** aged, un-pinned
photos from Photos so the live library stays small. osxphotos is the export +
metadata engine; PhotoKit is used only to delete.

## The safety model (the spine of the whole design)

Once a photo is purged it lives **only** in the archive, so the archive must be
trustworthy before anything is deleted. Every gate below must hold to delete one
photo:

1. **`purgeEnabled`** is ON (default OFF; behind an affirmative confirmation).
2. The photo is **older than `keepWindowDays`** (default 365) **and not pinned**
   (Save album / `save` keyword / optional Favorite) — `RetentionPolicy`.
3. The photo's file is **present + exact-size-matched in the primary archive AND
   ≥1 mirror** (the ≥2-copy gate) — `PurgePlanner` + `ArchiveIndex`.
4. The user clicks **Delete** in-app, then macOS shows its **own** delete
   confirmation (`PhotoKitPurger`).
5. Deletions land in Photos' **Recently Deleted (30 days)**.

Reinforcing properties: the 12-month window is itself a buffer (a just-taken
photo can't be purge-eligible for a year); the **CLI and the scheduler have no
purge path at all** — deletion exists only in the GUI; the **Optimize-Storage
guard** blocks archiving an incomplete library.

## Module map

```
PurpleAtticCore (library)   — pure logic + IO; NO Photos framework, NO deletion.
  RetentionPolicy            keep/purge predicate (pure, the highest-stakes code)
  ArchiveProfile/ProfileStore JSON job description shared by CLI + GUI
  ExportPlan                 builds the osxphotos export argv (pure)
  ExportEngine               export → rsync mirror → verify → vault; RunSummary + report
  VerifyService              inventory (path+size) / deep SHA-256 mirror check
  LibraryInspector           Optimize-Storage detection (originals-on-disk vs ZASSET)
  PhotoMetadata              `osxphotos query --json` → OsxphotosRecord
  ArchiveIndex               filename → byte-size index of an archive's originals/
  PurgePlanner               records + policy + indices → PurgePlan (eligible/verified)
  ArchiveSchedule            daily/weekly cadence model
  LaunchAgentPlist           pure launchd plist builder
  FreeSpaceCheck             estimate archive footprint vs per-volume free space (pure + statfs)
  Permissions                Full Disk Access probe (shared by GUI preflight + `pattic doctor`)
  VolumeReadiness            mount guard — destination base exists + is a real mounted volume
  OsxphotosLine              classify export output (benign embed-skip vs real failure vs noise)
  RunProgress / RunProgressTracker   live phase-stepper progress model (engine → GUI callback)
  ReviewStaging              copy each incremental run's NEW items → "NEW PHOTOS TO REVIEW"
                             (snapshot dest before/after, set-difference, copy; baseline-safe)
  Tooling / ProcessRunner / AtticLogger   tool locator, subprocess, logging

pattic (executable)         — CLI front-end. Subcommands: doctor/init/plan/export.
                              NO purge path. Safe to run headless / from the scheduler.

PurpleAtticApp (executable) — the SwiftUI app (PurpleAttic.app). Imports Core.
  AppState                   view-model; runs the engine off-main, streams log lines;
                             holds the permissions report + free-space checks; gates runs
  SettingsStore/AppSettings  profile + app settings (backup, schedule) as JSON
  Services/PermissionsService preflight: FDA (Core probe) + Photos Automation
                             (AEDeterminePermissionToAutomateTarget) + Photos (PhotoKit)
  Services/PhotoKitPurger    the ONLY deletion code (import Photos) — GUI-only
  Services/SchedulerService  writes the LaunchAgent + launchctl bootstrap/kickstart
  Services/BackupService     launch-time backup of config (PhantomLives standard)
  Services/WindowStateGuard  copied-verbatim split-view state fix
  Views/                     ContentView (manual HStack sidebar) + 5 panes:
                             Archive / Schedule / Settings / Backup / Purge
```

**Why this split:** deletion (PhotoKit) is isolated in the app target so it can
never leak into a headless/CLI path. Candidate metadata comes from **osxphotos**
(not PhotoKit) because PhotoKit cannot read keywords. The CLI links only Core, so
it is structurally incapable of purging.

## Data flow

- **Archive (safe):** GUI/CLI → `ExportEngine.run(profile)` → osxphotos export
  (HEIC originals pass + `--convert-to-jpeg` pass) → rsync mirror (no `--delete`)
  → `VerifyService` → rsync into mounted Cryptomator vault (skipped if locked) →
  detailed log (`~/Library/Logs/PurpleAttic/`) + report (`~/Downloads/PurpleAttic/`).
- **Purge (guarded, GUI-only):** `PurgePlanner.compute` runs `osxphotos query
  --to-date <cutoff> --json` → `RetentionPolicy` filters → `ArchiveIndex` verifies
  each against primary + mirrors → `PurgePlan`. UI previews it; on confirm,
  `PhotoKitPurger` maps osxphotos uuid → `PHAsset` (`"<uuid>/L0/001"`) → `deleteAssets`
  (batched + retry-backoff). **At scale, prefer staging:** `PhotoKitPurger.stageToAlbum` adds the
  verified set to the `PurpleAttic — To Delete` album (non-destructive → no confirmation,
  unattended, batched), then the user deletes inside Photos.app once — Apple's engine paces the
  iCloud sync. This avoids the two walls that break direct `deleteAssets` at scale: the
  un-suppressible per-`performChanges` macOS confirmation, and the `PHPhotosErrorDomain 3300`
  choke when iCloud is digesting a large deletion backlog (`cloudd` pegged). (Incident 2026-06-11.)
- **Scheduler:** `SchedulerService` installs `~/Library/LaunchAgents/com.bronty13.
  PurpleAttic.archive.plist` running the bundled `pattic export` on a calendar.

## Topology (operational)

Two Macs share **one** iCloud library. **Vortex** (4TB, "Download Originals",
mostly-on) is the **sole archival authority** — the only host with all originals,
so the only one that should archive or purge. **MBP14** (2TB, Optimize Storage)
is the dev box + a passive follower; it holds ~1,571 of ~78,360 originals, so the
library guard correctly blocks a real archive there. A third Mac on a different
iCloud account is the reuse case → its own export-only profile (`purgeEnabled=false`).

## Permissions preflight (0.6)

Three macOS grants are **hard-gated** before a dry run or archive (UI disables the
buttons; `AppState.runArchive` also refuses): **Full Disk Access**, **Photos
Automation** (Apple Events → Photos), **Photos Library** (PhotoKit). The key
insight that shaped this: **a spawned child inherits the parent's responsible-process
TCC grants** — proven live when the GUI's osxphotos child read 45k photos fine on
the app's FDA grant alone, while the *Automation* events it sent to Photos were
denied (no Automation grant), causing the "AppleScript export failed 10 consecutive
times, restarting Photos app" thrash. So checking the **GUI app's** grants is the
correct gate; they cover the osxphotos subprocess. FDA is probed by reading the
`.photoslibrary` `database/` dir (raw access ⇒ FDA, distinct from a PhotoKit grant).

## Archive subfolder (0.6)

`primaryDestination` / `mirrorDestinations` are now **drive/volume bases**; the
archive lives under `archiveSubfolder` (default "Photos Archive") on each, composed
by `profile.archiveRoot(forBase:)` / `primaryArchiveRoot` / `mirrorArchiveRoots`.
**Every** physical-path consumer routes through these — `ExportPlan.destination`,
`ExportEngine` mirror/verify/cloud, and `PurgePlanner`'s `ArchiveIndex.build` (the
≥2-copy gate). The **Cryptomator vault is exempt** (copied to the vault root).
Empty subfolder = pre-0.6 behavior. `ArchiveProfile` now decodes every key with
`decodeIfPresent` so old profiles migrate cleanly.

## Gotchas / lessons baked in

- **Entitlements file must be comment-free** — AMFI's XML parser rejects
  `<!-- -->` and codesign fails ("AMFIUnserializeXML: syntax error").
- **osxphotos / pattic need Full Disk Access** to read the library, including the
  scheduled background run (grant FDA to the bundled `pattic`).
- **Shared/syndicated items are excluded from the export by default** (`excludeSharedAndSyndicated`
  → osxphotos `--not-syndicated --not-shared`). "Shared with You" (Messages) and shared-album
  items aren't your originals and have **no downloadable master**, so without this they show
  up forever as bogus "missing" originals (incident 2026-06-11: the 3 un-fetchable "stragglers"
  were a texted pasta photo + a shared video — not owned content). Does NOT exclude your own
  iCloud **Shared Library** (`--shared-library`). NOTE for manual missing-checks: use
  `osxphotos query --missing --not-syndicated --not-shared --count` to match the archive's view.
- **`--download-missing` defaults to the PhotoKit path now** (`usePhotoKitForDownload`,
  → osxphotos `--use-photokit`). The legacy AppleScript path drives Photos and, on a
  slow/**indeterminate (`incloud=None`)** iCloud asset, **times out and `killall`s
  Photos** in a retry loop that wedges both Photos and the export (incident 2026-06-10:
  0/44 stragglers downloaded, Photos hung). PhotoKit requests the original directly and
  needs **no** Photos-Automation grant. Only turn the toggle off (AppleScript path) with
  a specific reason — and then the Automation grant is required again.
- **`AEDeterminePermissionToAutomateTarget` can hang** if Photos isn't frontmost —
  `PermissionsService.requestPhotosAutomation` launches/activates Photos first and
  calls the prompting form off the main thread.
- **macOS's default rsync is openrsync** (reports "2.6.9 compatible"), which rejects
  `--info=progress2` / `--progress` / `-P` and aborts instantly with a usage error.
  `ExportEngine.rsyncCopyArgs(versionBanner:)` branches on the `--version` banner —
  progress2 only for a real rsync 3.x, else plain `-ahv`. Don't reintroduce progress2
  unconditionally. (Broke mirror+verify+cloud on the first full run; verify's huge
  "discrepancy" count was a cascade from the empty mirror, not corruption.)
- **`AppSettings` decodes each key with `decodeIfPresent`** so adding a field
  doesn't reset older `settings.json`.
- **Purge ≥2-copy verification matches by FILENAME + primary↔mirror size CONSISTENCY, NOT the
  Photos `original_filesize`.** The export runs `--exiftool`, which writes metadata *into* each
  file, so an archived original is a few hundred bytes larger than its pre-export size. Matching
  the Photos size verified only 368/66,279 on the first real preview; the fix (filename present
  in primary + a mirror whose size-set intersects primary's) verifies 65,627/66,279. Don't
  reintroduce an `original_filesize` comparison. Future-proof option: correlate uuid→archived
  path via the osxphotos export DB. (Incident 2026-06-11.)
- **osxphotos `query --json` emits NON-STANDARD JSON** — bare `Infinity`/`-Infinity`/`NaN`
  literals (video audio `energyValues`, unset scores). Python parses them; **Swift's JSON
  parser rejects them** ("not valid JSON"), which silently broke the entire purge preview.
  `PhotoMetadataQuery.sanitizeNonFiniteLiterals` rewrites them to `null` in value position
  (string-aware) before decoding. Don't remove it. Also note the query payload is **large**
  (~727 MB / 68k records on a full library) because `--json` dumps every field; only ~9 are
  used. (Incident 2026-06-11: first real purge preview.)
- **osxphotos uuid → PHAsset.localIdentifier** is `"<uuid>/L0/001"`.
- **Deletion MUST be batched** — `PhotoKitPurger.deleteAssets` chunks (`defaultBatchSize` 1000)
  with one `performChanges` per chunk, continue-on-error, cancel-aware. A single atomic delete of
  the whole verified set fails with `PHPhotosErrorDomain 3300` at scale (and atomically, so one
  bad asset kills the batch). Don't revert to a one-shot delete. macOS confirms per chunk; re-runs
  retry anything not yet deleted. (Incident 2026-06-11: 65,627-asset atomic delete.) NOTE: PhotoKit
  deletion can't be validated headless (needs the app's Photos TCC grant + GUI) — unlike the purge
  *preview*, which a `swift run` harness CAN exercise.
- **Don't purge on MBP14** — its archive is only the local subset; treat purge as
  preview-only until Vortex holds the complete, verified archive.

## Status & open items

All planned phases complete: **A** engine + CLI, **B** GUI + backup + bundle +
library guard + vault status, **C** guarded purge (ships OFF), **D** launchd
scheduler. **0.6** added the permissions preflight, the "Photos Archive" subfolder
(physical destinations; vault exempt), and the free-space warning. **0.6.2–0.6.5**
fixed the openrsync↔Cryptomator cloud-copy issues (progress2 / `.DS_Store` /
chown / temp-file — see Gotchas). **0.7** added the live progress dashboard,
graceful embed-error handling, and the mirror mount guard. **0.8** added
"NEW PHOTOS TO REVIEW" staging of each incremental run's new items (on by
default; baseline-safe). **0.9** switched `--download-missing` to the PhotoKit
path (`usePhotoKitForDownload`, on by default) after the AppleScript path was
found to time out and kill Photos on indeterminate iCloud stragglers. The full
3-copy pipeline (export → mirror → verify → cloud) is validated end-to-end —
including on **production drives** (ROG_WHITE primary + LACIE mirror + vault),
Verify 350,522 files match, 0 discrepancies. **0.10** excludes shared/syndicated
("Shared with You") items from the export so non-owned content stops showing as
bogus "missing" originals. 93 tests passing.

Not yet done / possible next:
- First real **complete** archive on Vortex (gated on its iCloud download).
- Real-world purge run (only after the archive is complete + trusted).
- Possible: osxphotos export-DB-based correlation (currently filename+size), a
  `USER_MANUAL.md` Vortex first-run walkthrough, Sparkle auto-update.
