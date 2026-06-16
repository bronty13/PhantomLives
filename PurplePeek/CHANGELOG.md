# Changelog

All notable changes to PurplePeek are documented here.

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
