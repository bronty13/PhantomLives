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
photo can't be purge-eligible for a year); **deletion exists only in the app
target** (`PhotoKitPurger`) — the CLI links no Photos code and can never delete;
the **Optimize-Storage guard** blocks archiving an incomplete library.

**Automated staging vs. deletion (0.22).** The scheduler can now *stage*
automatically but still cannot *delete*. macOS shows an un-suppressible
confirmation on every `deleteAssets`, so unattended deletion is impossible by
design. Instead, when `purgeAutoStage` is on, a successful nightly archive writes
the verified-deletable set to `purge-plan.json` and the CLI launches the app's
**headless `--stage-agent`**, which adds that set to the "To Delete" album — a
*non-destructive* album-add (no confirmation). The album only ever *grows*; a
human emptying it in Photos is the sole deletion path. So the gate chain above is
intact: auto-staging is gate 1–3 done for you; gates 4–5 (the actual delete +
macOS's confirmation) remain human, every time.

## Module map

```
PurpleAtticCore (library)   — pure logic + IO; NO Photos framework, NO deletion.
  RetentionPolicy            keep/purge predicate (pure, the highest-stakes code)
  ArchiveProfile/ProfileStore JSON job description shared by CLI + GUI
  ExportPlan                 builds the osxphotos export argv (pure)
  ExportEngine               export → rsync mirror → verify → off-site (restic); RunSummary + report
  ResticService              non-interactive restic driver (env/args, init/backup/check/restore)
  CloudDestination           pluggable off-site target (kind: resticB2/resticRclone) in the profile
  RunLock                    single-writer flock so hourly+manual+on-mount runs never collide
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
  RunRecord / RunMetrics     typed per-run metrics + RunHistoryStore (run-history.jsonl) — the
                             machine-readable run history the dashboard charts
  PurgeManifest              the verified-deletable set a run computes (purge-plan.json) for the
                             stage-agent + dashboard; PurgeManifestStore read/write + staleness
  PurgeAuditRecord           one staged/deleted action (auto|manual) → PurgeAuditStore (purge-audit.jsonl)
  DashboardMetrics           pure roll-ups (summary + time-series) over the three stores above
  AtticJSON                  shared ISO-8601 JSONL/document coders for the stores
  Tooling / ProcessRunner / AtticLogger   tool locator, subprocess, logging

pattic (executable)         — CLI front-end. Subcommands: doctor/init/plan/export. Still links NO
                              Photos code: it PLANS the purge (pure Core → purge-plan.json) and,
                              when purgeAutoStage is on, LAUNCHES the app's stage-agent — but never
                              deletes/stages itself. Safe to run headless / from the scheduler.

PurpleAtticApp (executable) — the SwiftUI app (PurpleAttic.app). Imports Core.
  AppState                   view-model; runs the engine off-main, streams log lines;
                             holds the permissions report + free-space checks; gates runs
  SettingsStore/AppSettings  profile + app settings (backup, schedule) as JSON
  Services/PermissionsService preflight: FDA (Core probe) + Photos Automation
                             (AEDeterminePermissionToAutomateTarget) + Photos (PhotoKit)
  Services/PhotoKitPurger    the ONLY deletion code (import Photos) — GUI-only
  Services/StagingAgent      headless `--stage-agent` mode: read purge-plan.json → re-check drives →
                             stageToAlbum (non-destructive) → write audit → quit. App-target (PhotoKit)
  Services/SchedulerService  writes the LaunchAgent + launchctl bootstrap/kickstart
  Views/DashboardView        the monitoring dashboard (landing pane) — Swift Charts over the stores
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

- **Archive (safe):** GUI/CLI → `ExportEngine.run(profile)` (under a `RunLock`
  single-writer flock) → osxphotos export (HEIC originals pass + `--convert-to-jpeg`
  pass) → rsync mirror (no `--delete`) → `VerifyService` → **`ResticService.backup`
  per enabled `cloudDestination`** (E2EE off-site, e.g. B2; offline = clean skip;
  `restic check` after) → detailed log (`~/Library/Logs/PurpleAttic/`) + report
  (`~/Downloads/PurpleAttic/`). A blank replacement primary is re-seeded from a
  populated mirror before export. Secrets come from the macOS Keychain. *(The old
  Cryptomator/macFUSE → iCloud vault is retired; `cloudVaultPath` is decode-only.)*
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
- **Auto-stage (0.22, opt-in via `purgeAutoStage`):** after a fully-successful
  scheduled archive, `ExportEngine` runs `PurgePlanner.compute` (pure Core; the
  same query/verify as the GUI preview) and writes `purge-plan.json`. The CLI then
  `open -gj <App>.app --args --stage-agent`. The app launches with activation
  policy `.prohibited` (no window/Dock), `StagingAgent.run` re-checks the manifest
  is fresh + the primary and ≥1 mirror are mounted, calls `PhotoKitPurger.stageToAlbum`,
  appends a `PurgeAuditRecord(trigger: .auto)`, then `NSApp.terminate`. A failed/partial
  archive never stages; no GUI session → `open` fails and the manifest waits.
- **Instrumentation (0.22):** every real run appends a `RunRecord` (typed metrics)
  to `run-history.jsonl`; every stage/delete appends a `PurgeAuditRecord` to
  `purge-audit.jsonl`. `DashboardView` charts both + the latest manifest. All three
  stores live in `~/Library/Application Support/PurpleAttic/`.

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

## Scheduled-run "access data from other apps" prompt — KNOWN macOS LIMITATION (do not re-investigate)

**Symptom:** every scheduled run pops *"PurpleAttic would like to access data from
other apps"* (`kTCCServiceSystemPolicyAppData`). It recurs no matter what the user clicks.

**Root cause (Apple, "as expected" — Feedback FB13410100):** accessing *another app's
data container* — here `~/Library/Containers/com.apple.CloudPhotosConfiguration/Data`,
which osxphotos reads during "Processing shared iCloud library info" on every PhotosDB
load — is a **transient, process-lifetime TCC privilege**. It is *intentionally
non-persistent*: every new process (each scheduled `pattic`/osxphotos launch = new pid)
re-triggers it, and there is **no documented way to make it stick** without MDM. Clicking
*Allow* writes `auth_value=5` (a transient marker), never the durable `2`.

**Caveat to the "child inherits the parent's TCC grants" rule above:** that holds for
**Full Disk Access** (file reads) and is why osxphotos reads the library fine — but it does
**NOT** extend to this `SystemPolicyAppData` container consent.

**What was tried and PROVEN not to work** (2026-06-18, via the `tccd` unified log
`AUTHREQ_ATTRIBUTION` + system-vs-user `TCC.db`):
- FDA on the bundled `pattic` — granted (`auth_value=2`), still prompts.
- FDA on the osxphotos **Python** binary — granted, still prompts.
- Routing the scheduler through the FDA-holding `.app` (so `responsible=PurpleAttic.app`,
  like a terminal) — still prompts. (That headless-export experiment was reverted.)
- `tccutil reset SystemPolicyAppData …` — clears the row, but the next access re-prompts.
- A PPPC/TCC **configuration profile** would pre-authorize it, but local install is rejected
  ("must originate from a user-approved MDM server") — **not viable on a personal, non-MDM Mac.**

**Why Warp (a terminal) is silent but PurpleAttic isn't:** unresolved, but irrelevant — the
consent is non-persistent by design, so chasing app-side parity is a dead end.

**Mitigation in place:** schedule defaulted from **hourly → daily** (cadence `daily`, 02:00),
so the prompt is seen at most ~once/day instead of once/hour. The only true eliminations are
MDM (overkill) or osxphotos not touching the shared-library container (no flag for it).

Diagnostic recipe if this resurfaces: `log show --predicate 'process == "tccd"' --info --debug`
and grep `SystemPolicyAppData` / `AUTHREQ_ATTRIBUTION` for the `responsible`/`accessing` pair;
FDA lives in the **system** db `/Library/Application Support/com.apple.TCC/TCC.db` (world-readable),
NOT the user db.

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
bogus "missing" originals. **0.22** added automated nightly purge **staging**
(opt-in `purgeAutoStage`: plan in the CLI → `purge-plan.json` → app `--stage-agent`
adds the verified set to the "To Delete" album, non-destructively), structured
**run history + purge audit** stores (`run-history.jsonl` / `purge-audit.jsonl`),
and a **monitoring Dashboard** (the new landing pane: archive health, purge/space,
new-items, off-site B2 — Swift Charts + drill-down). 167 tests passing.

Not yet done / possible next:
- First real **complete** archive on Vortex (gated on its iCloud download).
- Watch the Dashboard's "ready to purge" for a night or two (auto-stage OFF) to
  confirm the criteria pick the right photos, THEN flip `purgeAutoStage` on.
- Possible: a retention/prune policy for the JSONL stores (currently unbounded —
  fine for years of daily runs, but trim eventually); osxphotos export-DB-based
  correlation (currently filename+size); Sparkle auto-update.
