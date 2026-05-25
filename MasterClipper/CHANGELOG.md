# Changelog

## 2026-05-16 — build-app.sh: stop breaking the signature post-build

The app stopped launching on macOS 26.5: every run crashed with `EXC_BREAKPOINT` deep inside `CKContainer.__allocating_init(identifier:)` (called from `ShareManager.shared` during `AppState.init`), and once the entitlements were preserved during re-sign it instead failed to even spawn with `Launchd job spawn failed (POSIX 163)`. Root cause was in `build-app.sh`:

1. After `xcodebuild` produced a signed bundle, the script dropped a hand-generated `AppIcon.icns` into `Contents/Resources/` and rewrote `CFBundleIconFile` to `AppIcon.icns`, which invalidated the signature.
2. It then re-signed with `codesign --force --sign "Developer ID Application" --deep` *without* `--entitlements`. The re-sign therefore stripped every entitlement Xcode's automatic signing had injected — `com.apple.developer.icloud-*`, `com.apple.application-identifier`, and `com.apple.developer.team-identifier`. With no iCloud entitlement the bundle had no permission to call `CKContainer(identifier:)` → trap. Once entitlements were restored, the *Developer ID* signature didn't match the embedded *Apple Development* provisioning profile, and `taskgated-helper` rejected the launch with `Unsatisfied entitlements: com.apple.developer.icloud-container-identifiers, com.apple.developer.icloud-services, com.apple.developer.ubiquity-container-identifiers`.

Fix: trust the asset catalog. The icon already ships through `Assets.xcassets/AppIcon.appiconset/`, and `xcodebuild` already produces `Assets.car` and a valid Apple-Development-signed bundle paired with a Mac Team Provisioning Profile that grants the iCloud entitlements. `Scripts/generate-icon.swift` (driven from `build-app.sh`) now writes the regenerated PNGs straight into the asset catalog so the next `xcodebuild` picks them up, instead of being baked into a post-build `.icns`. The post-build re-sign is gone entirely. The build script just `ditto --noextattr`'s the xcodebuild output to the project directory — `--noextattr` matters because the iCloud File Provider in `~/Documents/GitHub/…` re-attaches `com.apple.FinderInfo` to `.app` bundles, which fails `codesign --verify --deep --strict` and trips launchd with the same POSIX 163.

Behavioural change for distribution: with no Developer ID re-sign, distribution-quality bundles will require a separate signing/notarization step before being shipped to other Macs. For day-to-day local development on the maintainer's machine the new build runs cleanly out of `/Applications/`.

## 2026-05-12 — iOS companion app + time-limited CloudKit sharing (1.1.0 → 1.4.3)

Major capability landing: a universal iPhone/iPad companion app, and the ability to share a chosen subset of clips with someone who isn't you. Shipped as six phases over a single session.

### Phase 1 (1.1.0) — Shared SPM package

15 model files (`Clip`, `Persona`, `Site`, `ClipCategory` (renamed from `Category` to dodge the ObjC runtime `Category` typedef collision), `ClipPosting`, `ClipNote`, `ClipSegment`, `ClipHistoryEntry`, `CalendarEvent`, `CalendarRule`, `ExclusionReason`, `PriceEntry`, `PostingFilter`, `ImportModels`, `C4SHistoricalRecord`) plus `SearchService` and `FuzzyMatch` moved out of `Sources/MasterClipper/` into a new local SPM package at `Packages/MasterClipperCore/`. macOS app target now depends on the package (which re-exports GRDB). Every model gained an explicit `public init` with `= nil` defaults on optional params to mirror Swift's synthesized memberwise initializer.

### Phase 2 (1.2.0 worth of plumbing) — macOS snapshot publisher

`Sources/MasterClipper/Services/Sync/SnapshotPublisher.swift` runs `VACUUM INTO` against the live `DatabasePool`, mirrors thumbnails out of each clip's `production_folder`, writes a `manifest.json` (schema version, clip count, generated_at, publisher device id), and atomically swaps the result into the iCloud ubiquity container at `iCloud.com.bronty13.MasterClipper/Documents/snapshot/`. 30-second debounced trigger after any `clips`/`clip_postings`/`clip_notes` mutation; manual **Publish now** button in **Settings → Sync**. Opt-in via `AppSettings.iCloudPublishEnabled`. iCloud capability declared in `project.yml` so xcodegen regenerates entitlements consistently. Snapshot also gets a FTS5 `clips_fts` virtual table over `title / description_raw / description_refined / keywords / performers / transcript`; live macOS DB stays untouched.

### Phase 3 (1.2.0) — iOS reader app

New `MasterClipperiOS` Xcode target — universal iPhone/iPad, iOS 17+. Locates the ubiquity container, downloads + opens the snapshot read-only via GRDB `DatabaseQueue`, observes via `NSMetadataQuery` for new publishes. UI: `NavigationStack` on iPhone (compact), `NavigationSplitView` on iPad (regular). Searchable list with thumbnails, persona badges, status badges. Clip detail shows description, postings, notes, transcript — Mac-local paths (`fcp_project_folder`, `production_folder`, `clip_filename`) intentionally hidden. Search routes through FTS5 when available and falls back to the in-memory `SearchService.matches`. App icon shared with the Mac app.

### Phase 4 (1.3.0) — Light edits from iOS back to Mac

iOS gains a Compose Edit sheet on each clip: mark posted / unmark posted / add note / set status / toggle posting exclusion. Each edit composes an `IntentEnvelope` (UUID, kind, clip id, typed payload, `baseSnapshotGeneratedAt`, device id) and writes a JSON file into `iCloud/Documents/intents/pending/<uuid>.json` via `NSFileCoordinator`. The Mac's new `IntentInbox` watches that folder with `NSMetadataQuery`, decodes each envelope, calls `DatabaseService.apply(intent:)`, moves the file to `applied/` (or `conflicts/`) when done. Migration `v15_intent_idempotency` adds an `applied_intents` table so duplicate envelopes are no-ops. Conflict policy: last-writer-wins with an audit row + sidecar in `conflicts/`. iOS shows a pending-sync badge per clip and a banner in the detail until the next snapshot confirms.

### Phase 5 (1.3.2 → 1.3.3) — Polish

- FTS5 over the snapshot (Phase 2 detail).
- iOS Settings screen (`SettingsView`) — snapshot freshness, clip count, publisher device id, manual reload, editable operator name, pending-sync count. Gear icon in the list toolbar.
- iPad split view via size-class adaptive `RootView`.
- `BGAppRefreshTask` background snapshot refresh: registered in `App.init`, submitted on `scenePhase → .background`, 15-minute earliest-begin, re-arms before doing work so a crash or kill doesn't break the chain.
- `print()` diagnostics gated behind `#if DEBUG`.

### Phase 6 (1.4.0 → 1.4.3) — Time-limited external shares via CloudKit

`ShareManager` on macOS creates a CloudKit share per recipient bundle. Flow: each share lives in its own private-DB zone `share-<uuid>` containing one `SharedClip` CKRecord per clip (with a thumbnail CKAsset projected from the snapshot's thumbnails folder), a singleton `ShareMetadata` record (expiresAt, permission `readOnly`/`readWrite`, label, clipCount), and a `CKShare` anchored on the metadata record as its rootRecord. `createShare(clipIds:permission:expiresAt:label:) → URL` returns the participation URL. `revokeShare` deletes the zone. `ShareExpiryScheduler` arms a one-shot timer at the next-expiring share's `expiresAt`.

macOS UI:
- `Views/Share/CreateShareSheet.swift` — three-step wizard (pick clips → permission + expiry preset 24h/7d/30d/custom + label → confirm + copy/send the URL).
- `Views/Share/ActiveSharesView.swift` — list of every active share with time-remaining, copy-link, revoke-with-confirmation.
- Wired into the Sync settings tab.

iOS recipient side:
- `AppDelegate` (via `UIApplicationDelegateAdaptor`) catches `application(_:userDidAcceptCloudKitShareWith:)` and forwards to `SharedZoneReader` through a NotificationCenter event.
- `SharedZoneReader` accepts the share metadata via `CKAcceptSharesOperation`, enumerates `sharedCloudDatabase` zones, decodes each zone's metadata + `SharedClip` records into `SharedShareSession`s.
- `SharedTabView` surfaces only when at least one share is accepted (`RootView` swaps to a `TabView`); each session is a section, tap a clip → `SharedClipDetailView`.
- Read-write recipients get a `SharedEditSheet` (mirrors `EditClipSheet`); each edit becomes a `SharedClipEdit` CKRecord that wraps a JSON-encoded `IntentEnvelope`.
- `SharedZoneSync` on macOS polls every 60s, decodes each `SharedClipEdit`, routes through `DatabaseService.apply(intent:)`, deletes on success. Idempotency via `applied_intents` (reused from Phase 4). Site lookup bridges `id:<N>` payload form (recipients only see numeric site ids in the shared postings JSON) by primary key.

### Phase 6 follow-up fixes that surfaced during real-device testing

- **iPhone clip detail tap was a no-op**: Phase 5's `List(selection:)` was active in compact size too, eating `NavigationLink(value:)` row taps. Split into two `@ViewBuilder` paths gated on `horizontalSizeClass`.
- **`CKQuery` against auto-created schema rejected with "Field 'recordName' is not marked queryable"**: replaced all three TRUEPREDICATE enumerations (`ShareManager.refreshActiveShares` count, `SharedZoneReader.fetchClipRecords`, `SharedZoneSync.processZone`) with `CKFetchRecordZoneChangesOperation`. Also added a cached `clipCount` field on `ShareMetadata` so listing shares doesn't need a per-zone count fetch.
- **Snapshot-cache file race**: `SnapshotReader` was deleting the cached snapshot.sqlite while the previous GRDB queue still held a file descriptor (`BUG IN CLIENT OF libsqlite3.dylib: vnode unlinked while in use`). Now drops the queue, writes to a `.tmp` first, then atomic renames.
- **`NavigationSplitView` blank screen on iPhone**: switched to size-class-adaptive `RootView` — `NavigationStack` on compact, `NavigationSplitView` on regular.
- **`@objc` selector observers on non-`NSObject` Swift classes**: `SnapshotReader` and `IntentInbox` switched from `NSNotificationCenter.addObserver(_:selector:)` to the block-based `addObserver(forName:object:queue:using:)` API; tokens tracked for `deinit` cleanup.

## 2026-05-09 — Unify Verify Files: one workflow, snapshot-vs-live render fix

The per-clip **Verify files** sheet (`FileAuditSheet`) and the bulk **File-Verification Workflow** (`FileAuditWorkflow`) had drifted into two near-mirror implementations of the same audit panel — same conditions, same pills, same service calls, but with subtle behavioural divergence between them. Collapsed to a single workflow and fixed a real bug that was hiding pills.

- **`FileAuditSheet.swift` deleted (~1230 lines).** `ClipEditView`'s **Verify files** button (line 290) and `EditingWorkflowView`'s **Open full audit…** button (line 44) now both open `FileAuditWorkflow(clips: [draft])` / `(clips: [live])` instead. The workflow already supported single-clip lists — the All / Issues-only toggle, bulk-stamp header buttons, and Skip / Previous / Next footer behave correctly when there's only one clip; nothing in the workflow's plumbing assumes >1 entry. Single source of truth from here on.
- **Snapshot-vs-live render bug — fixed in `FileAuditWorkflow.clipPanel` (line 294).** The audit itself was already running off the live AppState clip via `runAudit(for:)`, but the row's pill conditions (`canPushFromFCP`, `canShowCapture`, the `prod` path the capture pill needs) were reading fields like `productionFolder` / `clipFilename` straight from the workflow's input snapshot. When `ClipEditView` opens the audit and passes `[draft]`, and `draft.productionFolder` is empty (e.g. the clip was just created and the field wasn't backfilled), the snapshot kept the **Push from FCP** and **Capture frames** pills hidden even though the live audit was correctly reporting Production folder ✅ — so the user saw the red Thumbnail-frames row with no button to act on it. Fix: `clipPanel` resolves `appState.clips.first { $0.id == clip.id } ?? clip` once at the top and passes the live clip down to `clipBanner` and every `rowView`. Keeps audit results and row conditions consistent.
- **Draft refresh on workflow dismiss.** `FileAuditSheet`'s narrow `onApplyDetections` callback (only ever fired by an "Apply detected filenames" button to patch `clipFilename` / `previewFilename` onto draft) is replaced by `ClipEditView.syncDraftFilesFromAppState`, called via `.sheet(onDismiss:)`. The workflow writes its mutations (push from FCP, provision production folder, capture thumbnail, transcribe, hash, refine) straight to AppState via `updateClip(_:)`; on dismiss we pull `clipFilename`, `previewFilename`, `thumbnailFilename`, `productionFolder`, `transcript`, all six MP4/reduced hash fields, and `hashesComputedAt` back into the local draft so the user's next save doesn't clobber them with stale snapshot values. Title / description / category / status / etc. are deliberately untouched — those are what the user is editing in the form.
- **Stale `// MARK:` comment** in `FileAuditWorkflow.swift` (`Row + actions (mirrors FileAuditSheet)`) and the `FileAuditSheet` reference in `EditingWorkflowView`'s header doc comment cleaned up.

## 2026-05-08 — Editorial UI redesign + UI hardening + structured clip notes

Two intertwined landings: the whole-app Editorial reskin (chrome, palette, typography, dashboard) and the immediate bug-fix / feature pass that followed first-use feedback.

### Editorial reskin

Whole-app reskin to the *Editorial · bone + ink* design language exported from claude.ai/design. Same data, same routes — different chrome and typography.

- **Top tab bar replaces the macOS sidebar.** `NavigationSplitView` + `SidebarView` are gone. `ContentView` now stacks `TopTabBarView` over a flat `DetailRouterView`. The bar is 56px tall: a 220px brand block (ink "M" mark + serif wordmark), eight horizontal tabs with mono count badges, a live clock, and a `⌘ N · NEW` ink-on-acid pill that fires `.newClipRequested`. The active tab gets ink fill, bone text, and a 3px acid-yellow under-rule. **Import** is no longer a tab — the existing `⌘⇧I` menu shortcut now flips `selectedSection = .importView` and the wizard opens in place.
- **Bumped `windowResetVersion` 2 → 3** to wipe the saved `NSSplitView` widths and sidebar-collapse keys on first launch of the new build, so users don't open into a vestigial sidebar gap.
- **EditorialTheme primitives** in `Views/Shared/EditorialTheme.swift`: palette (`EdColor.bone #f1ede4`, `ink #14110d`, `acid #dcff37`), typography helpers (`EdFont.serif/.sans/.mono` with weight + italic axes), reusable views (`EdEyebrow`, `EdHeadline` with acid-highlighted em word, `EdDeck`, `EdByline`, `EdSectionHeading`, `EdStatusPill`, `EdSiteCell`, `EdNumberCell`, `EdPersonaSwatch`, `EdHairline`, `EdPanel`, `EdPageShell`), and three button styles (`EdAcidPillButtonStyle`, `EdInkPillButtonStyle`, `EdGhostButtonStyle`). The root `.editorialChrome()` modifier sets bone bg, ink fg, and Inter Tight as the default font for everything underneath.
- **Bundled fonts.** Added `Sources/MasterClipper/Resources/Fonts/`: Source Serif 4 (Light, Regular, Semibold, Bold + matching italics), Inter Tight (variable, regular + italic), JetBrains Mono (Regular, Medium, SemiBold). Auto-registered via `ATSApplicationFontsPath = "."` in `Info.plist`. ~3.4 MB total.
- **Dashboard rewrite.** Two-column layout: 280px meta sidebar (issue eyebrow, Source Serif 4 italic-em headline, deck, persona list with swatches + counts, auto-derived pipeline) on the left; content column (4-cell number strip with acid-yellow accent on Fully Posted, then 1.35fr Clip×site table + 380px Per-target progress list) on the right. Number cells, status pills, and site cells are click-throughs to the Clips list with the matching filter pre-applied or the Posting Batch.
- **Other tabs reskinned** with `EdPageShell` (eyebrow + serif headline + italic deck + hairline rule above the body): Editing Queue, Posting Queue, Clips, Calendar, Posting Batch, Reports, C4S Historical, Import. Toolbar buttons relocated into the masthead trailing slot as `EdGhostButtonStyle` / `EdInkPillButtonStyle` pills since the macOS toolbar is gone with the sidebar. Status togglers in the queue filter bars are now ink-bordered with mono labels and 02-padded count badges.
- **Settings window** picks up `.editorialChrome()` at the root so the TabView renders against bone + ink + Inter Tight (the native macOS settings tab strip stays as-is — it's an OS-controlled control).
- **`ClipDetailView` empty state** uses Editorial typography (eyebrow + serif headline + italic deck) instead of the SF Symbol + secondary-text pattern.
- **Forced light color scheme** at the `WindowGroup` and `Settings` scene roots. Editorial is intrinsically a light design (bone canvas, ink ruling), and on a Mac running dark mode SwiftUI's `Table` / `TextField` / `TextEditor` system materials would otherwise resolve to near-black slabs against bone. `.preferredColorScheme(.light)` pins those controls to their light variants.

### UI hardening + new features

- **Debug Mode setting.** New `AppSettings.debugMode: Bool = false` (persists in `settings.json`), toggled from **Settings → General → Advanced**. When off, the UI hides diagnostic surfaces that clutter everyday use; when on, they reappear. Used today to gate two surfaces:
  - The **Order column** in **Settings → Categories** (`Category.sortOrder` readout), via SwiftUI's `.defaultVisibility(.automatic / .hidden)` so the column is omitted from rendering — not just collapsed — when debug mode is off.
  - The **manual status override** Menu in `ClipEditView` (sticky header + Workflow form section). Off-mode users see a plain non-interactive `statusBadge` instead of a clickable Menu — the auto-derived pipeline status is correct in normal use, and pinning a status by hand was masking real workflow gaps.
- **⌘N now opens New Clip in the existing window.** `AppMenuCommands` switched from `CommandGroup(after: .newItem)` to `CommandGroup(replacing: .newItem)` so SwiftUI's default File → New (which spawns a brand-new `WindowGroup` window) is gone. ⌘N posts `.newClipRequested` and `ClipListView` opens the wizard in place.
- **Clips tab trailing buttons rewired.** Workflow / Export had a stale-state bug where the sheet body's nil-branch could render ("No clip selected") even with a row selected, and the Workflow chain-from-new-clip relied on a fragile `.onChange(of:)` race. Replaced the `Bool + clipId?` state pair with `.sheet(item: $workflowClip)` / `.sheet(item: $exportingClip)` bound directly to `Clip?` — SwiftUI cannot show a sheet without the data backing it, and the new-clip→editing handoff defers the second sheet by 0.3s so the dismiss transition completes first. Selection reads through a single `selectedClip` computed (id-lookup against `appState.clips`) so all four trailing pills react to the same state.
- **Segment "rename to fix order" sort, made robust against copy-time clobbering.** `VideoFolderService.enumerate` previously sorted by `URLResourceKey.creationDateKey` only; on Dropbox-synced or AirDrop'd folders btime gets reset to the copy time while mtime is preserved, so the "natural recording order" got scrambled. Now sorts by `min(creationDate, contentModificationDate)` — agrees with btime on never-touched files and falls back to mtime when btime is suspicious — with file size and `localizedStandardCompare(filename)` as tiebreakers. The displayed timestamp matches the value used for sorting so the table preview matches the rename outcome.

### Structured clip notes

- **New `ClipNote` model + v14 migration**, table `clip_notes(id, clip_id, body, operator_name, created_at, updated_at)` with `idx_clip_notes_clip(clip_id, created_at)`. Cascade-deletes with the parent clip.
- **`ClipNotesPanel` view** in `Views/Clips/ClipNotesPanel.swift`, rendered inside `ClipEditView`'s **Notes** section: composer at top with operator-name byline, list of saved notes below with timestamps + Edit / Delete buttons, ⌘↩ to save. Mirrors the PurpleTracker NotesTab pattern.
- **Legacy `clip.notes` blob preserved** as a separate **Activity log (auto-generated markers)** disclosure right beneath the new panel — `[Renamed …]`, `[Posted …]`, `[Editing …]`, `[Status …]` markers still write there, and the disclosure surfaces them read-only. Nothing is lost from the old single-blob notes.
- **Auto-stamped notes for user-visible field changes.** `DatabaseService.updateClip(_:operatorName:)` now diffs old vs new for **Title, Description (raw), Go-Live, Status** and bundles the changed lines into a single `ClipNote` body inside the same write transaction (`Title: "old" → "new"\nStatus: editing → posting`). `setCategories(forClip:categoryIds:operatorName:)` does the same with category names resolved from IDs. The `operatorName` is threaded from `AppState.settings.operatorName`; system / import paths fall back to the literal `"system"`. New `AppState.setClipCategories(...)` wrapper so views don't reach into `DatabaseService` directly for category writes.

## 2026-05-07 — Manual status override + clip-ID copy button

- **Manual status override.** New v13 migration adds a nullable `clips.status_override` column. When set, `DatabaseService.computeStatus` returns it verbatim, bypassing the editing/posting heuristic. Clearing the override returns the clip to auto-derivation. `setStatusOverride(clipId:override:)` writes the column, recomputes `clip.status` from it, stamps a `[Status YYYY-MM-DD: old → new (manual)]` (or `cleared override`) marker into `notes`, and records two `clip_history` rows so the change is auditable. Mirrored on `AppState.setClipStatusOverride`.
- **Status picker in `ClipEditView`.** The status badge in both the sticky header and the Workflow-status form section is now a `Menu` of all five pipeline statuses (plus a *Clear manual override* item when one is set). Picking any value other than the current state opens an *Are you sure?* alert that names the from/to labels and explains the override semantics; only **Change status** / **Clear override** applies the write. A `manual` chip appears next to the in-form badge while the override is active.
- **Copy clip-ID button.** Explicit `doc.on.doc` button next to `ClipIDLabel` in the editor's sticky header, mirroring the title's existing copy button. The clip-ID label itself remains click-to-copy.

## 2026-05-06 — Window-state reset (one-shot + manual)

- **Auto reset on launch.** SwiftUI persists window frame, split-view widths, and sidebar collapse state in `UserDefaults`. Frames can drift off-screen (window saved at coordinates that no longer correspond to a connected display) and stick across relaunches — close + reopen doesn't help. `MasterClipperApp.init` now compares a stored `MasterClipper.windowResetVersion` against a hardcoded constant; when the stored value is lower, every key matching `NSWindow Frame*`, `NSSplitView*`, `NSWindow *`, `SwiftUI.SidebarSeparation*`, and anything containing `SidebarSplitView` is removed, the AppKit `~/Library/Saved Application State/<bundleId>.savedState` directory is deleted, and the leftover sandbox-era container plist (`~/Library/Containers/<bundleId>/Data/Library/Preferences/<bundleId>.plist`) is removed too. Bumped to v2 to ship one more reset for users on v1.
- **`.defaultSize(width: 1400, height: 900)`** added to the main `WindowGroup` so the post-reset launch opens with sensible dimensions instead of an arbitrary fallback.
- **Window → Reset Window State…** menu item (added via `CommandGroup(after: .windowArrangement)` in `AppMenuCommands`). Opens an alert with **Cancel** / **Reset & Quit** — Reset triggers `forceWindowResetNow()` (zeroes the version sentinel and re-runs the wipe synchronously), then calls `NSApp.terminate(nil)`. Relaunch from the Dock or Finder afterwards.

## 2026-05-06 — Re-stamp out-of-pattern production folders (in audit workflow header)

- **Header button in `FileAuditWorkflow`** — same re-stamp action as Settings → File Locations, surfaced where the user actually sees the audit results. Sits next to the existing **Stamp N missing production folders** button. Counts clips whose stored `production_folder` doesn't match `PathDefaultsService.productionPath(for:settings:)` and offers a one-click migration. After running, every visible clip is re-audited automatically so the rows turn green in place.

## 2026-05-06 — Re-stamp out-of-pattern production folders (Settings → File Locations)

- **One-shot re-stamp action** in `Settings → File Locations`. The DB-only pattern flip from the previous fix left existing clips' `production_folder` columns pointing at the brief-window date-only paths (e.g. `<base>/2026-05-05`); the audit reads those values directly so it kept showing the old shape. Re-stamp walks every active clip, computes the expected path via `PathDefaultsService.productionPath(for:settings:)`, and when the stored value differs:
  1. `mkdir -p` the new `<base>/<contentDate> <title>` folder.
  2. **Copy** every per-clip file from the old folder to the new one. A file counts as "per-clip" when its name is exactly `<sanitizedTitle>.<ext>` *or* starts with `<sanitizedTitle>_` (catching `Title.mp4`, `Title.png`, `Title_reduced.mp4`, `Title_frame_07.png`). Anything else stays in the old folder so other clips that historically shared a date-only folder still find their files.
  3. Update `clip.production_folder` to the new path.
- Old folders are **never** deleted — they may still be referenced by other clips that haven't been migrated yet, plus anything you put there manually. Idempotent: re-running with nothing to migrate is a no-op (`already-matched: N`).
- Reports per-run: `Stamped N · already-matched M · files copied X · failed Y`. Failures (mkdir failed, DB update failed) are listed by clip ID below the summary so you can investigate without losing the rest of the run.
- Side-effect: when the old folder was on an unmounted volume, the path is updated regardless and the file copy is skipped — the next audit will then surface the missing-file rows on the (already-correct) new path, which the regular per-clip pills can fix.

## 2026-05-06 — Production folder includes the title (`<date> <title>`)

- **Default `defaultProductionPattern` reverted to `{date} {title}`.** Final layout: `<base>/<contentDate> <Title>/<Title>.<ext>`. The folder is `<date> <title>` (human-scannable in Finder — one clip per row), the file inside is just `<Title>.<ext>` (matches the audit's expected `Title.Extension` lookup).
- **Legacy-upgrade reversed.** `AppSettings.legacyProductionPatternDefaults` now contains `["{date}"]` (was `["{date} {title}"]`) and the `AppState.init` block bumps anyone on `{date}` back to `{date} {title}`. So users who were auto-flipped to `{date}` by the previous build land on `{date} {title}` cleanly. Anyone who explicitly customized to anything else stays on their custom pattern.
- **`provisionProductionFolder` still delegates to `PathDefaultsService.productionPath`** so the pill, the wand button, the backfill, and the Settings preview all stay in lockstep — the path the pill shows is the path the pill creates, regardless of pattern.

## 2026-05-06 — Production-folder path consistency fix

- **Default `defaultProductionPattern` flipped from `{date} {title}` → `{date}`.** The shipped layout is now `<base>/<contentDate>/Title.<ext>` end-to-end — folder is the date, file is the title. Auto-upgrade in `AppState.init` (paralleling the existing legacy-refine-prompt upgrade): any user still on the previous shipped default `{date} {title}` is silently flipped to `{date}` on next launch via the new `AppSettings.legacyProductionPatternDefaults` array. Users who customized their pattern are left alone.
- **`provisionProductionFolder` now delegates path resolution to `PathDefaultsService.productionPath`.** The earlier copy hardcoded `<base>/<contentDate>` independently of the pattern setting — that drifted from the editor's "Set default" wand button and the Settings → File Locations preview, both of which still went through `PathDefaultsService` and were producing `<base>/<date> <title>` for users on the old default. Single resolver now means the pill, the wand, the backfill, and the preview can never disagree.
- **Pill previews use the same resolver.** `FileAuditSheet` and `FileAuditWorkflow` both render the planned production folder by calling `PathDefaultsService.productionPath(for:settings:)`, so the path shown in the pill is exactly the path that will be created.

## 2026-05-06 — Production-folder fix-pill in the audit (per-clip + bulk)

- **`FileAuditService.provisionProductionFolder(clip:settings:fcpSourceFilename:)`** — new service. Resolves the production path as `<settings.defaultProductionBase>/<contentDate>` (just the date — title-less, regardless of `defaultProductionPattern`), `mkdir -p`s it, and when an FCP source filename is supplied **copies** (not moves — FCP retains its render) `<fcpFolder>/<sourceName>` → `<prodFolder>/<sanitizedTitle>.<sourceExt>`. Returns `(productionPath, createdFolder, copiedFromFCP, canonicalFilename)`. Errors are typed: missing production base, missing content date, missing title, source missing, dest exists, copy failed, mkdir failed.
- **Per-clip pill** in `FileAuditSheet` on the **Production folder** check row, shown when the row isn't `.ok` and content date + title + production-base are all set. Two flavours: **Create + copy** (when an FCP MP4 candidate exists) writes the file in as `Title.<ext>` and stamps `clip.clipFilename`; **Create** alone just makes the empty folder. Both write `clip.productionFolder = <path>`. Re-audits in place so the row turns green. The pill also appears mid-walkthrough in `FileAuditWorkflow` for parity.
- **Bulk header action — *Stamp N missing production folders*** in `FileAuditWorkflow`. Walks every clip in the current queue with no production folder set but a content date + title, audits each one to find the FCP MP4 candidate, and runs the same provision pass per clip. Summary line: `Stamped 12 of 14 · 8 with FCP copy · 2 failed`. Per-clip failures (missing source, dest already exists, etc.) are tallied and don't abort the run; the rest still get stamped. Disabled when nothing matches.
- **Verify-Title-matches-File semantics.** The destination filename inside the new folder is always `sanitizeTitle(clip.title) + "." + sourceExtension`, so `Title.mov` from FCP becomes `<safeTitle>.mov` in production, `Title.mp4` becomes `<safeTitle>.mp4`. The clip's `clipFilename` column is updated in the same save so the next audit pass finds the file by the canonical name. Existing `pushFromFCP` still hardcodes `.mp4` and **moves** — kept untouched so the existing pill's behaviour doesn't change.

## 2026-05-06 — Editing workflow + notes timeline (`[New clip …]` / `[Editing …]` / `[Posted …]`)

- **`EditingWorkflowView`** — new sheet that runs after the new-clip workflow (or on demand from the Clips toolbar's **Editing Workflow** button). Shows a read-only file-audit summary at the top — counts pill (✅ OK / ⚠️ warning / ❌ missing), per-check rows (FCP folder, Production folder, Main MP4, Reduced MP4, Thumbnail frames, FCP bundle, Description, Transcript, Hashes), each with status icon, label, detail, and size. **Re-run** re-audits in place; **Open full audit…** hands off to the existing `FileAuditSheet` (with all the inline action pills for rename / push / hash / capture / refine) and re-audits when it dismisses.
- **Editing notes textarea** below the audit. On save, the input is appended to `clip.notes` as `[Editing YYYY-MM-DD] <text>`, mirroring the convention already used by the posting workflow (`[Posted <site> YYYY-MM-DD] <text>`) and the renamed-title marker (`[Renamed YYYY-MM-DD: "old" → "new"]`). Disclosure group below the editor previews the existing `clip.notes` so the user can see exactly which timeline they're appending to. Empty save acts as Close (no marker, no extra history row).
- **Notes field added to the new-clip workflow.** Same convention — saved as `[New clip YYYY-MM-DD] <text>`. Lives in the Metadata section under Go-Live Date. Empty draft is a no-op; a non-empty draft appends once per save and clears so a follow-up Save (Update) doesn't duplicate.
- **Sheet chain.** New `Save & Continue to Editing →` button in the new-clip workflow's action bar runs the same save+segment-capture path as Save & Close, then hands off to `EditingWorkflowView` for the same clip. SwiftUI's serialise-sheets quirk is handled with a 0.25s defer in `ClipListView.onChange(of: showingNewSheet)` so the second sheet opens cleanly after the first one dismisses.
- **Notes timeline now reads as one chronology** in the clip editor's Notes textarea: `[New clip 2026-05-06] kicked off…` → `[Editing 2026-05-06] checked thumbnails, looks good` → `[Posted c4s 2026-05-08] uploaded with 9 categories`. All three markers route through `clip.notes` (posting via `PostingClipWindow.postWithNotes` at `PostingClipWindow.swift:462`, editing via `EditingWorkflowView.appendNotesAndClose`, new-clip via `ClipWorkflowView.performSave`), so the Notes section in the editor stays the single source of truth without a separate "audit log" UI.

## 2026-05-06 — New Clip workflow: required fields + persisted file segments

- **Required-fields gate.** The new-clip workflow now refuses to save unless **Persona**, **Title**, *and* **Content date** are all set. Save & Close, Copy Status to Clipboard, and the Capture file metadata button all stay disabled until the form is complete; an inline orange "Required: Persona, Title, Content date" hint appears under the Identity section listing exactly what's missing, mirrored in the action bar's status line. Replaces the previous behaviour where a clip could be created with just a persona (title blank, content date "use today").
- **`clip_segments` table (v12 migration).** New per-segment metadata table — one row per `.mov` in the clip's source folder, keyed by `clip_id` + 1-based `position`. Columns: `filename`, microsecond-precision `creation_date`, `size_bytes`, `md5`, `sha1`, `sha256`, `hashed_at`, `created_at`, `updated_at`. FK references `clips(id)` with `ON DELETE CASCADE` so deleting a clip drops its segments automatically (also wired into `wipeAllClipData`). `UNIQUE(clip_id, position)` keeps the table consistent across re-captures.
- **Auto-hash on save.** Save & Close (and Copy Status to Clipboard) now run hashing for every `.mov` in the picked folder after the clip is saved, in a single streaming pass via `HashService` — MD5, SHA-1, SHA-256, plus byte size. Inline progress in the action bar reads `Hashing N of M — <filename>` while it runs; cancel/save buttons are disabled during. A per-file failure (unreadable file, permission error) is captured as a metadata-only segment row (filename + ctime preserved, hashes empty) and surfaced in the workflow's failure list — the rest of the files still hash.
- **Capture file metadata** button in the folder strip — runs the same capture pass on demand without closing the sheet (handy when you want to keep iterating on metadata while the hashes settle).
- **File segments section in the clip editor.** New `File segments` section under each clip's main editor: read-only Table with columns # / Filename / Created / Size / MD5 / SHA-1 / SHA-256. Hashes render as `xxxxxxxxxx…` truncations with click-to-copy and the full digest in the tooltip. **Refresh** re-pulls from DB; **Recapture** re-hashes the FCP folder and replaces the stored rows (also shows `Hashing N of M …` progress inline). When a clip has no segments yet but has an FCP folder set, a one-shot **Capture from FCP folder** prompt appears in the empty state.
- **`ClipSegmentService`** — orchestrates folder enumeration via `VideoFolderService` + per-file `HashService` streaming + single-transaction `DatabaseService.replaceSegments`. Per-file `progress(current, total, filename)` callback drives both the workflow sheet's action-bar progress and the editor's recapture spinner.

## 2026-05-06 — New Clip workflow (replaces small "New Clip" sheet)

- **`ClipWorkflowView`** replaces the 460×380 `NewClipView` sheet. Single bigger sheet (760×720 minimum) that captures everything you typically know at clip-creation time in one pass: identity (persona, title, content date), optional metadata (description, ordered categories, go-live date), and the source folder that becomes `fcp_project_folder`. ⌘N keyboard shortcut + the **+ New Clip** toolbar button still open it.
- **Source-folder browser inside the sheet.** Pick a folder via NSOpenPanel; the sheet enumerates every `.mov` directly inside, sorted ascending by macOS filesystem creation time. Each row shows its expected position (1, 2, 3…), current filename, **microsecond-precision** creation timestamp formatted as `yyyy-MM-dd HH:mm:ss.SSSSSS +0000` (the same `kMDItemFSCreationDate` the user's shell pipeline reads, with the sub-second precision shell `mdls` doesn't surface), and an OK / Out-of-order status. Files whose current name doesn't match `<pos>.mov` are flagged orange with an inline `→ N.mov` target hint.
- **Fix order (rename to N.mov)** — one-click rename pass that renumbers every `.mov` in the folder so its name matches its 1-based chronological position. Two-phase implementation in `VideoFolderService.fixOrder`: pass 1 moves every file to a unique `__mc_tmp_<uuid>_<n>.mov` staging name; pass 2 renames temp → final. Collision-free even when files are merely permuted (e.g. swapping 1.mov ↔ 2.mov). Pre-flight check: if a non-`.mov` file in the folder happens to occupy a target name, the operation aborts before touching anything and surfaces a clear conflict error.
- **Copy Status to Clipboard** button in the workflow's action bar. Saves first if needed (so the clipboard payload always has a real clip ID), then drops the status block in the user's preferred format:
  ```
  <id> - <title> [<persona>]
  Description: <desc or "Blank">
  Categories: <list or "None Defined">
  Go-live date: Not set
  ```
  The `Go-live date:` line appears **only** when the date hasn't been set, matching the spec. Button flashes **Copied** for ~1.6 s as visual confirmation. Pasteboard payload via `NSPasteboard.general`.
- **`VideoFolderService`** — new service centralising the folder enumeration (`Item` rows with `creationDate`, `creationDateString`, `expectedPosition`, `expectedName`, `isOutOfOrder`), the precision date formatter (microsecond fractional + zone offset), and the safe two-phase reorder rename. Pure filesystem ops — no DB writes.
- **No schema change.** The workflow writes to existing columns: `clips.description_raw`, `clips.go_live_date`, `clips.fcp_project_folder`, plus `clip_categories` rows with their `position`. Status auto-recompute kicks in via `updateClip`, so a brand-new clip with FCP folder set lands in `editing` (one of three editing fields filled), exactly as it would if you'd typed the path into the editor manually.

## 2026-05-06 — Category cleanup

- **Archive unused (N)…** button on **Settings → Categories** with a count badge. One click + confirmation flips `archived = 1` on every category not currently referenced by any `clip_categories` row. Reversible — flip the row's Archived toggle in the same table to bring it back. Single-transaction `UPDATE`. The button greys out + drops the count once everything's clean.
- **`ensureCategory` un-archives on re-use.** If an archived category is re-attached to a clip later (via inline picker, import, or the historical-categories backfill), it automatically un-archives back into the picker. So the cleanup is fully reversible without manual intervention even when the import path runs.

## 2026-05-06 — Information Needed report

- New **Information Needed** report under Reports. Lists every active clip in `new` / `editing` status that's missing at least one of: raw description, categories, go-live date. Each card shows `ID — Title [Persona]`, the description (or `Blank` if empty), the categories (or `None Defined` if empty), plus the go-live row only when it's the missing field. Orange `desc` / `cats` / `go-live` badges in the card header summarize what's open.
- **Copy for creator** button copies a clipboard payload prefixed with `Please confirm/provide the following:` in the exact per-clip layout the user wanted, ready to paste into Messages / email.

## 2026-05-06 — Historical-clip category backfill from C4S snapshot

- **Backfill historical categories…** button on the C4S Historical view's toolbar. Opens a planner sheet that finds production clips with no categories assigned and matches each against `c4s_historical` by title (using `FuzzyMatch.normalize` so apostrophes / commas / punctuation drift count as the same title), then proposes the C4S row's `categories + keywords` as the new category list — in that order, deduped, uppercased, position-preserved.
- **Four buckets in the sheet** with per-row checkboxes: *Exact*, *Strong fuzzy* (≥ 0.92), *Maybe* (0.75–0.92), *Cannot match*. Defaults: exact + strong checked; maybe unchecked; cannot-match shown as a copyable list. Each match row shows the persona pill, source title → C4S title (with an orange `(store: X)` warning if the candidate sits in the other store), and a chip preview of every category that would be applied. Score pill on every fuzzy row.
- **Match-key rationale.** `external_clip_id` in the `clips` table turned out to be the legacy import sequence number, not the C4S clip ID, so it can't be used to join. Title is the only viable key.
- **Single-transaction commit.** `DatabaseService.applyHistoricalCategoryBackfill(_:)` ensures every category exists (uppercased via `ensureCategoryInTransaction` so we never deadlock by re-entering `dbPool.write`) and inserts each `clip_categories` row with `position = i`. Clips that gained categories between plan-time and commit-time are silently skipped — no overwrites, ever.
- **Filter scope** for "historical": `status = 'production' AND zero clip_categories rows` (operational definition, since there's no `is_historical` flag — `Mark as historical` just calls `markAllScopedSitesPosted`).

## 2026-05-05 — Clips4Sale historical snapshot table, dashboard exclusion fix

- **C4S Historical** — new sidebar section + `c4s_historical` table holding the most recent on-demand Clips4Sale storefront export per store. Columns mirror the C4S export 1:1 (status, clip ID, tracking tag, title, description, categories, keywords, three filenames, performers, price/sales/income); plus a `store` key (CoC | PoA) and `imported_at` timestamp. Each import wholly replaces every row for the chosen store inside one transaction, so the table is always a current snapshot, never a journal.
- **C4S Historical importer** — modal sheet with file picker, store toggle (auto-pre-selected from `COC_…` / `POA_…` filename prefixes), and a 3-row preview before commit. Accepts the .xlsx export verbatim and the "csv" export which C4S writes as **pipe-delimited** with `"`-quoted fields and embedded newlines inside descriptions; the parser is a state machine over Unicode scalars that handles both. Shows extension and existing row count up-front; falls back to ZIP-magic content sniffing when the file has no recognizable extension.
- **C4S Historical view** — `HSplitView` table (Store, Title, Status, C4S ID, Price, Sales, Income, Categories) with sortable columns and free-text search across title / description / keywords / categories / clip-id / performers; right-side detail panel with persona-coloured store pill, full description, category and keyword chips, file row, and tracking tag — all click-to-copy via `.textSelection(.enabled)`. Top toolbar segmented control filters All / CoC / PoA with live counts.
- **Schema migration v11** — adds `c4s_historical` and its `store` / `clip_id` indexes. Append-only; fresh installs and upgrades both pick it up.
- **Dashboard fix** — `Clip × site posting status` matrix on the Dashboard now filters out `posting_excluded` clips. They auto-promote to `production` (since there's nothing to post) and don't belong on the per-site grid.

## 2026-05-05 — Status auto-recompute fix, click-to-copy IDs, file-audit hardening

- **Status-recompute bug fix.** `PostingService.markPosted` was writing posting rows directly via `row.save(db)`, bypassing the clip-status recompute that lives inside `DatabaseService.upsertPosting`. Result: clips with postings created via the batch flow stayed in `to_post` even after the first scoped site was marked posted. `markPosted` now routes through `upsertPosting`, which triggers status recompute + history-row writes. Backfilled via `v9_recompute_clip_status` migration.
- **Excluded clips auto-promote to production.** `computeStatus` now returns `production` when `postingExcluded == true` — there's nothing to post, so the clip is "done" pipeline-wise and shouldn't sit in `to_post`. Same auto-promotion when the clip's persona has no scoped sites (e.g. `Shr` / `N/A` without site assignments) and editing is complete. Backfilled via `v10_status_for_excluded_and_no_scope`.
- **Click-to-copy clip IDs.** New reusable `ClipIDLabel` view replaces every visible `Text(clip.id)` in the editor sticky header, Clips list, Editing Queue, Posting Queue, Posting Batch queue rows, posting window header, and bulk audit clip banner. Tap any ID to copy; brief "Copied" pill flashes. Two callsites kept as plain Text because they live inside parent `Button` rows (audit-report card, workflow summary list).
- **Posting workflow refinements**:
  - **Skip for now** button — advances without marking posted; the clip stays in the queue. `advanceAfter` now correctly walks past the current clip (was picking `pendingClips.first`, which was the same clip when nothing had been removed).
  - Counter math fix: position is now `(batchStartCount − pending) + currentClipIndexInPending + 1`, so both Mark posted and Skip advance the counter by exactly one.
  - **Show queue list** button + `PostingQueueListSheet` — modal sheet listing every pending clip in order with click-to-copy ID / title / production filename, plus bulk-copy buttons (Titles / Filenames / Markdown table) for sites that allow uploading multiple clips at once.
  - **Editable price** field in the schedule strip — saves on submit, on Mark posted, on disappear. Mark posted is gated on the price being set (zero allowed for free clips); inline orange hint appears when empty.
  - **Title copy button** next to the title in both the posting window header and the clip editor's sticky header.
  - **Posting notes mirror to clip notes** — when posting notes are saved, they're appended to `clip.notes` as `[Posted <siteCode> YYYY-MM-DD] <text>` so the editor's main Notes field surfaces every posting context together.
  - Per-clip identity (`.id(clip.id)`) on `PostingClipWindow` so `@State` (priceDraft, notes, picked categories) doesn't carry across clips on Posted-and-next.
  - Header font bumps — counter `.caption` → `.callout`, current-clip title in breadcrumb `.headline` → `.title3.weight(.semibold)`.
- **File-audit hardening**:
  - **Sandbox dropped** — `com.apple.security.app-sandbox` is gone, leaving just `com.apple.security.network.client` (Ollama). The audit calls `FileManager.fileExists(atPath:)` with string paths, which the sandbox refused for user-selected URLs (the bookmark-grant only carries via the URL, not the string), so audit rows stayed red even after the user picked the right folder.
  - **`isDirectory` is now multi-pass** — exact literal → URL standardisation → Unicode NFC normalisation → whitespace-trimmed fallback. Catches volume-name NFC/NFD differences (common on external drives) and round-trip whitespace mismatches.
  - **`expand()` preserves trailing/leading spaces** in filenames — macOS allows them and we've seen real folder names like `...MILF ` (trailing space) that would otherwise mismatch after trimming. Only `\n`, `\r`, `\t`, NUL are stripped now.
  - **Pickers save `URL.standardizedFileURL.path`** — so subsequent existence checks match the volume's canonical form.
- **Description-refine action on the Description (raw only) audit row.** New purple inline pill with **Refine** button — streams Ollama with the configured model + prompt, runs `cleanRefineOutput` for quote-stripping + paragraph-format normalisation, persists to `clip.descriptionRefined`, appends `[Refined YYYY-MM-DD]` to notes, re-audits. Same wiring in both the per-clip sheet and the workflow.

## 2026-05-04 — Posting workflow refinements, exclusion flag, uppercase categories

- **Skip in posting workflow** — new **Skip for now** button in `PostingClipWindow` advances to the next clip without marking the current one posted. The clip stays in the queue so the user can come back to it later.
- **Price required to post** — Mark posted / Posted & next are disabled until the price is set (zero is allowed for free clips). Inline orange hint appears in the action bar when the price is empty so the gate is obvious.
- **Editable price in the posting window** — Price moved into the schedule strip as a TextField with `$` prefix; saves on submit, on Mark posted / Posted & next, and on view dismissal. Persists via `appState.updateClip` so the rest of the app sees the new price immediately.
- **Posting Queue: Price column** — added between Length and ID, sortable (nils last via a dedicated `priceCentsKeyPosting` key extension).
- **Per-clip "do not post" flag** — new clip columns (`posting_excluded`, `exclusion_reason`, `exclusion_notes`) plus a configurable `exclusion_reasons` table seeded with **Custom**, **Not Posted - Sent Individually**, **Other - Please specify**. New **Posting status** section in the editor: toggle, reason dropdown (filtered to non-archived reasons), free-text notes. Excluded clips are filtered out of `PostingService.clipsNotPosted` (per-site batches) and the Posting Queue.
- **Posting settings tab** — new **Settings → Posting** tab for managing the exclusion-reason dropdown (label CRUD, archive toggle, sort order).
- **Categories are uppercase** — v8 migration uppercases every existing category name and dedupes case-collisions onto the lowest-id row, re-pointing `clip_categories` links and deleting the duplicates. Going forward, `DatabaseService.ensureCategory(named:)` and the categories settings tab uppercase on input — every code path that creates a category lands on the same canonical row.
- **DB migration**:
  - `v8_categories_uppercase_and_exclusions` — three things in one migration: uppercase + dedupe categories, add the exclusion columns to `clips`, create + seed `exclusion_reasons`.
- **PostingClipWindow header redesign** — persona-coloured banner with big persona pill (gradient, drop shadow, code + display name), title, clip ID, full Production folder path with **Reveal** + **Open clip in editor** buttons, thumbnail filename row, and MD5 / SHA-1 / SHA-256 rows (each with copy-to-clipboard).
- **PostingClipWindow body slim-down** — Description (refined) is read-only; Categorization is editable via `CategoryChipPicker` and persists every change immediately; schedule strip shows Length / Price (editable) / Content date / Go-Live date. Removed Keywords, Performers, Clip filename, Preview filename, and the raw-description block.

## 2026-05-04 — File-verification flow, queues, transcripts, hashes

- **Verify files** — per-clip file audit (button in the editor's "Editing (post-production)" section) opens a sheet checking nine things: FCP project folder, Production folder, Main MP4 (`<Title>.mp4`), Reduced MP4 (`<Title>_reduced.mp4`, only required when main is over threshold), Thumbnail frames (`<Title>_frame_NN.png`), FCP bundle (`<Title>.fcpbundle`), Description, Video transcription, File hashes. Each row reports OK / warn / missing / N/A with file size, detail line, and a Reveal button.
- **All-checks-passed banner** — when nothing's broken, the sheet leads with a tall green "All checks passed" card so the user can see at a glance that the clip is done.
- **Self-correcting rename suggestions** — when an expected file is missing, the audit scans the parent folder for files of the right type, picks the closest match by `FuzzyMatch.similarity` (Levenshtein), and offers a single-click rename. **Fix all** in the footer applies every rename in one pass.
- **Inline action pills on audit rows.** Each row that can be fixed in place exposes the relevant action: **Choose…** for the FCP folder when the path isn't set or reachable, **Reduce now** on a missing reduced MP4, **Capture / Re-capture** on the Thumbnail frames row (above the picker), **Generate / Re-generate** on the Video transcription row, **Compute / Re-compute** on the File hashes row.
- **Bulk file-verification workflow** — toolbar button on both Editing Queue and Posting Queue walks every visible clip through the audit sheet one at a time. Header has a segmented `All clips · Only with issues` filter (preflight audits every clip on open), a progress bar, Previous / Skip / Next / Finish buttons, and a summary at the end with click-through to clips still needing work. Pickers and audit caches are keyed per clip ID so selections survive Previous / Next / re-audit.
- **`ClipReduceService`** — `AVAssetExportSession` (HEVC at source resolution → H.264 1080p → 720p → 540p) iteratively re-encodes the main MP4 down to a `<Title>_reduced.mp4` companion until under the configured threshold. No ffmpeg dependency.
- **`FrameCaptureService`** — `AVAssetImageGenerator` pulls N stills from the production MP4: frame 1 from the 1–9 s window (catches the title card), frames 2–N evenly distributed across the rest of the clip in random samples. Output: `<Title>_frame_01.png` … `<Title>_frame_NN.png`.
- **Visual thumbnail picker** — captured frames render as a wrapping `LazyVGrid` of preview tiles. Click any tile to select it; the chosen frame is promoted to `<Title>.png` in Production (overwriting any prior copy) and any `<Title>.png` mirror in the FCP folder is cleaned up. The picked frame's filename is stored on `clip.thumbnailFilename` so it survives across sessions.
- **`TranscriptionService`** — shells out to the sibling `~/Documents/GitHub/PhantomLives/transcribe/transcribe.py` (MLX Whisper) with `-i ... -o - -f txt -m turbo -q`, captures stdout, normalises CR/LF/tabs into a single continuous paragraph, and stores the result on `clip.transcript`. Disabled with a hint when `transcribe.py` isn't installed.
- **`HashService`** — streams the main and reduced MP4 through MD5 / SHA-1 / SHA-256 in a single 4 MB-chunked pass via CryptoKit. Persists hex digests + sizes + ISO timestamp onto the clip; **Recompute hashes** button in the editor's new **Integrity** section (with click-to-copy on every digest) and an audit-row equivalent.
- **Posting Queue** — new sidebar section parallel to the Editing Queue, defaulting to `to_post + posting` status. Posting-progress column shows per-site pills (`✓ c4s · ○ mv · ✓ nf`) plus an `X/N` count. Sidebar gets count badges for both Editing Queue and Posting Queue.
- **Path defaults** — Settings → File Locations now lets you configure Production base + pattern (default `~/Dropbox/Sallie Content/Clips`, `{date} {title}`) and FCP base + pattern (default `/Volumes/PRO-G40/`, `Content Working/{date} Session/{title}`). `wand.and.rays` button on each folder row in the editor sets the path to the configured default. One-time backfill (`pathBackfillV1Done`) runs at first launch, populating the columns for every Production-status clip whose paths are empty; "Run backfill now" button forces a re-run.
- **Per-report exports + Reveal.** Full Clip / Weekly / Posting Status / Category Usage / Clip Audit each get their own `ReportExportMenu` (Markdown / PDF / CSV) that auto-reveals in Finder after save and surfaces a persistent **Reveal** button next to the menu. Distinct from the toolbar Export which still dumps the full clip dataset.
- **Weekly report** — three-week go-live window (Last / This / Next), plus a "Not in production" list of active clips that haven't reached the Production stage. Anchor date shifts with chevrons. Exportable to MD / PDF / CSV.
- **DB migrations**:
  - `v5_clip_categories_order` — `clip_categories.position` for ordered categories per clip.
  - `v6_clip_transcript` — `clips.transcript` text column.
  - `v7_clip_hashes` — `clips.{mp4,reduced}_{md5,sha1,sha256,size_bytes}` + `hashes_computed_at`.
- **Settings additions**: `largeFileThresholdMB` (default 950), `numFramesToCapture` (default 15), `defaultProductionBase`, `defaultProductionPattern`, `defaultFCPBase`, `defaultFCPPattern`, `pathBackfillV1Done`.

## 2026-05-04 — Audit, delete, simpler UI, date pickers

- **Clip audit** — new `ClipAuditService` with seven checks: clip ID exists, persona is set + resolves, title exists and isn't a placeholder, refined description set, ≥ 1 category, content date set, go-live date set.
  - **Per-clip banner** at the top of `ClipEditView`. Orange triangle + each open issue listed when failing; green checkmark "all checks passed" when clean. Recomputes live from the in-edit `draft` + selected categories — no save / refresh cycle needed.
  - **Bulk audit report** in `Reports → Clip Audit`. Lists every failing clip as a clickable card; click navigates to the clip editor with focus pre-applied. "Hide clean" toggle, running tally, Re-run button.
- **Delete records** — three discoverable paths:
  - Toolbar **trash button** in the Clips list (⌘⌫ keyboard shortcut, disabled when nothing's selected).
  - Right-click context menu (was already there).
  - **Delete clip…** button in the clip editor footer.
  - All three open the same confirmation alert quoting the clip's title before deleting. `ON DELETE CASCADE` cleans up postings, category links, and history rows.
- **Date pickers** for `contentDate` and `goLiveDate`. macOS native compact `DatePicker` when set; "Set date" button + "Not set" label when nil; `×` icon to clear back to nil. Also wired into the New Clip sheet (toggle + picker, default off = "Use today"). Storage stays as ISO `YYYY-MM-DD` strings.
- **Inline category creation** in `CategoryChipPicker`. Type a new category name and hit Return — the row is inserted via `DatabaseService.ensureCategory(named:)` and immediately selected on the clip. Existing-name match is case-insensitive (won't create duplicates).
- **Editing Queue: persona filter + sortable columns**. Filter bar gets a Persona dropdown next to the status chips. Every column is now a sortable `KeyPathComparator` — `Recorded` and `Go-Live` use a custom `OptionalStringComparator` that sinks nils to the end regardless of direction. New `Go-Live` column added.
- **Simpler clip editor**. Removed Identity → "Clip ID" duplicate label (it's in the sticky header), External Clip ID, Tracking Tag; removed Categorization → Keywords / Performers; removed the Files section entirely. Eight fields gone. Underlying columns preserved — imports still populate them, exports still emit them, search still indexes them.
- **Strict refine improvements**:
  - **Strip wrapping quotes** from Ollama output (straight + smart `"…"` and `'…'`). Up to 3 nested wraps peeled.
  - **Paragraph format normalisation**: trims, collapses 2+ spaces to one, collapses 3+ newlines to a single paragraph break, **joins single in-paragraph newlines with spaces** so sentence-per-line input becomes flowing prose. Idempotent.
  - Both run as a single `OllamaService.cleanRefineOutput(...)` post-processing pass after streaming completes.

## 2026-05-03 — Polish pass

- **Mobile-friendly HTML export.** Cards now pre-render as static HTML (no JSON.parse / no `atob`) so the file works in iOS Files preview, iMessage Quick Look, and any environment that limits JavaScript. JS layer is a progressive enhancement that adds live filter on top.
- **Auto-save in clip editor.** Pending edits flush on `.onDisappear` (selection change, sidebar nav, window close). Dirty/clean state shown in the footer with a coloured icon. The explicit Save button (⌘S) and Discard buttons disable when there are no unsaved changes.
- **Strict word-for-word refine prompt.** Default Ollama prompt rewritten with five worked examples and explicit "do not paraphrase / swap synonyms / restructure" rules. Temperature dropped 0.4 → 0.0 (greedy decoding) and `top_p` raised to 1.0 for the proofread workload. Auto-migration: any user still on a legacy default gets the new prompt on next launch; customised prompts are left alone. **Reset to default** button next to the prompt editor.
- **Persona pills got cutesy.** Heart icon, gradient fill, soft shadow. Extracted to a shared `PersonaPill` view. Used in Clips list, Editing Queue, Calendar dots, and the clip-editor sticky header.
- **Sticky title in clip editor.** Title is now `.title2.weight(.semibold)` (~22 pt) and lives outside the ScrollView so it never scrolls away. Truncates with "…" + tooltip on hover; never shrinks.
- **Title columns in Clips list and Editing Queue.** Title is now column 1 with `.title3.weight(.semibold)` (20 pt) and `min: 240–260, ideal: 460–520`. Other columns trimmed to free space.
- **Light / Dark / Auto** appearance picker in Settings → General. Saved as `colorScheme` in `settings.json`; applied via `.preferredColorScheme(...)`.
- **ColorPicker for accent + persona colours.** Replaces the old hex text fields. Hex string is still stored.
- **Default persona colours updated.** CoC = `#FFB6C1` (light pink), PoA = `#B22222` (sunset dark red). v4 migration only overwrites if the previous defaults are still in place.
- **Calendar auto-populates from clip go-live dates.** No manual link step needed. Display-only synthesised events (negative IDs) are merged into `eventsByDate` if no `calendar_events` row links to the clip yet.
- **Dashboard cards are clickable.** Each top-stat card (Clips / Fully posted / Partial / Not posted / No site scope) navigates to the Clips section with a matching posting-completeness filter pre-applied. New "Posting" filter dropdown in the Clips list.
- **Mark as historical** import option + per-clip context-menu action. Bulk-marks every persona-scope site as posted, posted_date defaulting to `goLiveDate ?? contentDate ?? today`. Status auto-recomputes to `production`.
- **Wipe / Reset clip data** in Settings → Backup. Runs a safety backup first, then deletes clips / postings / categories / history / calendar events while preserving personas, sites, categories, and rules.
- **Backup verify (Test) + restore.** Each backup row gets Test / Restore / Reveal buttons. Test extracts to a temp dir, opens the SQLite, returns a sheet with row counts and migrations applied. Restore confirms with an alert, runs a safety backup of current state, replaces support-dir contents, reopens the GRDB pool, and reloads `AppState`.
- **History capture.** Every field-level change to a clip — including title rename, status auto-transition, posting toggle, category set update — appends to `clip_history`. Visible in the clip editor as a collapsible "Change history" section.
- **Posting batch refactor — drill-down wizard.** Sites grid → site queue → focused per-clip posting window. Per-(site, persona) targets (so Clips4Sale [CoC] and Clips4Sale [PoA] are separate batches with their own login flows). Each clip opens an inline window with per-field copy buttons, posting-notes textarea, "Mark posted" + "Posted & next" (⌘↩).
- **Editing pipeline.** New status enum: `new` → `editing` → `to_post` → `posting` → `production`, all auto-derived from data + posting state. New columns `fcp_project_folder`, `production_folder`. New "Editing Queue" sidebar section. Per-stage hints on the clip editor explain what's needed to advance.
- **Clip ID format** changed to `YYYY-MM-DD-#####` (was `YYYYMMDD####`). 5-digit suffix gives 99 999 clips/day before expansion.
- **App icon redrawn** as a hand-painted clapperboard with violet→indigo gradient and diagonal stripes on the open snap. CFBundleIconFile now correctly set in Info.plist.
- **Smarter import.**
  - Single-sheet workbooks auto-route the largest sheet to Clips (no more "all sheets routed to Skip" dead-ends).
  - Header detection picks the row with the most populated text-ish cells in the first 15 rows (handles xlsx files with merged-title preambles).
  - "Mark as historical" toggle on the Preview step.
  - New `descriptionRefined` mapping target (was missing). New aliases for `Title (NEW)` / `Description Transcribe` / `Description Corrected` / `Session`.
  - Categories cleanup: strips voice-transcription preambles ("So, the categories are…", "cat shoes , flats", "categories chastity , …").
  - Persona normalization: `COC`/`coc`/`CoC` → `CoC`, etc.
  - Hero "Continue with \<sheet\> → Mapping" card on the Sheets step makes the recommended path obvious.

## 2026-05-03 — Phase 13 — Backup + polish

- `BackupService.runIfEnabled` triggers at app launch; throttle stored in `settings.lastBackupAt`. Auto-backup zip lands in `~/Downloads/MasterClipper backup/` with rolling retention by day count (0 = keep forever).
- `BackupSettingsTab` — toggle, dir picker, retention stepper, Run Now, recent backups list.
- `wipeAllClipData()` deletes clip / posting / history / calendar / price rows while keeping personas / sites / categories / rules. Always runs a backup first.

## 2026-05-03 — Phases 10–11 — Exports + Reports

- `ExportService` — CSV (RFC 4180), Markdown (full + per-clip), XLSX & DOCX via manual OOXML to a temp dir + `/usr/bin/zip`, PDF via `CGContext(consumer:)` + `NSGraphicsContext`.
- `HtmlExportService` — single self-contained `.html`. Now mobile-first, static-first (see top of changelog).
- `ReportService` — `postingStatus`, `categoryUsage`, `calendarRollup` aggregations.
- `ReportsRootView` — sidebar with four reports + ⌘-menu Export submenu.
- `ClipExportSheet` — per-clip toolbar action: plain-text / Markdown / PDF.
- `ImportExportTab` — default export directory + duplicate strategy + include-notes-in-search.

## 2026-05-03 — Phase 9 — Calendar

- `CalendarService.generateYear(_:rules:)` — walks Jan 1 → Dec 31, inserts blank `(date, persona)` rows for every weekday matching enabled rules.
- `CalendarRulesTab` — per-persona × weekday checkbox grid + year stepper + Generate button.
- `CalendarRootView` — segmented Year / Quarter / Month / Week / Day picker. Click-through navigation, "Today" jump, mini-month grids in Year/Quarter, full grid in Month, vertical week stack, full event cards on Day.
- Events render as `Title[Persona]` with persona-color dots and category line.

## 2026-05-03 — Phase 8 — Ollama refine

- `OllamaService` — streamed `/api/chat`, decoupled refine method.
- `OllamaSetup` — detects ollama in PATH, auto-starts `ollama serve` when needed, polls `/api/tags`.
- `AppState.init()` runs setup + connection in the background and falls back to the first installed model if the configured one isn't available.
- `OllamaSettingsTab` — base URL, model picker (live from `/api/tags`), refine prompt template editor with `Reset to default`, Test refine pane with streamed output.
- `ClipEditView` Refine button — streamed tokens, error display, history stamp on first refine.

## 2026-05-03 — Phase 7 — Smart Import (MVP cutoff)

- `XLSXReader` — hand-rolled. `/usr/bin/unzip -p` + `XMLParser` for sharedStrings / workbook / rels / sheet XML. Resolves shared-string references, pads cells by A1 column ref.
- `FuzzyMatch` — Levenshtein + alias dictionary; threshold ≥ 0.78. Punctuation (incl. parens) stripped during normalize so `Title (NEW)` matches `title new`.
- `ImportService` — orchestrator: xlsx / csv / tsv / pasted text. `commitClips`, `commitCalendarEvents`. Dup detection on `external_clip_id` then `(title, content_date)`.
- Dates parse ISO, US, EU, month-name, Excel serials. Lengths parse `mm:ss`, `hh:mm:ss`, fractional days, `7m49s`.
- `ImportWizardView` — 5-step wizard with hero recommended-action card, mapping table, preview, commit + historical toggle.

## 2026-05-03 — Phase 6 — Posting workflow

- `PostingService.clipsNotPosted(toSiteId:personaScope:)`, `markPosted`.
- `PostingBatchView` initially built as a single split view; later refactored to drill-down (Sites → Queue → Posting window) per user feedback.
- `PostingClipWindow` (formerly sheet) — per-field copy buttons, posting-notes textarea, Mark posted + Posted & next (⌘↩).

## 2026-05-03 — Phases 4–5 — Clip CRUD + Settings

- `ClipListView` master/detail with sortable Table, AND-token search across title / description / keywords / id / external id / notes, filters for persona / status / archived / posting (added later).
- `ClipDetailView` + `ClipEditView` — full editable form, sticky header, status badge, posting grid, change-history disclosure, auto-save on disappear.
- `NewClipView` sheet, auto ID via `IDGeneratorService`.
- `Personas / Categories / Sites` settings tabs with full CRUD.
- `AppState` mutation methods, `SearchService` AND-token LIKE.

## 2026-05-03 — Phases 2–3 — Models, DB, Settings, App shell

- 11 GRDB tables on v1: `personas`, `sites`, `categories`, `clips`, `clip_categories`, `clip_postings`, `id_sequences`, `calendar_events`, `calendar_rules`, `prices`, plus `grdb_migrations`.
- Seed data: 4 personas, 5 sites with persona scopes, calendar rules CoC=Mon+Thu / PoA=Wed+Fri.
- Models, `SettingsStore`, `DatabaseService`, `IDGeneratorService`, `AppState`, app shell, theme system, app menu commands, `DurationFormatter`.

## 2026-05-03 — Phase 1 — Skeleton

- Initial scaffold. XcodeGen `project.yml`. `build-app.sh` (auto-version from git, ad-hoc + Developer ID signing, builds in `/tmp`). Empty-window app launches.

## Schema migrations (cumulative)

| Migration | Effect |
|---|---|
| `v1_initial` | All 11 tables created with current columns. Seeded personas / sites / calendar_rules. |
| `v2_clip_history` | Added `clip_history` table for per-field change tracking. |
| `v3_editing_pipeline` | Added `clips.fcp_project_folder` + `clips.production_folder`. Remapped legacy status strings to the new pipeline. Migrated old `status='archived'` → `archived = 1`, `status = 'new'`. |
| `v4_persona_color_refresh` | Updated default persona colours: CoC `#7A4FFF` → `#FFB6C1` (light pink), PoA `#E9508C` → `#B22222` (sunset dark red). Idempotent — leaves user-customised colours alone. |
