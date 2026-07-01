# PurplePeek — Architecture Handoff

Canonical architecture snapshot. **Read this before non-trivial changes.** For *what changed
when*, see `CHANGELOG.md`; for *how to use it*, `USER_MANUAL.md`; for the *why* behind key
decisions, `DESIGN.md`.

## What it is

A macOS (14+) SwiftUI app that triages media before importing it to Photos. Scan a folder →
browse/preview → decide (keep/skip, favorite, hidden, title, caption, keywords, albums) →
import keepers to Photos / keep-export audio / delete the rest. Decisions persist in a local
SQLite database keyed by file path. Plain SwiftPM + GRDB; Developer-ID-or-adhoc signed; built
and installed via `./build-app.sh`.

## Build / run / test

```sh
./build-app.sh                 # build + install to /Applications + relaunch (the default "done")
./build-app.sh --no-install    # build only   (also: --no-open, BUILD_ONLY=1)
./run-tests.sh                 # XCTest, 37 tests — sets DEVELOPER_DIR to full Xcode
```

`run-tests.sh` points `DEVELOPER_DIR` at full Xcode so XCTest resolves under Command Line
Tools. The app's UI only activates from the installed `.app` bundle.

## The spine: decisions are data, keyed by file path

Everything is built around `media_files`, one row per discovered file, **UNIQUE on
`file_path`**. A re-scan upserts on that key, so it preserves the row `id` and all decisions
while refreshing on-disk metadata. This is what makes re-scanning safe and triage resumable.
Two lifecycle columns matter:

- `keep` — tri-state (`NULL`/`1`/`0` = undecided/keep/skip), bridged via `MediaFile.keepDecision`.
- `deleted_at` (user deleted in-app, terminal) vs `missing_at` (re-scan found it gone,
  reversible). Don't conflate them — see `DESIGN.md` → *Missing vs deleted*.
- `content_hash` — SHA-256 for exact-duplicate grouping; a decision on one copy propagates to
  all, and only one copy imports. See `DESIGN.md` → *Exact-duplicate detection*.

## State flow

```
View ──(intent)──▶ AppState (@MainActor, single source of truth)
                      │  persists via DatabaseService, then republishes a slice
                      ▼
                 DatabaseService (owns the GRDB DatabasePool)
                      ▲
discovery (off-main) ─┘  MediaDiscoveryService.scan → [ScannedFile] (pure, Sendable)
```

Views **never** touch `DatabaseService` directly. Every mutation is an `AppState` method that
writes then calls a `reloadX()` / `patchLocal` to refresh the published slice.

### Cached derived state (performance-critical)

`AppState` publishes raw `mediaFiles` **and** cached derivations: `visibleMediaFiles`,
`previewQueue`, `folderTree`, and toolbar enable-flags. `recomputeDerived()` rebuilds them in
one O(n) pass, called only when an input changes (file set / folder selection / decision /
the `showTaggedOnly` toggle). Single-item edits use `patchLocal` (O(1) via an `id → index`
map) to mutate in place. Don't reintroduce per-`body` filtering — it was the main large-library
lag source.

`fileKeywordNames` (`[fileId: [name]]`) is a published slice of the same kind: bulk-loaded once
via `DatabaseService.allFileKeywordNames()` (refreshed on any keyword change + on launch), it
backs the per-item tag labels (grid cells, list rows, the Preview tag strip) and the "Tagged
only" filter — so the grid never does a per-cell keyword query. The tagged gate is applied
inside `recomputeDerived()` to both `visibleMediaFiles` and `previewQueue`, alongside the
`DecisionFilter` lens.

## Remote mode (PeekServer client)

PurplePeek can run as a **client of PeekServer** (`PhantomLives/PeekServer/`, a LAN HTTP service
on the Mac that has the media attached): Settings → PeekServer connection flips the whole app to
remote — roots/items/decisions come from the server instead of local GRDB, so multiple Macs share
one authoritative review state.

- **`DataSource`** (`Services/DataSource.swift`) is the seam: `DatabaseService` (local) and
  `RemotePeekDataSource` → `PeekServerClient` (remote) both conform. Everything not on the
  protocol (scanning, sidebar sections, keyword vocabulary) stays local-only.
- **Media bytes** follow a tiered policy: originals read **directly over SMB** when the server's
  volume is mounted here at the same `/Volumes/<name>` path (fast LAN filesystem; video plays the
  original), else HTTP — `/thumb` (grid), `/display` (screen-size preview JPEG, PeekServer ≥0.7),
  `/preview` (720p video proxy), `/full` (originals/import).
- **`LocalReachability`** (`Services/RemoteMedia.swift`) owns the SMB-vs-HTTP answer: a
  per-volume cache probed only on a background queue (mount/unmount notifications + 30 s TTL).
  **Never call `FileManager.fileExists` on a `/Volumes/` path from the main thread** — a stale
  SMB mount blocks `stat` indefinitely and beachballs the app; ask `LocalReachability` instead.
- **`PeekTransport`** (same file) is the only sanctioned way to talk HTTP to the server: an
  `interactive` session (short timeouts, disk URLCache — the server's immutable/ETag headers do
  the caching) and a `bulk` session (whole-original pulls, separate pool). Don't reintroduce
  `URLSession.shared`.
- **Writes are optimistic** (`patchLocal` then POST): keep/favorite/hidden revert or resync on
  failure; title/caption are debounced + strictly ordered per field (`scheduleRemoteTextWrite`);
  keyword/album failures revert. Known gap: no offline write queue — a decision made during a
  connectivity blip surfaces an error and resyncs to server truth.
- `QuickLookCoordinator.prewarm` pre-downloads **photos only** (size-capped, cancelled on the
  next selection) so spacebar peeks are synchronous; videos stream on demand.

## Module map

```
Sources/PurplePeek/
  App/
    PurplePeekApp.swift      @main scene; AppDelegate; WindowStateGuard
    AppState.swift           ★ single source of truth — scan, decisions, import, delete,
                               cached-derived, FSEvents auto-watch wiring, Preview navigation
    Version.swift            reads git-derived CFBundleShortVersionString back from the bundle
  Models/
    MediaFile.swift          the row record (GRDB), tri-state keep, isMissing/isDeleted, content_hash
    ScanRoot.swift           one scanned folder (path PK, total, label, section_id, sort_order)
    SidebarSection.swift     user-defined sidebar group (id, name, sort_order)
    Keyword.swift            local keyword vocabulary record
    AppSettings.swift        Codable prefs (default mode, theme, exclude name, autoRescan,
                               backup, audio export path)
    Enums.swift              AppMode, AppAppearance, DecisionFilter (the decision lens), MediaType
    FolderTreeNode.swift     sidebar tree model + FolderTree.build (O(files × depth))
    EXIFData.swift           Preview-panel EXIF value object
  Services/
    DatabaseService.swift    ★ owns the DatabasePool; migrations v1→v3 (immutable!); CRUD;
                               upsertScannedFiles + markMissingFiles (the watermark sweep)
    MediaDiscoveryService.swift  recursive scan by UTType → [ScannedFile] (pure, off-main)
    FileHashService.swift    streaming SHA-256 of a file (exact-duplicate detection; pure, off-main)
    FolderWatchService.swift FSEvents watcher → debounced onChange (auto-refresh)
    PhotoKitService.swift    import to Photos; favorite/hidden/album; authorization
    MetadataStagingService.swift  exiftool: embed title/caption/keywords into a staged photo copy
    PhotosAppleScriptService.swift  set title/caption/keywords on a Photos asset (videos + fallback)
    PhotosKeywordImporter.swift  osxphotos: read the library's keyword vocabulary
    AudioKeepService.swift   copy a kept audio file to the export folder (dedupes names)
    DeleteService.swift      Trash / permanent delete of on-disk files
    EXIFService.swift        load EXIF for the Preview panel
    ThumbnailService.swift   async thumbnail generation/caching for the grid
    BackupService.swift      launch-time zip backup + retention; isoNow() timestamp helper
    DataSource.swift         the local-vs-remote seam (protocol; DatabaseService + remote conform)
    PeekServerClient.swift   PeekServer HTTP client (wire DTOs, PeekMediaProvider URL builder)
    RemotePeekDataSource.swift  DataSource over PeekServerClient (DTO→model mapping, parallel paging)
    RemoteMedia.swift        LocalReachability (cached SMB-vs-HTTP probe) + PeekTransport sessions
    KeychainStore.swift      PeekServer password storage (device-only Keychain)
    SettingsStore.swift      AppSettings ⇄ UserDefaults; computed default output paths
    Utilities.swift          Array.chunked, small helpers
    WindowStateGuard.swift   window-frame persistence
  Views/
    ContentView.swift        toolbar (mode picker, Photos/Clean Up/Keywords menus, Refresh ⌘R,
                               Open Folder ⌘O), drop intake, status toast, empty state
    Sidebar/SidebarView.swift  grouped scan-roots List (drag-reorder, Move-to-Section,
                               sections +/rename/delete), active root's folder outline, footer total
    FolderView/              FolderBrowseView (header + Space-to-peek monitor), MediaGridView,
                               MediaThumbnailCell (badges incl. missing), MediaListRow
    PreviewMode/             PreviewModeView (keyboard triage + Space→QuickLook),
                               MediaViewerView, EXIFPanelView
    Detail/                  MediaDetailPanel, KeywordPickerView, KeywordManagerSheet,
                               AlbumPickerView, DeleteConfirmationView
    Import/ImportWizardView.swift  filtered batched import + progress/report
    Settings/                SettingsView (tabs) → General / ScanRoots / Backup
    Shared/                  QuickLookBridge (QuickLookCoordinator), ThemeEnvironment
Tests/PurplePeekTests/       DatabaseTests, MediaDiscoveryTests, BackupTests, ServicesTests (37)
```

## Database & migrations

`DatabaseService` owns the single `DatabasePool` for `purplepeek.sqlite` under
`~/Library/Application Support/PurplePeek/`. Migrations are registered in
`static applyMigrations(to:)` (so tests run the *real* migrator against an in-memory DB):

- `v1_initial` — scan_roots, media_files (+ indices), keywords, file_keywords, file_albums.
- `v2_add_is_hidden` — `media_files.is_hidden`.
- `v3_add_missing_at` — `media_files.missing_at` (+ index).
- `v4_add_sidebar_sections` — `sidebar_sections` table + `scan_roots.section_id` /
  `sort_order` (+ index). Sidebar groups and per-root ordering.
- `v5_add_content_hash` — `media_files.content_hash` (+ `(scan_root, content_hash)` index).
  Exact-duplicate detection.

**Migrations are immutable once shipped** (repo `CLAUDE.md`). To change shipped schema/data,
add a new migration — never edit an existing one. `testMigrationLedgerIsFrozen` guards this
(update its expected list when you add one). Junction tables cascade-delete from their parents.

## External dependencies (all runtime-optional except GRDB)

- **GRDB** (SwiftPM) — the only hard dependency.
- **`exiftool`** (`brew`) — photo metadata embedding. Absent → photos import without embedded
  title/caption/keywords.
- **`osxphotos`** (`pipx`) — keyword-vocabulary import. Absent → that button is disabled.
- **Photos.framework + automation** — import + video metadata. The "control Photos" automation
  prompt gates video metadata specifically.

## Conventions / gotchas

- **Single Quick Look panel**: Browse and Preview both drive `QuickLookCoordinator.shared`.
  The Browse key monitor must pass Space through when `firstResponder is NSText` (caption
  editing).
- **Discovery is off-main and pure**; persistence is main-actor and batched. Keep new heavy
  work off the main actor and hand back `Sendable` values.
- **Auto-backup-on-launch** is a ship requirement (zip of the support dir, 14-day retention).
- **Sidebar is a manual `HStack`**, not `NavigationSplitView` (monorepo rule).
- **Icon is code-generated** (`Scripts/generate-icon.swift`); no binary icon source committed.
- **Version is git-derived** (commit count) — there's no hand-edited version constant; bump the
  CHANGELOG instead.

## What's NOT here (intentionally)

- No editing of originals during triage; no star rating (Photos has none — see *Mirror Photos*).
- No background/headless mode — discovery and import are user-driven from the UI.
- Audio is never imported to Photos; kept audio is copied to the export folder.
