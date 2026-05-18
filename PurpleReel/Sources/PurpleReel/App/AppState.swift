import Foundation
import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var rootFolder: URL?
    @Published var workspaceRoots: [URL] = []
    @Published var assets: [Asset] = []
    @Published var folderTree: FolderNode?
    @Published var selectedFolderPath: String?   // nil = root (all)
    @AppStorage("drilldownEnabled") var drilldownEnabled: Bool = true  // legacy default
    @AppStorage("typeFilter") var typeFilter: String = "all"  // all/video/audio/image
    @AppStorage("sortKey") var sortKey: String = "name"        // name/date/size/duration/fps/rating/modified/title
    @AppStorage("sortAscending") var sortAscending: Bool = true
    @AppStorage("viewMode") var viewMode: String = "list"      // grid/list/detail (Kyno ⌘1/⌘2/⌘3). Reset to `defaultViewOnLaunch` on every launch via init.
    /// User-selectable default view applied on every app launch. Set
    /// in Settings → General. Mid-session switches to a different view
    /// still work; this only decides what we land on at startup.
    @AppStorage("defaultViewOnLaunch") var defaultViewOnLaunch: String = "list"
    @AppStorage("timeFilter") var timeFilter: String = "any"   // any/hour/24h/2d/7d/30d/3m/6m/year

    /// Set of optional List-view columns the user has turned on.
    /// Built-in columns (Name/Codec/Resolution/FPS/Duration/Size) are
    /// always shown; everything else is opt-in via the column menu.
    /// Persisted as a comma-joined string via @AppStorage.
    @AppStorage("listColumns") var listColumnsRaw: String = "rating"

    var listColumns: Set<ListColumn> {
        get {
            let parts = listColumnsRaw.split(separator: ",").map(String.init)
            return Set(parts.compactMap { ListColumn(rawValue: $0) })
        }
        set {
            listColumnsRaw = newValue.map(\.rawValue).sorted().joined(separator: ",")
        }
    }

    func toggleListColumn(_ column: ListColumn) {
        var cols = listColumns
        if cols.contains(column) { cols.remove(column) } else { cols.insert(column) }
        listColumns = cols
    }

    /// Cached `clip_metadata` lookups indexed by asset row id, so the
    /// List view can show Title / Reel / Scene / etc. without a DB
    /// round-trip per row per render. Refreshed at scan time and
    /// after explicit edits via `updateClipMetadata(_:value:)`.
    @Published private(set) var clipMetadataIndex: [Int64: ClipMetadata] = [:]

    /// Path → tag-name set, used by `FilterCriterion.hasTag` so the
    /// filter pass doesn't hit SQLite per asset per render.
    /// Refreshed alongside `clipMetadataIndex`.
    @Published private(set) var tagIndex: [String: Set<String>] = [:]

    /// Path → rating stars, used by `FilterCriterion.ratingAtLeast`
    /// for the same reason. 0 = unrated.
    @Published private(set) var ratingIndex: [String: Int] = [:]

    /// Active advanced-filter criteria. Pinned by the user from the
    /// toolbar Filter menu; AND-combined in `displayedAssets`.
    /// Persisted as a `;`-joined token string in UserDefaults so the
    /// set survives across launches.
    @Published var activeFilters: [FilterCriterion] = [] {
        didSet {
            let encoded = activeFilters.map { $0.encoded() }.joined(separator: ";")
            UserDefaults.standard.set(encoded, forKey: "activeFilters")
        }
    }

    func addFilter(_ c: FilterCriterion) {
        if !activeFilters.contains(c) { activeFilters.append(c) }
    }

    func removeFilter(_ c: FilterCriterion) {
        activeFilters.removeAll { $0 == c }
    }

    func clearFilters() { activeFilters.removeAll() }

    private func refreshClipMetadataIndex() {
        var meta: [Int64: ClipMetadata] = [:]
        var tags: [String: Set<String>] = [:]
        var ratings: [String: Int] = [:]
        for asset in assets {
            guard let id = asset.rowId else { continue }
            if let m = try? db.clipMetadata(assetId: id) {
                meta[id] = m
            }
            if let assetTags = try? db.tags(assetId: id) {
                tags[asset.path] = Set(assetTags.map { $0.name })
            }
            // `db.rating` is `throws -> Rating?` → `try?` gives
            // `Rating??`; flatten before binding.
            let r: Rating? = (try? db.rating(assetId: id)) ?? nil
            if let r {
                ratings[asset.path] = r.stars
            }
        }
        clipMetadataIndex = meta
        tagIndex = tags
        ratingIndex = ratings
    }

    /// Flatten of all tag names across the workspace — fed to the
    /// Filter menu's "Has Tag …" submenu so the user picks from
    /// existing tags rather than typing.
    var knownTagNames: [String] {
        var names: Set<String> = []
        for set in tagIndex.values { names.formUnion(set) }
        return names.sorted()
    }

    /// Per-folder drilldown setting (Kyno parity): each path in the
    /// set has drilldown enabled, meaning selecting that folder shows
    /// every file under it including subfolders. Paths not in the set
    /// show only direct children. Persisted as JSON in UserDefaults.
    /// Initialized in `init` because Swift forbids `Self.…()` in a
    /// stored-property initializer.
    @Published var drilldownPaths: Set<String> = []

    private func persistDrilldownPaths() {
        UserDefaults.standard.set(Array(drilldownPaths), forKey: "drilldownPaths")
    }

    /// Is drilldown enabled for this folder? Per-folder ONLY — a folder
    /// is drilled if and only if its path is in `drilldownPaths`. The
    /// legacy global `drilldownEnabled` is no longer consulted: it was
    /// creating the bug where toggling drilldown on one folder visually
    /// "drilled" every folder in the tree because the empty-set
    /// fallback flipped every row's badge on. Workspace folders and
    /// Devices folders share this same set but their paths are
    /// disjoint (`/Users/…` vs `/Volumes/…`) so they're independent.
    func isDrilldownEnabled(forPath path: String) -> Bool {
        return drilldownPaths.contains(path)
    }

    /// Toolbar "Drilldown" button action: toggle drilldown for the
    /// currently-selected folder. Kyno's behavior — the toolbar
    /// affordance acts on the selection, not a hidden global flag.
    func toggleDrilldownForSelection() {
        guard let path = selectedFolderPath, !path.isEmpty else { return }
        toggleDrilldown(forPath: path)
    }

    func toggleDrilldown(forPath path: String) {
        let turningOn = !drilldownPaths.contains(path)
        if turningOn {
            drilldownPaths.insert(path)
        } else {
            drilldownPaths.remove(path)
        }
        persistDrilldownPaths()
        // Kyno-style ephemeral browse: when the user enables drilldown
        // on a path the catalog doesn't know about (a Devices folder,
        // including the whole boot volume), recursively scan it on
        // demand. Per Kyno's docs: "In order to search an entire hard
        // disk, you need to enable Drilldown on the entire hard disk."
        // We do NOT pin the path to `workspaceRoots` — that would
        // pollute the user's curated workspace surface. The scanned
        // content lands in the DB and persists across launches.
        if turningOn, !isPathUnderAnyWorkspaceRoot(path), !path.isEmpty {
            Task { await scanOnDemand(path: path) }
        }
    }

    /// Tracks paths that have been shallow-scanned this session via
    /// `navigate(to:)` so we don't re-walk a folder every time the
    /// user clicks it. Drilldown-triggered deep scans use the DB's
    /// existing upsert path so they're naturally idempotent.
    private var shallowScannedPaths: Set<String> = []

    private func isPathUnderAnyWorkspaceRoot(_ path: String) -> Bool {
        let p = (path as NSString).standardizingPath
        for root in workspaceRoots {
            let r = (root.path as NSString).standardizingPath
            if p == r || p.hasPrefix(r + "/") { return true }
        }
        return false
    }

    /// Recursive scan of an arbitrary path. Used when the user navigates
    /// into / drills into a Devices folder that isn't covered by any
    /// workspace root — Kyno's browse-anywhere semantic. Persists to
    /// the catalog like a normal scan so the assets show up in the
    /// grid; doesn't add the path to `workspaceRoots` so the
    /// workspace section stays user-curated.
    func scanOnDemand(path: String) async {
        let url = URL(fileURLWithPath: path)
        isScanning = true
        defer { isScanning = false; scanProgress = "" }
        do {
            scanProgress = "Scanning \(url.lastPathComponent)…"
            let found = try await scanner.scan(root: url) { [weak self] count in
                Task { @MainActor in
                    self?.scanProgress = "Found \(count) media files in \(url.lastPathComponent)…"
                }
            }
            try db.upsertAssets(found)
            self.assets = try db.allAssets()
            self.rebuildFolderTree()
            self.refreshClipMetadataIndex()
        } catch {
            NSLog("[PurpleReel] on-demand scan failed for \(path): \(error)")
        }
    }

    /// Map a boot-volume firmlink (e.g. `/Volumes/Macintosh HD`) back to
    /// its canonical `/`. External volumes pass through unchanged.
    /// macOS firmlinks aren't symlinks, so `resolvingSymlinksInPath()`
    /// doesn't help — instead we compare APFS volume identifiers.
    static func canonicalizeBootVolumePath(_ path: String) -> String {
        guard path.hasPrefix("/Volumes/") else { return path }
        let rootKey = (try? URL(fileURLWithPath: "/")
            .resourceValues(forKeys: [.volumeIdentifierKey]))?
            .volumeIdentifier as? NSObject
        let pathKey = (try? URL(fileURLWithPath: path)
            .resourceValues(forKeys: [.volumeIdentifierKey]))?
            .volumeIdentifier as? NSObject
        if let r = rootKey, let p = pathKey, r == p { return "/" }
        return path
    }

    // History stack for the back/forward navigation arrows.
    // Each entry is the `selectedFolderPath` value at that point.
    @Published private(set) var historyStack: [String?] = [nil]
    @Published private(set) var historyIndex: Int = 0
    private var suppressHistory = false
    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < historyStack.count - 1 }
    @Published var isScanning = false
    @Published var scanProgress: String = ""
    @Published var selectedAssetPath: String? {
        didSet { loadSelectionDetail() }
    }

    /// Multi-select for batch operations (Convert, Move to Trash, Tags,
    /// SFTP delivery, etc.). The `selectedAssetPath` above stays as the
    /// "primary" / viewer-focus single selection; this set is what
    /// batch actions consume.
    @Published var selectedAssetPaths: Set<String> = [] {
        didSet {
            // Keep the primary selection in sync with the multi-select
            // anchor — when the set is reduced to one, that one is the
            // primary; when the set is cleared, clear the primary.
            if selectedAssetPaths.count == 1,
               let only = selectedAssetPaths.first,
               only != selectedAssetPath {
                selectedAssetPath = only
            }
        }
    }

    /// Apply a click in a single-select / multi-select context to the
    /// assets list. Standard macOS modifier semantics: plain click =
    /// replace, Cmd-click = toggle, Shift-click = range-extend from
    /// the current primary selection.
    func handleAssetClick(path: String, modifiers: EventModifiers) {
        let list = displayedAssets.map(\.path)
        if modifiers.contains(.shift),
           let anchor = selectedAssetPath,
           let lo = list.firstIndex(of: anchor),
           let hi = list.firstIndex(of: path) {
            let range = lo <= hi ? lo...hi : hi...lo
            selectedAssetPaths = Set(list[range])
            selectedAssetPath = path
        } else if modifiers.contains(.command) {
            if selectedAssetPaths.contains(path) {
                selectedAssetPaths.remove(path)
                if selectedAssetPath == path {
                    selectedAssetPath = selectedAssetPaths.first
                }
            } else {
                selectedAssetPaths.insert(path)
                selectedAssetPath = path
            }
        } else {
            selectedAssetPaths = [path]
            selectedAssetPath = path
        }
    }

    /// Assets currently in the batch selection — driven by paths in
    /// `selectedAssetPaths`. Returns assets ordered by their display
    /// order in the catalogue.
    var selectedAssets: [Asset] {
        guard !selectedAssetPaths.isEmpty else {
            return selectedAsset.map { [$0] } ?? []
        }
        return assets.filter { selectedAssetPaths.contains($0.path) }
    }

    // Bridges `selectedFolderPath` writes through a history-aware
    // setter so the back/forward arrows see every navigation event.
    // Direct `selectedFolderPath = …` is still valid and supported;
    // when it changes from a non-suppressed path, we append.
    func navigate(to folder: String?) {
        let cur = historyStack.indices.contains(historyIndex) ? historyStack[historyIndex] : nil
        guard cur != folder else { return }
        // Drop any forward history past the current point — same as
        // browser history semantics.
        if historyIndex < historyStack.count - 1 {
            historyStack = Array(historyStack.prefix(historyIndex + 1))
        }
        historyStack.append(folder)
        historyIndex = historyStack.count - 1
        suppressHistory = true
        selectedFolderPath = folder
        suppressHistory = false
        // Kyno-style "select a folder → see top-level media
        // immediately" — when the user navigates to a folder that
        // ISN'T under any workspace root, shallow-scan it on demand
        // so its direct-children media files appear in the grid
        // without requiring drilldown. One scan per path per
        // session via `shallowScannedPaths`.
        if let path = folder,
           !path.isEmpty,
           !isPathUnderAnyWorkspaceRoot(path),
           !shallowScannedPaths.contains(path) {
            shallowScannedPaths.insert(path)
            Task { await shallowScanAndUpsert(path: path) }
        }
    }

    /// Shallow scan (direct children only) used by navigate(to:) for
    /// non-workspace paths. Per-path one-shot per session — cheap
    /// because it doesn't recurse.
    private func shallowScanAndUpsert(path: String) async {
        let url = URL(fileURLWithPath: path)
        do {
            let found = try await scanner.scanShallow(root: url)
            if !found.isEmpty {
                try db.upsertAssets(found)
                self.assets = try db.allAssets()
                self.refreshClipMetadataIndex()
            }
        } catch {
            NSLog("[PurpleReel] shallow scan failed for \(path): \(error)")
        }
    }

    func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        suppressHistory = true
        selectedFolderPath = historyStack[historyIndex]
        suppressHistory = false
    }

    func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        suppressHistory = true
        selectedFolderPath = historyStack[historyIndex]
        suppressHistory = false
    }

    func clearHistory() {
        let current = historyStack.indices.contains(historyIndex) ? historyStack[historyIndex] : nil
        historyStack = [current]
        historyIndex = 0
    }

    /// Move the asset-table selection up or down by `delta` rows
    /// (within the currently-displayed list). Wired to ⌘← / ⌘→.
    func selectAdjacentAsset(delta: Int) {
        let list = displayedAssets
        guard !list.isEmpty else { return }
        if let current = selectedAssetPath,
           let idx = list.firstIndex(where: { $0.path == current }) {
            let newIdx = max(0, min(list.count - 1, idx + delta))
            selectedAssetPath = list[newIdx].path
        } else {
            selectedAssetPath = list.first?.path
        }
    }

    /// Filtered view of `assets` driven by `selectedFolderPath`,
    /// `drilldownEnabled`, `typeFilter`, and sorted by `sortKey`.
    /// Matches Kyno's browser-toolbar semantics.
    var displayedAssets: [Asset] {
        // Always scope to *some* root: either the explicitly-selected
        // folder, the current active root, or — if a workspace has
        // multiple roots — the union of all of them. Without this,
        // catalogue-wide history bleeds previous folders into the view.
        var base: [Asset]
        if let folder = selectedFolderPath, !folder.isEmpty {
            // Canonicalize: clicking "Macintosh HD" in Devices sets
            // `selectedFolderPath` to the firmlink `/Volumes/Macintosh HD`,
            // but asset paths in the catalogue are stored as `/Users/…`,
            // `/Applications/…` etc. — none of them prefix-match the
            // firmlink even though they're all on the same volume. Resolve
            // the boot-volume firmlink back to `/` so its prefix matches
            // everything on the boot volume.
            let canonical = Self.canonicalizeBootVolumePath(folder)
            let normalized = (canonical as NSString).standardizingPath
            // Drilldown is strictly user-controlled. Earlier builds
            // force-enabled it for volume roots (`/`, `/Volumes/<name>`)
            // on the theory that "direct children of /" never matches
            // any catalogued asset — but that turned out to be wrong:
            // when the user selects Mac HD with drilldown OFF they
            // genuinely expect to see the direct-children listing
            // (which is zero items, since no media lives at /), and
            // they'll toggle drilldown ON when they want the recursive
            // listing. Matches Kyno's Devices behaviour.
            let drilldown = isDrilldownEnabled(forPath: folder)
            if drilldown {
                // Root path "/" matches every asset; for nested paths
                // use "<path>/" so siblings don't accidentally match.
                let prefix = normalized == "/" ? "/" : normalized + "/"
                base = assets.filter { ($0.path as NSString).standardizingPath
                                         .hasPrefix(prefix) }
            } else {
                base = assets.filter { asset in
                    let parent = ((asset.path as NSString).standardizingPath as NSString)
                        .deletingLastPathComponent
                    return parent == normalized
                }
            }
        } else if !workspaceRoots.isEmpty {
            // Show every asset under any workspace root.
            let normalizedRoots = workspaceRoots.map { ($0.path as NSString).standardizingPath }
            base = assets.filter { asset in
                let p = (asset.path as NSString).standardizingPath
                return normalizedRoots.contains { p.hasPrefix($0 + "/") }
            }
        } else {
            base = assets
        }

        // Time filter (modification date)
        let now = Date()
        let cutoff: TimeInterval? = {
            switch timeFilter {
            case "hour": return 3600
            case "24h":  return 86_400
            case "2d":   return 2 * 86_400
            case "7d":   return 7 * 86_400
            case "30d":  return 30 * 86_400
            case "3m":   return 90 * 86_400
            case "6m":   return 180 * 86_400
            case "year": return 365 * 86_400
            default:     return nil
            }
        }()
        if let c = cutoff {
            base = base.filter { now.timeIntervalSince($0.modifiedAt) <= c }
        }

        // Media-type filter
        switch typeFilter {
        case "video":
            base = base.filter { AssetKind.from(extension: ($0.filename as NSString).pathExtension) == .video }
        case "audio":
            base = base.filter { AssetKind.from(extension: ($0.filename as NSString).pathExtension) == .audio }
        case "image":
            base = base.filter { AssetKind.from(extension: ($0.filename as NSString).pathExtension) == .image }
        default: break
        }

        // Advanced filter criteria (additive AND). Applied after the
        // time/type chips so the chips still scope the working set
        // and these are layered refinements (rating, tag, codec,
        // resolution, framerate, size, duration).
        if !activeFilters.isEmpty {
            let tags = tagIndex
            let ratingFor: (Asset) -> Int = { [self] asset in
                self.ratingIndex[asset.path] ?? 0
            }
            base = base.filter { asset in
                activeFilters.allSatisfy {
                    $0.matches(asset, ratingForAsset: ratingFor, tagIndex: tags)
                }
            }
        }

        // Sort. Direction-aware via `sortAscending`.
        let asc = sortAscending
        switch sortKey {
        case "date", "modified":
            base.sort { asc ? $0.modifiedAt < $1.modifiedAt : $0.modifiedAt > $1.modifiedAt }
        case "size":
            base.sort { asc ? $0.sizeBytes < $1.sizeBytes : $0.sizeBytes > $1.sizeBytes }
        case "duration":
            base.sort {
                let a = $0.durationSeconds ?? 0, b = $1.durationSeconds ?? 0
                return asc ? a < b : a > b
            }
        case "fps":
            base.sort {
                let a = $0.frameRate ?? 0, b = $1.frameRate ?? 0
                return asc ? a < b : a > b
            }
        default:
            // Kyno-compat mode (and most users' expectation): treat
            // numeric runs naturally so `clip2` sorts before `clip10`.
            // PurpleReel's original default was lexicographic via
            // `localizedCaseInsensitiveCompare`; flag persists via
            // `naturalFileSort` AppStorage.
            let natural = UserDefaults.standard.bool(forKey: "naturalFileSort")
            base.sort {
                let cmp: ComparisonResult = natural
                    ? $0.filename.localizedStandardCompare($1.filename)
                    : $0.filename.localizedCaseInsensitiveCompare($1.filename)
                return asc ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        }
        return base
    }

    // Detail state for the currently selected asset.
    @Published private(set) var selectedAsset: Asset?
    @Published private(set) var markers: [Marker] = []
    @Published private(set) var subclips: [Subclip] = []
    @Published private(set) var tags: [Tag] = []
    @Published private(set) var rating: Rating?
    @Published private(set) var clipMetadata: ClipMetadata = .empty

    private let scanner = MediaScanner()
    let db: DatabaseService
    /// Mount/unmount + FSEvents observer. Consumes Settings → Devices
    /// toggles to decide what to react to.
    let volumeWatcher = VolumeWatcher()
    let transcodeQueue = TranscodeQueue()
    @Published var transcodeSheetVisible = false
    @Published var backupSheetVisible = false
    @Published var sftpSheetVisible = false
    @Published var detailSheetVisible = false
    @Published var aiSheetState: AISheetState?
    @Published var batchRenameSheetVisible = false
    @Published var batchMetadataSheetVisible = false
    @Published var shortcutsCheatSheetVisible = false

    @Published private(set) var transcript: TranscriptDocument?
    @Published var aiStatus: String = ""

    init() {
        do {
            self.db = try DatabaseService()
        } catch {
            fatalError("PurpleReel could not open its database: \(error)")
        }
        BackupService.runOnLaunchIfNeeded()
        // Hydrate per-folder drilldown set from defaults.
        if let arr = UserDefaults.standard.array(forKey: "drilldownPaths") as? [String] {
            self.drilldownPaths = Set(arr)
        }
        // Hydrate active filter set from defaults.
        if let raw = UserDefaults.standard.string(forKey: "activeFilters"),
           !raw.isEmpty {
            self.activeFilters = raw.split(separator: ";").compactMap {
                FilterCriterion.decoded(String($0))
            }
        }
        // Hydrate workspace from defaults: prefer the new
        // `workspaceRoots` array; fall back to the legacy single
        // `rootFolder` string for users upgrading from earlier builds.
        if let savedArray = UserDefaults.standard.array(forKey: "workspaceRoots") as? [String],
           !savedArray.isEmpty {
            self.workspaceRoots = savedArray.map { URL(fileURLWithPath: $0) }
            self.rootFolder = self.workspaceRoots.first
        } else if let saved = UserDefaults.standard.string(forKey: "rootFolder") {
            self.rootFolder = URL(fileURLWithPath: saved)
            self.workspaceRoots = [URL(fileURLWithPath: saved)]
        }
        if let root = rootFolder {
            self.selectedFolderPath = root.path
            self.historyStack = [root.path]
            self.historyIndex = 0
            self.assets = (try? db.allAssets()) ?? []
            self.rebuildFolderTree()
            self.refreshClipMetadataIndex()
            Task { await rescan() }
        }
        // Mount/unmount + FSEvents observer. Kicked off after every
        // other init step so the watcher sees the fully-hydrated
        // workspace on its first stream rebuild.
        volumeWatcher.start(appState: self)
        // Per-launch view reset. The user picks the preferred startup
        // view in Settings → General → "Default view on launch";
        // mid-session switches still stick (and are persisted), but
        // every launch lands back on the configured default.
        self.viewMode = defaultViewOnLaunch
    }

    // MARK: - Root folder / scan

    /// "Open Folder…" semantics: replace the workspace with a single
    /// root and scan it. Behaves like a fresh-start.
    func chooseRootFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            self.workspaceRoots = [url]
            self.rootFolder = url
            self.selectedFolderPath = url.path
            self.historyStack = [url.path]
            self.historyIndex = 0
            persistWorkspace()
            Task { await rescan() }
        }
    }

    /// Workspace addition: pick a folder and add it as a sibling
    /// root without dropping the existing roots. Matches Kyno's
    /// "Add Folder to Workspace…".
    func addFolderToWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if !workspaceRoots.contains(url) {
                workspaceRoots.append(url)
            }
            self.rootFolder = url   // make the newly-added root active
            self.selectedFolderPath = url.path
            persistWorkspace()
            navigate(to: url.path)
            Task { await rescan() }
        }
    }

    func clearWorkspace() {
        workspaceRoots = []
        rootFolder = nil
        selectedFolderPath = nil
        assets = []
        folderTree = nil
        historyStack = [nil]
        historyIndex = 0
        persistWorkspace()
    }

    func removeWorkspaceRoot(_ url: URL) {
        workspaceRoots.removeAll { $0 == url }
        if rootFolder == url { rootFolder = workspaceRoots.first }
        persistWorkspace()
        Task { await rescan() }
    }

    private func persistWorkspace() {
        let paths = workspaceRoots.map { $0.path }
        UserDefaults.standard.set(paths, forKey: "workspaceRoots")
        UserDefaults.standard.set(rootFolder?.path, forKey: "rootFolder")
        // Workspace shape changed — re-aim the FSEvents stream so new
        // roots are observed and removed roots stop firing rescans.
        volumeWatcher.rebuildStream()
    }

    /// Scan every workspace root and union the results into the
    /// catalogue. Always reloads `assets` from the DB at the end so
    /// the displayed view reflects EVERY catalogued file under any
    /// workspace root, with no stale entries from previously-opened
    /// folders.
    func rescan() async {
        let roots: [URL] = !workspaceRoots.isEmpty
            ? workspaceRoots
            : (rootFolder.map { [$0] } ?? [])
        guard !roots.isEmpty else { return }
        isScanning = true
        defer { isScanning = false; scanProgress = "" }

        do {
            for root in roots {
                scanProgress = "Scanning \(root.lastPathComponent)…"
                let found = try await scanner.scan(root: root) { [weak self] count in
                    Task { @MainActor in
                        self?.scanProgress = "Found \(count) media files in \(root.lastPathComponent)…"
                    }
                }
                try db.upsertAssets(found)
            }
            self.assets = try db.allAssets()
            self.rebuildFolderTree()
            self.refreshClipMetadataIndex()
            // Soft warning when the workspace balloons past the
            // safety limit. Doesn't block; we still load every asset.
            // The user can either narrow the workspace or raise
            // `fileCountSafetyLimit` in Settings → Advanced.
            if self.assets.count > self.fileCountSafetyLimit,
               self.fileCountWarning == nil {
                self.fileCountWarning = self.assets.count
            }
        } catch {
            NSLog("[PurpleReel] scan failed: \(error)")
        }
    }

    // MARK: - Safety limit (rescan warning)

    /// Max files PurpleReel will silently catalogue without warning
    /// the user. Stored as `@AppStorage` so power users can raise it.
    var fileCountSafetyLimit: Int {
        let raw = UserDefaults.standard.integer(forKey: "fileCountSafetyLimit")
        return raw > 0 ? raw : 50_000
    }

    /// Posted when the rescanned asset count crosses the safety limit.
    /// UI presents a sheet; the catalogue still loads in full.
    @Published var fileCountWarning: Int?

    /// Rebuild the sidebar folder tree(s) from the current asset list.
    /// For a single-root workspace it's still rendered as one tree; for
    /// multi-root, the sidebar walks `workspaceRoots` and builds one
    /// tree per root (via the helper below).
    func rebuildFolderTree() {
        guard let root = rootFolder else {
            folderTree = nil
            return
        }
        folderTree = FolderTreeBuilder.build(rootPath: root.path, assets: assets)
    }

    func folderTree(forRoot root: URL) -> FolderNode? {
        FolderTreeBuilder.build(rootPath: root.path, assets: assets)
    }

    // MARK: - Selection detail

    private func loadSelectionDetail() {
        markers = []
        subclips = []
        tags = []
        rating = nil
        transcript = nil
        selectedAsset = nil
        clipMetadata = .empty
        guard let path = selectedAssetPath else { return }
        do {
            guard let asset = try db.asset(forPath: path),
                  let id = asset.rowId else { return }
            selectedAsset = asset
            markers = try db.markers(assetId: id)
            subclips = try db.subclips(parentAssetId: id)
            tags = try db.tags(assetId: id)
            rating = try db.rating(assetId: id)
            transcript = try db.transcript(assetId: id)
            clipMetadata = try db.clipMetadata(assetId: id)
        } catch {
            NSLog("[PurpleReel] selection load failed: \(error)")
        }
    }

    /// Apply a `BatchMetadataChange` to every asset in the current
    /// multi-selection (or the single primary selection if no
    /// multi-select). Each field is opt-in via the `apply…` flags —
    /// unticked fields stay untouched on every target; ticked fields
    /// write the corresponding value (empty string clears).
    /// Tags are additive, never destructive.
    /// Refreshes caches + the currently-loaded selection at the end.
    func applyBatchMetadata(_ change: BatchMetadataChange) -> Int {
        let targets: [Asset]
        if !selectedAssetPaths.isEmpty {
            targets = assets.filter { selectedAssetPaths.contains($0.path) }
        } else if let a = selectedAsset {
            targets = [a]
        } else {
            return 0
        }
        var applied = 0
        for asset in targets {
            guard let id = asset.rowId else { continue }
            var meta = (try? db.clipMetadata(assetId: id))
                ?? ClipMetadata(assetId: id, title: nil, description: nil,
                                 reel: nil, scene: nil, shot: nil,
                                 take: nil, angle: nil, camera: nil)
            meta.assetId = id

            // Single-line log fields.
            if change.applyTitle       { meta.title       = sanitize(change.title) }
            if change.applyDescription { meta.description = sanitize(change.description) }
            if change.applyReel        { meta.reel        = sanitize(change.reel) }
            if change.applyScene       { meta.scene       = sanitize(change.scene) }
            if change.applyShot        { meta.shot        = sanitize(change.shot) }
            if change.applyTake        { meta.take        = sanitize(change.take) }
            if change.applyAngle       { meta.angle       = sanitize(change.angle) }
            if change.applyCamera      { meta.camera      = sanitize(change.camera) }
            try? db.setClipMetadata(meta)
            clipMetadataIndex[id] = meta

            // Rating.
            if change.applyRating {
                let existing = (try? db.rating(assetId: id)) ?? nil
                try? db.setRating(assetId: id, stars: change.rating,
                                    colorLabel: existing?.colorLabel,
                                    description: existing?.description)
                ratingIndex[asset.path] = change.rating
            }

            // Tags — additive (never clears existing). De-duplicates
            // implicitly because asset_tag is keyed (assetId, tagId).
            if change.applyTags {
                for tag in change.tagsToAdd {
                    let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    _ = try? db.addTag(name: trimmed, assetId: id)
                }
            }

            applied += 1
        }
        // If the primary selection was one of the targets, refresh
        // the inspector pane so the user sees the new values.
        if let p = selectedAssetPath, selectedAssetPaths.contains(p)
                                   || targets.count == 1 {
            loadSelectionDetail()
        }
        // Rebuild tag index — additive writes may have introduced new
        // tag names not in the cache yet.
        refreshClipMetadataIndex()
        return applied
    }

    private func sanitize(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Persist a single ClipMetadata field. The Metadata pane calls
    /// this on each .onSubmit / .onChange so edits stick without an
    /// explicit Save button (Kyno's UX).
    func updateClipMetadata(_ keyPath: WritableKeyPath<ClipMetadata, String?>,
                             value: String) {
        guard let id = selectedAsset?.rowId else { return }
        var copy = clipMetadata
        copy.assetId = id
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        copy[keyPath: keyPath] = trimmed.isEmpty ? nil : trimmed
        do {
            try db.setClipMetadata(copy)
            clipMetadata = copy
            clipMetadataIndex[id] = copy
        } catch {
            NSLog("[PurpleReel] clip metadata save failed: \(error)")
        }
    }

    private func refreshMarkers() {
        guard let id = selectedAsset?.rowId else { return }
        markers = (try? db.markers(assetId: id)) ?? []
    }

    private func refreshSubclips() {
        guard let id = selectedAsset?.rowId else { return }
        subclips = (try? db.subclips(parentAssetId: id)) ?? []
    }

    private func refreshTags() {
        guard let id = selectedAsset?.rowId else { return }
        tags = (try? db.tags(assetId: id)) ?? []
    }

    private func refreshRating() {
        guard let id = selectedAsset?.rowId else { return }
        rating = try? db.rating(assetId: id)
    }

    // MARK: - Markers

    func addMarker(timecodeIn: Double, note: String? = nil) {
        guard let id = selectedAsset?.rowId else { return }
        _ = try? db.addMarker(assetId: id, timecodeIn: timecodeIn, note: note)
        refreshMarkers()
    }

    func deleteMarker(_ marker: Marker) {
        guard let mid = marker.id else { return }
        try? db.deleteMarker(id: mid)
        refreshMarkers()
    }

    /// ⌥M handler — remove the marker closest to the current player
    /// playhead. ε = 1/(fps) so anything within a frame counts.
    /// `currentTime` comes from the menu-bar listener, since AppState
    /// doesn't own the PlayerController directly.
    func removeMarkerNearestPlayhead(currentTime: Double, fps: Double) {
        guard !markers.isEmpty else { return }
        let epsilon = max(0.05, 1.0 / max(fps, 1))
        let candidates = markers.filter {
            abs($0.timecodeIn - currentTime) <= epsilon
        }
        if let target = candidates.first ?? markers.min(by: {
            abs($0.timecodeIn - currentTime) < abs($1.timecodeIn - currentTime)
        }) {
            deleteMarker(target)
        }
    }

    /// ⌥S handler — remove the most recently created subclip on the
    /// current selection.
    func removeLastSubclipForSelection() {
        guard let last = subclips.last else { return }
        deleteSubclip(last)
    }

    func updateMarkerNote(_ marker: Marker, note: String) {
        var copy = marker
        copy.note = note.isEmpty ? nil : note
        try? db.updateMarker(copy)
        refreshMarkers()
    }

    // MARK: - Subclips

    func addSubclip(name: String, timecodeIn: Double, timecodeOut: Double) {
        guard let id = selectedAsset?.rowId else { return }
        let lo = min(timecodeIn, timecodeOut)
        let hi = max(timecodeIn, timecodeOut)
        // Kyno collision quirk: identical subclip names on the same
        // asset silently overwrote each other. We auto-disambiguate
        // with a numeric suffix so the user never loses a take.
        let finalName = uniqueSubclipName(base: name, on: id)
        _ = try? db.addSubclip(parentAssetId: id, name: finalName,
                                timecodeIn: lo, timecodeOut: hi)
        refreshSubclips()
    }

    /// Pick the next non-colliding subclip name on `assetId`. If
    /// `base` isn't taken, returns it unchanged; otherwise appends
    /// " 2", " 3", … until free.
    private func uniqueSubclipName(base: String, on assetId: Int64) -> String {
        let existing = (try? db.subclips(parentAssetId: assetId).map(\.name)) ?? []
        if !existing.contains(base) { return base }
        var counter = 2
        while existing.contains("\(base) \(counter)") { counter += 1 }
        return "\(base) \(counter)"
    }

    func deleteSubclip(_ subclip: Subclip) {
        guard let sid = subclip.id else { return }
        try? db.deleteSubclip(id: sid)
        refreshSubclips()
    }

    // MARK: - Tags

    func addTag(name: String) {
        guard let id = selectedAsset?.rowId else { return }
        _ = try? db.addTag(name: name, assetId: id)
        refreshTags()
    }

    func removeTag(name: String) {
        guard let id = selectedAsset?.rowId else { return }
        try? db.removeTag(name: name, assetId: id)
        refreshTags()
    }

    // MARK: - Rating + description

    func setRating(stars: Int) {
        guard let id = selectedAsset?.rowId else { return }
        let desc = rating?.description
        let color = rating?.colorLabel
        try? db.setRating(assetId: id, stars: stars,
                          colorLabel: color, description: desc)
        refreshRating()
    }

    // MARK: - AI: Whisper transcription

    func transcribeSelected(generateMarkers: Bool) {
        guard let asset = selectedAsset, let id = asset.rowId else { return }
        aiSheetState = .transcribing(filename: asset.filename)
        aiStatus = "Loading MLX Whisper…"
        // Honor user overrides from Settings → AI. Empty = defaults.
        let scriptPathOverride = UserDefaults.standard.string(forKey: "whisperScriptPath")
        let scriptPath = (scriptPathOverride?.isEmpty == false) ? scriptPathOverride : nil
        let model = UserDefaults.standard.string(forKey: "whisperModel") ?? "turbo"
        Task {
            do {
                let doc = try await WhisperService.transcribe(
                    file: URL(fileURLWithPath: asset.path),
                    model: model,
                    scriptPath: scriptPath
                )
                try await MainActor.run {
                    try db.saveTranscript(doc, assetId: id)
                    transcript = doc
                    if generateMarkers {
                        for seg in doc.segments {
                            _ = try? db.addMarker(
                                assetId: id, timecodeIn: seg.start,
                                timecodeOut: seg.end, note: seg.text
                            )
                        }
                        markers = try db.markers(assetId: id)
                    }
                    aiStatus = "Transcribed \(doc.segments.count) segments"
                    aiSheetState = .transcriptReady(doc: doc, assetName: asset.filename)
                }
            } catch {
                await MainActor.run {
                    aiStatus = "Transcription failed: \(error.localizedDescription)"
                    aiSheetState = .error(message: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - AI: Ollama auto-describe

    func autoDescribeSelected() {
        guard let asset = selectedAsset, let id = asset.rowId else { return }
        aiSheetState = .describing(filename: asset.filename)
        aiStatus = "Calling local LLM…"
        let model = UserDefaults.standard.string(forKey: "ollamaModel") ?? OllamaService.defaultModel
        Task {
            do {
                let snippet = transcript?.fullText
                let description = try await OllamaService.describe(
                    filename: asset.filename,
                    transcriptSnippet: snippet,
                    model: model
                )
                await MainActor.run {
                    let starsNow = rating?.stars ?? 0
                    try? db.setRating(assetId: id, stars: starsNow,
                                       colorLabel: rating?.colorLabel,
                                       description: description)
                    self.rating = try? db.rating(assetId: id)
                    aiStatus = "Description generated."
                    aiSheetState = .describeReady(
                        text: description, assetName: asset.filename
                    )
                }
            } catch {
                await MainActor.run {
                    aiStatus = "LLM failed: \(error.localizedDescription)"
                    aiSheetState = .error(message: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - AI: Similar takes

    @Published var similarClusters: [SimilarTakeCluster] = []

    func findSimilarTakes() {
        aiSheetState = .findingSimilar(progress: 0, total: 0)
        Task {
            var ratingsById: [Int64: Rating] = [:]
            for a in assets {
                if let id = a.rowId, let r = try? db.rating(assetId: id) {
                    ratingsById[id] = r
                }
            }
            let clusters = await SimilarTakesService.findClusters(
                assets: assets,
                ratings: ratingsById,
                onProgress: { done, total in
                    Task { @MainActor in
                        self.aiSheetState = .findingSimilar(progress: done, total: total)
                    }
                }
            )
            await MainActor.run {
                self.similarClusters = clusters
                self.aiSheetState = .similarReady(count: clusters.count)
            }
        }
    }

    // MARK: - FCPXML export

    enum FCPXMLExportScope {
        case allCatalogued
        case selectedOnly
    }

    @Published var lastFCPXMLExportPath: URL?

    /// Build a Send-to-FCP package: gather every asset (or just the
    /// selection) plus its markers, subclips, tags, and rating, write
    /// the FCPXML to `~/Downloads/PurpleReel/exports/`, and (optionally)
    /// hand it to Final Cut Pro via `open -a`.
    @discardableResult
    func exportFCPXML(scope: FCPXMLExportScope, openInFCP: Bool) -> URL? {
        let targetAssets: [Asset]
        switch scope {
        case .allCatalogued: targetAssets = assets
        case .selectedOnly:
            if let a = selectedAsset { targetAssets = [a] } else { return nil }
        }
        guard !targetAssets.isEmpty else { return nil }

        var items: [FCPXMLExportInput] = []
        items.reserveCapacity(targetAssets.count)
        for a in targetAssets {
            guard let id = a.rowId else { continue }
            let m = (try? db.markers(assetId: id)) ?? []
            let s = (try? db.subclips(parentAssetId: id)) ?? []
            let t = (try? db.tags(assetId: id)) ?? []
            let r = (try? db.rating(assetId: id)) ?? nil
            let meta = (try? db.clipMetadata(assetId: id))
            items.append(FCPXMLExportInput(asset: a, markers: m, subclips: s,
                                            tags: t, rating: r,
                                            clipMetadata: meta))
        }
        guard !items.isEmpty else { return nil }

        do {
            let dir = try fcpxmlExportDirectory()
            let stamp = exportTimestamp()
            let eventName = scope == .allCatalogued
                ? "PurpleReel Library \(stamp)"
                : "PurpleReel — \(targetAssets[0].filename)"
            let url = dir.appendingPathComponent("PurpleReel_\(stamp).fcpxml")
            try FCPXMLWriter.write(
                eventName: eventName,
                items: items,
                toolVersion: AppVersion.marketing,
                to: url
            )
            lastFCPXMLExportPath = url
            if openInFCP {
                let fcpURL = URL(fileURLWithPath: "/Applications/Final Cut Pro.app")
                if FileManager.default.fileExists(atPath: fcpURL.path) {
                    NSWorkspace.shared.open([url], withApplicationAt: fcpURL,
                                              configuration: NSWorkspace.OpenConfiguration())
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            return url
        } catch {
            NSLog("[PurpleReel] FCPXML export failed: \(error)")
            return nil
        }
    }

    private func fcpxmlExportDirectory() throws -> URL {
        let downloads = try FileManager.default.url(
            for: .downloadsDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let dir = downloads.appendingPathComponent("PurpleReel/exports", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func exportTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f.string(from: Date())
    }

    // MARK: - Transcode

    /// State driving the Convert & Transcode Media dialog. Set when
    /// the user picks a preset from the Convert submenu (or the
    /// toolbar's Transcode menu); cleared when the dialog dismisses.
    @Published var convertSheet: ConvertSheetState?

    /// Compose the Convert dialog state from the current multi-
    /// selection (or the single primary selection as fallback) plus
    /// the chosen preset, and open the dialog. The actual enqueue
    /// happens when the user confirms with Start in the dialog.
    func openConvertDialog(preset: TranscodePreset) {
        let assetsToConvert: [Asset]
        if !selectedAssetPaths.isEmpty {
            let ordered = displayedAssets.filter { selectedAssetPaths.contains($0.path) }
            assetsToConvert = ordered.isEmpty ? selectedAssets : ordered
        } else if let a = selectedAsset {
            assetsToConvert = [a]
        } else {
            return
        }
        guard !assetsToConvert.isEmpty else { return }
        // Default the dialog's destination to ~/Downloads/PurpleReel/
        // transcoded/ (PhantomLives convention), unless the user has
        // a sticky override.
        let defaultDir = (try? TranscodeService.defaultOutputDirectory().path)
            ?? "~/Downloads/PurpleReel/transcoded"
        let stickyDir = UserDefaults.standard.string(forKey: "convertOutputDir")
        let keep = UserDefaults.standard.object(forKey: "convertKeepFolderStructure") as? Bool ?? false
        let skip = UserDefaults.standard.object(forKey: "convertSkipExisting") as? Bool ?? true
        convertSheet = ConvertSheetState(
            assets: assetsToConvert,
            preset: preset,
            destinationDir: stickyDir ?? defaultDir,
            keepFolderStructure: keep,
            skipExisting: skip
        )
    }

    /// Enqueue the configured jobs from the Convert dialog. Called
    /// from `ConvertSheet` when the user confirms.
    func confirmConvert(_ state: ConvertSheetState) {
        // Persist sticky settings.
        UserDefaults.standard.set(state.destinationDir, forKey: "convertOutputDir")
        UserDefaults.standard.set(state.keepFolderStructure, forKey: "convertKeepFolderStructure")
        UserDefaults.standard.set(state.skipExisting, forKey: "convertSkipExisting")
        RecentPresets.push(state.preset)

        let baseDir = URL(fileURLWithPath: (state.destinationDir as NSString)
                            .expandingTildeInPath)
        try? FileManager.default.createDirectory(at: baseDir,
                                                   withIntermediateDirectories: true)

        // Use the common ancestor of every asset's parent dir as the
        // "source root" when keep-folder-structure is on — files end up
        // at `<destination>/<relativePath>`.
        let parents = state.assets.map {
            URL(fileURLWithPath: $0.path).deletingLastPathComponent().path
        }
        let commonRoot = ConvertSheetState.commonAncestor(of: parents)

        var enqueued = 0
        for asset in state.assets {
            let srcURL = URL(fileURLWithPath: asset.path)
            let outDir: URL
            if state.keepFolderStructure, let root = commonRoot, !root.isEmpty {
                let rel = srcURL.deletingLastPathComponent().path
                    .replacingOccurrences(of: root, with: "")
                outDir = baseDir.appendingPathComponent(
                    rel.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                    isDirectory: true
                )
            } else {
                outDir = baseDir
            }
            try? FileManager.default.createDirectory(at: outDir,
                                                      withIntermediateDirectories: true)
            let dest = TranscodeService.outputURL(for: srcURL, preset: state.preset,
                                                    in: outDir)
            if state.skipExisting, FileManager.default.fileExists(atPath: dest.path) {
                continue
            }
            let job = TranscodeJob(source: srcURL, preset: state.preset, outputURL: dest)
            transcodeQueue.enqueue(job)
            enqueued += 1
        }
        convertSheet = nil
        if enqueued > 0 { transcodeSheetVisible = true }
    }

    /// Legacy single-asset entry point retained for the older toolbar
    /// menus that fire-and-forget. New call sites should use
    /// `openConvertDialog(preset:)`.
    func transcodeSelected(preset: TranscodePreset) {
        openConvertDialog(preset: preset)
    }

    // MARK: - Metadata clipboard (Kyno-parity Paste Metadata)

    /// Snapshot of one asset's user-editable metadata, captured by
    /// "Copy Metadata" and applied verbatim to every target asset by
    /// "Paste Metadata". Doesn't copy markers/subclips — those are
    /// clip-anchored on absolute timecodes and would land wrong on a
    /// different-duration target. Tags union additively (Kyno's
    /// behavior). Rating overrides.
    struct MetadataClipboard {
        let title: String?
        let description: String?
        let reel: String?
        let scene: String?
        let shot: String?
        let take: String?
        let angle: String?
        let camera: String?
        let audioChannelNames: String?
        let stars: Int?
        let colorLabel: String?
        let tags: [String]
        let sourceFilename: String
    }

    @Published var metadataClipboard: MetadataClipboard?

    func copyMetadataFromSelected() {
        guard let asset = selectedAsset, let id = asset.rowId else { return }
        let meta = (try? db.clipMetadata(assetId: id))
            ?? ClipMetadata(assetId: id, title: nil, description: nil,
                             reel: nil, scene: nil, shot: nil,
                             take: nil, angle: nil, camera: nil)
        let r: Rating? = (try? db.rating(assetId: id)) ?? nil
        let tagList = (try? db.tags(assetId: id).map(\.name)) ?? []
        metadataClipboard = MetadataClipboard(
            title: meta.title, description: meta.description,
            reel: meta.reel, scene: meta.scene, shot: meta.shot,
            take: meta.take, angle: meta.angle, camera: meta.camera,
            audioChannelNames: meta.audioChannelNames,
            stars: r?.stars, colorLabel: r?.colorLabel,
            tags: tagList,
            sourceFilename: asset.filename
        )
    }

    @discardableResult
    func pasteMetadataToSelected() -> Int {
        guard let clip = metadataClipboard else { return 0 }
        let targets: [Asset]
        if !selectedAssetPaths.isEmpty {
            targets = assets.filter { selectedAssetPaths.contains($0.path) }
        } else if let a = selectedAsset {
            targets = [a]
        } else { return 0 }
        var applied = 0
        for asset in targets {
            guard let id = asset.rowId else { continue }
            var meta = (try? db.clipMetadata(assetId: id))
                ?? ClipMetadata(assetId: id, title: nil, description: nil,
                                 reel: nil, scene: nil, shot: nil,
                                 take: nil, angle: nil, camera: nil)
            meta.assetId = id
            meta.title = clip.title
            meta.description = clip.description
            meta.reel = clip.reel
            meta.scene = clip.scene
            meta.shot = clip.shot
            meta.take = clip.take
            meta.angle = clip.angle
            meta.camera = clip.camera
            meta.audioChannelNames = clip.audioChannelNames
            try? db.setClipMetadata(meta)
            clipMetadataIndex[id] = meta
            if let stars = clip.stars {
                try? db.setRating(assetId: id, stars: stars,
                                    colorLabel: clip.colorLabel,
                                    description: nil)
                ratingIndex[asset.path] = stars
            }
            for tagName in clip.tags {
                _ = try? db.addTag(name: tagName, assetId: id)
            }
            applied += 1
        }
        refreshClipMetadataIndex()
        loadSelectionDetail()
        return applied
    }

    // MARK: - Find Lost Metadata (file-fingerprint reconnect)

    struct FindLostResult {
        var reconnected: [(filename: String, oldPath: String, newPath: String)] = []
        var stillMissing: [String] = []
        var skipped: [String] = []
    }

    /// Walk the catalogue for entries whose path no longer resolves;
    /// for each, search workspace roots for a file with matching
    /// (filename, sizeBytes) and rewrite the DB row's path. Linked
    /// metadata stays connected because everything is keyed off
    /// `assetId`, not path. Returns a per-asset outcome summary.
    func findLostMetadata() async -> FindLostResult {
        var result = FindLostResult()
        let fm = FileManager.default
        let dbAssets = (try? db.allAssets()) ?? []
        let missing = dbAssets.filter { !fm.fileExists(atPath: $0.path) }
        guard !missing.isEmpty else { return result }
        var index: [String: [URL]] = [:]
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey]
        for root in workspaceRoots {
            guard let walker = fm.enumerator(
                at: root, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in walker {
                let values = try? url.resourceValues(forKeys: keys)
                if values?.isDirectory == true { continue }
                let key = "\(url.lastPathComponent)|\(values?.fileSize ?? 0)"
                index[key, default: []].append(url)
            }
        }
        for asset in missing {
            let key = "\(asset.filename)|\(asset.sizeBytes)"
            let candidates = index[key] ?? []
            if candidates.count == 1, let hit = candidates.first {
                try? db.updateAssetPath(oldPath: asset.path, newPath: hit.path)
                result.reconnected.append(
                    (asset.filename, asset.path, hit.path)
                )
            } else if candidates.count > 1 {
                result.skipped.append(asset.path)
            } else {
                result.stillMissing.append(asset.path)
            }
        }
        self.assets = (try? db.allAssets()) ?? self.assets
        rebuildFolderTree()
        refreshClipMetadataIndex()
        loadSelectionDetail()
        return result
    }

    // MARK: - Play-all-selected (continuous playback)

    @Published var playAllQueue: [String] = []
    @Published var playAllIndex: Int = 0

    /// Queue the current multi-selection (or the visible list as
    /// fallback) for continuous play. ClipDetailInline observes
    /// AVPlayerItem.didPlayToEndTime and calls advancePlayAll().
    func startPlayAllSelected() {
        let queue: [String]
        if !selectedAssetPaths.isEmpty {
            queue = displayedAssets.map(\.path).filter {
                selectedAssetPaths.contains($0)
            }
        } else {
            queue = displayedAssets.map(\.path)
        }
        guard !queue.isEmpty else { return }
        playAllQueue = queue
        playAllIndex = 0
        selectedAssetPath = queue[0]
    }

    @discardableResult
    func advancePlayAll() -> Bool {
        guard !playAllQueue.isEmpty else { return false }
        playAllIndex = (playAllIndex + 1) % playAllQueue.count
        selectedAssetPath = playAllQueue[playAllIndex]
        return true
    }

    func stopPlayAll() {
        playAllQueue = []
        playAllIndex = 0
    }

    func setDescription(_ text: String) {
        guard let id = selectedAsset?.rowId else { return }
        let stars = rating?.stars ?? 0
        let color = rating?.colorLabel
        try? db.setRating(assetId: id, stars: stars,
                          colorLabel: color,
                          description: text.isEmpty ? nil : text)
        refreshRating()
    }
}
