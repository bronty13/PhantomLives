# PurpleReel Changelog

PurpleReel uses a build-number-as-version scheme — every commit
bumps the bundle version via `build-app.sh`. The v1.0 milestone
declared the schema baseline; subsequent commits increment the
patch number (`1.0.<count-since-baseline>`). Older 0.1.x builds
are still installable from their original artefacts.

Newest first.

---

## C40 — Tahoe-correct Privacy & Security wizard

The first-launch Privacy & Security wizard previously told users to
grant Removable Volumes and Network Volumes in System Settings, then
tick a checkbox. On macOS 15+ (Sequoia / Tahoe) those rows in System
Settings → Privacy & Security don't exist until an app has actually
attempted to read from a real mount and triggered a TCC prompt —
there is no "Add app" affordance, so the instructions were
unfollowable. The wizard now reflects the consent-on-first-use model:

- Header subtitle and per-row blurbs explain that macOS will prompt
  inline when PurpleReel first touches a USB drive / SD card / NAS
  share — no preparation in System Settings is needed.
- The **Trigger prompt…** button on each row fires the OS dialog on
  demand: Removable opens an `NSOpenPanel` rooted at `/Volumes/`,
  Network kicks Finder's Connect-to-Server panel plus the same
  picker, then PurpleReel attempts the read against the chosen
  volume so macOS will Allow/Deny inline.
- The checkbox is now **Don't remind me** — purely a nag-dismiss
  flag. It auto-checks when a Trigger prompt succeeds, and a tooltip
  makes clear it grants nothing on its own.
- Per-row status line echoes the outcome (granted / cancelled /
  denied + reason) without an extra alert.
- Auto-detected rows (Files & Folders, Full Disk Access) and the
  Re-check / Quit / Done footer are unchanged.

New `Tests/PurpleReelTests/PermissionsCheckTests.swift` covers
`canRead`, the new `attemptRead(at:)` shared helper, `Result`'s
`hasMinimumViable` short-circuit, and parseability of the deep-link
URLs. UserDefaults keys changed from `permissionsRemovableConfirmed`
/ `permissionsNetworkConfirmed` to `…Dismissed` to match the new
semantics — users who'd previously ticked the boxes will see the
rows re-appear once. Docs: USER_MANUAL.md gains a *Privacy &
Security on macOS 15+* subsection; README.md mentions it under
*macOS permissions*.

---

## v1.0 — Kyno parity + Beyond-Kyno polish (milestone)

**Shipped:** all 85 rows of `KYNO_RESEARCH.md` are either
addressed in code or explicitly out of scope (UI localization,
Resolve FCP7-XML, Op-Atom MXF / R3D / P2 native — see
`KYNO_PARITY_ROADMAP.md` for the per-row table). Plus 19 commits
of post-parity polish (C21–C39):

- **Combine Clips as a real editor**: per-clip trim + drag-reorder
  (C16), marker preservation (C17), audio-only (C18), dimension-
  match (C19), cross-fades with per-pair override + 8-segment
  non-linear easing (C20/C23/C24/C27/C36).
- **FCPXML round-trip**: project-membership tracking on import
  (C25), destination picker + recents on export (C38).
- **Discoverability sweep**: drilldown hint banner (C21), no-
  results banner (C29), offline-root / permission-denied / stale-
  catalogue / multi-root summary banners (C31).
- **Workflow chains as a real automation surface**: continueOnFailure
  + built-in templates (C33), run resumption across launches via
  on-disk snapshots (C34), per-step cancel including mid-flight
  backup interrupt (C32/C37).
- **Workspace cache complete**: orphan + age-based prune (C32/C35),
  auto-prune on launch (C36), schema-version + multi-root coverage
  (C32).
- **Schema growth**: v8 `fcp_project_usage` (C25), v9 `clip_metadata.{cameraLUTPath,creativeLUTPath}` (C30).
- **Inspector polish**: per-clip LUT pinning (C30), `${markerTitle}`
  token in batch rename (C22), recent destinations across Convert
  and Combine (C22) and FCPXML (C38), custom-file LUT picker (C22),
  XLSX section-toggle column dropping with OOXML column-letter
  realignment (C26).
- **Docs**: README "Why PurpleReel" (C28), MIGRATING_FROM_KYNO.md
  step-by-step guide (C39), parity-roadmap refresh (C39).

**Deferred to v2 (planned)**:
- macOS Tahoe `AVMutableVideoComposition` migration —
  `AVVideoComposition.Configuration` API. C20/C23/C27/C36 all use
  the deprecated form; tech-debt-only until next macOS major.
- Real Frame.io upload (OAuth + REST + C2C auto-upload). C38 ships
  the preset only.
- Mid-step resumption for workflow chains (cooperative
  checkpointing inside VerifiedBackupService / TranscodeJob).
- Category J — Live monitoring, automated QC pass, AI/ML
  metadata, cloud-team workflow.

Test totals at v1.0: 250+ XCTest cases across 50+ test files,
covering services / models / view-state computeds. UI integration
is manual QA per CHANGELOG entries.

---

## Sprint 10 (in progress) — Convert dialog + right-click reshape

Multi-commit restructure to match Kyno's Convert / Combine / Export
Subclips UX (per user screenshots showing ~120 presets across 8
buckets + per-channel Copy/Re-encode controls + tabbed Settings…
editor for Encoding / Filters / LUTs / Overlays / Container).

### C39 — Docs: parity-roadmap refresh + Migrating-from-Kyno guide

No-code release. Two doc deliverables:

**Item 13 — `KYNO_PARITY_ROADMAP.md` refresh.** The roadmap was
last-updated at the end of Sprint 4 ("status: complete"). C21–C38
added a meaningful pile of follow-ups (Combine Clips maturation,
discoverability sweep, workflow chain run resumption, workspace
cache age-based eviction, per-clip LUT pinning, …). C39 appends a
"Post-parity polish (C21–C38)" section with cross-references to
the relevant CHANGELOG entries — keeps the doc trustworthy as a
status snapshot. Also updates the Frame.io entry under "items
that fell out of scope" to reflect C38's review-preset addition.

**Item 14 — `MIGRATING_FROM_KYNO.md` (NEW).** A step-by-step
walkthrough for the Kyno user evaluating PurpleReel:
1. First launch — workspace setup + Permissions Wizard.
2. Bringing in `.LP_Store/` metadata (one-way, merge rules
   spelled out).
3. Round-trip with Final Cut via FCPXML (C25's per-project
   tracking gets a mention).
4. Camera-card workflow (workflow chain templates from C33 +
   run resumption from C34).
5. Keyboard-shortcut mapping (Coming from Kyno toggle + table).
6. Deliberate differences (centralized catalog, no live-waveform-
   on-import, no `.fcpbundle` introspection, Apple Silicon
   native).
7. On-disk file locations cheat-sheet.

README's "Why PurpleReel (vs Kyno)" section gains a paragraph
pointing at the new doc.

### C38 — FCPXML destination picker + Frame.io review preset

Two unrelated mediums bundled.

**Item 10 — Recent destinations for FCPXML export.** Pre-C38 the
FCPXML export sheet had no destination picker — every export
landed in the hardcoded `~/Downloads/PurpleReel/exports/` path.
Users couldn't redirect a one-off export to (say) the production's
delivery share, and there was no "recent destinations" memory
across sessions.

- New `RecentDestinations.Scope.fcpxml` enum case alongside
  `.convert` and `.combine` (matches C22's per-scope pattern).
- `FCPXMLExportOptions.outputDir: URL?` (nil = legacy default).
- `AppState.exportFCPXML(scope:options:)` honors the new field:
  when set, uses it + pushes onto recents; when nil, falls back
  to the legacy `fcpxmlExportDirectory()` path.
- `FCPXMLExportSheet` adds a `destinationRow` between the event
  name and file-reference rows: "Save to:" label + path + a
  Choose… button + a clock-arrow Menu listing recents (with a
  "Use Default" item at the top to clear the override). Menu
  hidden when recents list is empty (first-run UX matches
  pre-C38).

**Item 11 — Frame.io review preset.** Adds a built-in transcode
preset that produces Frame.io's recommended ingest format:
H.264 1080p MP4, AAC audio. Streams cleanly in their player + no
re-transcode cost on upload + universal audio support in their
review UI.

- New `frameio-review` preset in `TranscodePreset.all` (web
  category, suffix `_frameio`).
- Note: the preset stops at producing the file. Real auto-upload
  via Frame.io's OAuth + REST API is intentionally deferred —
  that's a separate feature decision (credentials storage, the
  C2C "auto-upload as soon as ingested" question, project /
  workspace mapping). Surfaces as a marketing bullet for now
  ("PurpleReel exports to Frame.io's recommended format"); real
  integration is a future commit when there's user demand.

### C37 — Real backup-step cancel for workflow chains

C32 noted that VerifiedBackupService didn't honor mid-flight
cancellation — the chain's `cancel()` only stopped processing at
step boundaries (the next step never started, but the current
backup ran to completion). C37 closes that gap.

**Model** — `BackupJob`:
- New `@Published private(set) var isCancelled: Bool` + `cancel()`.
- New `BackupFileState.cancelled` case alongside `.failed` /
  `.done` so the run sheet can render "you stopped this one"
  separately from "it broke at verify".

**Service** — `VerifiedBackupService.run(...)`:
- Per-file loop checks `job.isCancelled` at the top of each
  iteration. Files NOT yet processed get marked `.cancelled`
  and a `cancelledCount` is tracked alongside `succeeded` /
  `failed`. Granularity: between files, not mid-bytestream —
  a partial copy would be invalid anyway, so we let the
  in-flight file finish (verified or fail-fast) before bailing.

**Workflow runner** — `WorkflowChainRun.cancel()`:
- Drops the C32 "known gap" comment, calls
  `activeBackup?.cancel()`. The chain's existing
  `activeBackup: weak BackupJob?` link (already wired by
  C32 for tracking) becomes load-bearing instead of just
  bookkeeping.

**View** — `BackupView.swift`:
- Per-file row renders `.cancelled` with a
  "minus.circle.fill" + secondary tint and "cancelled" label,
  distinct from `.failed`'s xmark.octagon.fill red.

**Tests** — `BackupJobCancelTests` (NEW, 4 cases):
- Default state: not cancelled.
- `cancel()` flips the flag.
- Idempotent (re-cancel is a no-op).
- `.cancelled` ≠ `.failed` (different enum cases).

Full mid-bytestream cancel within a single hash/copy/verify of
a multi-GB file is still deferred — that needs cooperative
cancellation inside the hash + copy loops via Task cancellation.
Documented in the file-loop comment.

### C36 — Polish bundle: auto-prune-on-launch + ConvertSheet LUT defaults + per-pair easing

Three smalls bundled.

**Item 2 — Auto-prune-on-launch for workspace cache.** C32 + C35
shipped the prune logic but it was manual-button-only. C36 adds
an interval-based auto-run on app launch:
- New `@AppStorage("sidecarAutoPruneIntervalDays")`. 0 disables;
  1-90 enables.
- AppState's static `runWorkspaceCacheAutoPruneIfNeeded()` reads
  workspace roots + maxAge cap from UserDefaults (works pre-init
  fully populating self), checks `now - sidecarLastPruneAt`
  against the interval, and kicks a detached background Task if
  due. Persists `sidecarLastPruneAt` on completion.
- Settings → Workspace Cache adds a Stepper "Auto-prune on
  launch every N day(s)" alongside the existing age-cap stepper.

**Item 9 — Convert dialog auto-defaults from pinned LUTs.** C30
shipped per-clip Camera + Creative LUT pinning on
`clip_metadata`, but the Convert dialog still picked defaults
from `TranscodePreset.defaultOptions()` regardless. C36 wires
the pinned paths through:
- `ConvertSheet.onAppear` checks if `state.assets.count == 1`
  and the asset has `clipMetadata.cameraLUTPath` /
  `creativeLUTPath` set, then patches `editableOptions.cameraLUT`
  / `creativeLUT` to `.file(path:)` before stashing the baseline.
- Batch jobs (2+ assets) skip — ambiguous which clip's LUT
  should win.

**Item 12 — Per-pair easing override in Combine.** C27 shipped a
chain-wide easing curve. C36 lets each pair carry its own:
- `CombineSource.crossfadeEasingAfter: CrossfadeEasing?` (nil =
  inherit job's global `crossfadeEasing`). Same "ownership" rule
  as the C24 per-pair cross-fade duration override — owned by
  the clip BEFORE the transition.
- `applyEasedOpacityRamp` and `applyEasedVolumeRamp` accept an
  `easing: CrossfadeEasing?` parameter that takes precedence
  over `self.crossfadeEasing`. Nil falls through to the global.
- Video composition + audio mix builders take a parallel
  `easings: [CrossfadeEasing?]` array threaded from the source
  list, mirroring the C24 `crossfades: [Double]` shape.
- Sheet row gets a small "function" / "function.fill" Menu next
  to the per-row CF→ field with Inherit + Linear + Ease In +
  Ease Out + Ease In-Out options. Filled icon + tint when an
  override is set; outline + secondary when inheriting.

### C35 — Workspace cache: age-based eviction

Deferred G3. The C32 orphan-prune handles sidecars whose source
file is gone, but a long-lived NAS workspace also accumulates
sidecars that are technically "live" (source still exists) yet
genuinely stale — the user hasn't touched that clip in 18 months,
the cached log fields haven't changed in years, etc. Pre-C35
these stayed forever; C35 adds a per-installation "delete sidecars
older than N days" policy.

**Service** — `WorkspaceCacheService.pruneOrphans(under:maxAgeDays:)`:
- New optional `maxAgeDays: Int?` parameter (default nil = no
  age limit, orphan-only sweep matching pre-C35 behavior).
- Per-sidecar decision: delete if **orphan OR over-age**. Either
  reason fires, both rules compose. A live + young sidecar
  survives both filters.
- Age check reads `attributesOfItem(atPath:)[.modificationDate]`;
  cutoff = `now - days * 86400`. Older = delete.

**Settings** — General → Workspace Cache:
- New Stepper "Also delete sidecars older than N day(s)" (0-365).
  0 disables the cap (orphan-only). Persists via
  `@AppStorage("sidecarMaxAgeDays")`.
- `pruneOrphanedSidecars()` reads the stepper value and passes
  through to the service; the Settings UI now controls both the
  trigger (button) AND the policy (age cap).

**Tests** — `WorkspaceCacheServiceTests` (3 new, 14 total):
- `testPruneWithoutAgeCapKeepsOldButLiveSidecars` — a 100-day
  old sidecar with a live source survives when nil is passed.
- `testPruneWithAgeCapDeletesOverAgeSidecars` — same setup with
  `maxAgeDays = 30` deletes the over-age but keeps a fresh
  sibling.
- `testPruneWithZeroAgeCapIsOrphanOnly` — 0 behaves the same as
  nil (matches the Settings stepper's "off" semantics).

### C34 — Workflow chain run resumption across app launches

Deferred from C33's E3. A workflow-chain run can be 30+ minutes
(verified backup of a 256GB camera card → 30 transcodes → CSV
report). Pre-C34, a force-quit / crash / "Cmd-Q during a backup"
lost every per-step state and the user had to re-run the whole
chain from scratch — re-verifying every file, re-encoding every
clip.

C34 snapshots the run's progress to disk after every successful
step. On the next app launch, AppState surfaces a one-shot resume
prompt offering to pick up at the first incomplete step.

**Persistence service** — new `ActiveRunPersistence` enum:
- `Snapshot` codable type: id, chain (full JSON), sourcePath,
  startedAt, lastUpdatedAt, completedStepIndices.
- Files at `~/Library/Application Support/PurpleReel/active-runs/<UUID>.json`.
- API: `save(_:)` (atomic write), `delete(UUID)`, `loadAll()`
  (newest-first), `clearAll()` for the "Discard all" button.
- Test seam: `directoryOverride` lets unit tests redirect to a
  temp path without mocking FileManager.

**Runner integration** — `WorkflowChainRun`:
- New `snapshotID`, `preCompletedIndices`, `isResumed` fields.
- New `init(resumingFrom: Snapshot)` reconstructs a run from a
  snapshot — steps in `completedStepIndices` are pre-marked
  `.finished` with detail "Already finished in prior session"
  + progress 1.
- `run()`:
  - Writes initial snapshot before the first step (so an
    immediate crash leaves something to resume).
  - Refreshes snapshot after every step that transitions to
    `.finished`.
  - On overall `.finished`: deletes the snapshot (clean exit).
  - On `.cancelled`: deletes (user explicitly abandoned).
  - On `.failed`: KEEPS the snapshot (user might retry).
- Resumed runs skip steps whose index is in
  `preCompletedIndices` — the loop bumps `currentStep` past
  them without re-running.

**Launch prompt** — `AppState` + `ContentView`:
- `AppState.interruptedRuns: [Snapshot]` populated in init via
  `ActiveRunPersistence.loadAll()`.
- `AppState.resumeInterruptedRun(_:)` stashes the chosen
  snapshot in `pendingResumeSnapshot` and pops open the
  Workflow Chains sheet.
- `WorkflowChainsSheet.consumePendingResume()` picks up the
  stash on appear, ensures the chain is in the local list
  (re-adds if the user deleted it), and kicks
  `WorkflowChainRun(resumingFrom:).run()` after a short delay
  for the layout to settle.
- `ContentView` adds a single-shot `.alert` gated by
  `resumePromptShown` — fires when AppState's `interruptedRuns`
  is non-empty after launch. Three buttons:
  - **Resume "<name>"** — calls `resumeInterruptedRun`.
  - **Discard All** — wipes every snapshot via
    `ActiveRunPersistence.clearAll()`.
  - **Not Now** — leaves snapshots on disk for next launch.

**Tests** — `ActiveRunPersistenceTests` (NEW, 8 cases):
- Save + loadAll round-trip with all fields preserved.
- Empty dir → empty list.
- Save same id → overwrite (no duplicates).
- Delete removes the file; delete unknown id is a no-op.
- clearAll wipes every snapshot.
- loadAll sorts newest-first by `lastUpdatedAt`.
- Resume reconstruction: pre-completed indices land as
  `.finished` step states with progress 1; non-completed
  remain `.queued`.

**Known gap**: a chain that was interrupted mid-step (e.g.
verified backup halfway through hash-checking) still has to
restart that step from scratch — we only resume at step
boundaries. True mid-step resumption needs cooperative
checkpointing inside `VerifiedBackupService` / `TranscodeJob`
itself, which is much bigger. Documented as a follow-up for
the day someone files a "my 8-hour ingest crashed at 7h59m"
ticket.

### C33 — Workflow chains: continueOnFailure + templates library

Two more Category E deferrals. Skip-failed-step opens the
"best-effort" pipeline pattern (where one codec-quirky source
shouldn't terminate the whole chain), and templates eliminate the
"empty editor with no idea what to build" cold-start.

**E2 — Skip-failed-step option** (`WorkflowChain` + runner):
- `WorkflowChain.continueOnFailure: Bool = false` field. Default
  matches pre-C33 abort-on-first-failure behavior; explicit `true`
  opts into best-effort.
- Custom `Codable` decoder (`decodeIfPresent` for every field
  except `id`/`name`) so chain JSON saved before C33 still loads
  cleanly — users don't lose their saved chains on upgrade.
- `WorkflowChainRun.run(...)` checks the flag on per-step
  failure; aborts when off, marks-and-continues when on. Final
  run state is `.failed("X of N step(s) failed")` if any step
  failed regardless of mode — the user always sees a clear
  outcome.
- Sheet adds "Continue running remaining steps when one fails
  (best-effort)" toggle in the editor topRow.

**E4 — Chain templates library** (`WorkflowChain.swift` +
sheet):
- New `WorkflowChainTemplates` enum with four built-in
  templates:
  - **Camera Card Offload** — Verified Backup only;
    `runOnCameraMediaMount: true` baked in for DIT set workflow.
  - **Daily Delivery (Backup + H.264 + CSV)** — three-step
    end-of-day pipeline; `continueOnFailure: true` so a codec-
    quirky source doesn't block the report.
  - **Proxy Generation Only** — single Transcode step, ProRes
    Proxy preset; useful when the backup lives elsewhere.
  - **Catalogue Report Only** — single HTML report;
    no-render shortcut for producer/director clip-list shares.
- Each template carries `id`, `name`, `description`, `icon`,
  and a `build()` factory that mints a fresh UUID per call (so
  two "Add from template" clicks produce two distinct rows).
- Sheet's chain-management toolbar gains a "doc.on.doc" Menu
  next to the existing "+" button. Each template surfaces as a
  Label with its icon + tooltip carrying the description.

**Tests** — 7 new in `WorkflowChainTests` (total 13):
- continueOnFailure defaults to false.
- Legacy JSON (pre-C33, no continueOnFailure field) decodes as
  false — explicit back-compat coverage.
- continueOnFailure survives Codable round-trip.
- Every template builds a chain with at least one step + only
  fails validation for the expected "no destinations" reason
  (templates intentionally leave backup destinations empty for
  the user to fill in).
- Template builds are not aliased (each call → fresh UUID).
- Daily Delivery template carries continueOnFailure=true
  (per its self-description).
- Camera Card Offload template auto-triggers on mount.

### C32 — Workflow chain + workspace cache polish bundle

Five small deferrals from Categories E and F bundled together.

**E1 — Per-step cancel for Transcode + Report** (WorkflowChainsService):
- `WorkflowChainRun.cancel()` now propagates beyond setting the
  run-state flag. Holds an `activeTranscodes: [TranscodeJob]`
  field that the Transcode step populates while its jobs are in
  flight; cancel calls `.cancel()` on each sub-job and the loop
  breaks promptly on the next poll tick.
- Report-export step (CSV + HTML) checks the run's `state` at
  await boundaries: pre-export (skip the export entirely if
  already cancelled) and post-export (remove partial output if
  the user hit cancel during the HTML write).
- Backup step still respects step-boundary cancel only —
  `VerifiedBackupService` doesn't currently expose mid-flight
  interruption; documented as a known gap for a future
  BackupJob.cancel() API.

**E5 — Drag-reorder steps in editor** (WorkflowChainsSheet):
- Replaced the up/down arrow buttons with a native `List + .onMove`.
- Step rows lose `canMoveUp`/`canMoveDown` props; the list takes
  care of drag-handle rendering and reorder math.
- Caption added: "drag rows to reorder" when 2+ steps present.

**G1 — Orphan-sidecar prune** (WorkspaceCacheService):
- New `pruneOrphans(under: URL) -> PruneResult` walks
  `.purplereel/*.json` sidecars and deletes any whose source
  file is gone. Walker explicitly does NOT use
  `.skipsHiddenFiles` (we need to descend into the `.purplereel/`
  directory).
- New "Prune Orphaned Sidecars…" button in Settings → General →
  Workspace Cache. Shown only when workspaceRoots is non-empty;
  runs on a detached Task; reports aggregated scanned/deleted/
  failed counts in an NSAlert.

**G2 — Schema versioning regression guard**
(WorkspaceCacheServiceTests):
- `testLoadReturnsNilWhenVersionExceedsCurrent` — writes a
  hand-crafted v99 sidecar and verifies `loadIfFresh` returns
  nil. Pins the rejection rule so a future schema bump can't
  silently break older builds.
- `testCurrentVersionIsLockedAtOne` — lock current version at 1
  to prevent accidental bumps without a migration path.

**G4 — Multi-root workspace coverage**:
- `testTwoRootsEachWriteToOwnPurplereelDirectory` — two assets
  on two different roots each get their own `.purplereel/`
  directory; both load back independently. Pins the per-asset
  path math against future regressions toward a global cache
  index.

**Tests added/modified**: 4 new + 1 baseline = 11 total in
WorkspaceCacheServiceTests (was 7).

### C31 — Silent-gotcha sweep #2: workspace + catalogue banners

Sibling of C21 / C29. Surfaces four more "the UI is technically
correct but the user has no idea why it's behaving this way"
states with inline banners + a toolbar caption.

**AppState** — three new computeds + one PermissionsCheck change:
- `offlineWorkspaceRoots: [URL]` — workspace roots whose paths
  don't resolve on disk right now.
- `catalogueOfflineCount: Int` and
  `catalogueOfflineFraction: Double` — how much of the catalogue
  is currently unreachable.
- `permissionDeniedWorkspaceRoots: [URL]` — roots that exist but
  PurpleReel can't enumerate (Files & Folders / FDA not granted).
- `PermissionsCheck.canRead(path:)` is now public so the AppState
  computed can probe arbitrary user-chosen folders.

**BrowserView** — four new surfaces stacked below the toolbar
Divider, each self-suppressing:

1. **`offlineWorkspaceRootsBanner`** — red strip,
   externaldrive.badge.xmark icon. Lists the offline roots and
   shows a "Reconnect…" button that opens an NSOpenPanel and
   swaps the stale URL in `workspaceRoots` for the new mount
   point. Triggers a rescan automatically.

2. **`permissionsBanner`** — orange strip, lock.fill icon. Fires
   when a workspace root exists per FileManager but
   `contentsOfDirectory` throws. "Open System Settings…" jumps
   straight to Files & Folders pane.

3. **`staleCatalogueBanner`** — yellow strip, questionmark.folder
   icon. Threshold: ≥5 offline assets AND ≥10% of total catalogue
   AND offline-workspace-roots banner isn't already explaining
   the loss. "Rescan" + "Find Lost Metadata…" actions wire to
   existing AppState methods.

4. **`multiRootSummary`** — small toolbar-end caption
   `rectangle.stack  N/M ✗` (online / total + red drive icon
   when any offline). Only when `workspaceRoots.count >= 2`.

**Thresholds chosen for signal/noise**:
- Stale-catalogue: ≥5 + ≥10% avoids firing on tiny 3-asset
  workspaces where one offline = 33%.
- Stale-catalogue suppressed when offlineWorkspaceRoots > 0 —
  the offline-roots banner already explains the same loss.
- Multi-root caption only at ≥2 roots: single-root is the
  assumed default UX; one root with no caption is silent.

No unit tests — all four are state inspection + UI render; the
detection helpers are thin wrappers over FileManager.fileExists
and PermissionsCheck.canRead(path:). Manual QA: eject a drive
that hosts a workspace root → red banner; deny PurpleReel's
Files & Folders permission for a Movies folder → orange banner;
delete a chunk of catalogued files → yellow banner.

### C30 — Per-clip Camera + Creative LUT pinning

Deferred from C5. Camera LUT and Creative LUT are conceptually
distinct roles — Camera LUT inverts log-encoded source back to
scene-linear (e.g. SLog3 → Rec.709), Creative LUT layers a
stylistic grade on top. C5 split them at the
`TranscodeOptions` layer but the choice was transient — every
transcode required re-picking. C30 lands per-clip persistence so
the same look re-applies across sessions automatically.

**Schema** — `DatabaseService.swift` migration v9:
- Adds `cameraLUTPath TEXT` and `creativeLUTPath TEXT` columns to
  `clip_metadata` (both NULL by default for existing rows).

**Model** — `ClipMetadata.swift`:
- Two new nullable fields:
  `cameraLUTPath: String?` and `creativeLUTPath: String?`.
- `ClipMetadata.empty` initializer updated to pass nil for both
  (back-compat default).

**UI** — `MetadataPaneView.swift`:
- New "LUTs" inspector section with two rows:
  - Camera row: shows pinned LUT filename + Change… / clear (×),
    or "None" + Pick… when unset.
  - Creative row: same affordances.
- `pickLUT(...)` helper opens NSOpenPanel filtered to
  `.cube` / `.3dl` / `.dat` / `.lut`.
- Setting via `appState.updateClipMetadata(\.cameraLUTPath,
  value:)` reuses the existing string-trim-to-nil persistence
  pattern; empty string clears.

**Tests** — `ClipMetadataLUTTests.swift` (NEW, 6 cases):
- `ClipMetadata.empty` has both LUT paths nil.
- Camera LUT round-trips through DB; creative stays nil
  independently.
- Creative LUT round-trips; camera stays nil.
- Both LUTs persist independently when set together.
- Replacing a LUT path overwrites the prior value.
- Nil round-trips correctly (verifies v9 migration's NULL
  default works).

**Deferred follow-up**: when a single clip is selected in the
Convert dialog, default the LUT pickers to the pinned paths. That
requires plumbing `clipMetadata` through `ConvertSheetState` and
isn't strictly required for the persistence story to be useful
(users can still pick once and re-pick from Recent the next
session). Separate commit.

### C29 — Silent-gotcha sweep: "no results" banner for active filters

Sibling of C21's drilldown-hint banner. When the user lands on a
folder that has assets in the catalogue but the visible list is
empty because of one or more active gates (search term / type chip
/ date filter / advanced filter pills), the UI used to silently
show a blank list. C29 replaces the blank list with an inline panel
that explains *which* gate is hiding things and offers a one-click
clear button per gate.

**Detection** — `BrowserView.shouldShowNoResultsBanner`:
- Folder has at least one catalogued asset (direct or nested via
  C21's `folderCounts(forFolder:)`).
- AND filteredAssets is empty.
- AND at least one gate is non-default:
  `typeFilter != "all"`, `timeFilter != "any"`,
  `!activeFilters.isEmpty`, or non-empty search term.

If folder really has zero assets (or drilldown is off — C21
covers that), the banner stays quiet.

**UI** — `noResultsBanner` view:
- Centered "No assets match the current filters" message.
- One row per active gate listing the cause + a Clear button
  that drops just that gate. So a user with both a typed
  search and a type-chip selection sees two distinct rows
  with their own clear actions — no all-or-nothing.
- Date-filter rows use human-readable labels ("Last 24 hours")
  instead of the storage keys ("24h").

No new tests — the helper is straight state inspection that
mirrors existing UI bindings (Picker selections + AppStorage
keys). Manual QA: type a search that matches nothing → banner
appears; click "Clear search" → list re-populates.

### C28 — Marketing copy sweep ("Why PurpleReel")

KYNO_RESEARCH rows 71/72/77/81 are non-engineering marketing
levers — competitive advantages PurpleReel already has but doesn't
surface to potential users. C28 lands them as a "Why PurpleReel
(vs Kyno)" section in the README:

- **Row 77 — Apple Silicon native.** Kyno's auto-updater ships
  Intel-only on Apple Silicon; PurpleReel has no Intel build by
  construction.
- **Row 71 — Active development, public roadmap.** Counters
  Signiant-acquisition abandonment perception by pointing at the
  monthly CHANGELOG cadence and the public parity roadmap doc.
- **Row 81 — Pay-once licensing.** Kyno is €159/year renewal-for-
  updates; PurpleReel ships from PhantomLives one-time-pay,
  every update included.
- **Row 72 — Community on GitHub Discussions.** Kyno forums were
  taken offline; PurpleReel's community lives in the
  bronty13/PhantomLives repo's Discussions/Issues.

No code changed.

### C27 — Combine Clips: non-linear easing on cross-fades + edge fades

Deferred from C20 ("non-linear easing curves — needs custom
compositor"). C27 lands the feature without the custom compositor
overhead: we approximate the curves via 8 piecewise-linear segments
per fade, using AVFoundation's built-in `setOpacityRamp` /
`setVolumeRamp` repeatedly. Visually indistinguishable from a true
non-linear curve at typical 0.5–3-second fade durations; no
AVVideoCompositing pixel-pool plumbing required.

**Why piecewise over a custom compositor**: AVVideoCompositing is
notoriously fiddly — pixel-buffer pool management, async request
flow, color-space gotchas, OOM risk. Eight piecewise-linear segments
buy a smooth result with zero new failure modes.

**Model** — `CombineClipsService.swift`:
- New `CrossfadeEasing` enum:
  - `.linear` — y = x (pre-C27 default, single full-range ramp).
  - `.easeIn` — y = x² (slow start, snappy finish).
  - `.easeOut` — y = 1 - (1-x)² (snappy start, soft landing).
  - `.easeInOut` — y = 3x² - 2x³ (smoothstep — soft on both ends).
- `CombineClipsJob` gains `crossfadeEasing: CrossfadeEasing = .linear`
  on both inits.
- New `nonisolated static func easedRampValues(samples:easing:reversed:)`
  → `[Double]` pure helper, returns N+1 sample points for N
  piecewise-linear segments. `reversed: true` flips the curve so
  fade-OUT pairs symmetrically with a fade-IN of the same easing.

**Service**:
- `buildCrossfadeVideoComposition` / `buildCrossfadeAudioMix` —
  every `setOpacityRamp` / `setVolumeRamp` call routes through new
  `applyEasedOpacityRamp` / `applyEasedVolumeRamp` helpers. They
  short-circuit to a single ramp when `crossfadeEasing == .linear`
  (no overhead for the common case) or emit 8 segments otherwise.

**Sheet** — `CombineClipsSheet.swift`:
- New "Easing:" Picker row with four options (Linear / Ease In /
  Ease Out / Ease In-Out). Sheet frame 680→720.
- Easing applies globally to every cross-fade + edge fade in the
  job. Per-pair easing override not exposed.

**Tests** — `CrossfadeEasingTests.swift` (NEW, 10 cases):
- Every curve hits y=0 at t=0 and y=1 at t=1 (fade-in) /
  y=1, y=0 (fade-out).
- Linear is exactly evenly-spaced.
- EaseIn at t=0.5 = 0.25 (below linear).
- EaseOut at t=0.5 = 0.75 (above linear).
- EaseInOut at t=0.5 = 0.5 exactly (smoothstep is symmetric).
- EaseInOut at t=0.25 = 0.15625.
- EaseIn is monotonic non-decreasing.
- `samples` parameter controls value count (N+1).
- Zero / negative samples clamp to N=1 (degenerate but valid).

### C26 — XLSX report honors section toggles

Deferred from C12. When PurpleReel's CSV/HTML exports shipped the
Report Definition section gating, the XLSX path was excluded with
a note that "OOXML column-letter realignment when sections drop is
a follow-up." C26 lands that — XLSX now matches CSV/HTML.

**Why the deferral mattered**: OOXML cell references are
positional (`<c r="C5">…`). If we just dropped a column upstream
without recomputing the letter for each later cell, Excel would
either reject the file or render columns mis-aligned. The fix is
emit cells in a single dynamic list whose order is gated by the
sections OptionSet — `rowXML`'s existing `columnLetter(col)` call
already picks up the right letter from the cell's position in the
emitted array, so the realignment is automatic once the upstream
list shrinks.

- `XLSXReportWriter.writeXLSX(...)` gains
  `sections: ReportSections = .all`. Threaded through to
  `sheetXML(...)`.
- `sheetXML` rewritten: header + per-row cells built via the same
  always-on / `.formatDetails` / `.duration` /
  `.descriptiveMetadata` gates the CSV path uses.
- AppState's XLSX export call site now passes `sections` (was
  previously discarded with a TODO comment).

**Tests** — `XLSXReportWriterTests.swift` (+4 cases, total 9):
- `.all` includes every expected header (regression baseline).
- Dropping `.descriptiveMetadata` removes Title/Description/Reel/
  Scene/Take/Angle/Audio Channels/Tags; format columns stay.
- Dropping `.formatDetails` removes Resolution/FPS/Date* but
  keeps Duration (gated independently).
- OOXML column-letter realignment: with only `.duration` on
  (formatDetails + descMeta off), Size lands at column E in
  row 2 — verified by grep for `r="E2"` in the sheet XML.

### C25 — FCPXML project-membership tracking

Deferred from C11. The FCPXML round-trip importer already pulls
markers, keywords (→ tags), favorites (→ 5★), and clip log fields
back into the catalogue when an editor re-exports an FCPXML after
their cut. C25 captures the *other* signal in that file: which
project(s) each clip is referenced from.

Doesn't introspect `.fcpbundle` packages directly — those are
sealed CoreData / binary plist boxes, brittle to parse, FCP-
version-specific. Leveraging the already-supported FCPXML export
gives us the same signal through a documented format.

**Schema** — `DatabaseService.swift` migration v8:
- New `fcp_project_usage(assetId, projectName, eventName?,
  libraryPath?, importedAt)` table, composite PK on
  `(assetId, projectName)` so re-importing the same FCPXML
  upserts rather than duplicates.
- Index on `assetId` for the inspector's per-asset lookup.

**Model** — `Models/FCPProjectUsage.swift` (NEW):
- GRDB-backed value type. Identifiable via `"\(assetId)#\(projectName)"`
  composite so SwiftUI lists render uniquely.

**DatabaseService** API:
- `recordFCPProjectUsage(assetId:projectName:eventName:libraryPath:)`
  — upserts via `ON CONFLICT(...) DO UPDATE` on the composite PK.
- `fcpProjectUsage(assetId:) -> [FCPProjectUsage]` —
  most-recently-imported first.

**Importer** — `FCPXMLImportService.swift`:
- New parser state: `eventNameStack` and `projectNameStack` that
  push/pop on `<event>` / `<project>` start/end. The innermost
  name is stamped on each clip as it's finalized.
- `ClipRecord` gains `projectName: String?` and `eventName: String?`.
- `importXML(at:db:)` writes a usage row per clip whose surrounding
  context named a `<project>`. Clips that sit directly under an
  `<event>` without a `<project>` (FCP's "event browser" layout)
  are skipped — they're not part of a cut.
- `Result.projectUsageRecorded` count surfaced for the alert.
- libraryPath records the FCPXML file's URL (provenance), not
  the underlying `.fcpbundle`.

**AppState**:
- New `@Published var fcpProjectUsage: [FCPProjectUsage]` populated
  on each selection change alongside markers / tags / rating /
  clipMetadata.

**Inspector** — `MetadataPaneView.swift`:
- New `fcpProjectsBlock` section: shows a "FCP Projects" header
  with film.stack icon, then one capsule per project membership
  (project name + event name as caption). Tooltip shows
  importedAt date + the FCPXML's libraryPath. Hidden when the
  list is empty (no FCPXML has been imported yet for this asset).

**Tests** — `FCPProjectUsageTests.swift` (NEW, 5 cases):
- Clip inside `<project>` records usage row with eventName +
  projectName.
- Clip outside `<project>` (bare event browser) does NOT record.
- Re-import is idempotent via composite-PK upsert.
- Two distinct projects across two FCPXML files both recorded.
- libraryPath captures the FCPXML's own path.

### C24 — Combine Clips: per-clip cross-fade override

C20 shipped a global cross-fade scalar applied uniformly to every
pair of consecutive clips; C24 lets each source carry its own
override so the user can mix dissolve sections with hard cuts
(e.g. cross-fade between interview takes A and B, hard cut into
B-roll for clip C, cross-fade again between C and D).

**Model** — `CombineClipsService.swift`:
- `CombineSource` gains
  `crossfadeAfterSeconds: Double?` — the cross-fade duration after
  this clip. `nil` = inherit the job's global default. The last
  source's value is ignored (no neighbor after).
- New `nonisolated static func clampPerPairCrossfades(perPairRequested:globalDefault:trimmedDurations:)`
  → `[Double]` of length `n-1`. Resolves each pair against
  `min(durs[i], durs[i+1]) / 2`, falling back to `globalDefault`
  for nil entries. Explicit `0` stays `0` (so a user can mix
  cross-fade and hard-cut in one batch); negative requests clamp
  to `0`.
- New `nonisolated static func combinedOffsetsPerPair(trimmedDurations:perPairCrossfades:)`
  — per-clip insertion offsets accounting for the running total
  of preceding pair fades. Degenerates to C20's scalar helper
  when every pair carries the same value.

**Service** — `CombineClipsService.swift`:
- `run()` now resolves cross-fades via the per-pair clamp and
  offsets via the per-pair helper. `useDual` flips on whenever
  any pair carries a non-zero fade (was: a single non-zero scalar).
- `buildCrossfadeVideoComposition` and `buildCrossfadeAudioMix`
  swap their scalar `crossfade: Double` parameter for
  `crossfades: [Double]`. Each clip's leading and trailing
  cross-fade come from `crossfades[i-1]` / `crossfades[i]`
  (first/last clip's outer side is 0). Overlap-region
  instructions only emit when the corresponding pair's fade > 0.

**Sheet** — `CombineClipsSheet.swift`:
- Per-row `CF→` text field next to the trim fields. Hidden on
  the last row and when there are fewer than 2 sources. Empty =
  inherit; explicit value = override.
- Global "Cross-fade:" label re-captioned to "default seconds —
  per-clip CF→ overrides above" to make the precedence explicit.

**Tests** — `PerPairCrossfadeTests.swift` (NEW, 12 cases):
- Clamp: empty / single / all-nil / mixed overrides / pair-half-
  min / explicit-zero-stays-zero / negative-clamps-to-zero.
- Offsets: all-zero degenerates to cumulative sum / uniform
  matches C20 helper / mixed per-pair accumulates / empty / single.

### C23 — Combine Clips: fade-from / fade-to black

Edge-fade follow-up deferred from C20. The cross-fade work landed
the dual-track + AVMutableVideoComposition machinery for clip-to-
clip dissolves; C23 layers two new dials on the same path:
  - Fade-from-black on the first clip's leading edge.
  - Fade-to-black on the last clip's trailing edge.

Both are independent of cross-fade — either dial can be used alone
(e.g. fade-from-black with hard cuts in between, for podcast/
voiceover work) or together with cross-fades for the full
A/B-roll-dissolve story.

**Service** — `CombineClipsService.swift`:
- `CombineClipsJob` gains
  `fadeFromBlackSeconds` and `fadeToBlackSeconds` (both default 0)
  on both inits.
- New `nonisolated static func clampEdgeFadeSeconds(_:edgeClipDuration:)`
  pure helper. Bounds each fade by its edge clip's trimmed
  duration so we don't ask AVFoundation to ramp opacity over a
  segment that doesn't exist.
- `run()` now decides `useVideoComp` and `useAudioMix`
  independently (was a single `useDual`). Either flag flips on
  when **any** of cross-fade / fade-from-black / fade-to-black is
  non-zero. Audio-only outputs still skip video composition.
- `buildCrossfadeVideoComposition` gains
  `fadeFromBlack` + `fadeToBlack` params:
  - First clip's solo region trimmed by `fadeFromBlack` so the
    edge ramp gets its own instruction `[0, fadeFromBlack]` with
    layer opacity ramping 0→1. AVFoundation's default video-
    comp background is black, so a 0→1 ramp reveals it as
    "fade from black."
  - Last clip mirrored: `[tail - fadeToBlack, tail]` instruction
    with 1→0 opacity.
  - Instructions sorted by `timeRange.start` so the append order
    of edge / solo / overlap segments doesn't matter.
- `buildCrossfadeAudioMix` mirrored: leading 0→1 / trailing 1→0
  volume ramps on the first / last clip when the corresponding
  fade is on. Stacks correctly with the cross-fade ramps via
  `setVolumeRamp` accumulating on the same input parameters.

**Sheet** — `CombineClipsSheet.swift`:
- New "Fade in: N sec from black on first clip" and
  "Fade out: N sec to black on last clip" rows next to the
  existing "Cross-fade" row in the output-controls block.
- Sheet frame height 620→680 to accommodate the new rows.

**Tests** — `EdgeFadeTests.swift` (NEW, 7 cases):
- Zero / negative request → zero.
- Request < edge duration → pass-through.
- Request > edge duration → clamp to edge duration.
- Request exactly == edge duration → pass-through.
- Zero / negative edge duration → zero (degenerate guard).

### C22 — Polish bundle: recent destinations + custom LUT + ${markerTitle}

Three small, independent polish items bundled into a single commit.

**Part 1 — Recent destinations dropdown** (deferred from C4 / C16):
- New `RecentDestinations` service with per-scope persistence
  (UserDefaults), case-insensitive dedupe, cap at 6. Mirrors the
  existing `RecentPresets` pattern. Scopes: `.convert`, `.combine`.
- Convert dialog (`ConvertSheet`) and Combine Clips
  (`CombineClipsSheet`) now push the chosen destination onto the
  scope-specific recents list every time the user picks via
  NSOpenPanel.
- Small `recentsMenu` dropdown (clock-arrow icon) next to the
  Select…/Choose… button in both sheets. Lists recents most-recent-
  first; selecting one sets the destination and re-pushes (so the
  rolling LRU stays useful). Hidden when empty — first-run UX
  matches pre-C22.

**Part 2 — Custom-file LUT picker** (deferred since the C5
VideoSettingsSheet rollout):
- New `Pick from disk…` option in the LUT picker. Wires an
  `NSOpenPanel` with `allowedFileTypes = ["cube", "3dl", "dat",
  "lut"]` so the panel greys out files `LUTService.load(url:)`
  doesn't understand.
- Cancel reverts to the previous mode (no stranding on an empty
  `.file(path: "")` selection).
- When `.file` mode is active, a small caption below the picker
  shows the picked filename + a `Change…` button to swap.

**Part 3 — `${markerTitle}` token in batch rename** (declared in
C10, stubbed pending DB access):
- `BatchRenameService.plan(...)` gains
  `markerTitleLookup: ((Asset) -> String?)? = nil`. Closure threads
  through `expand(...)` and `value(forToken:)` so the service stays
  GRDB-free.
- `BatchRenameView` passes a closure that looks up the asset's
  first marker via `appState.db.markers(assetId: rowId).first?.note`.
- New `BatchRenameService.sanitizeForFilename(_:)` — folds
  newlines/tabs/control codes to single spaces, replaces nine
  filesystem-hostile chars (`/ \ : * ? " < > |`) with `_`,
  collapses whitespace runs, trims. Marker notes are free-form
  user input (multi-line, emoji, special chars); the rest of the
  rename pipeline assumes single-line clean segments.
- Nil / empty closure return collapses to `""` so a template like
  `${originalName}_${markerTitle}${extension}` against an un-marked
  asset produces a stable `clip_.mov` filename rather than leaking
  a literal `{markerTitle}` token.

**Tests** — 16 new cases:
- `RecentDestinationsTests` (7) — empty initial, push-to-front,
  dedupe-on-repush, case-insensitive dedupe (`/Volumes/CardA` vs
  `/volumes/carda`), 6-entry cap with oldest eviction, scope
  independence, clear.
- `MarkerTitleTokenTests` (9) — closure-routed resolution, missing
  closure → empty, nil / empty-string returns → empty, sanitizer
  rules (9 hostile chars, newlines/tabs, whitespace trim, safe
  chars survive, emoji preserved).

### C21 — Drilldown hint banner

When a user clicks into a folder with one (or zero) direct media
files but more in subfolders, the UI used to silently show only the
top-level entries — and `drilldown is off, you can't see the rest`
was a hidden gotcha. C21 surfaces an inline banner above the asset
list ("N more files in subfolders — drilldown is off") with a
"Show all" button that flips drilldown on for that folder (sticky;
the user only does it once per folder).

**Threshold**: `direct ≤ 1 AND nested ≥ 1`. Documents the user's
exact complaint ("I know there are videos but I only see one"). At
2+ direct items the banner stays quiet — the user is already
seeing a populated listing and an extra prompt would be noise.

**AppState** — `App/AppState.swift`:
- New `FolderCounts { direct, nested }` struct.
- New `folderCounts(forFolder:) -> FolderCounts` — reuses the same
  canonicalization (`canonicalizeBootVolumePath` + standardizing
  path) the displayedAssets filter uses, so the banner's numbers
  always match what the user would see after toggling drilldown.
  Includes a trailing-`/` guard so sibling paths
  (`/Volumes/CardABig` vs `/Volumes/CardA`) don't leak in.

**BrowserView** — `Views/BrowserView.swift`:
- New `drilldownHintBanner` @ViewBuilder slotted between the
  toolbar Divider and the content Group.
- Renders only when `selectedFolderPath != nil`, drilldown is OFF
  for that folder, and the threshold matches.
- "Show all" button calls `appState.toggleDrilldown(forPath:)` —
  same code path as the toolbar toggle and ⌘⇧D.

**Tests** — `FolderCountsTests.swift` (NEW, 6 cases):
- Empty assets → (0, 0).
- Direct-only / nested-only / sparse-with-hidden-nested splits.
- Sibling-prefix leak guard
  (`/Volumes/CardABig` ⊄ `/Volumes/CardA`).
- Mixed direct + nested + deeper-nested → correct split.

### C20 — Combine Clips: cross-fades

Category F follow-up #5 — the medium-effort one that closes out
Category F. Previously every clip boundary was a hard cut; now a
global cross-fade duration (seconds) ramps both video opacity and
audio volume across every clip boundary. Doc / interview workflow
gets the natural-feeling A/B-roll dissolves; podcast workflow gets
audio cross-fades free.

**Service layer** — `CombineClipsService.swift`:
- `CombineClipsJob` gains `crossfadeSeconds: Double = 0` on both
  inits. 0 = hard cut (default, pre-C20 behavior).
- New `nonisolated static func clampCrossfadeSeconds(_:trimmedDurations:)`
  — pure helper that clamps the requested cross-fade to half of
  the shortest trimmed segment so consecutive segments never
  overlap to the point of swallowing a clip's solo region whole.
  Returns 0 for empty input, single source, or negative request.
- New `nonisolated static func combinedOffsets(trimmedDurations:crossfade:)`
  — pure helper for the per-clip insertion offsets:
  `offset[i] = sum(durs[0..<i]) - i * cf`. Degenerates to the
  cumulative-sum cursor of the hard-cut path when cf=0.
- `run()` restructured into three phases:
  1. **Pre-pass**: load each source's `.duration` so we can clamp
     cross-fade against trimmed durations *before* committing to
     a track topology.
  2. **Build composition**: allocate 1 or 2 video tracks and 1 or
     2 audio tracks depending on `useDual = cf > 0 && n >= 2`.
     Clips alternate across the dual tracks (i % 2 → track A or B)
     so the cross-fade overlap region carries two visible layers.
  3. **Build video composition + audio mix** (cross-fade path
     only). The hard-cut path leaves both nil so
     `AVAssetExportSession` takes its default "play all tracks
     at full volume / opacity" behavior.
- New `buildCrossfadeVideoComposition(...)` — emits per-clip
  *solo region* instructions (single-layer, opacity 1) and
  *overlap region* instructions (two-layer, opacity-ramp 1→0
  outgoing + 0→1 incoming).
- New `buildCrossfadeAudioMix(...)` — mirrors with `setVolumeRamp`
  calls on per-track `AVMutableAudioMixInputParameters`. Each
  clip gets a leading fade-in (skipped for the first clip) and
  trailing fade-out (skipped for the last).
- Audio-only outputs (m4a) still cross-fade audio via the same
  audio-mix path; video composition is skipped.

**Sheet layer** — `CombineClipsSheet.swift`:
- New row "Cross-fade: [N] seconds (0 = hard cut)" in the
  output-controls block. Stored as text so the user can type
  freely; parsed at runCombine time. Defaults to 0.
- Frame height bumped to 620 to accommodate the new row.

**Tests** — `CombineCrossfadeTests.swift` (NEW, 13 cases):
- Clamp: zero stays zero, negative → zero, single-source / empty
  → zero, request under half-shortest passes through, request
  over half-shortest clamps to half-shortest, request exactly
  half-shortest passes through.
- Offsets: cf=0 yields cumulative sum, cf>0 reduces each index
  by `i * cf`, heterogeneous durations resolve correctly, total
  output duration matches `tail = last_offset + last_dur`,
  empty list yields empty, single-clip lands at 0.

**Deferred** — per-clip individual cross-fade durations (vs the
current global), fade-from-black on the first clip / fade-to-black
on the last (separate Kyno feature, will get its own commit), and
non-linear easing curves on the ramps (AVFoundation only does
linear out of the box; would need a custom video compositor).

### C19 — Combine Clips: dimension-match override

Category F follow-up #4. The pre-C19 path always picked the first
clip's natural size as the combined canvas, which is the right
default but wrong when (a) the first clip happens to be the
smallest in the set, or (b) the delivery spec wants a fixed canvas
the source set doesn't naturally satisfy ("must be 1920×1080").

**Service layer** — `CombineClipsService.swift`:
- New `CombineDimensionMode` enum with three cases:
  `.firstClip` (default, pre-C19 behavior), `.largestSource`
  (max width × max height across sources — independent axes, so
  mixed orientations pillarbox/letterbox without downscaling),
  `.explicit(width: Int, height: Int)`.
- `CombineClipsJob` gains a `let dimensionMode:` property with a
  `.firstClip` default on both inits (memberwise and the
  legacy URL-only convenience init), so existing workflow-chain
  callers keep producing the same output.
- New `nonisolated static func resolveTargetSize(mode:sourceSizes:)`
  — pure helper that takes the policy and per-source natural
  sizes (in render order) and returns the resolved
  `CGSize`. Returns nil when the policy can't be satisfied
  (empty source list for `.firstClip`/`.largestSource`, or
  non-positive WxH for `.explicit`).
- `run()` collects per-source natural sizes during the loop and
  applies the resolved size to `comp.naturalSize` after the
  loop. The first video source's `preferredTransform` is still
  copied onto the composition's video track (portrait phone
  footage still orients correctly).

**Sheet layer** — `CombineClipsSheet.swift`:
- New Picker "Canvas size:" with three options — "Match first
  clip" / "Largest source" / "Custom WxH". Hidden for audio-only
  presets (no canvas to pick).
- W and H TextFields surface only when "Custom WxH" is the
  active choice. Default values 1920 / 1080.
- `resolvedDimensionMode()` helper projects the picker's Int kind
  + the W/H text back into a `CombineDimensionMode` at runCombine
  time. Unparseable / non-positive WxH falls back to `.firstClip`
  so a typo doesn't blow up the export — user can fix the field
  and re-Combine.

**Tests** — `CombineDimensionModeTests.swift` (NEW, 8 cases):
- `.firstClip` returns the first source's size; nil for empty.
- `.largestSource` picks max W and max H independently — covered
  by both a homogeneous set (3840×2160 wins) and a mixed-
  orientation case (1920×1080 + 1080×1920 → 1920×1920).
- `.largestSource` returns nil for empty sources.
- `.explicit` returns the requested size and ignores source sizes
  (delivery-spec takes precedence).
- `.explicit` with zero or negative dimensions returns nil
  (resolver guards against typos that AVAssetExportSession
  would otherwise blow up on).

### C18 — Combine Clips: audio-only output

Category F follow-up #3. Adds an "Audio Only (AAC m4a)" preset to
the catalogue and teaches `CombineClipsJob` to skip the video track
when the chosen preset is audio-only. The use case is doc / podcast
work where the user wants to glue dialogue takes together without
ever rendering video — was previously a manual ffmpeg-on-the-side
step.

**Catalogue** — `TranscodePreset.swift`:
- New built-in `m4a-audio-only` preset in `TranscodePreset.all`:
  AAC in an `.m4a` container, `category: .audio` (the enum case
  has existed since Sprint 3 but was unused).
- New computed property `isAudioOnly` — true when
  `category == .audio` OR `avPresetName == AVAssetExportPresetAppleM4A`
  OR `fileExtension ∈ {m4a, wav, aiff}`. The extension fallback
  lets a future user-created WAV / AIFF preset pick up audio-only
  semantics without the service needing to learn another constant.

**Service layer** — `CombineClipsService.swift`:
- `run()` now builds `vTrack` as Optional: nil for audio-only
  presets, the usual `AVMutableCompositionTrack` otherwise. The
  source loop guards both the per-clip `insertTimeRange(.video)`
  call and the post-loop `preferredTransform` / `naturalSize`
  copy on the optional track.
- `containerType()` recognises `AVAssetExportPresetAppleM4A` →
  `.m4a` ahead of the default `.mp4` fallthrough.

**Sheet layer** — `CombineClipsSheet.swift`:
- `retitleForPreset()` swaps from a hardcoded ProRes-vs-mp4
  ternary to reading the preset's declared `fileExtension`. The
  audio-only preset's `m4a` extension flows through naturally;
  the existing ProRes path stays correct because the ProRes
  presets declare `fileExtension: "mov"`.
- `combinePresets` (which already filtered out ffmpeg + passthrough)
  picks up `m4a-audio-only` automatically; no UI logic needed.

**Tests** — `AudioOnlyPresetTests.swift` (NEW, 3 cases):
- `testM4APresetExistsInCatalogueAndIsAudioOnly` — pins the
  catalogue entry shape (`id`, `avPresetName`, `fileExtension`,
  `category`, `isAudioOnly`).
- `testVideoPresetsAreNotMarkedAudioOnly` — sanity check that
  H.264 / HEVC / ProRes / pass-through don't accidentally pick
  up the audio-only treatment.
- `testWAVAndAIFFExtensionsFallBackToAudioOnly` — documents the
  extension-based fallback so a future WAV preset doesn't break
  the rule.

### C17 — Combine Clips: marker preservation

Category F follow-up #2. Builds on the C16 trim/reorder pass.
Markers that PurpleReel has catalogued against each source clip now
ride onto the combined output at the right segment offset, so a
doc editor who's tagged "good answer at 4:12" on clip A and "B-roll
cue at 2:30" on clip B sees both markers reappear at the right
times on the combined file's timeline.

**Service layer** — `CombineClipsService.swift`:
- `CombineSource` gains `sourceMarkers: [Marker] = []`. Callers
  pre-populate the list with the source clip's catalogued markers
  (or leave empty if they don't want preservation).
- New `nonisolated static func offsetMarkers(_:trimInSec:trimOutSec:cursorSec:)`
  — pure helper that filters markers to those inside the trim
  window and shifts them by `cursor + (originalTC - trimIn)`. Extracted
  as a free function so the rule is testable without spinning up
  `AVAssetExportSession`. `nonisolated` because the service is
  `@MainActor` but the helper is referentially-transparent and the
  tests don't want to hop the actor.
- `CombineClipsJob.run()` now calls `offsetMarkers` once per source
  inside its existing source-loop (cursor is captured *before* the
  advance, so the offset lines up with the segment's start in the
  output), accumulates the results into a new `@Published var
  preservedMarkers: [PreservedMarker]`, and republishes the array
  after the loop.
- New value type `PreservedMarker(timecodeIn, timecodeOut?, note?)`
  — no GRDB conformance, no assetId yet. The sheet attaches it to
  the freshly-catalogued output asset's id after rescan.

**Filter & offset rules** — covered by
`CombineSourceMarkerPreservationTests`:
- Marker inside the trim window: kept, shifted by
  `cursor + (originalTC - trimIn)`.
- Marker before trim-in: dropped (points at footage clipped off the
  front).
- Marker after trim-out: dropped (same on the trailing side).
- Marker `timecodeIn` inside but `timecodeOut` past the window:
  the in-point survives, the out clamps to the trim's end so the
  output doesn't carry a marker pointing past the combined
  timeline's natural duration.
- Empty / inverted range (trimOut ≤ trimIn): zero markers.
- Markers exactly on either boundary are kept (inclusive — the
  segment renders that frame, so the marker on it should ride
  along).
- Whole-clip path (trimIn = 0, cursor = 0): markers keep their
  absolute positions. Most-common case.

**Sheet layer** — `CombineClipsSheet.swift`:
- `Row` struct gains `sourceMarkers: [Marker] = []`; populated at
  sheet open by `loadSourceMarkers()` via
  `appState.db.markers(assetId:)` against `Asset.rowId`.
- Per-row badge ("🔖 N") rendered next to the trim fields when a
  source has markers and preservation is on. Tooltip notes that
  some may still drop based on the trim window. Hidden when
  preservation is off or the row has no markers.
- Master toggle "Preserve markers on combined output" in the
  output-controls block, default **on**. Hidden when no source
  has any markers (no point asking).
- `runCombine()` forwards `preserveMarkers ? row.sourceMarkers : []`
  into each `CombineSource`. After the job finishes and the rescan
  has catalogued the output, it looks up the new asset via
  `db.asset(forPath:)` and writes each preserved marker via
  `db.addMarker(...)` against the new asset's `rowId`. Lookup
  failures fail silently rather than nuking the combine.

**Why opt-out, not opt-in**: the dominant use case (gluing
interview takes, doc-shooter "review notes at the right spot")
wants markers carried. The off branch exists for delivering a
fresh output to a client who shouldn't see the editor's review
notes; surfacing the toggle solves that without blocking the
default path.

**Tests** — `CombineSourceMarkerPreservationTests.swift` (NEW, 7
cases covering the filter/offset/clamp/boundary/empty-range/
whole-clip-path rules above).

### C16 — Combine Clips: per-clip in/out trim + drag-reorder

Category F follow-up. The original Combine Clips MVP (Sprint 3-4)
shipped whole-clip head-to-tail concat only with up/down arrows for
reordering. C16 lands the two highest-leverage follow-ups: per-clip
in/out trim and native drag-reorder.

**Service layer** — `CombineClipsService.swift`:
- New `CombineSource` struct: `(url, trimInSeconds: Double?,
  trimOutSeconds: Double?)`. Nil on both sides = whole-clip
  (pre-C16 MVP path).
- `CombineClipsJob.sources` switched from `[URL]` to
  `[CombineSource]`. Legacy URL-only `init` becomes a
  `convenience init` that wraps each URL into an un-trimmed
  CombineSource — so workflow-chain and scripted call sites keep
  compiling without migration.
- `run()` resolves each source's trim points into a
  `CMTimeRange(start: in, duration: out - in)`, clamps to the
  asset's actual duration so an out-of-bounds trimOut clips to
  the end rather than failing, and refuses an empty trim range
  with a clear "X has an empty trim range (Ys → Zs)" error.

**Dialog layer** — `CombineClipsSheet.swift`:
- `sources: [Asset]` → `rows: [Row]` where Row carries the asset
  + two trim text fields. Text-not-Double so the user can type
  freely; parsing happens at Combine time.
- Reordering switched from up/down `arrow.up`/`arrow.down`
  buttons to native SwiftUI `List` + `.onMove(fromOffsets:toOffset:)`.
  Free drag handles + free swipe-to-delete via `.onDelete`. The
  legacy `move(_:by:)` helper deleted.
- Each row now has inline `In` + `Out` TextFields (90pt monospace)
  accepting `HH:MM:SS`, `MM:SS`, or plain seconds. Empty = use
  the clip's natural in/out. Placeholder text in the Out field
  shows the source's full duration.
- "Total: m:ss" readout now sums each row's *effective* duration
  (after trim) so the user sees what'll actually render.

4 new tests (`CombineSourceTests`):
- Default trim is nil on both sides
- Trim range round-trips
- Equatable conformance via stored properties (incl. id)
- Legacy URL-only init wraps each URL into an un-trimmed
  CombineSource (no behavior drift for workflow chains)

Still queued for Category F: cross-fades, audio-only output,
dimension match (override the first-clip-wins default), marker
preservation. Sequenced for follow-up commits.

---

### C15 — List view column-header click-to-sort

List view's Table headers are now clickable to sort, with the native
SwiftUI chevron indicating the active column + asc/desc direction.
Switched the Table to use the `sortOrder:` API so the chevron, click
handling, and direction toggle come for free.

**Sortable columns** (6): Name, Codec, Resolution (sorts by
widthPx — close-enough proxy since the catalogue is overwhelmingly
landscape), FPS, Duration, Size. Thumbnail column stays unclickable
(no value to sort by).

**Optional columns** (rating, recordedAt, etc.) keep their current
non-clickable headers — adding sortability per `ListColumn` case
needs a per-case comparator dispatch and is a follow-up.

**Bidirectional bridge with `appState.sortKey` + `sortAscending`**:
- Click a header → `tableSortOrder` updates → `applyTableSortToAppState`
  writes the matching string sortKey + asc bool to AppState. The
  Grid view, the toolbar Sort menu, and the table stay in lockstep.
- Change `sortKey`/`sortAscending` externally (toolbar Sort menu)
  → `syncTableSortFromAppState` mirrors back into `tableSortOrder`
  so the column chevron tracks.
- Both directions guard against re-fire loops by comparing values
  before writing.

**New file** — `Views/NilHandlingComparator.swift`. `SortComparator`
that pushes nil entries to the end in both sort directions
(standard library's optional `Comparable` would put nils first in
ascending, which is noise for "no data" rows). Used for Codec /
Resolution / FPS / Duration columns where the underlying field is
optional.

5 new tests (`NilHandlingComparatorTests`):
- Ascending pushes nils to end
- Descending also pushes nils to end (not flipped to front)
- Equal values → .orderedSame
- Both nil → .orderedSame
- Works for String? (not just Int?)

---

### C14 — Single-clip Edit Tags dialog

Kyno's right-click Tags (Image #91) routes single-clip taggings to
a dedicated "Tag <filename>" dialog; multi-select stays on the
batch additive editor. PurpleReel was sending both paths to the
batch editor before C14 — meaning a one-clip tag edit went through
a UI optimized for "add tags to N clips" semantics. C14 splits the
two:

**New view** — `Views/SingleClipTagDialog.swift`:
- Title bar: "Tag <filename>"
- "Select or Create Tag" TextField + autocomplete Menu (filtered
  on draft, excludes already-applied tags, top 20 by name).
- Current-tags list with selection + Remove / Remove All buttons.
- Footer: Cancel / Save Changes (disabled until edits land).
- Save diffs against the original snapshot, calling
  `addTag(name:)` for additions and `removeTag(name:)` for
  deletions in one pass — single source of truth stays on the
  existing AppState helpers.

**AppState plumbing**:
- `singleClipTagState: SingleClipTagState?` — dialog open flag.
- `openTagEditor()` is the new resolver: multi-selection
  (`selectedAssetPaths.count > 1`) → batch editor; single (or
  empty) → single-clip dialog (or fall back to batch's empty
  state when no asset resolves).

**Wiring**:
- `AssetContextMenu` "Tags…" button now sets the right-clicked
  clip as the primary selection and calls `openTagEditor()`.
- `PurpleReelApp` `⌘⇧T` menu item routes through `openTagEditor()`
  too, so the keyboard shortcut respects the single/multi split.

3 new tests (`TagEditorRouterTests`):
- Multi-select → batch editor; single-clip dialog stays nil
- Single-select → single-clip dialog; batch editor stays closed;
  the dialog carries the right path + filename
- Empty selection → falls back to batch (empty-state)

---

### C13 — Pre-analyze Analysis Scope dialog

C7 shipped Pre-analyze that always re-ran the AVAsset probe; Kyno's
pattern (Image #90) pops an intermediate dialog letting the user
pick which work to redo. C13 inserts that dialog between the right-
click menu pick and the actual probe run.

**New model** — `Models/AnalysisScope.swift`:
- `AnalysisScope` OptionSet (`.technicalMetadata`, `.thumbnails`,
  `.keyFrames`).
- `.default` = `[.technicalMetadata, .thumbnails]` matching Kyno's
  Image #90 checked state.

**New view** — `Views/AnalysisScopeSheet.swift`:
- Three Toggle rows with tooltip-style `.help` on each.
- Key frames Toggle disabled with explanatory tooltip — reserved
  for a future build (scene-change extraction; the existing strip
  uses evenly-distributed frames).
- Cancel / Start footer; Start disabled when scope is empty.

**AppState changes**:
- `analysisScopeState: AnalysisScopeState?` — dialog open flag.
- `openAnalysisScopeDialog()` — refuses to open with empty
  selection, then publishes the state with `.default` scope.
- `preAnalyzeSelected(scope:)` replaces the zero-arg variant.
  Branches on the scope: `.technicalMetadata` runs the C7
  `MediaScanner.loadAVTech` path; `.thumbnails` calls the new
  `ThumbnailService.purgeStripCache(for:)`; `.keyFrames` no-ops
  for now (placeholder for future scene-change extraction).

**ThumbnailService changes**:
- New `purgeStripCache(for:)` actor-call. Re-derives the same
  `cacheDirectory(for:count:)` hash the generator uses, then nukes
  the on-disk directory for each known strip-count bucket
  (12 / 20 / 30). Follows with `inMemoryCache.purgeAll()` so the
  next render misses cache and regenerates.
- New `InMemoryCache.purgeAll()` actor method.

**Right-click menu**: AssetContextMenu's "Pre-analyze" button
becomes "Pre-analyze…" (Apple HIG: ellipsis for items that present
a dialog) and now calls `appState.openAnalysisScopeDialog()`.

**ContentView**: new `.sheet(item:)` for `AnalysisScopeSheet`.

4 new tests (`AnalysisScopeTests`):
- `.default` matches Kyno's Image #90 (Tech + Thumbnails on, Key
  frames off)
- Individual options use disjoint bits
- `.isEmpty` is honest (insert/remove round-trip)
- Codable round-trip through JSON

---

### C12 — Report Definition section toggles

Inserted Kyno's "Report Definition" dialog (Image #89) between
Export Report menu pick and the NSSavePanel. User picks which
section groups to include — File size + File type are locked-on
(every row keeps the minimum identification columns), the other
three (Duration / Format Details / Descriptive Metadata) are
toggles. CSV and HTML reports drop the gated columns entirely
(headers + cells); XLSX still ships the full schema for now
(rebuilding OOXML column-letter alignment per-section is a
follow-up).

**New model** — `Models/ReportDefinition.swift`:
- `ReportSections` OptionSet with `.fileSize`, `.fileType`,
  `.duration`, `.formatDetails`, `.descriptiveMetadata`.
- `.locked` static = `[.fileSize, .fileType]` (the two grayed
  checkboxes in Kyno's dialog).
- `.all` static = the full set (default ticked state).

**ReportExporter changes**:
- `writeCSV` + `writeHTML` gained an optional `sections:` parameter
  defaulting to `.all` (existing callers unchanged).
- `csvHeader` / `csvRow` / `htmlHeader` / `htmlRow` rebuilt to gate
  column blocks by section: Filename + Codec + Size always emit;
  Resolution/Display/Aspect/FPS + dates gated by `.formatDetails`;
  Duration gated by `.duration`; Rating + log fields + tags gated
  by `.descriptiveMetadata`.

**New file** — `Views/ReportDefinitionSheet.swift`:
- Format Picker (CSV / HTML / XLSX) at the top — PurpleReel has
  three formats vs Kyno's one, so the dialog also picks format.
- Sections section with the 5 checkboxes; locked rows render
  disabled at 60% opacity so users see them as "always included".
- Footer: Cancel / Create Report. Create handoff via
  `appState.runReportExportFromDialog(format:sections:)` which
  publishes a `ReportRunRequest`; ContentView observes and drives
  the NSSavePanel + writer.

**AppState plumbing**:
- New `reportDefinitionState: ReportDefinitionState?` — opens the
  dialog when non-nil.
- New `reportRunRequest: ReportRunRequest?` — handoff between
  dialog Create button and the actual writer run.
- `openReportDefinition(format:)` — used by File menu's CSV /
  HTML / XLSX leaves.
- `runReportExport(format:sections:)` — relocated from
  `PurpleReelApp` (private) to AppState so ContentView's onChange
  observer can drive it.

**ContentView**: new `.sheet(item:)` presentation for the dialog +
`.onChange(of: appState.reportRunRequest)` observer that fires the
writer with the chosen format + sections.

4 new tests (`ReportSectionsTests`):
- `.locked` contains fileSize + fileType only
- `.all` covers every defined section
- `writeCSV(sections: .all)` emits the full column list
- `writeCSV(sections: .locked)` drops Duration / Resolution / Title

---

### C11 — Export FCPX XML dialog redesign

Inserted Kyno's options dialog (Image #88) between the menu click
and the actual file write. Every FCPXML export path (File menu,
right-click Send To, AssetContextMenu) now lands on the same dialog,
which collects the user's preferences before `FCPXMLWriter` writes.

**New model** — `Models/FCPXMLExportOptions.swift`:
- `eventName` — editable string; defaults to `PurpleReel Library
  <timestamp>` for all-catalogued exports or `PurpleReel — <name>`
  for single-clip exports.
- `fileReference: .copyToLibrary` / `.leaveInPlace` — controls
  whether the FCPXML embeds copy-to-library hints.
- `useRelativePaths: Bool` — emit `<media-rep>` URLs relative to the
  FCPXML's directory (for when the user is handing off the XML +
  source folder together).
- `openExportedFile: Bool` — `NSWorkspace.open` to FCP after write.
- **Keywords**: `keywordsFromTags` (default on), `keywordsFromSubclips`,
  `keywordsFromFolders` + a `folderKeywordScope`
  (`.containingFolder` / `.allParents`).
- **Favorites**: `favoritesFromSubclips`, `favoritesFromInOutPoints`,
  `favoritesFromRating` (default on) + `favoritesMinStars` (default
  1, threshold "any rated clip is a Favorite").

**Writer changes** — `FCPXMLWriter.makeXML` / `.write` gained an
optional `options:` parameter; `assetClipElement` reads it to decide
which keyword sources concatenate (one comma-joined `<keyword>`
element per clip) and which Favorite `<rating>` ranges emit (whole-
clip vs per-subclip). Rejected clips (`stars = -1`, C7 sentinel) are
explicitly excluded from Favorite emission regardless of threshold.

**New file** — `Views/FCPXMLExportSheet.swift`. Two-section layout
matching Image #88: Library / Event / Files at the top, Metadata
Mapping with Keywords + Favorites checkboxes below. The "From
folders" / "From rating" rows reveal their scope/threshold Picker
inline when ticked (no flicker on toggle).

**AppState plumbing** — the legacy
`exportFCPXML(scope:openInFCP:)` signature still exists but now opens
the dialog instead of writing immediately; the actual write moved to
a new overload `exportFCPXML(scope:options:)` that the dialog's
Export button calls. ContentView gains an `.sheet(item:)`
presentation bound to `appState.fcpxmlExportSheetState`.

7 new tests (`FCPXMLExportOptionsTests`):
- Keywords from tags only (default) emit one comma-joined value
- Keywords from folders / containing-folder scope emits only parent
- Keywords from folders / all-parents scope walks the ancestor chain
- All keyword sources off → no `<keyword>` element emitted
- Favorites threshold honors `favoritesMinStars` (3★ + threshold 4
  doesn't emit; 4★ + threshold 4 does)
- Rejected clips (-1★) are never Favorited
- `favoritesFromSubclips` emits a Favorite range per subclip

One existing test updated (`FCPXMLWriterTests.testLowRatingDoesNotEmitFavorite`)
to pin the strict-threshold path explicitly with `favoritesMinStars
= 4`, since the default changed from a hard-coded 4 to a dialog-
exposed 1.

---

### C10 — Batch Rename redesign + Manage Filename Presets

Layered a named-preset system on top of the existing token engine
(Kyno-parity, Images #88-#91). User picks a preset from a dropdown
(system catalog + their own saved customs + a Manage… leaf) instead
of typing a raw `{date}_{orig}_{counter}{ext}` template. Custom Name
field appears only when the picked preset includes `${customName}`;
a live Example renders the first asset's resulting filename.

**Model** — new `Models/FilenameRenamePreset.swift`:
- `FilenameRenamePreset` value type (id, name, template, isSystem).
- `FilenameRenamePresetCatalog.system` ships 13 Kyno-shaped presets:
  Add Prefix / Add Suffix, Custom Name (+ Index / + Global Index /
  + Original Name / + Timecode), Original Name (+ Custom Name / +
  Custom Name + Index / + Date Modified / + Index / + Timecode).
- `BatchRenamePresets` enum handles user-preset persistence via a
  single JSON-encoded UserDefaults key (`batchRenameUserPresets`).
- `BatchRenamePresets.variables` lists the 8 variables surfaced in
  the "Add Variable" picker: customName / originalName / extension /
  index / globalIndex / timecode / dateModified / markerTitle.

**Service** — `BatchRenameService` gained `${variable}` syntax
alongside the legacy `{token}` form; both can coexist in the same
template. `normalize(template:)` rewrites `${originalName}` →
`{orig}`, `${extension}` → `{ext}`, `${dateModified}` → `{date}`,
`${index}` → `{counter}` before per-row expansion, so the existing
token-expander handles them transparently. New C10 tokens:
- `${customName}` — typed by the user in the Custom Name field;
  threaded through `plan(template:items:startCounter:customName:)`.
- `${timecode}` — `HHmmss` filename-safe formatting of the
  embedded source TC (falls back to mtime when not catalogued).
- `${globalIndex}` — monotonic counter persisted in
  `UserDefaults["batchRenameGlobalIndex"]`; survives across batches.
- `${markerTitle}` — placeholder for now (DB lookup is a follow-up).

**UI** — `BatchRenameView` rewritten:
- Pattern Picker grouped by system / Custom / "Manage…" leaf.
  Clicking Manage… opens the new sheet and snaps the picker back
  to a valid preset so the menu never parks on the action item.
- Custom Name TextField appears conditionally when the active
  template references `${customName}`.
- Live Example reads the first scoped asset (or a synthetic
  placeholder when no asset is selected so the dialog is useful
  before clicking a clip).
- Output-empty warning surfaces when Custom Name is required but
  blank ("⚠ Output file has an empty name") — Start Renaming
  button disables in that state.

**New sheet** — `Views/ManageFilenamePresetsSheet.swift`:
- Two-pane list: presets (left, with lock icons for system) +
  Delete / Duplicate buttons (right). System presets are locked
  and can't be edited / deleted; user can Duplicate one to start
  from a known-good shape.
- Template editor field at the bottom for the selected user
  preset, monospaced font.
- "Add Variable" Menu emits `${variable}` tokens into the editor.

9 new tests (`FilenameRenamePresetTests`):
- System catalog ships the expected 5 anchor presets
- Every system preset is locked
- `${originalName}` resolves to the source basename
- `${customName}` lands the user's typed text
- `${index}` matches the legacy `{counter}` behavior
- Mixed `${variable}` + `{token}` syntaxes coexist in one template
- Unknown `${variable}` passes through as literal (typo-friendly)
- User-preset persistence round-trips through UserDefaults JSON
- combined() lists system before user-created presets

---

### C9 — Inline filter rows (operator + value + unit editors)

Active-filter bar restructured to match Kyno's full-width inline rows
(per user screenshot). Continuous-value criteria (Duration, Size,
Rating) now render as editable rows with operator dropdown + value
field + unit dropdown + remove (⊖) button; discrete criteria (codec,
resolution preset, tag, folder, online status, etc.) keep the
compact pill shape since there's nothing to edit beyond presence.

**Editable rows**:

- **Duration**: `[Duration] [is at least ⇅] [HH:MM:SS] [hh:mm:ss] [⊖]`.
  Operator dropdown swaps between `.durationAtLeastSeconds` ↔
  `.durationAtMostSeconds`. Value parser accepts `H:MM:SS` /
  `MM:SS` / plain `SS` (typing "120" lands as 120 seconds; next
  render reformats to `00:02:00`).
- **Size**: `[Size] [is greater than ⇅] [100] [MB ⇅] [⊖]`. Unit
  dropdown switches MB ↔ GB (GB normalizes to nearest MB multiple).
- **Rating**: `[Rating] is at least [★★★ stepper] [⊖]`. Stepper
  clamped to 1…5.

**Plumbing**:

- New `Views/InlineFilterRow.swift` — pure-SwiftUI row, reads the
  current criterion, calls `onReplace(new)` on every edit. Falls
  back to a pill display for cases it doesn't recognize (so an
  unknown criterion never breaks the bar).
- New `AppState.replaceFilter(_:with:)` — finds the old criterion
  by equality, replaces it in-place at the same index. De-dupes
  when the new criterion already exists elsewhere in the list
  (replacing one row's value with another row's value collapses to
  one).
- `BrowserView.activeFiltersBar` restructured from horizontal
  ScrollView-of-pills to a VStack: top chrome (filter icon +
  AND/OR toggle + Clear All) → editable rows → pill ScrollView for
  the discrete criteria.

4 new tests (`ReplaceFilterTests`):
- In-place replacement preserves position
- Operator swap across enum cases (.durationAtLeastSeconds →
  .durationAtMostSeconds) lands cleanly
- No-op when the old criterion isn't present
- Dedup when the new criterion would duplicate an existing row

---

### Dark mode — Help / User Manual viewer contrast fix

User-reported regression: the User Manual window (Help → User Manual
→ MarkdownDocWindow → WKWebView) was unreadable in Dark mode because
the bundled `PurpleReel.help` HTML hard-coded light-mode colors
(`#222` body, `#111` headings, `#f2f2f2` code backgrounds) with no
`prefers-color-scheme: dark` overrides.

`Scripts/generate-help-book.swift` (the build-time generator that
emits every help page under `Resources/PurpleReel.help/.../en.lproj/`)
gained:

- `:root { color-scheme: light dark; }` so WKWebView's system surface
  picks the right background under the body.
- Explicit `background: #fff` on the body so light mode stays light.
- A full `@media (prefers-color-scheme: dark)` block that re-tints
  body / headings / borders / code / pre / table / blockquote / nav
  for legible dark-mode contrast (`#1c1c1e` background, `#e6e6e6`
  body, `#f2f2f2` headings, `#b39bff` accent links, etc.).

All 5 docs (USER_MANUAL.html, INSTALL.html, SHORTCUTS.html,
KYNO_PARITY_ROADMAP.html, KYNO_RESEARCH.html) plus the
PurpleReelHelp.html index regenerate via the same `htmlTemplate`
helper, so the fix lands across every page in one shot.

---

### C8 — Edit Multiple Items dialog Keep-dropdown redesign

`BatchMetadataSheet` rebuilt to match Kyno's "Edit Multiple Items"
flyout (Image #87). Each row now leads with a **Keep / Set** Picker
on the left instead of a checkbox.

- Layout switched to a 3-column Grid: `[Keep dropdown] [Label]
  [Value editor]`. Every row aligns vertically; Picker width fixed
  at 90pt.
- Underlying `BatchMetadataChange` model unchanged — `applyX: Bool`
  flags stay, bridged to the new `FieldMode` enum (.keep / .set) via
  a translating Binding so `AppState.applyBatchMetadata(_:)` is not
  touched.
- **Rating row** gains a Rejected (Ø) button next to the 5 stars,
  using the C7 sentinel (`stars = -1`). Visual: gray when inactive,
  red when selected.
- **Tags row** renamed from "Add Tags" → "Tags" and prompt text
  switched to Kyno's "Select or Create Tag". Chips list still
  click-to-remove.
- Description gets full TextEditor row; OK button enabled only when
  any field is in `.set` mode.
- Default sheet size bumped 620×600 → 720×640 to fit Kyno's wider
  per-row layout cleanly.

---

### C7 — Right-click polish (Rejected / Send to Resolve / Pre-analyze / richer Open With)

Closes 4 of 5 Kyno-parity gaps surfaced by the right-click screenshots
(Images #94-#102). Camera/Creative LUT split deferred to a follow-up
because it needs a real `clip_metadata` schema migration.

**Rejected rating state** (Image #98). Sentinel `stars = -1` rather
than a schema migration — the `rating` table's `stars: Int` column
already accepts any value, so the existing row layout carries it
straight through.

- `AssetContextMenu.metadataSection` Rating submenu adds a
  Rejected entry alongside the 5 stars + Unrated.
- `PurpleReelApp.swift` Metadata → Rating menu mirrors the new shape.
- `BrowserView.ratingDots(_:)` renders rejected clips as a single
  red `xmark.circle.fill` instead of a star row.
- `ReportExporter.csvRow` / `htmlRow` emit the literal `Rejected`
  string when stars < 0, preventing
  `String(repeating: "★", count: -1)` crashes.
- `≥ N stars` filters naturally exclude rejected clips because any
  positive threshold rejects -1.
- 3 new tests (`RejectedRatingTests`) covering label rendering,
  Codable round-trip with negative stars, and filter exclusion.

**Send To → DaVinci Resolve** (Image #100). New entry in the right-
click Send To submenu. Looks up the Resolve bundle ID
(`com.blackmagic-design.DaVinciResolve` or `.DaVinciResolveStudio`)
via `NSWorkspace.urlForApplication(withBundleIdentifier:)` and hides
the entry when neither is installed. Multi-selection lands as a
single `open` call so Resolve imports them as one batch into the
Media Pool.

Ships menu-only (no shortcut). Kyno binds ⌘⇧D to this but
PurpleReel's Sprint-1 Kyno-compat alias already wires ⌘⇧D to the
drilldown toggle — pinning the same combo here would silently break
one of the two.

**Pre-analyze** (Image #97). New menu item under the AI section in
the right-click menu (mirrors Kyno's bottom-of-menu placement).
Walks the multi-selection (or the single active clip), re-runs
`MediaScanner.loadAVTech` for each, applies the refreshed
duration / codec / dims / fps / audio codec / recordedAt / isVFR
fields, and writes the updated rows back to the DB. Useful after the
user has fixed source-file metadata out-of-band (corrected the
camera clock, repaired a partial container, etc.) without doing a
full workspace rescan.

`MediaScanner.loadAVTech` / `applyAVTech` / `AVTech` struct dropped
their `fileprivate` keywords so `AppState.preAnalyzeSelected()` can
call into them without duplicating probe logic.

**Richer Open With** (Image #99). The 8-handler cap was clipping
common video apps (Compressor, Pixelmator Pro, VLC) when a user had
a dozen+ installed. Bumped to 20 — NSWorkspace already sorts by
relevance, so the most likely-useful apps still appear first.

**Camera LUT + Creative LUT split** — *deferred*. The dual-slot UI
already lives in C5's VideoSettingsSheet LUTs tab, but persisting
per-clip Camera vs Creative selections needs a `clip_metadata`
schema migration (two new columns) plus repath through the player /
transcode pipelines. Tracked as the C7 follow-up; right-click
Camera LUT / Creative LUT submenus will ship alongside it.

3 new tests (RejectedRatingTests); full suite green.

---

### C6 — Non-modal Transcode Queue window

Original complaint that kicked off this whole reshape (Image #77 →
#78): the Transcode Queue was a `.sheet` on the main window, which
blocked all other interaction while jobs ran. C6 promotes it to a
stand-alone `Window` scene that floats independently.

**Window scene** added in `PurpleReelApp.swift`:

    Window("Transcode Queue", id: "transcode-queue") {
        TranscodeQueueView(queue: appState.transcodeQueue)
            …
    }
    .defaultSize(width: 640, height: 480)
    .commandsRemoved()

`.commandsRemoved()` keeps a "New Transcode Queue" entry out of the
File menu (we never want a second one).

**Trigger mechanics** — the existing
`@Published var transcodeSheetVisible` boolean is now treated as an
"open me" *pulse*: when it flips to true, ContentView's `.onChange`
handler calls `openWindow(id: "transcode-queue")` and immediately
resets the flag so the next enqueue (or the next manual menu click)
can re-fire. Idempotent — `openWindow` brings an existing window to
front rather than spawning duplicates.

**Status indicator chip** in the main window's toolbar
(`.placement(.status)`): a small Capsule with the spin-icon + "N
jobs" label, only renders when `running + pending > 0`. Clicking it
brings the floating Queue window back to the front. Live-updates as
the queue's @Published lists change.

**Queue view** updates:
- `@Environment(\.dismissWindow)` instead of `\.dismiss` so the
  Close button targets the right window.
- Existing "Show Queue…" menu item still functions — it just
  triggers the same boolean pulse the auto-open does.

Net result: queue lives in its own window. App stays usable.
Multiple transcodes can run in the background while you keep
browsing, logging, even queueing more jobs.

---

### C5 — Per-channel composable editing (Settings… tabbed editor)

Convert dialog's per-channel rows are now **functional**:
File format / Video / Audio / Trimming dropdowns edit the live
`TranscodeOptions`, and the Settings… buttons open three new sheets
that bind through the same state. When the user diverges from the
preset's defaults the job runs through C3's composable runtime
instead of the legacy preset path.

**New file** `Sources/PurpleReel/Models/TranscodePreset+Options.swift`
materializes a starting `TranscodeOptions` from any existing preset's
`avPresetName` / `ffmpegArgs`:

- AVAssetExportSession constants → matching VideoCodec + size
  (pass-through → copy/copy; size-keyed presets pick the right
  `.fixed(W, H)`; ProRes 422 / 4444 constants map to their codecs)
- ffmpeg recipes → sniff `-c:v <codec>` + `-profile:v` + `-b:v` /
  `-crf` out of the argv. `dnxhd` with `dnxhr_*` profile maps to
  `.dnxhr`; bare `dnxhd` stays `.dnxhd`. Bitrate parser handles
  `220M` / `192k` / plain integers.
- Audio extracted from `-c:a <codec>` + `-b:a <kbps>`. Audio-only
  recipes (`-vn` present) collapse video channel to `.disabled` and
  container to `.audioOnly`.

**New sheets**:

- `Views/ContainerSettingsSheet.swift` — File & Container Settings
  flyout (Image #85). Streamability, keep-source-timestamps,
  timecode source (fromSource / zeroBased / custom), embed XMP.
- `Views/AudioSettingsSheet.swift` — Audio codec picker, sample
  rate (44.1 / 48 / 96 kHz), bitrate (128 / 192 / 256 / 320 kbit/s).
  Renders a "switch the channel to Re-Encode first" message when the
  audio channel is `.copy` or `.disabled`.
- `Views/VideoSettingsSheet.swift` — Tabbed editor matching Kyno's
  Video Settings flyout (Images #80-#84, #86):
  - **Encoding**: Codec, Frame rate (Like Source + standard cinema
    rates), Size (Like Source + standard ladder + Half/Quarter),
    Quality (Codec Default / Bitrate / CRF — the latter two with
    inline editors).
  - **Filters**: Denoise, Sharpen/Blur (luma+chroma radius +
    strength sliders), Add noise (luma+chroma), Fade in/out
    steppers.
  - **LUTs**: Camera LUT + Creative LUT selection (None /
    Automatic / Sidecar / As Defined in Player). Custom-file
    selection wires in via a follow-up.
  - **Overlays**: Timecode toggle, size (small / regular / large),
    9-position grid picker, opacity slider.

**ConvertSheet plumbing**:

- New `@State editableOptions: TranscodeOptions` seeded on first
  render from `state.preset.defaultOptions()`.
- New `@State optionsBaseline: TranscodeOptions` snapshot of the
  same seed, so `isEdited` is "diff vs baseline" instead of "diff
  vs `TranscodeOptions()`".
- Per-channel `Picker` bindings (Copy / Re-Encode / Off) for video
  and audio; switching to Re-Encode restores the baseline's encoding
  shape if it had one, else defaults to H.264 / AAC.
- Container Picker (MOV / MP4 / MKV / MXF / Audio Only) wired.
- Trimming Picker (None / In - Out) wired.
- "(edited)" indicator + new "Reset" button that snaps everything
  back to the baseline.

**AppState routing** — `confirmConvert(_:editedOptions:)` now takes
an optional `TranscodeOptions`. When non-nil the job runs through
`TranscodeJob(source:options:outputURL:displayName:fadeInSeconds:
fadeOutSeconds:tcBurnIn:)` (C3); when nil the legacy
`TranscodeJob(source:preset:...)` path runs. ConvertSheet's Start
button passes `editableOptions` when it differs from baseline.

11 new tests (`PresetDefaultOptionsTests`) covering Apple-native
preset → options mapping (H.264 / HEVC / ProRes 422 / passthrough),
ffmpeg preset → options mapping (DNxHR / DNxHD with bitrate
extraction / Cineform / ProRes Proxy via `-profile:v 0`), audio-only
preset mapping (Wav → pcm16 + audioOnly + video disabled; M4A →
aac + carries bitrate), plus a coverage probe that asserts every
non-passthrough non-rewrap preset maps to a non-default options
shape (catches future codec gaps).

---

### C4 — Convert dialog UI restructure (Kyno-shaped layout)

ConvertSheet rebuilt to match Kyno's compact layout per the user's
reference screenshots. The runner stays on the legacy preset path;
the new composable execution path (C3) wires in during C5 alongside
the per-channel Settings… tabbed editor.

**Destination section** stays at top, plus:

- **File name pattern** Picker — `Original name + Suffix` (legacy
  default, sticks for upgrade compat), `Original name + Transcoding
  Preset` (Kyno default, e.g. `clip-H2641080p.mp4`), `Original name`.
  Persisted under `UserDefaults["convertFilenamePattern"]`.
- **Example** preview — live filename for the first asset under the
  current pattern + preset (`stem(from:preset:pattern:)` runs the
  same logic the actual job runner does, with no disk dependency).
- **Collision warning row** — counts how many output paths already
  exist on disk and surfaces `"N warnings: Would overwrite existing
  file"` in orange with a triangle icon. When `skipExisting` is on,
  appends `(will be skipped)` so the user knows nothing destructive
  is queued.
- **More Options** disclosure — collapses fades + TC burn-in by
  default so the main dialog footprint matches Kyno's; expanding
  reveals the same controls PurpleReel has always shipped.

**Conversion Preset section** rebuilt with:

- Header: `Conversion Preset: <name>` + `(edited)` indicator (today
  fires when filename pattern diverges from the legacy default — the
  C5 full options editor will pipe more deltas through it) + gear
  icon with help tooltip (preset Save As / Reset land in C5).
- Per-channel grid rows: **File format / Video / Audio / Trimming**
  each showing the preset's effective value + a short descriptor
  (`Streamable, Source Timecode` / `Do not re-encode` / `H.264 1080p,
  Size Like Source` etc.) + a `Settings…` button that's disabled
  with a tooltip flagging C5.

**TranscodeService changes**:

- New `stem(from:preset:pattern:) -> String` pulled out so the
  Convert dialog's Example preview can render filenames without
  hitting the filesystem.
- New `outputURL(for:preset:in:pattern:)` overload routes the
  pattern through to the actual collision-resolving URL builder.
  Legacy `outputURL(for:preset:in:)` delegates with
  `.originalPlusSuffix` so existing callers see no change.
- `confirmConvert(_:)` and `openConvertDialog(preset:)` thread the
  sticky pattern through.

9 new tests (`FilenamePatternTests`) covering stem construction for
each pattern, slug stripping (parens / dots / spaces / slashes),
default = `.originalPlusSuffix`, rawValue round-trip for the sticky
persistence, and `outputURL` collision-counter behavior.

USER_MANUAL update deferred to C5 (when the full options-edit story
is in place — current dialog is a UI restructure, not new user-facing
capability beyond the filename pattern picker).

---

### C3 — Composable runtime (TranscodeOptions → executable backend)

Bridge between the new composable spec (C1 / `TranscodeOptions`) and
the existing `TranscodeJob` runner. The smallest possible change:

- **New file** `Sources/PurpleReel/Services/TranscodeOptionsResolver.swift`
  ships a `TranscodeOptions.resolveBackend() -> ResolvedBackend` that
  picks the right executor.
- **`ResolvedBackend` enum** matches the two paths `TranscodeJob` already
  handles: `.avAssetExport(presetName, ext, alwaysAvailable)` or
  `.ffmpeg(args, ext)`.

Routing strategy:

1. **video = .copy + audio = .copy** → `AVAssetExportPresetPassthrough`
   (container rewrap; always available).
2. **container = .audioOnly OR video = .disabled** → ffmpeg with `-vn`
   + audio codec args. Extension follows the codec (Wav, AIFF, M4A,
   MP3, MP2 → wav / aiff / m4a / mp3 / mp2).
3. **video = .reencode(VideoEncoding) + codec.isAppleNative**:
   - H.264 → size-keyed `AVAssetExportPreset…` (likeSource →
     HighestQuality; 1280×720 → 1280x720; 1920×1080 → 1920x1080;
     3840×2160 → 3840x2160; sub-720 → 640x480)
   - HEVC → likeSource → HEVCHighestQuality; 4K → HEVC3840x2160;
     else HEVC1920x1080
   - ProRes 422 / 4444 → the matching `AppleProRes…LPCM` constant
   - ProRes 422 HQ / LT / Proxy → **fall through** to ffmpeg
     (`prores_ks` profile 3/1/0); no Apple constants on macOS
4. **video = .reencode** otherwise → ffmpeg with codec-specific recipe.
   DNxHR → `-c:v dnxhd -profile:v dnxhr_*` + `yuv422p` (HQ) or
   `yuv422p10le` (HQX) or `yuv444p10le` (444). VP8/VP9 → `libvpx` /
   `libvpx-vp9` → `webm`. FLV → `flv`. WMV → `wmv2`.
5. **video = .copy + audio = .reencode** → ffmpeg with `-c:v copy` +
   audio recipe.

Filter chain limited for now to `-vf scale=…` when size is fixed or
fractional. Denoise / sharpen / fade-in-out / TC overlay all stay on
the AVFoundation composition path (`TranscodeJob.applyComposition`)
and are NOT yet baked into the ffmpeg argv. C5 will add the full
`-vf` chain.

**New `TranscodeJob` convenience init** accepts `TranscodeOptions`
directly:

    TranscodeJob(source: url, options: opts, outputURL: out,
                 displayName: "DNxHR HQ 23.98")

Builds a synthetic single-use `TranscodePreset` wrapping the
resolved backend, then defers to the existing designated initializer.
Synthetic preset is never persisted — it's a one-shot adapter so the
AVAssetExportSession branch / ffmpeg branch / progress polling /
cancellation flow downstream unchanged.

14 new tests (`TranscodeOptionsResolverTests`):
- Pass-through routing for copy/copy in MOV + MP4
- H.264 size routing (1080p → 1920x1080 preset; 4K → 3840x2160;
  likeSource → HighestQuality)
- HEVC 4K routing → HEVC3840x2160
- ProRes 422 → AppleProRes422LPCM (alwaysAvailable = true)
- ProRes 422 HQ falls through to ffmpeg `prores_ks` profile 3
- DNxHR routes to ffmpeg `dnxhd` encoder with `dnxhr_hq` profile +
  `yuv422p`
- VP9 routes to `libvpx-vp9` with webm extension + carries -b:v
- Audio-only PCM 16-bit routes to ffmpeg with `-vn` + `pcm_s16le` +
  wav extension
- Audio-only MP3 routes to `libmp3lame` + carries bitrate + mp3
  extension
- Fixed size emits `-vf scale=W:H`
- Half-scale emits `-vf scale='trunc(iw/2.0/2)*2':-2` (even-rounding)

Foundation for C4 (new Convert dialog) and C5 (tabbed Settings…
editor). No user-visible behavior change in this commit — the new
init is dormant until C4 surfaces it.

---

### C2 — Extended preset catalog (~50 new presets)

`Sources/PurpleReel/Models/PresetCatalog.swift` ships a curated
extended catalog wired into `TranscodePreset.combined()` so the
right-click Convert / Combine / Export Subclips menus immediately
gain Kyno-shaped coverage across all 8 categories:

- **Audio (10)**: Wav 16/24/32, AIFF 16/32, M4A 128/192/256,
  MP3 128/256. All ffmpeg-routed with `-vn` so no video stream
  leaks into the audio container.
- **Distribution extras (6)**: H.264 480p, HEVC 4K UHD, Flash
  Video (FLV), WMV HQ, WebM VP8/Vorbis, WebM VP9/Vorbis.
- **DNxHD (10)**: bitrate ladder × framerates DITs actually
  deliver (23.98 / 25 / 29.97 / 50 / 59.94 fps at 115-440 Mbps).
- **DNxHR (9)**: HQ + HQX + 444 across UHD and 4K at 23.98 /
  29.97 / 50 fps. ffmpeg's `dnxhr_*` profiles are resolution-
  independent; the menu name carries the resolution for legibility.
- **Editing extras (6)**: ProRes 422 HQ / LT / Proxy / 4444
  (via ffmpeg `prores_ks` profile 0-4; AVAssetExportSession
  doesn't expose these as preset constants on macOS), Photo
  JPEG, V210 Uncompressed.
- **Proxies (7)**: H.264 Web Proxy 1080/720/540 × LQ/HQ,
  ProRes Editing Proxy 1080/720. Augments the existing
  smart-proxy half/quarter.
- **Web extras (2)**: HEVC 8K UHD (via Highest Quality preset),
  HEVC 720p.
- **Rewrap variants (2)**: Rewrap to MOV, Rewrap to MXF.

Every preset is executable today — Apple-native codecs (H.264 /
HEVC) use AVAssetExportSession preset names; everything else
uses ffmpeg with the same `{IN}` / `{OUT}` placeholder
substitution the existing built-ins use.

Curated, not exhaustive. Kyno ships ~28 DNxHD and ~30 DNxHR
variants; the long-tail entries are 1-2-per-decade deliveries
that we can surface via "Save as Preset…" once C4 lands.

9 new tests (`PresetCatalogTests`):
- Catalog ships non-empty
- IDs disjoint from legacy `TranscodePreset.all`
- IDs unique within catalog
- Every TranscodeCategory has ≥1 preset (so no submenu collapses)
- `combined()` is a strict superset of `all` + extended
- Every preset is executable (has avPresetName OR ffmpegArgs)
- All ffmpeg recipes carry `{IN}` / `{OUT}` placeholders
- Audio presets all include `-vn` (no video stream)
- Extended catalog reports `isCustom = true` (since IDs aren't
  in `builtInIDs` — pinned behavior for this commit)

No menu code changed — `AssetContextMenu.convertSubmenuContents`
already iterates `TranscodeCategory.allCases` and calls
`TranscodePreset.byCategory(_:)`, which routes through
`combined()`. So the new presets auto-surface in the right
submenus. Right-click any clip → Convert / Combine / Export
Subclips submenus now show the full Kyno-style tree.

C3 next: rebuild TranscodeJob to read TranscodeOptions directly
so per-channel Copy/Re-encode + filter chain + per-channel
settings dialogs can drive the runtime.

---

### C1 — TranscodeOptions composable model

New `Sources/PurpleReel/Models/TranscodeOptions.swift` introduces the
foundation value type that the new Convert dialog will edit
field-by-field and the new job runner will execute against:

- **ContainerFormat** — MOV / MP4 / MKV / MXF / audioOnly.
- **VideoChannel** — Copy / Disabled / Reencode(VideoEncoding) where
  VideoEncoding carries codec + profile + frame rate + size + display
  AR + rotation + field type + quality (codecDefault / bitrate(kbps) /
  crf(value)).
- **VideoCodec** — H.264, HEVC, the ProRes family, DNxHD/HR, Cineform,
  MPEG-4, Photo JPEG, V210, VP8 / VP9, Flash Video, WMV. Each carries
  `displayName` + `isAppleNative` so the C3 job-runner can route to
  AVAssetExportSession vs AVAssetWriter vs ffmpeg.
- **AudioChannel** + **AudioEncoding** — Copy / Disabled / Reencode
  with codec (AAC, ALAC, PCM 16/24/32, MP3, MP2, Vorbis) + sample
  rate + bitrate.
- **FilterChain** — Denoise, SharpenBlur (luma+chroma radius+strength),
  AddNoise (luma+chroma), fade in / out seconds.
- **LUTSelection** — none / automatic / sidecarIfPresent /
  asDefinedInPlayer / file(path). Stored separately for Camera LUT
  (input correction) and Creative LUT (look) per Kyno's split.
- **OverlaySettings** — TC overlay enable + size + 9-position grid +
  opacity.
- **ContainerSettings** — streamable, keep source timestamps,
  timecode source (fromSourceIfAvailable / zeroBased / custom), embed
  XMP metadata.
- **Trimming** — none / inToOut.

Everything is Codable + Equatable + Hashable so the model can carry
custom-preset persistence and live edit state without manual
serialization plumbing. 9 tests covering defaults, equality, full
JSON round-trip with every nested type populated, default bitrate /
codec values, Apple-native routing classification, and the 9-cell
overlay grid coverage.

This commit ships the foundation only — no UI changes, no
TranscodePreset migration yet. Existing transcode behavior unchanged.
Next commit (C2) will migrate TranscodePreset to embed
TranscodeOptions and add the ~100 missing preset entries.

---

## Sprint 9 — Excel (XLSX) report with embedded thumbnails

File → Export Report → **Excel (XLSX, with thumbnails)…** —
producer / AE deliverable with one row per clip and a JPEG
thumbnail anchored over the first column. Closes Kyno-parity
rows 16/24 (Excel report with thumbnails was the single most
common producer ask in the Kyno feature surveys).

- New `Services/XLSXReportWriter.swift` builds the OOXML structure
  (the 8 XML parts + `xl/media/imageN.jpeg`) into a temp directory
  and shells out to `/usr/bin/zip -r -X -q` to seal the `.xlsx`.
  Pure Swift otherwise — no XLSX library dependency.
- Cell strings inlined via `<c t="inlineStr">` so there's no
  `sharedStrings.xml` to maintain.
- Image anchors via `<xdr:oneCellAnchor>` in `drawing1.xml` —
  each thumbnail pinned to its asset's row at the top-left, sized
  in EMU (9525 EMU per pixel at 96dpi). 120px-wide thumbnails;
  height computed from the asset's actual pixel aspect ratio
  (falls back to 16:9). Row heights bumped to ~51pt so the image
  doesn't crowd the gridlines.
- Filenames XML-escaped (`&`, `<`, `>`, `"`, `'`) so a clip named
  `weird<&>name.mov` produces valid XML, not garbage.
- 5 new tests (`XLSXReportWriterTests`) covering: empty-list valid
  workbook, content-types declares spreadsheetml MIME, sheet
  contains header + asset filenames, special characters escape
  correctly, no drawing reference when there are no thumbs.
- File menu → Export Report submenu now lists three formats:
  CSV, HTML (with thumbnails), Excel (XLSX, with thumbnails).
- USER_MANUAL gets a new "## Reports — Producer / AE
  deliverables" section documenting all three formats and the
  23-column schema.

---

## Sprint 8 — Hover-scrub polish (more frames + SMPTE TC tooltip)

Hover-scrub thumbnails (Kyno-parity row 67) were already shipped in
both List view (`ThumbnailCell`) and Grid view (`GridCell`). This pass
polishes them.

- **Strip granularity 12 → 20 frames.** `ThumbnailService.defaultFrameCount`
  bumped so scrubbing a long clip is noticeably finer. Cache key encodes
  the count, so old 12-frame strips stay on disk as orphans and the
  next hover regenerates a 20-frame strip. `ClipDetailInline.GridCell`
  switched from a hard-coded `count: 12` to the default so all hover
  surfaces share the same granularity.
- **SMPTE timecode tooltip during hover.** Both cells now show the
  clip-time at the cursor position (e.g. `00:01:23:15`) as a small
  monospaced overlay near the top of the cell. Uses
  `Timecode.format(seconds: dur * frac, fps: ...)` with the asset's
  duration + frame rate (defaults fps to 30 when missing).
- **Tick-row cleanup.** `ThumbnailCell` previously inferred the active
  frame index by round-tripping `loadedImage.tiffRepresentation`
  against every URL in the strip (O(N) heavy comparison per render).
  Replaced with a state-tracked `activeIdx` mutated in `loadFrame(at:)`.

---

## Sprint 7 — Dark mode (Settings → Appearance)

User-facing appearance picker in Settings → General → Appearance:
**Match System / Light / Dark** (segmented Picker). The pick lives
in UserDefaults under the `appearance` key.

Applied on two layers so the entire window stays consistent —
SwiftUI's `.preferredColorScheme(...)` only retints SwiftUI surfaces;
title bars, NSOpenPanel, NSSavePanel, NSAlert, and any AppKit chrome
keep following `NSApp.appearance`.

- **SwiftUI**: `.preferredColorScheme(preferredColorScheme)` applied
  to the WindowGroup root AND the Settings scene root. The shared
  helper maps `"light" → .light`, `"dark" → .dark`, `"system" → nil`.
- **AppKit**: `AppDelegate.applyAppearance()` mirrors the same pick
  onto `NSApp.appearance` (`.aqua` / `.darkAqua` / `nil`). Observes
  `UserDefaults.didChangeNotification` and re-applies on every flip,
  gated on a value-changed check so unrelated defaults writes don't
  thrash the appearance.

USER_MANUAL: documented under Settings → General → Appearance.

---

## Sprint 6 — Sprint 2 verification + zero-based TC honesty

Sweep of the 15 items in `KYNO_RESEARCH.md`'s Sprint-2 ("Migration
safety net + standalone Smalls") block. Reconnaissance confirmed
all 15 are already wired in trunk:

- Find Lost Metadata, Paste Metadata, Play-All-Selected, Incremental
  transcoding (`AppState.confirmConvert` skip-existing check), shift-
  click hard refresh (`ContentView.swift` modifier detect), smart
  proxy auto-scale presets, Date Recorded/Created columns, Display
  size + Aspect ratio columns, LUT-on-frame-export default, audio
  channel names field, subclip name-collision auto-disambiguate,
  file-count safety-limit warning, transcoder file-timestamp
  preservation, fade in/out.

Only honesty gap was the Settings → Advanced → "Use zero-based
timecode" toggle, which read its UserDefaults key into `_`
(literally discarded the result) in `Timecode.format(seconds:fps:)`.
Today every clip already starts at 00:00:00:00 because the formatter
gets seconds-from-start as input — so the toggle had no observable
effect. Surprises users who flip it expecting a behavior change.

- **Timecode.swift**: removed the dead `_ = UserDefaults...` placeholder
  read; trimmed the surrounding comment to clarify that
  `useZeroBasedTimecode` is reserved for a future container-TC build.
- **SettingsView (Advanced → Timecode)**: added a caption under the
  toggle telling users it's reserved for container-embedded source TC
  surfacing, so they don't think it's broken.

---

## Sprint 5 — Coming-from-Kyno polish

Verification + final polish on the Kyno compatibility bundle that
shipped across Sprints 1-4. Confirmed all 12 keyboard / sort / label
items in `KYNO_RESEARCH.md`'s "Recommended starting sprint" are now
wired end-to-end (preset, first-launch sheet, Settings toggle, menu
bindings, shortcuts catalogue).

- **Detail-view clip stepper visible affordance.** `ClipDetailInline`
  header now shows ◀ / ▶ chevron buttons next to the filename,
  disabled at the ends of the displayed list. The ⌘← / ⌘→ keybindings
  remained as before (wired in `PurpleReelApp.swift`'s View menu) — the
  chevrons just make the feature discoverable for users who didn't
  read the Kyno-compat sheet.
- **Shortcuts catalogue + cheat-sheet.** Added the previously-missing
  ⌘← / ⌘→ "Previous / Next clip" entries to `Help/Shortcuts.swift`
  under the Browser group; cheat-sheet and `SHORTCUTS.md` now show
  them.
- **First-launch sheet copy.** `ComingFromKynoSheet`'s "regardless of
  your choice" paragraph now lists ⌘← / ⌘→ alongside the rest of the
  Kyno-familiar bindings.

---

## Sprint 3-4 — Kyno parity closeout (Medium + Large rows)

A run through every remaining Kyno parity item in `KYNO_RESEARCH.md`.
Builds 327 → 348. Canonical status: `KYNO_RESEARCH.md` (per-row), this
section is the user-facing rollup.

### Medium bucket (rows 10, 11, 14, 15, 18, 27, 28, 41, 47, 52, 61,
68, 80)

- **Timecode burn-in during transcode** (row 10). Convert dialog →
  "Burn timecode into video". `TranscodeJob.applyComposition` switches
  to a CIFilter-handler videoComposition that runs the opacity ramp +
  per-frame TC overlay in one pass.
- **LUT auto-detection** (row 11). `LUTLibraryService` walks PurpleReel
  + FCP `*.fcpbundle` + Resolve LUT roots; `PlayerController.load`
  matches filename keywords (`SLog3` / `V-Log` / `LogC` / `HLG` etc.)
  and auto-applies. Settings → General → "Auto-apply suggested LUT".
- **Folder-tree metadata transfer** (row 14). File → "Transfer Metadata
  Between Folders…" copies clip_metadata + rating + tags across two
  folders matched by filename + size.
- **Batch export frames at every marker, with LUT baked in** (row 15).
  Playback → "Export Frames at Markers…" (⌥⌘⇧E). One PNG per marker,
  filename embeds `HHMMSS_FFf_<note-slug>`.
- **Excel/CSV report with thumbnails** (row 16). File → Export Report
  → CSV / HTML. HTML embeds the middle-frame thumbnail per row as
  base64 PNG; CSV writes 22 columns with RFC 4180 escaping.
- **Paste & rename** (row 18). File → "Paste with Rename…" (⌘⇧V) reads
  file URLs from NSPasteboard, applies a `{date}_{orig}{ext}` template,
  copies into a chosen folder.
- **AND / OR filter combine mode** (row 27). `filterMatchMode` AppStorage
  flips active-filter set between AND and OR. Pills bar exposes the
  chip.
- **VFR vs CFR filter** (row 28). v5 schema adds `asset.isVFR`.
  MediaScanner detects via `nominalFrameRate` vs `minFrameDuration`
  (>10% gap = VFR). Filter → Frame Rate → CFR / VFR / Unknown.
- **Poster-frame keyboard P** (row 41). v6 schema adds
  `asset.posterFrameSeconds`. P key captures the playhead; ⇧P clears.
  `ThumbnailService.posterFrame(for:seconds:)` caches one frame per
  (path, modtime, seconds). Grid + List cells render the poster as the
  at-rest frame; hover-scrub still uses the 12-frame strip.
- **Edit Tags ⌘⇧T + autocomplete** (rows 25, 47). `BatchTagEditorSheet`
  shows union-of-selection tags with "partial" badges, autocomplete
  from known tag names, additive add / batch remove.
- **Pitch-preserved playback at 0.5/0.75/1.25/1.5/2×** (row 52).
  `item.audioTimePitchAlgorithm = .spectral`. Playback → Speed
  sub-menu.
- **C4 IDs + ASC-MHL v2.0** (row 61). `HashAlgorithm.c4` = SHA-512
  base58-with-c4-prefix. New `ASCMHLWriter` emits the Netflix-required
  v2.0 schema. `BackupJob.mhlFormat` picks legacy vs ASC-MHL.
- **Live waveform column in the list view** (row 68). Optional
  `ListColumn.waveform`. `WaveformService.cachedOrGenerate` caches
  peaks as JSON keyed by (path, modtime, bucketCount).
- **Kyno `.LP_Store/` XML import** (row 80). Metadata → "Import from
  Kyno (.LP_Store)…" recursively walks the chosen root and parses
  sidecar XMLs with a permissive XMLParserDelegate (accepts
  schema-drift synonyms — `<asset>`/`<clip>`/`<file>`,
  `<rating>`/`<stars>`, `<tag>`/`<keyword>`).

### Large bucket (rows 5, 7, 8, 29, 57, 66)

- **FCPXML re-import / round-trip** (row 5). Metadata → "Import
  FCPXML…". `FCPXMLImportService.importXML(at:db:)` parses 1.8-1.11
  with a permissive XMLParserDelegate. Match strategy: full URL-decoded
  path → filename fallback. Merge is additive — markers de-duped by
  ±1/fps + note, keywords union as tags, FCP `favorite` raises rating
  to 5★ but never demotes, `<metadata><md/>` fills empty log fields
  only.
- **Combine multiple clips** (row 8). Convert → "Combine Clips…" (⌘⇧J).
  `CombineClipsJob.run()` builds an `AVMutableComposition`, inserts
  video + audio at a running CMTime cursor, copies the first clip's
  `preferredTransform` + `naturalSize` so portrait phone footage stays
  upright, exports via AVAssetExportSession.
- **Shared workspace cache for NAS / SAN** (row 7). Off by default.
  Settings → General → "Write shared metadata cache next to media".
  `<dir>/.purplereel/<filename>.json` per clip carries technical + user
  metadata. MediaScanner's read path checks `loadIfFresh(for:)` first
  and skips AVAsset probes on hit. After scan, `hydrateUserMetadataFromCache`
  runs the user portion through additive merge.
- **Spanned-clip detection** (row 29). `SpanDetectionService.detect(in:)`
  pure-Swift heuristic: same-dir + same-ext + matching tech specs +
  sequential trailing digits (MVI_0001/MVI_0002, C0001/C0002,
  00000/00001) + modtime within 120s. New "Spanned Clips" sidebar
  section; right-click → "Combine Segments…" opens the row-8 sheet
  pre-populated.
- **Centralized cross-volume offline search** (row 57). v7 schema adds
  `asset.volumeUUID` (indexed) + `asset.volumeLabel`. Catalogue persists
  across unmounts; cells fade-overlay + cloud-slash badge offline
  assets. Filter → "Volume / Online status" → Online / Offline.
  `VolumeWatcher.handleMounted` calls `AppState.reconnectVolume(...)`
  to re-anchor paths after a remount renames the volume.
- **Workflow chains** (row 66). `WorkflowChain` model + `WorkflowChainsStore`
  (JSON in UserDefaults). Three step kinds: Verified Backup, Transcode,
  Export Report. `WorkflowChainRun` drives sequential execution with
  per-step state. File → "Workflow Chains…" (⌘⇧Y) does CRUD + run.
  `runOnCameraMediaMount` flag auto-offers the chain when a camera
  card mounts.

### Polish & UX

- **Detail-view tabbed right pane** (Kyno-style). Segmented control
  toggles Metadata / Content / Subclips / Tracks. New `ClipFramesGrid`
  extracted from `ClipContentView`'s frames block. Active tab sticky
  via `clipDetailInspectorTab` AppStorage.
- **Sidebar snap-back from Detail to List**. Clicking a sidebar folder
  while in single-clip Detail used to leave the previous clip stuck
  on screen. `AppState.navigate(to:)` flips `viewMode` to "list" so
  the user lands somewhere browse-able.
- **Right-click menu wired to shipped features**. Five items used to
  fire an "On the Kyno-parity roadmap" alert despite the underlying
  features shipping — Export Markers as Stills, Import Metadata,
  Tags, Edit Multiple, Export Markers as Stills (in Edit menu).
  All now invoke the real methods. Dropped dead-end items (Batch
  Image Transform, per-clip LUT picker).
- **App version**: bumped through builds 327→356 during this run.

---

## Kyno-parity Round 2 — Workspace + history + full menu bar

- **Workspace = multiple roots** (was: single rootFolder). `Open
  Folder…` replaces the workspace; new **Add Folder to Workspace…**
  (⌘I) extends it. Sidebar renders one folder tree per root with
  a context menu (Remove from Workspace / Reveal in Finder), a
  Workspace header gear-menu (Add Folder / Clear Workspace), and
  persists across launches.
- **Bug fix**: opening a different folder no longer leaves the
  previous folder's clips visible. `displayedAssets` now always
  filters by either the explicitly-selected folder or — when no
  folder is selected — the union of all workspace roots.
- **History navigation**: ⌘[/⌘] back/forward through folder
  selections, with a History menu plus back/forward arrow buttons
  in the browser toolbar. The History → Clear History menu wipes
  the stack but keeps the current location.
- **Comprehensive Kyno-style menu bar**: File / Edit / Playback /
  Metadata / Convert / View / History / Window / Help, mirroring
  the reference screenshots. Wires every action that already
  exists (Open, Add Folder, Reveal, Rename, Export Subclips/
  Metadata, Copy and Verify [opens Verified Backup], Playback
  shortcuts, Rating ⌘0…⌘5, Transcribe / Auto-Describe / Similar
  Takes, every Transcode preset including ffmpeg, Previous/Next
  Clip ⌘←/⌘→, Drilldown ⌘D, Back/Forward ⌘[/⌘], Reset Window
  State, Keyboard Shortcut Reference). Menu items routed to the
  player (loop, in/out, markers, export frame, in-to-out) post
  `Notification.Name.playerCommand` so the menu drives the same
  pipeline as the existing keyboard handler.
- **Previous/Next Clip** (⌘← / ⌘→) — moves the asset selection up
  or down one row within the current displayed list. Wraps to
  start/end at boundaries.
- New `KYNO_PARITY_ROADMAP.md` tracks the complete gap from Kyno
  with ✅ / 🟡 / ⬜ status per item.

## Kyno-parity round 1 (Content/Tracks tabs, folder tree, browser controls)

User-driven; replicating the parts of Kyno's UX that close the most
visible gaps. Working from Kyno reference screenshots + the support
keyboard-shortcuts reference page.

- **Content tab** (`ClipContentView`): file metadata block (filename,
  path, size, modification/recording date, container, codec, fps,
  bitrate, audio codec/rate/channels) stacked above a 5×6 = 30-frame
  grid. Each tile shows the seconds offset overlay and is clickable
  to seek the player. `ClipDetailsService` pulls the extended
  metadata from `AVURLAsset` on demand.
- **Tracks tab** (`ClipTracksView`): per-stream technical breakdown
  matching Kyno's Tracks view — Track #1 (video) with codec / fps /
  resolution / aspect / bitrate / duration; Track #2 (audio) with
  codec / sample rate / channel layout / bitrate. Loads lazily on
  appear.
- **`ThumbnailService` parameterized**: accepts a frame count;
  hover-scrub cell still uses 12, the Content grid uses 30. Cache
  dir hash now includes the count so different counts cohabit.
- **Player View menu**: Rotate (0/90/180/270) + Flip H/V applied as
  a `CALayer.setAffineTransform` on `AVPlayerLayer`. Preview-only —
  the underlying file and any transcode are untouched.
- **Folder tree sidebar + drilldown**: recursive `FolderNode` tree
  built from the asset list's paths; expandable rows with disclosure
  triangles, recursive asset count badges. Selection drives a
  `displayedAssets` filter on AppState. Drilldown toggle in the
  browser toolbar controls whether subfolder contents are included.
- **Type filter chips**: All / Video / Audio / Images, capsule
  buttons in the browser toolbar.
- **Sort dropdown**: Name / Date / Size / Duration / FPS, persisted
  in `@AppStorage`. Drives the `displayedAssets` sort order.

## Round 2 follow-ups (thumbnails, SFTP pwd, BK-tree)

- **Thumbnail strip with hover-scrub** in the browser:
  `ThumbnailService` generates 12 evenly-spaced JPEGs per video
  (spread over the middle 90% to skip slates/leader), JPEG-encoded
  at 240px max, cached under
  `~/Library/Application Support/PurpleReel/thumbnails/<hash>/`.
  Cache key includes file modification time so touching the source
  invalidates. `ThumbnailCell` is the SwiftUI view: lazy-loads the
  middle frame on appear, cycles frames based on cursor X under
  `onContinuousHover`, falls back to a film icon when frame
  extraction fails. Added as the leftmost (90px) column of the
  asset table.
- **SFTP password auth** via `sshpass` + Keychain:
  `KeychainService` wraps `SecItem*` for per-destination password
  storage keyed by the destination's UUID. `SFTPService` detects
  `sshpass` (Homebrew or system path); when a password is stored
  for the active destination, sftp is launched as
  `sshpass -e /usr/bin/sftp …` with the password injected via the
  `SSHPASS` env var (safer than `-p` which would expose it in
  `ps`). UI gets a SecureField + a green/orange status line
  indicating whether sshpass is installed.
- **BK-tree similar-takes clustering**: replaces the previous
  O(n²) pairwise loop. `BKTree.swift` is the Burkhard-Keller tree
  with triangle-inequality pruning at each level. Scales us up to
  tens of thousands of clips without changing the
  `SimilarTakesService.findClusters` API. Verified against
  brute-force on 500 synthetic UInt64 hashes at four thresholds
  (2, 8, 20, 64) — results agree exactly.
- **Tests**: +4 BK-tree tests (exact match, within-threshold
  set membership, brute-force agreement, insertion count). All
  28 tests still green.

## Post-MVP follow-ups

- **XCTest suite** (24 tests across 6 files, `./run-tests.sh`):
  BatchRenameService token expansion, HashingService SHA-1/MD5/SHA-256
  against canonical FIPS vectors + chunked-matches-single-shot,
  MHLWriter XML well-formedness + escape, FCPXMLWriter
  well-formedness + special-chars escape, WhisperService.parseSRT
  shape coverage, WindowStateGuard preflight semantics.
- **FCPXMLWriter bug fix** caught by the new tests: `file://` URLs
  with `&` in the path were emitted unescaped, breaking XML parse.
  `fileURL()` now percent-encodes and XML-escapes.
- **Settings → AI pane** (`AISettingsView`): override `transcribe.py`
  path, pick Whisper model (turbo/tiny/base/small/medium/large-v3),
  pick Ollama model from live `/api/tags` query with reachability +
  script-presence indicators. Persisted via `@AppStorage`.
- **AI service overrides plumbed** through `transcribeSelected` and
  `autoDescribeSelected` — settings take effect immediately.
- **Per-byte SFTP progress**: streaming stdout parser hops on the
  main actor as sftp emits `Uploading <path> to <name>` / `100% …`
  lines, updating `SFTPFileItem.state` live. Raw log accumulates in
  real time too instead of all-at-end.
- **Parallel multi-destination backup**: when ≥2 destinations are
  configured, copy + verify happen concurrently via `TaskGroup`.
  Source hash still computed once per file. Wall time ~= slowest
  destination (was: sum across destinations).
- **Phase-2 codecs via ffmpeg** (4 new presets): DNxHR SQ, DNxHR HQ,
  Cineform, and ProRes-in-MXF rewrap. `TranscodeJob.runFFmpeg`
  shells out to `ffmpeg`, parses `time=HH:MM:SS.xx` from stderr to
  drive the progress bar, surfaces a clear error if ffmpeg isn't
  installed.

## Phase 11-12: polish + docs

- **Audio waveform overlay**: `WaveformService` runs an AVAssetReader
  pass over the first audio track at file-load time, bucketing
  16-bit PCM into 800 peak amplitudes (Accelerate-friendly inner
  loop, sqrt curve so dialog stays visible against transients).
  Renders behind the scrubber playhead via a custom `WaveformShape`.
- **Multi-rate J/K/L shuttle**: J/L step through ±¼× / ±½× / ±1× /
  ±2× / ±4×. Direction-reverse resets to 1× in the new direction
  (FCP/Premiere semantics). K stops.
- **Batch rename** with token template (`{orig}` `{ext}` `{date[:fmt]}`
  `{counter[:width]}` `{codec}` `{fps}` `{w}` `{h}` `{size_mb}`),
  live preview with red-flag conflict detection, on-disk move +
  catalog DB path update + auto-rescan.
- **USER_MANUAL.md**: full feature reference — install, keyboard,
  toolbar, logging, LUT, transcode, backup+MHL, SFTP, FCPXML, all
  three AI flows, batch rename, output paths, recovery.

## Phase 9-10: AI augmentation

All three differentiators that make this not-a-Kyno-clone, fully local
(nothing leaves the machine):

**Whisper transcription** (`WhisperService`):
- Bridges the sibling `transcribe/` MLX-Whisper project via Process.
- Probes for Homebrew Python (3.10+) first, falls back to `/usr/bin/python3`.
- Runs `transcribe.py -i <file> -o <tmp> -f srt --quiet -m turbo`,
  parses the produced SRT into `[TranscriptSegment]` (verified parser
  against synthetic SRT).
- Persists `TranscriptDocument` JSON in the existing `transcript`
  table; surfaces a segment-by-segment reader in the AI sheet.
- "Transcribe + Create Markers" option auto-emits one marker per
  segment with the transcribed text as the marker note.

**Ollama auto-description** (`OllamaService`):
- HTTP POST to `localhost:11434/api/generate` with `stream:false`.
- Round-trip verified live against `dolphin-mistral:latest`.
- Reachability probe (`/api/tags`, 1s timeout) — fast fail when
  Ollama isn't running.
- Prompt assembled from filename + (if present) transcript snippet;
  result lands in the asset's description field.

**Similar takes** (`SimilarTakesService`):
- 64-bit dHash (8×9 luminance grid, adjacent-pixel comparison) of
  each video's middle frame — deterministic, verified across repeated
  runs.
- Naive O(n²) pair-wise Hamming clustering with union-find at
  threshold 10/64 bits. Adequate for hundreds of clips; BK-tree port
  is a Phase-2 optimization.
- Per-cluster "best" pick: highest rating → longest duration →
  filename tiebreak. Surfaces in the AI sheet with a rationale.

**UI:**
- New "AI" sparkles menu in the toolbar (Transcribe / Auto-Describe /
  Find Similar Takes).
- Unified `AISheetView` sheet handles all three flows via an
  `AISheetState` enum (progress / ready / error).

## Phase 8: SFTP delivery

- `SFTPDestination` model + `SFTPDestinationStore` (JSON-backed
  UserDefaults persistence). Multiple named destinations.
- `SFTPService` shells out to `/usr/bin/sftp` with a generated batch
  script (`-mkdir` + `cd` + `put` per file + `bye`); captures stdout
  + stderr, parses per-file success/failure into `SFTPFileItem` state.
  Command construction dry-run-verified against expected CLI form.
- `SFTPDeliveryView` sheet: 220px destinations list (add / duplicate /
  delete), grouped editor form (host / port / user / remote path /
  identity-file / accept-new-host-keys), file picker (add from disk
  or "all catalogued"), per-file progress, raw `sftp` log disclosure.
- Auth model: SSH key only for MVP (use ssh-agent / `~/.ssh/config`,
  or an explicit identity-file path). Password auth deferred —
  requires `sshpass` and Keychain integration.
- `com.apple.security.network.client` added to entitlements
  (defensive; sandbox is off so not strictly required).

## Phase 8: FCPXML export

- `FCPXMLWriter`: emits well-formed FCPXML v1.10 (validates with
  `xmllint`). Per-asset `<asset>` + `<format>` dedup, rational-time
  math snapped to the asset's frame grid (uses canonical NTSC
  timescales 24000/30000/60000 for 23.98/29.97/59.94 and 100-based
  for 24/25/30/50/60). Logged markers, subclips, tags, and 4–5 star
  ratings cross over to the FCP timeline as `<marker>`, `<asset-clip>`
  with explicit `start`/`duration`, `<keyword>` (tags joined), and
  `<rating name="Favorite">`.
- Send-to-FCP toolbar menu: send selected clip, send entire library,
  with/without auto-launch of `/Applications/Final Cut Pro.app`.
  Falls back to Finder reveal when FCP isn't installed.
- Output lands in `~/Downloads/PurpleReel/exports/`.

## Phase 7: verified backup + MHL

- Chunked streaming hasher (`HashingService`): CryptoKit-backed SHA-1,
  MD5, SHA-256. 4 MB chunks. Cross-validated bit-for-bit against
  system `shasum`.
- Industry-standard ASC Media Hash List v1.1 writer (`MHLWriter`):
  `<hashlist>` with `<creatorinfo>` + per-file `<hash>` records,
  ISO-8601 timestamps, well-formed XML (validates with `xmllint`).
- `VerifiedBackupService`: walks source tree, hash → copy →
  re-hash → compare for each destination, emits one `.mhl` manifest
  per destination on completion. Mismatches fail the file
  individually (others continue).
- BackupView sheet: source + up to 4 destination pickers, hash algo
  segmented control (SHA-1 default per MHL convention), live per-file
  progress with state icons (queued/hashing/copying/verifying/done/
  failed), reveal-in-finder for each written `.mhl`.
- Toolbar action: "Verified Backup" (next to Transcode).

## Sidebar layout: HStack pattern adopted

- Replaced `NavigationSplitView` in `ContentView` with manual `HStack` +
  fixed 240px sidebar (MusicJournal-proven pattern). Rationale:
  `NavigationSplitView` on macOS 14+ does not reliably honor
  `.navigationSplitViewColumnWidth(min:)` at runtime layout — persisted
  state inside the declared range still mis-rendered the sidebar
  narrower than min, even after `.savedState` wipe.
- Added `⌃⌘S` Toggle Sidebar via `@AppStorage("sidebarVisible")`.
- `WindowStateGuard` retained for nested `VSplitView`/`HSplitView`
  inside the detail tree (browser table / player split).
- Documented as canonical PhantomLives pattern in
  `~/Documents/GitHub/PhantomLives/CLAUDE.md` and memory rule
  `feedback_split_view_state_guard`.

## Phase 6: transcode

- Six built-in transcode presets: H.264 1080p/720p, HEVC 1080p,
  ProRes Proxy, ProRes 422, and pass-through rewrap.
- `TranscodeService` wraps `AVAssetExportSession` with progress
  polling, output naming with collision suffix, and codec
  compatibility gating (H.264/HEVC require asset compatibility check;
  ProRes / pass-through always available).
- `TranscodeQueue` (@MainActor): single-worker serial drain — keeps
  the hardware HEVC encoder unsaturated and progress predictable.
- Transcode menu in toolbar (enabled when a clip is selected); queue
  sheet with per-job progress, cancel, and "Reveal in Finder" on
  completion.
- Default output: `~/Downloads/PurpleReel/transcoded/`.

## Phase 5: LUT preview

- Adobe `.cube` LUT parser (3D LUTs native; 1D LUTs synthesized into
  a 33³ cube by per-channel curve sampling).
- LUTs applied in real time via `AVVideoComposition` with a
  `CIColorCubeWithColorSpace` filter; rebuild on LUT change or asset
  load.
- LUT bar under the transport: load `.cube`, show name + cube size,
  clear, persist last-used path via UserDefaults.

## Phase 2: player + logging

- AVPlayer-based detail pane with custom transport (play/pause, 1-frame
  step, J/K/L shuttle rates, I/O markers, click-to-seek scrubber).
- Frame-accurate SMPTE timecode (HH:MM:SS:FF, non-drop) display.
- Marker creation at playhead (M); markers list with inline note
  editing and timecode-jump-to-marker.
- Subclip creation from I/O range (S); subclips list with jump-to-in
  and jump-to-out.
- Tag chips with add (Return) and remove (× click).
- 1–5 star rating + free-form description per asset.
- All detail state persists through GRDB CRUD on `marker`, `subclip`,
  `tag` / `asset_tag`, `rating` tables.

## Phase 1 skeleton

- Scaffolded XcodeGen project, GRDB dependency, asset catalog with
  programmatic film-reel `AppIcon`.
- Catalog schema (assets, tags, markers, subclips, ratings, transcripts,
  FTS5 search table).
- Finder-rooted recursive `MediaScanner` with AVFoundation-derived
  video metadata (codec, resolution, fps, duration).
- Browser view: filterable table of catalog contents.
- Auto-backup-on-launch (zip of `~/Library/Application Support/PurpleReel/`)
  per PhantomLives convention.
- Build/install scripts mirroring `PurpleTracker` conventions.
