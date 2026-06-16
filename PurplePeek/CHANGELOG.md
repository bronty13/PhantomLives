# Changelog

All notable changes to PurplePeek are documented here.

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
