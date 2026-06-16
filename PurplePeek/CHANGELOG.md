# Changelog

All notable changes to PurplePeek are documented here.

## [1.0] — Metadata reaches imported videos (AppleScript)

- Title/caption/keywords now reach **imported videos** (and serve as a fallback for photos
  whose embedding didn't run). Root cause: exiftool embedding is photo-only, so metadata on
  videos never had a path into Photos — and most real imports are videos.
- New `PhotosAppleScriptService`: after import, sets the asset's `name` (title) +
  `description` (caption) via AppleScript, and `keywords` as a separate best-effort script
  (Photos' keyword-settability varies by macOS). In-process `NSAppleScript` so the Automation
  consent is attributed to PurplePeek. Photos still use exiftool embedding; AppleScript runs
  for videos and any photo where embedding was skipped.
- First import now also triggers a one-time "PurplePeek controls Photos" Automation prompt.
- (See also the title-save fix below — titles were additionally never persisted before.)

## [1.0] — Fix: title/caption sometimes not saving between items

- Title and caption now **write through on every edit** instead of committing on focus loss.
  The old approach relied on `onChange(of: focus)` firing when navigating — but when the
  focused `TextField` is torn down as you move to the next item, that didn't always fire, so
  the last edit was lost. Write-through persists each change immediately, before any
  navigation.
- A loaded-baseline guard means a programmatic load (showing the next item) never writes the
  value back to the wrong file, avoiding any cross-item corruption during the transition.
- `patchLocal` is now O(1) (id→index map) so per-keystroke persistence stays fast even on
  tens-of-thousands-of-item roots.

## [1.0] — Album picker enumerates Photos albums

- The album picker now lists your **Photos library albums** (read via PhotoKit
  `PHAssetCollection`, regular albums only — those the importer can actually add to) merged
  with albums already used in PurplePeek, de-duplicated; a photo glyph marks the ones from
  Photos. Loaded on demand when the picker opens (cached).
- `PhotoKitService.fetchAlbumNames()`, `AppState.loadPhotosAlbumsIfNeeded` +
  `photosAlbumNames` / `isLoadingPhotosAlbums`.
- Verified live: picker surfaced the library's "PurplePeek Test" and "Save" albums.

## [1.0] — Review decided items (decision filter)

- New `DecisionFilter` lens (All / Undecided / Decided / Kept / Skipped) so you can revisit
  choices you've already made — not just triage undecided ones.
- **Folder grid**: a "Show" menu in the header filters the grid by decision.
- **Preview mode**: the old "Show all" toggle is now a **Review** menu — step one-by-one
  through Decided / Kept / Skipped / All items and change any decision in place. Deciding an
  item advances correctly whether it stays in the filtered queue or drops out of it.
- The Preview top bar (with the Review menu) now stays visible even when the queue is empty,
  so when everything's decided you can still switch the filter to review your decisions
  (previously the menu was hidden behind the "All caught up" state).
- Grid and Preview keep independent filters (grid defaults All, Preview defaults Undecided).
  Test: +`testDecisionFilterMatches` (26 total).

## [1.0] — Performance on large libraries

- Derived collections (`visibleMediaFiles`, `previewQueue`, `folderTree`) are now **cached
  stored properties recomputed only when their inputs change**, instead of computed
  properties re-evaluated on every SwiftUI render. On a 65k-item root these were O(n) /
  O(n·depth) each and ran many times per second while scrolling/typing/navigating — the main
  source of large-library lag. `visibleMediaFiles` + `previewQueue` + toolbar
  enable-flags are built in one O(n) pass; the folder tree rebuilds only on scan/select/delete.
- Toolbar Clean Up enable-state uses cached `hasDeletableImported`/`hasDeletableSkipped`
  flags instead of filtering all rows per render.
- Scan persistence uses a **reusable prepared statement** for the upsert (no per-row SQL
  re-parse) — a 6,000-file scan persists in well under a second.
- Thumbnail cache raised 500 → 1000 so fast scrolling re-decodes less.

## [1.0] — Top-level exclude folder

- New General setting **Exclude (top level only)** (default `originals`): a folder with this
  name is skipped — along with its whole subtree — **only when it sits directly under the
  scanned folder**. Same-named folders nested deeper are still scanned (e.g. `/ALASKA/
  originals` is scanned; a root-level `/originals` is not). Empty ⇒ exclude nothing.
- Implemented in `MediaDiscoveryService.scan(root:excludeTopLevelName:)` via the directory
  enumerator's `skipDescendants()` gated on a parent-path-equals-root check (case-insensitive,
  tolerates a leading slash). Tests: +3 (top-level skip vs nested keep, case/slash, no-exclude).

## [1.0] — Import keywords from Photos

- Keyword Manager gains **Import from Photos** — pulls the Photos library's keyword
  vocabulary via `osxphotos keywords --json` (PhotoKit can't read keywords) and adds any new
  ones to the local store tagged `source = photos`; existing names are skipped
  (case-insensitive dedup). Button is disabled with guidance when osxphotos isn't installed.
- `PhotosKeywordImporter` service (locate + fetch/parse), `DatabaseService.importKeywords`,
  `AppState.importKeywordsFromPhotos` (+ `isImportingKeywords` progress). osxphotos path is
  discovered at launch.
- Verified live: imported Laura/Maddy/Rachel/Sallie/Save (source=photos) while the existing
  local "Summer" was de-duplicated.

## [1.0] — Hidden attribute

- New per-item **Hidden** decision (mirrors `PHAsset.isHidden`, one of the four properties
  PhotoKit *can* write — so it goes straight through PhotoKit, no exiftool staging).
- Added via a **new migration `v2_add_is_hidden`** (`ALTER TABLE media_files ADD COLUMN
  is_hidden`) — `v1_initial` is shipped and stays untouched (immutable-migration rule). An
  existing install runs only v2 and matches a fresh install's schema (verified live).
- UI: Hidden toggle in the detail panel, a Hidden button + **H** key in Preview mode (the
  text-field focus guard means H types normally while editing a title/caption), and an
  eye.slash grid badge.
- On import, a hidden item is hidden in Photos via `PHAssetChangeRequest.isHidden`
  (best-effort, alongside favorite). Test suite now 22 (added `testHiddenColumnRoundTrips`;
  the migration-ledger guard updated to `["v1_initial","v2_add_is_hidden"]`).

## [1.0] — Phase 7: Tests + polish (feature-complete)

- Test suite (21 XCTest cases): `DatabaseTests` (migration creates all tables, frozen
  migration ledger, `MediaFile` round-trip, keep tri-state, **re-scan upsert preserves
  decisions**, scan-root cascade delete), `MediaDiscoveryTests` (UTType classification,
  skips hidden, recurses, captures size/path), `BackupTests` (zip creation, retention trim
  of only our prefixed archives, newest-first listing, retention-0 keeps all),
  `ServicesTests` (audio export copy + de-dup + missing-source, delete permanent + missing,
  staging-metadata emptiness, `chunked`).
- `run-tests.sh` — points `DEVELOPER_DIR` at full Xcode so XCTest resolves even though the
  app build uses the active Command Line Tools toolchain. All 21 pass.
- The migration-ledger test doubles as the immutability guard (per CLAUDE.md): editing or
  removing `v1_initial` fails the suite; adding a migration updates the expected list.

PurplePeek is now feature-complete end to end: scan → browse/preview → decide → import to
Photos (with staged metadata) / keep-export audio → delete → manage in Settings.

## [1.0] — Phase 6: Delete functions + full Settings (in progress)

- `DeleteService` — delete files from disk to Trash or permanently (idempotent: an
  already-gone file counts as succeeded). `AppState.performDelete` marks only the rows that
  actually succeeded and clears the selection if it was deleted.
- Clean Up toolbar menu → **Delete Imported Files** / **Delete Skipped Files**, each opening
  a confirmation sheet (count + sample filenames + Trash-vs-permanent choice, with a warning
  for permanent).
- Settings window (⌘,) with three tabs:
  - **General** — default mode, appearance (Light/Dark/System), color theme (10), and the
    Kept Audio Export folder.
  - **Scan Roots** — per-root rename/forget (DB only, never touches disk), plus auto-forget
    after N days (default 180) + Clean Up Now. Forgetting cascades to the root's media +
    keyword/album junctions.
  - **Backup** — toggle, location, retention, Back Up Now, recent-backups list.
- `AppState` bridges nested `SettingsStore` changes via Combine so theme/appearance apply
  live; auto-cleanup runs on launch when enabled. DB gains `markDeleted`, `deleteScanRoot`,
  `updateScanRootLabel`, `deleteScanRootsOlderThan`.

## [1.0] — Phase 5: PhotoKit import + metadata staging + audio keep-export (in progress)

- `PhotoKitService` (actor) — imports photos/videos via `PHAssetCreationRequest.forAsset()`
  (copy, never move), adds each asset to its per-file albums (find-or-create, cached) and
  sets favorite via `PHAssetChangeRequest`. Adapted from PurpleDedup's proven importer.
- `MetadataStagingService` — embeds title/caption/keywords into a **staged copy** of a photo
  via `exiftool` (XMP:Title, IPTC:Caption-Abstract/XMP-dc:Description, IPTC:Keywords/
  XMP-dc:Subject) so Photos ingests them on import. Photos only; videos import as-is.
  Falls back gracefully when exiftool is absent.
- `AudioKeepService` — keeping an audio file copies it into the **Kept Audio Export** folder
  (default `~/Downloads/PurplePeek/Kept Audio/`, de-duped names); tracked by `exported_at`.
  Audio is never imported to Photos.
- `ImportWizardView` — 3-step sheet (filter All/Keep-only/Undecided → progress → report with
  succeeded/failed + Open Photos). Detail panel gains a context-aware action button
  (Import to Photos / Copy to Kept Audio, or a done state).
- `AppState`: `runImport`/`importSingle`/`exportAudio`, `importCandidates`, exiftool
  discovery at launch; DB `markImported`/`markExported`/`keywordNames(forFile:)`.
- Verified live in the real Photos library: an imported asset carried title, caption,
  keywords (via exiftool staging), favorite + album (via PhotoKit), with the stored
  `photos_asset_id` matching the library UUID. exiftool staging + audio keep-export also
  verified independently.

## [1.0] — Phase 4: Preview mode (in progress)

- `PreviewModeView` — full-screen one-by-one triage: large viewer + EXIF panel + decision
  bar. Walks the undecided queue by default; "Show all" revisits decided items.
- Keyboard-driven: **Y** keep, **N** skip, **F** favorite, **←/→** navigate, **Space**
  Quick Look — via an `NSEvent` local monitor guarded by `firstResponder is NSText` so the
  keys never fire while a title/caption field is being edited.
- `MediaViewerView` — fit-to-frame image (photos), inline `AVPlayerView` (video, rebuilt
  only on URL change), waveform backdrop + audio transport (audio).
- `EXIFService` + `EXIFPanelView` — ImageIO for photos (dimensions, camera/lens, aperture/
  shutter/ISO, GPS, color profile), AVFoundation for video/audio (duration, dimensions,
  creation date), grouped File / Camera / Exposure / Location.
- `QuickLookCoordinator` — drives the shared `QLPreviewPanel` for the current file.
- Decisions advance the queue (undecided items drop out; show-all advances explicitly);
  title/caption commit on focus-loss to the right row.

## [1.0] — Phase 3: Decision UI (in progress)

- `MediaDetailPanel` (320pt right column) — large preview + file facts and every decision
  control: **Keep/Skip** (toggle to undecided), **Favorite**, **Title**, **Caption**,
  **Keywords**, **Albums**. Each persists immediately.
- Title/caption commit on focus-loss against the file the text belongs to (`editingFileId`),
  and the single-column write + in-place array patch means a decision never refetches the
  list or steals the text cursor.
- `KeywordPickerView` (popover) — search, toggle keywords on the file, create-and-apply new
  ones. `AlbumPickerView` (popover) — add/remove albums, quick-add from existing names.
- `KeywordManagerSheet` (⌥ toolbar) — every keyword with its in-use count; create new,
  delete unused (blocked while applied, with the count shown).
- Grid/list cells are now `Button`s (keyboard-focusable + accessible) and load keyword/album
  metadata on selection via `AppState.selectFile`.
- `DatabaseService` gains targeted decision updates + keyword/album CRUD (junction replace,
  usage count, distinct album names).
- Mode picker now shows a Preview-mode placeholder (Phase 4). Single-item Import to Photos
  is deferred to Phase 5 (where `PhotoKitService` lands) rather than shipping a dead button.

## [1.0] — Phase 2: Media discovery + grid (in progress)

- `MediaDiscoveryService` — recursive scan classifying photos/videos/audio by **UTType
  conformance** (not extension); skips hidden files and package contents.
- `ThumbnailService` — an `actor` over `QLThumbnailGenerator` with a 500-entry `NSCache`;
  grid/list cells load via `.task(id:)` so off-screen loads cancel on scroll.
- Folder intake — drag a folder onto the window (dashed drop highlight) or **Open Folder…**
  (⌘O / `NSOpenPanel`). Discovery runs off the main actor; persistence happens on it in
  500-row batches with `Task.yield()` and a live progress overlay.
- Re-scan upsert (`INSERT … ON CONFLICT(file_path) DO UPDATE`) refreshes on-disk metadata
  but **preserves decisions** (`keep`, favorite, title, caption) and the original
  `scan_root` — honoring the nested-root rule.
- Sidebar — scanned roots + a recursive **folder-tree outline** (`OutlineGroup`) for the
  selected root, with per-folder recursive counts; selecting a folder narrows the grid.
- `FolderBrowseView` — grid (adaptive 160pt `LazyVGrid`) / list toggle, scope title +
  counts (total · undecided · keep), and an empty state. `MediaThumbnailCell` shows type,
  decision (✓/✗), and favorite badges.

## [1.0] — Phase 1: Foundation (in progress)

Initial scaffolding — a buildable, launchable shell.

- SwiftPM package (`swift-tools-version:5.10`, macOS 14+) with GRDB 6.x; Photos /
  AVFoundation / Quartz / ImageIO frameworks linked up front so a link failure surfaces on
  the first build.
- `build-app.sh` → `PurplePeek.app` (deterministic code-generated icon via
  `Scripts/generate-icon.swift`, Developer-ID-or-adhoc signed) auto-chaining into
  `install.sh` (force-kill → replace in `/Applications` → relaunch → prove freshness).
- `DatabaseService` with the immutable `v1_initial` migration: `scan_roots`, `media_files`,
  `keywords`, `file_keywords`, `file_albums` (+ indexes).
- `AppState` (`@MainActor` observable store) with the full set of published slices and the
  launch sequence (backup-on-launch → reload).
- `SettingsStore` (UserDefaults-backed `AppSettings`) with computed defaults under
  `~/Downloads/PurplePeek/`.
- `BackupService` — PhantomLives auto-backup-on-launch standard (zip Application Support →
  `~/Downloads/PurplePeek backup/`, 14-day retention, 5-min debounce, never throws).
- `WindowStateGuard` wired in `AppDelegate` (canonical split-view-state fix).
- Manual `HStack` sidebar + main layout (not `NavigationSplitView`), themed background, and
  the 10-theme `AppTheme` system (Purple Dusk default).

### Design notes
- **"Mirror Photos" principle:** the option set is a faithful subset of what macOS Photos
  can represent — title, caption, keywords, favorite, album. **No rating field** (Photos has
  no star rating).
- Title/caption/keywords reach Photos via XMP/IPTC embedded into a staged copy before import
  (exiftool); favorite + album via PhotoKit. Audio is keep-exported to a folder, never
  imported. (Both land in Phase 5.)
