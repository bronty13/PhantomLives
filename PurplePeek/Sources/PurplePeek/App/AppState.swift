import SwiftUI
import Combine
import Photos

/// Which files an import run targets.
enum ImportFilter: String, CaseIterable, Identifiable {
    case all
    case keepOnly
    case undecided
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:       return "All photos & videos"
        case .keepOnly:  return "Keep only"
        case .undecided: return "Undecided only"
        }
    }
}

/// Which on-disk files a bulk delete targets.
enum DeleteKind: Identifiable {
    case imported
    case skipped
    var id: String { self == .imported ? "imported" : "skipped" }
    var title: String { self == .imported ? "Delete Imported Files" : "Delete Skipped Files" }
    var blurb: String {
        self == .imported
            ? "These files have been imported to Photos. Deleting removes the on-disk copies."
            : "These files were marked Skip. Deleting removes them from disk."
    }
}

/// One undoable keep/skip action: the prior keep value of every file it touched (more than
/// one when the file is part of a duplicate group, since the decision propagates to all copies).
struct DecisionUndo: Equatable {
    struct Change: Equatable { let id: String; let previousKeep: Int? }
    let fileName: String
    let changes: [Change]
}

/// One rendered sidebar group: the implicit default group (`id == nil`, "Folders") or a
/// user-defined section, with its roots already in display order.
struct SidebarGroup: Identifiable, Equatable {
    let id: String?          // nil = the default "Folders" group
    let name: String
    let roots: [ScanRoot]
}

/// Live progress of an import run, published for the wizard.
struct ImportProgress {
    var total: Int
    var done: Int = 0
    var succeeded: Int = 0
    var failed: Int = 0
    var current: String = ""
    var finished: Bool = false
    var failures: [(name: String, reason: String)] = []
}

/// Single source of truth for the UI. All data mutations funnel through here (views never
/// touch `DatabaseService` directly), and every mutation is followed by a `reloadX()` that
/// republishes the affected slice.
///
/// Phase 1 establishes the full set of `@Published` slices and the launch sequence
/// (backup-on-launch → reload). Discovery, decisions, import, and delete land in later
/// phases as methods on this class.
@MainActor
final class AppState: ObservableObject {

    // MARK: - Mode
    @Published var appMode: AppMode = .folderBrowse

    // MARK: - Data slices
    @Published var scanRoots: [ScanRoot] = []
    @Published var sidebarSections: [SidebarSection] = []
    @Published var mediaFiles: [MediaFile] = []
    @Published var keywords: [Keyword] = []

    // file_id → its sorted keyword names, for the whole store. Bulk-loaded once (the grid would
    // otherwise need a per-cell DB hit) and refreshed on any keyword change. Files with no
    // keywords are simply absent. Drives the per-item tag labels and the "Tagged only" filter.
    @Published private(set) var fileKeywordNames: [String: [String]] = [:]

    // Derived views, cached (recomputed only when inputs change — not per render). For a
    // 65k-item root these are O(n)/O(n·depth) to build, so recomputing them on every
    // SwiftUI body evaluation was the main source of large-library lag.
    @Published private(set) var visibleMediaFiles: [MediaFile] = []
    @Published private(set) var previewQueue: [MediaFile] = []
    @Published private(set) var folderTree: FolderTreeNode?
    // Cheap flags for toolbar enable-state (so the Clean Up menu doesn't filter 65k per render).
    @Published private(set) var hasDeletableImported = false
    @Published private(set) var hasDeletableSkipped = false

    // Metadata for the currently selected file (loaded on selection).
    @Published var selectedKeywordIds: Set<String> = []
    @Published var selectedAlbums: [String] = []

    // Album names read from the Photos library (for the album picker). Loaded on demand.
    @Published var photosAlbumNames: [String] = []
    @Published var isLoadingPhotosAlbums = false
    private var loadedPhotosAlbums = false

    // MARK: - Selection
    @Published var selectedRootPath: String? {
        didSet { if selectedRootPath != oldValue { updateFolderWatch() } }
    }
    @Published var selectedFolderPath: String? {  // nil ⇒ show the whole root
        didSet { if selectedFolderPath != oldValue { recomputeDerived() } }
    }
    @Published var selectedFileId: String?
    @Published var previewIndex: Int = 0
    /// Decision lens for the Folder grid (default: show everything).
    @Published var gridDecisionFilter: DecisionFilter = .all {
        didSet { if gridDecisionFilter != oldValue { recomputeDerived() } }
    }
    /// Decision lens for Preview mode (default: triage the undecided; switch to Decided/Kept/
    /// Skipped to review items you've already decided).
    @Published var previewDecisionFilter: DecisionFilter = .undecided {
        didSet { if previewDecisionFilter != oldValue { recomputeDerived() } }
    }
    /// When on, the Folder grid shows only items that have at least one keyword/tag — pairs with
    /// the decision lens so you can surface the tagged items among those you've already decided.
    @Published var showTaggedOnly: Bool = false {
        didSet { if showTaggedOnly != oldValue { recomputeDerived() } }
    }

    // MARK: - Decision undo
    /// Recent keep/skip changes, newest last. The Undo control reverts the most recent one.
    @Published private(set) var decisionUndoStack: [DecisionUndo] = []
    var canUndoDecision: Bool { !decisionUndoStack.isEmpty }
    /// Filename of the change Undo would revert (for the button tooltip).
    var lastDecisionName: String? { decisionUndoStack.last?.fileName }

    // MARK: - Scan progress
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0
    @Published var scanMessage: String = ""

    // MARK: - Import
    @Published var importProgress: ImportProgress?

    /// Path to exiftool if installed (enables embedding title/caption/keywords into imports).
    let exiftoolPath: String?
    /// Path to osxphotos if installed (enables importing the Photos keyword vocabulary).
    let osxphotosPath: String?
    @Published var isImportingKeywords = false

    // MARK: - Status / errors
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    // MARK: - Sub-stores / services
    let settingsStore = SettingsStore()
    /// Concrete local store — always used for local-only ops (scanning, dedup hashing, sidebar
    /// sections, keyword *vocabulary*, scan-root management), regardless of mode.
    private let db = DatabaseService.shared
    /// The active data source for the reviewable set (roots/items) + decision writes. Points at
    /// `db` in local mode, or a `RemotePeekDataSource` when connected to a PeekServer. Rebuilt by
    /// `rebuildDataSource()` at init and whenever the connection settings change.
    private var dataSource: DataSource = DatabaseService.shared
    /// True when connected to a PeekServer (roots/items/decisions are remote).
    var isRemote: Bool { !(dataSource is DatabaseService) }
    /// The live PeekServer client in remote mode (nil locally) — for media rendering + import-pull.
    var peekClient: PeekServerClient? { (dataSource as? RemotePeekDataSource)?.client }
    /// Handle for rendering PeekServer media by id (nil in local mode).
    var peekMediaProvider: PeekMediaProvider? { peekClient?.mediaProvider }
    private var settingsObserver: AnyCancellable?

    /// FSEvents watcher for the selected scan root (auto-rescan). Created lazily; only active
    /// while `autoRescanEnabled` is on and a root is selected (see `updateFolderWatch`).
    private lazy var folderWatch = FolderWatchService { [weak self] in
        Task { @MainActor in self?.handleFolderChange() }
    }

    // MARK: - Settings convenience
    var settings: AppSettings {
        get { settingsStore.settings }
        set { settingsStore.settings = newValue }
    }

    var currentTheme: AppTheme { AppTheme.named(settings.themeName) }

    var preferredColorScheme: ColorScheme? {
        switch settings.appearance {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }

    // MARK: - Lifecycle

    init() {
        exiftoolPath = MetadataStagingService.locateExiftool()
        osxphotosPath = PhotosKeywordImporter.locate()
        // Bubble nested settings changes up so views observing AppState (theme, appearance,
        // default mode) re-render live.
        settingsObserver = settingsStore.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            self.objectWillChange.send()
            // `objectWillChange` fires in willSet (before `settings` is assigned), so react on
            // the next tick to read the new values — honors live folder-watch and de-dup toggles.
            Task { @MainActor in
                self.updateFolderWatch()
                self.rebuildDuplicateIndex()
                self.recomputeDerived()
            }
        }
        // PhantomLives auto-backup-on-launch standard — runs first, never throws.
        BackupService.runOnLaunchIfDue(settingsStore: settingsStore)
        // Honor the user's default mode for a fresh launch.
        appMode = settings.defaultMode
        if settings.scanRootAutoCleanupEnabled { cleanupOldScanRoots(announce: false) }
        rebuildDataSource()
        reloadAll()
    }

    /// Point `dataSource` at a PeekServer (remote mode) or back at local GRDB, from current
    /// settings + Keychain. Call after changing the connection, then `reloadAll()` to refetch.
    func rebuildDataSource() {
        if settings.peekServerEnabled, !settings.peekServerHost.isEmpty {
            let conn = PeekServerConnection(host: settings.peekServerHost,
                                            port: settings.peekServerPort,
                                            user: settings.peekServerUser)
            let pw = KeychainStore.password(account: conn.account) ?? ""
            dataSource = RemotePeekDataSource(connection: conn, password: pw)
        } else {
            dataSource = db
        }
        // Thumbnails render from the server (or local QuickLook) depending on mode.
        let provider = peekMediaProvider
        Task { await ThumbnailService.shared.setRemoteProvider(provider) }
        // A mode change invalidates the current selection's media set.
        selectedRootPath = nil
        selectedFolderPath = nil
    }

    /// Apply an edited PeekServer connection: persist the password to the Keychain, flip settings,
    /// rebuild the data source, and refetch everything. Pass an empty host (or enabled=false) to
    /// return to local mode.
    func applyPeekServerConnection(enabled: Bool, host: String, port: Int, user: String, password: String) {
        var s = settings
        s.peekServerEnabled = enabled
        s.peekServerHost = host
        s.peekServerPort = port
        s.peekServerUser = user
        settings = s
        if enabled, !host.isEmpty {
            let conn = PeekServerConnection(host: host, port: port, user: user)
            if !password.isEmpty { KeychainStore.setPassword(password, account: conn.account) }
        }
        rebuildDataSource()
        reloadAll()
    }

    // MARK: - Reload helpers

    func reloadAll() {
        reloadScanRoots()
        reloadSections()
        reloadKeywords()
        reloadMediaFiles()
    }

    func reloadScanRoots() {
        // Fire-and-forget async so the same call works for both local (runs inline on the main
        // actor) and remote (suspends on URLSession) data sources; @Published mutation stays on main.
        Task {
            do { scanRoots = try await dataSource.fetchAllScanRoots() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func reloadSections() {
        do { sidebarSections = try db.fetchAllSections() }
        catch { errorMessage = error.localizedDescription }
    }

    func reloadKeywords() {
        do { keywords = try db.fetchAllKeywords() }
        catch { errorMessage = error.localizedDescription }
        reloadFileKeywordNames()
    }

    /// Refresh the bulk file→keyword-names map (cheap; one query). Call after any keyword
    /// assignment change so the grid's tag labels and "Tagged only" filter stay in sync.
    func reloadFileKeywordNames() {
        Task {
            do { fileKeywordNames = try await dataSource.allFileKeywordNames() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    /// Sorted keyword names assigned to `id` (empty when untagged) — read by the grid/list cells.
    func keywordNames(for id: String) -> [String] { fileKeywordNames[id] ?? [] }

    /// Whether `id` has at least one keyword/tag.
    func isTagged(_ id: String) -> Bool { !(fileKeywordNames[id]?.isEmpty ?? true) }

    func reloadMediaFiles() {
        guard let root = selectedRootPath else {
            mediaFiles = []
            folderTree = nil
            recomputeDerived()
            return
        }
        Task {
            do {
                let files = try await dataSource.fetchMediaFiles(scanRoot: root)
                // Guard against a slow fetch landing after the user switched roots — otherwise a
                // large/slow root's results could clobber the now-selected root (async race that
                // only appears once fetches have real network latency).
                guard selectedRootPath == root else { return }
                mediaFiles = files
            } catch {
                guard selectedRootPath == root else { return }
                errorMessage = error.localizedDescription
            }
            guard selectedRootPath == root else { return }
            rebuildIndex()
            rebuildDuplicateIndex()
            rebuildFolderTree()
            recomputeDerived()
        }
    }

    // MARK: - Duplicate index (exact-content groups)

    /// repId → all member ids (including the representative); built from `contentHash`.
    private var dupMembersByRep: [String: [String]] = [:]
    /// any member id → its group's representative id.
    private var dupRepByMember: [String: String] = [:]
    /// non-representative members — collapsed out of the grid/preview so a group shows once.
    private var hiddenDuplicateIds: Set<String> = []

    /// Number of copies in `id`'s duplicate group (1 if it isn't a duplicate). Only the
    /// representative is shown, so the grid reads this off the representative for its badge.
    func duplicateCount(for id: String) -> Int { dupMembersByRep[id]?.count ?? 1 }

    /// Every file id sharing `id`'s exact content (just `[id]` when it has no duplicates or
    /// de-dup is off) — the set a keep/skip decision propagates across.
    private func duplicateGroupMembers(_ id: String) -> [String] {
        guard let rep = dupRepByMember[id], let members = dupMembersByRep[rep] else { return [id] }
        return members
    }

    /// Group non-deleted files by content hash; for each group of 2+, pick a representative
    /// (an already-imported copy if any, else the lexicographically-first path) and collapse
    /// the rest. No-op when de-dup is disabled — every file then stands alone.
    private func rebuildDuplicateIndex() {
        dupMembersByRep = [:]
        dupRepByMember = [:]
        hiddenDuplicateIds = []
        guard settings.dedupeEnabled else { return }

        let hashed = mediaFiles.filter { $0.deletedAt == nil && ($0.contentHash?.isEmpty == false) }
        for (_, group) in Dictionary(grouping: hashed, by: { $0.contentHash! }) where group.count > 1 {
            let rep = group.sorted { a, b in
                let ai = a.importedAt != nil, bi = b.importedAt != nil
                return ai != bi ? ai : a.filePath < b.filePath
            }.first!
            let ids = group.map(\.id)
            dupMembersByRep[rep.id] = ids
            for m in group {
                dupRepByMember[m.id] = rep.id
                if m.id != rep.id { hiddenDuplicateIds.insert(m.id) }
            }
        }
    }

    /// id → position in `mediaFiles`, so `patchLocal` is O(1) even on huge roots. Valid
    /// between reloads because `patchLocal` mutates in place and never reorders.
    private var indexById: [String: Int] = [:]
    private func rebuildIndex() {
        indexById = Dictionary(mediaFiles.enumerated().map { ($0.element.id, $0.offset) },
                               uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Derived views (cached; recomputed only when inputs change)

    /// Rebuild the sidebar folder tree. O(n·depth) — only call when the file set or paths
    /// change (scan, root select, delete), NOT on per-item decisions.
    private func rebuildFolderTree() {
        guard let root = selectedRootPath else { folderTree = nil; return }
        folderTree = FolderTree.build(rootPath: root, files: mediaFiles)
    }

    /// Recompute the cached derived collections + toolbar flags in a single O(n) pass over
    /// `mediaFiles`. Call after any change to the file set, folder selection, or show-all.
    private func recomputeDerived() {
        let folder = selectedFolderPath
        let gridFilter = gridDecisionFilter
        let previewFilter = previewDecisionFilter
        let taggedOnly = showTaggedOnly
        var visible: [MediaFile] = []
        var preview: [MediaFile] = []
        var deletableImported = false
        var deletableSkipped = false

        for file in mediaFiles where file.deletedAt == nil {
            if file.importedAt != nil { deletableImported = true }
            if file.keepDecision == false { deletableSkipped = true }

            // Collapse exact duplicates: only the representative appears in the grid/preview
            // (the flags above still counted the hidden copies, so bulk delete reaches them).
            if hiddenDuplicateIds.contains(file.id) { continue }

            // Grid: optional folder narrowing + the grid's decision lens + optional tagged-only.
            if gridFilter.matches(file), !(taggedOnly && (fileKeywordNames[file.id]?.isEmpty ?? true)) {
                if let folder {
                    let dir = (file.filePath as NSString).deletingLastPathComponent
                    if dir == folder || file.filePath.hasPrefix(folder + "/") { visible.append(file) }
                } else {
                    visible.append(file)
                }
            }
            // Preview: whole-root, the preview's decision lens + optional tagged-only.
            if previewFilter.matches(file), !(taggedOnly && (fileKeywordNames[file.id]?.isEmpty ?? true)) {
                preview.append(file)
            }
        }

        visibleMediaFiles = visible
        previewQueue = preview
        hasDeletableImported = deletableImported
        hasDeletableSkipped = deletableSkipped
        clampPreviewIndex()
    }

    /// The file currently shown in Preview mode (index clamped into the cached queue).
    var currentPreviewFile: MediaFile? {
        guard !previewQueue.isEmpty else { return nil }
        return previewQueue[min(max(previewIndex, 0), previewQueue.count - 1)]
    }

    // MARK: - Preview navigation

    func startPreview() {
        previewIndex = 0
        syncSelectionToPreview()
    }

    func nextPreview() {
        let count = previewQueue.count
        guard count > 0 else { return }
        previewIndex = min(previewIndex + 1, count - 1)
        syncSelectionToPreview()
    }

    func prevPreview() {
        previewIndex = max(previewIndex - 1, 0)
        syncSelectionToPreview()
    }

    private func clampPreviewIndex() {
        let count = previewQueue.count
        previewIndex = count == 0 ? 0 : min(max(previewIndex, 0), count - 1)
    }

    /// Keep the shared selection (used by the keyword/album popovers) pointed at the current
    /// preview file, loading its keyword/album metadata.
    private func syncSelectionToPreview() {
        selectFile(currentPreviewFile?.id)
    }

    /// Apply a keep/skip decision to the current preview item and advance. `setKeep`
    /// recomputes the queue: if the decision dropped the item out of the current filter
    /// (e.g. Undecided), clamping already lands us on the next one; if the item stays in the
    /// queue (e.g. Decided/All/Kept/Skipped review), we advance explicitly.
    func decidePreview(keep: Bool) {
        guard let file = currentPreviewFile else { return }
        let id = file.id
        setKeep(id, keep)   // recomputes previewQueue + clamps index
        if currentPreviewFile?.id == id {
            nextPreview()           // still in queue → step forward
        } else {
            syncSelectionToPreview() // dropped out → clamp already advanced; load new current
        }
    }

    /// Toggle favorite on the current preview item (does not advance).
    func toggleFavoritePreview() {
        guard let file = currentPreviewFile else { return }
        setFavorite(file.id, !file.isFavorite)
    }

    /// Toggle hidden on the current preview item (does not advance).
    func toggleHiddenPreview() {
        guard let file = currentPreviewFile else { return }
        setHidden(file.id, !file.isHidden)
    }

    // MARK: - Scanning

    /// Discover media under `url` (recursively) and persist it. Discovery runs off the main
    /// actor; persistence happens here on the main actor in 500-row batches so the UI stays
    /// responsive. If `url` is a file, its parent directory is scanned.
    func scanFolder(_ url: URL) {
        guard !isScanning else { return }

        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let dir = isDir ? url : url.deletingLastPathComponent()
        let rootPath = dir.standardizedFileURL.path

        isScanning = true
        scanProgress = 0
        scanMessage = "Scanning \(dir.lastPathComponent)…"
        errorMessage = nil

        let excludeName = settings.topLevelExcludeName
        Task {
            let scanned = await Task.detached(priority: .userInitiated) {
                MediaDiscoveryService.scan(root: dir, excludeTopLevelName: excludeName)
            }.value
            await self.persistScan(rootPath: rootPath, files: scanned)
        }
    }

    /// Re-scan the currently selected root in place. Same machinery as a fresh scan, so the
    /// upsert preserves every decision and the missing-files sweep reconciles deletions.
    func rescanSelectedRoot() {
        guard let root = selectedRootPath else { return }
        scanFolder(URL(fileURLWithPath: root))
    }

    /// Re-scan a specific root in place — the sidebar row's right-click "Refresh". Same machinery
    /// as the toolbar refresh, but targeted at `path` regardless of which root is selected, so
    /// right-clicking any folder re-scans that one (decision-preserving upsert + missing sweep).
    func rescanRoot(_ path: String) {
        scanFolder(URL(fileURLWithPath: path))
    }

    /// FSEvents callback target: auto-rescan the selected root when its contents change on
    /// disk. Guarded so an in-flight scan (or the scan's own writes, which the export folders
    /// can trigger) doesn't kick off a re-entrant pass.
    private func handleFolderChange() {
        guard settings.autoRescanEnabled, !isScanning, selectedRootPath != nil else { return }
        rescanSelectedRoot()
    }

    /// Start/stop the FSEvents watcher to match the current setting + selection.
    private func updateFolderWatch() {
        if settings.autoRescanEnabled, let root = selectedRootPath {
            folderWatch.start(path: root)
        } else {
            folderWatch.stop()
        }
    }

    private func persistScan(rootPath: String, files: [ScannedFile]) async {
        let now = BackupService.isoNow()
        var missingCount = 0
        do {
            try db.ensureScanRoot(path: rootPath, now: now)
            var done = 0
            let total = max(files.count, 1)
            for chunk in files.chunked(into: 500) {
                try db.upsertScannedFiles(chunk, scanRoot: rootPath, now: now)
                done += chunk.count
                scanProgress = Double(done) / Double(total)
                scanMessage = "Saving \(done)/\(files.count)…"
                await Task.yield()
            }
            // Reconcile deletions: anything not seen this pass (older watermark) is now missing.
            missingCount = try db.markMissingFiles(scanRoot: rootPath, now: now)
            try db.updateScanRootStats(path: rootPath, totalFiles: files.count, now: now)
        } catch {
            errorMessage = error.localizedDescription
        }

        selectedRootPath = rootPath
        selectedFolderPath = nil
        selectedFileId = nil
        decisionUndoStack = []
        reloadScanRoots()
        reloadMediaFiles()

        // The scan itself is finished and the grid is populated, so release the scanning gate
        // NOW — the toolbar Refresh button and auto-rescan are disabled while `isScanning` is
        // true, and exact-duplicate detection (next) reads every file's FULL content (sha256),
        // which is minutes-to-hours on slow/remote storage like the REDONE archive. Holding the
        // gate across hashing made Refresh appear permanently disabled. Hashing now runs in the
        // background and surfaces its groups when ready (same path as a freshly-selected root).
        isScanning = false
        scanProgress = 1
        var base = "Scanned \(files.count) item\(files.count == 1 ? "" : "s") in \((rootPath as NSString).lastPathComponent)."
        if missingCount > 0 { base += " \(missingCount) now missing from disk." }
        statusMessage = base

        // Exact-duplicate detection (size-prefiltered content hashing), if enabled — off the
        // `isScanning` gate so it can't freeze the UI on slow storage.
        hashSelectedRootIfNeeded(rootPath)
    }

    /// Select a scan root (from the sidebar) and load its files.
    func selectRoot(_ path: String) {
        selectedRootPath = path
        selectedFolderPath = nil
        selectedFileId = nil
        selectedKeywordIds = []
        selectedAlbums = []
        decisionUndoStack = []   // undo is scoped to the loaded root
        reloadMediaFiles()
        hashSelectedRootIfNeeded(path)
    }

    private var hashingInProgress: Set<String> = []

    /// Hash a root's not-yet-hashed, size-collision candidates and store the results. Cheap
    /// when nothing's outstanding (the size pre-filter + the NULL-hash filter make repeat calls
    /// near-free). Reads file bytes off the main actor. Does not reload — the caller does.
    private func computeAndStoreHashes(for root: String) async {
        guard settings.dedupeEnabled, !hashingInProgress.contains(root) else { return }
        let toHash = (try? db.pathsNeedingHash(scanRoot: root)) ?? []
        guard !toHash.isEmpty else { return }
        hashingInProgress.insert(root)
        defer { hashingInProgress.remove(root) }
        let hashed = await Task.detached(priority: .userInitiated) {
            toHash.compactMap { path in
                FileHashService.sha256(of: URL(fileURLWithPath: path)).map { (path: path, hash: $0) }
            }
        }.value
        try? db.setContentHashes(hashed)
    }

    /// Hash a freshly-selected root in the background (covers libraries scanned before de-dup
    /// existed, or after the toggle is turned on), then reload to surface the groups.
    private func hashSelectedRootIfNeeded(_ path: String) {
        guard settings.dedupeEnabled else { return }
        Task {
            await computeAndStoreHashes(for: path)
            guard selectedRootPath == path else { return }   // user moved on; don't clobber
            reloadMediaFiles()
            let sets = dupMembersByRep.count
            if sets > 0 { statusMessage = "\(sets) duplicate set\(sets == 1 ? "" : "s") found." }
        }
    }

    // MARK: - File selection + decisions

    var selectedFile: MediaFile? {
        guard let id = selectedFileId else { return nil }
        return mediaFiles.first { $0.id == id }
    }

    /// Select a file and load its keyword/album metadata for the detail panel.
    func selectFile(_ id: String?) {
        selectedFileId = id
        guard let id else { selectedKeywordIds = []; selectedAlbums = []; return }
        // Keyword IDs are a local-vocabulary concept (remote keyword tagging lands in P5); albums are
        // per-file review state → through the active data source.
        do { selectedKeywordIds = Set(try db.keywordIds(forFile: id)) }
        catch { errorMessage = error.localizedDescription }
        Task {
            do { selectedAlbums = try await dataSource.albums(forFile: id) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    /// Mutate one row in `mediaFiles` in place — republishes for the grid badge without a
    /// full refetch (which would disturb a focused text field in the detail panel).
    private func patchLocal(_ id: String, _ transform: (inout MediaFile) -> Void) {
        // Update the master array (O(1) via the index) …
        if let i = indexById[id], i < mediaFiles.count, mediaFiles[i].id == id {
            transform(&mediaFiles[i])
        } else if let i = mediaFiles.firstIndex(where: { $0.id == id }) {
            transform(&mediaFiles[i])
        } else {
            return
        }
        // … and the cached derived copies, so currentPreviewFile / the grid reflect
        // field changes (title/caption/favorite/hidden) without a full recompute. Without
        // this, the cached previewQueue stays stale and navigating back shows old text.
        if let i = previewQueue.firstIndex(where: { $0.id == id }) { transform(&previewQueue[i]) }
        if let i = visibleMediaFiles.firstIndex(where: { $0.id == id }) { transform(&visibleMediaFiles[i]) }
    }

    func setKeep(_ id: String, _ keep: Bool?) {
        let now = BackupService.isoNow()
        // A decision on one copy applies to every exact duplicate — decide once, recorded for all.
        let members = duplicateGroupMembers(id)
        let value = keep.map { $0 ? 1 : 0 }

        // Record the prior values of every affected member so the action undoes as a unit.
        let changes = members.compactMap { mid in
            mediaFiles.first(where: { $0.id == mid }).map { DecisionUndo.Change(id: mid, previousKeep: $0.keep) }
        }
        if let name = mediaFiles.first(where: { $0.id == id })?.fileName, !changes.isEmpty {
            decisionUndoStack.append(DecisionUndo(fileName: name, changes: changes))
            if decisionUndoStack.count > 50 { decisionUndoStack.removeFirst() }
        }

        // Optimistic: patch the UI now, persist in the background. On failure, resync from source.
        for mid in members { patchLocal(mid) { $0.keepDecision = keep } }
        recomputeDerived()   // keep affects the undecided queue + grid badge
        Task {
            do { for mid in members { try await dataSource.updateKeep(id: mid, keep: value, now: now) } }
            catch { errorMessage = error.localizedDescription; reloadMediaFiles() }
        }

        // Keeping an audio file copies it to the Kept Audio Export folder (once).
        if keep == true, let f = mediaFiles.first(where: { $0.id == id }),
           f.mediaType == .audio, f.exportedAt == nil {
            exportAudio(id)
        }
    }

    /// Revert the most recent keep/skip change, restoring that file's prior decision. In
    /// Preview mode it also jumps back to the affected item when it's in the current queue.
    func undoLastDecision() {
        guard let last = decisionUndoStack.popLast() else { return }
        let now = BackupService.isoNow()
        for change in last.changes {                          // restore every affected copy (optimistic)
            patchLocal(change.id) { $0.keep = change.previousKeep }
        }
        recomputeDerived()
        if let firstId = last.changes.first?.id {
            selectFile(firstId)
            if appMode == .preview, let idx = previewQueue.firstIndex(where: { $0.id == firstId }) {
                previewIndex = idx
            }
        }
        statusMessage = "Undid decision for \(last.fileName)."
        Task {
            do { for change in last.changes { try await dataSource.updateKeep(id: change.id, keep: change.previousKeep, now: now) } }
            catch { errorMessage = error.localizedDescription; reloadMediaFiles() }
        }
    }

    func setFavorite(_ id: String, _ value: Bool) {
        let now = BackupService.isoNow()
        let prev = mediaFiles.first(where: { $0.id == id })?.isFavorite ?? !value
        patchLocal(id) { $0.isFavorite = value }
        recomputeDerived()   // refresh the cached copy so the grid heart badge updates
        Task {
            do { try await dataSource.updateFavorite(id: id, isFavorite: value, now: now) }
            catch { errorMessage = error.localizedDescription; patchLocal(id) { $0.isFavorite = prev }; recomputeDerived() }
        }
    }

    func setHidden(_ id: String, _ value: Bool) {
        let now = BackupService.isoNow()
        let prev = mediaFiles.first(where: { $0.id == id })?.isHidden ?? !value
        patchLocal(id) { $0.isHidden = value }
        recomputeDerived()   // refresh the cached copy so the grid hidden badge updates
        Task {
            do { try await dataSource.updateHidden(id: id, isHidden: value, now: now) }
            catch { errorMessage = error.localizedDescription; patchLocal(id) { $0.isHidden = prev }; recomputeDerived() }
        }
    }

    func setTitle(_ id: String, _ value: String?) {
        let now = BackupService.isoNow()
        let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = (clean?.isEmpty ?? true) ? nil : clean
        let prev = mediaFiles.first(where: { $0.id == id })?.title
        patchLocal(id) { $0.title = stored }
        Task {
            do { try await dataSource.updateTitle(id: id, title: stored, now: now) }
            catch { errorMessage = error.localizedDescription; patchLocal(id) { $0.title = prev } }
        }
    }

    func setCaption(_ id: String, _ value: String?) {
        let now = BackupService.isoNow()
        let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = (clean?.isEmpty ?? true) ? nil : clean
        let prev = mediaFiles.first(where: { $0.id == id })?.caption
        patchLocal(id) { $0.caption = stored }
        Task {
            do { try await dataSource.updateCaption(id: id, caption: stored, now: now) }
            catch { errorMessage = error.localizedDescription; patchLocal(id) { $0.caption = prev } }
        }
    }

    // MARK: - Keywords

    @discardableResult
    func createKeyword(name: String) -> Keyword? {
        let now = BackupService.isoNow()
        do {
            let kw = try db.createKeyword(name: name, now: now)
            reloadKeywords()
            return kw
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    /// Seed the local keyword store from the Photos library via osxphotos.
    func importKeywordsFromPhotos() {
        guard let path = osxphotosPath else {
            errorMessage = "osxphotos isn't installed (pipx install osxphotos)."
            return
        }
        guard !isImportingKeywords else { return }
        isImportingKeywords = true
        Task {
            do {
                let names = try await Task.detached(priority: .userInitiated) {
                    try PhotosKeywordImporter.fetchKeywords(osxphotosPath: path)
                }.value
                let added = try db.importKeywords(names: names, source: "photos", now: BackupService.isoNow())
                reloadKeywords()
                statusMessage = "Imported \(added) new keyword\(added == 1 ? "" : "s") from Photos (\(names.count) found)."
            } catch {
                errorMessage = "Couldn't read Photos keywords: \(error.localizedDescription)"
            }
            isImportingKeywords = false
        }
    }

    func deleteKeyword(_ id: String) {
        do {
            try db.deleteKeyword(id: id)
            selectedKeywordIds.remove(id)
            reloadKeywords()
        } catch { errorMessage = error.localizedDescription }
    }

    func usageCount(forKeyword id: String) -> Int {
        (try? db.keywordUsageCount(keywordId: id)) ?? 0
    }

    /// Toggle a keyword on the selected file and persist.
    func toggleKeyword(_ keywordId: String) {
        guard let fileId = selectedFileId else { return }
        if selectedKeywordIds.contains(keywordId) {
            selectedKeywordIds.remove(keywordId)
        } else {
            selectedKeywordIds.insert(keywordId)
        }
        do {
            try db.setKeywords(fileId: fileId, keywordIds: Array(selectedKeywordIds))
            // Reflect the change in the bulk map so this item's tag label updates and the
            // "Tagged only" filter re-evaluates it (it may now enter or leave the grid).
            let names = selectedKeywordNames()
            fileKeywordNames[fileId] = names.isEmpty ? nil : names
            if showTaggedOnly { recomputeDerived() }
        } catch { errorMessage = error.localizedDescription }
    }

    /// The names of the currently selected keyword ids, sorted — keeps the bulk map's per-file
    /// entry consistent with `keywordNames(forFile:)` after an in-place toggle.
    private func selectedKeywordNames() -> [String] {
        keywords.filter { selectedKeywordIds.contains($0.id) }.map(\.name).sorted()
    }

    // MARK: - Albums

    func distinctAlbumNames() -> [String] {
        (try? db.distinctAlbumNames()) ?? []
    }

    /// Fetch the Photos library's album names once (the album picker calls this on open).
    /// First load may prompt for Photos access.
    func loadPhotosAlbumsIfNeeded(force: Bool = false) {
        guard force || (!loadedPhotosAlbums && !isLoadingPhotosAlbums) else { return }
        isLoadingPhotosAlbums = true
        Task {
            let names = await PhotoKitService.shared.fetchAlbumNames()
            photosAlbumNames = names
            loadedPhotosAlbums = true
            isLoadingPhotosAlbums = false
        }
    }

    func addAlbum(_ name: String) {
        guard let fileId = selectedFileId else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !selectedAlbums.contains(trimmed) else { return }
        selectedAlbums.append(trimmed)
        selectedAlbums.sort()
        let albums = selectedAlbums
        Task {
            do { try await dataSource.setAlbums(fileId: fileId, albumNames: albums) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func removeAlbum(_ name: String) {
        guard let fileId = selectedFileId else { return }
        selectedAlbums.removeAll { $0 == name }
        let albums = selectedAlbums
        Task {
            do { try await dataSource.setAlbums(fileId: fileId, albumNames: albums) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    // MARK: - Audio keep-export

    /// Copy a kept audio file into the Kept Audio Export folder (idempotent via exported_at).
    func exportAudio(_ id: String) {
        guard let f = mediaFiles.first(where: { $0.id == id }), f.mediaType == .audio else { return }
        let dir = settingsStore.resolvedKeptAudioPath
        let src = f.fileURL
        let name = f.fileName
        Task {
            do {
                _ = try await Task.detached(priority: .userInitiated) {
                    try AudioKeepService.export(source: src, to: dir)
                }.value
                let now = BackupService.isoNow()
                try db.markExported(id: id, now: now)
                patchLocal(id) { $0.exportedAt = now }
                statusMessage = "Exported \(name) to Kept Audio."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Photos import

    /// Files eligible for a Photos import under `filter` (photos/videos only, not yet
    /// imported, not deleted).
    func importCandidates(_ filter: ImportFilter) -> [MediaFile] {
        mediaFiles.filter { f in
            guard f.deletedAt == nil, f.importedAt == nil, f.mediaType.isImportableToPhotos else { return false }
            // De-dup-aware: only the representative of a duplicate group imports, so a kept
            // group lands in Photos once instead of N identical copies.
            if hiddenDuplicateIds.contains(f.id) { return false }
            switch filter {
            case .all:       return true
            case .keepOnly:  return f.keepDecision == true
            case .undecided: return f.keep == nil
            }
        }
    }

    /// Run a batched import. Photos are exiftool-staged (title/caption/keywords) when
    /// possible; videos import as-is. Favorite + albums are applied via PhotoKit.
    func runImport(filter: ImportFilter) {
        let candidates = importCandidates(filter)
        var prog = ImportProgress(total: candidates.count)
        importProgress = prog
        guard !candidates.isEmpty else { prog.finished = true; importProgress = prog; return }

        let exif = exiftoolPath
        Task {
            let authorized = await PhotoKitService.shared.requestAuthorization()
            guard authorized else {
                prog.done = candidates.count
                prog.failed = candidates.count
                prog.failures = candidates.map { ($0.fileName, "Photos access not granted") }
                prog.finished = true
                importProgress = prog
                return
            }
            await PhotoKitService.shared.beginRun()
            for file in candidates {
                prog.current = file.fileName
                importProgress = prog
                switch await importOneFile(file, exiftoolPath: exif) {
                case .success(let assetId):
                    let now = BackupService.isoNow()
                    try? db.markImported(id: file.id, assetId: assetId, now: now)
                    patchLocal(file.id) { $0.importedAt = now; $0.photosAssetId = assetId }
                    prog.succeeded += 1
                case .failure(let err):
                    prog.failed += 1
                    prog.failures.append((file.fileName, err.message))
                }
                prog.done += 1
                importProgress = prog
            }
            prog.finished = true
            importProgress = prog
            reloadMediaFiles()
        }
    }

    // NOTE: "Re-apply Metadata to Imported Items" was removed in the Tier-1 TCC change.
    // Its only mechanism was driving Photos via AppleScript ("control Photos"), which we
    // dropped along with the apple-events entitlement. Metadata now reaches Photos only by
    // embedding it into the file *before* import (the embed-then-import path), and PhotoKit
    // offers no way to edit an already-imported asset's title/caption/keywords — so there is
    // no supported way to re-push metadata to items already in the library. Set metadata
    // before importing. (See docs/tcc-prompt-research-spike.md.)

    /// Import a single file (detail-panel button).
    func importSingle(_ id: String) {
        guard let file = mediaFiles.first(where: { $0.id == id }),
              file.mediaType.isImportableToPhotos, file.importedAt == nil else { return }
        let exif = exiftoolPath
        Task {
            let authorized = await PhotoKitService.shared.requestAuthorization()
            guard authorized else { errorMessage = "Photos access not granted."; return }
            await PhotoKitService.shared.beginRun()
            switch await importOneFile(file, exiftoolPath: exif) {
            case .success(let assetId):
                let now = BackupService.isoNow()
                try? db.markImported(id: id, assetId: assetId, now: now)
                patchLocal(id) { $0.importedAt = now; $0.photosAssetId = assetId }
                recomputeDerived()
                statusMessage = "Imported \(file.fileName) to Photos."
            case .failure(let err):
                errorMessage = "Import failed: \(err.message)"
            }
        }
    }

    /// Stage (embed title/caption/keywords into a copy) + import one file. Photos read these
    /// fields from the file on import — XMP/IPTC for photos, the QuickTime `Keys:` group for
    /// videos — so no post-import AppleScript is needed. Returns the asset id or an error.
    private func importOneFile(_ file: MediaFile, exiftoolPath: String?) async -> Result<String, ImportFailure> {
        let type: PHAssetResourceType = (file.mediaType == .photo) ? .photo : .video
        let albums = (try? db.albums(forFile: file.id)) ?? []
        let keywords = (try? db.keywordNames(forFile: file.id)) ?? []
        let hasMetadata = (file.title?.isEmpty == false) || (file.caption?.isEmpty == false) || !keywords.isEmpty

        // Embed title/caption/keywords into a staged copy so Photos ingests them on import —
        // photos via XMP/IPTC, videos via the QuickTime `Keys:` group. PhotoKit can't write
        // these fields directly; this is the only path, and it needs no AppleScript / no
        // "control Photos" automation prompt (see docs/tcc-prompt-research-spike.md). Only
        // files that actually carry metadata are staged (copied); the rest import in place.
        var importURL = file.fileURL
        var stagedURL: URL?
        if hasMetadata, let ep = exiftoolPath {
            let kind: MetadataStagingService.Kind = (file.mediaType == .photo) ? .photo : .video
            let meta = MetadataStagingService.Metadata(title: file.title, caption: file.caption, keywords: keywords)
            let original = file.fileURL
            stagedURL = try? await Task.detached(priority: .userInitiated) {
                try MetadataStagingService.stage(original: original, metadata: meta, exiftoolPath: ep, kind: kind)
            }.value
            if let stagedURL { importURL = stagedURL }
        }

        do {
            let assetId = try await PhotoKitService.shared.importOne(
                url: importURL, type: type, isFavorite: file.isFavorite, isHidden: file.isHidden, albums: albums
            )
            if let stagedURL { try? FileManager.default.removeItem(at: stagedURL) }
            return .success(assetId)
        } catch {
            if let stagedURL { try? FileManager.default.removeItem(at: stagedURL) }
            return .failure(ImportFailure(message: error.localizedDescription))
        }
    }

    // MARK: - Delete on disk

    /// Files eligible for a bulk delete of `kind` (not already deleted), within the loaded
    /// root.
    func deletionCandidates(_ kind: DeleteKind) -> [MediaFile] {
        mediaFiles.filter { f in
            guard f.deletedAt == nil else { return false }
            switch kind {
            case .imported: return f.importedAt != nil
            case .skipped:  return f.keepDecision == false
            }
        }
    }

    /// Delete the given files from disk (Trash or permanent) and mark the succeeded ones.
    func performDelete(_ files: [MediaFile], permanently: Bool) {
        let urlToId = Dictionary(uniqueKeysWithValues: files.map { ($0.fileURL, $0.id) })
        let urls = files.map { $0.fileURL }
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                DeleteService.deleteFiles(urls, permanently: permanently)
            }.value
            let now = BackupService.isoNow()
            for url in outcome.succeeded {
                if let id = urlToId[url] {
                    try? db.markDeleted(id: id, now: now)
                    patchLocal(id) { $0.deletedAt = now }
                }
            }
            if outcome.failed.isEmpty {
                statusMessage = "Deleted \(outcome.succeeded.count) file\(outcome.succeeded.count == 1 ? "" : "s")."
            } else {
                errorMessage = "Deleted \(outcome.succeeded.count); \(outcome.failed.count) failed."
            }
            if selectedFile?.deletedAt != nil { selectedFileId = nil }
            reloadMediaFiles()
        }
    }

    // MARK: - Scan-root management

    func deleteScanRoot(_ path: String) {
        do {
            try db.deleteScanRoot(path: path)
            if selectedRootPath == path { selectedRootPath = nil; selectedFolderPath = nil; selectedFileId = nil; mediaFiles = [] }
            reloadScanRoots()
        } catch { errorMessage = error.localizedDescription }
    }

    func renameScanRoot(_ path: String, label: String?) {
        let clean = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try db.updateScanRootLabel(path: path, label: (clean?.isEmpty ?? true) ? nil : clean)
            reloadScanRoots()
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Sidebar grouping + ordering

    /// Total media items across all scan roots (the sidebar footer count).
    var totalItemCount: Int { scanRoots.reduce(0) { $0 + $1.totalFiles } }

    /// The sidebar's groups in display order: the default "Folders" group first, then each
    /// user-defined section. Roots within a group are ordered by `sortOrder` (recency breaks
    /// ties). Built from the already-loaded `scanRoots` + `sidebarSections` — no DB hit.
    var sidebarGroups: [SidebarGroup] {
        let bySection = Dictionary(grouping: scanRoots) { $0.sectionId }
        func ordered(_ roots: [ScanRoot]) -> [ScanRoot] {
            roots.sorted { a, b in
                a.sortOrder != b.sortOrder ? a.sortOrder < b.sortOrder : a.lastScannedAt > b.lastScannedAt
            }
        }
        var groups = [SidebarGroup(id: nil, name: "Folders", roots: ordered(bySection[nil] ?? []))]
        for section in sidebarSections {
            groups.append(SidebarGroup(id: section.id, name: section.name, roots: ordered(bySection[section.id] ?? [])))
        }
        return groups
    }

    @discardableResult
    func createSection(name: String) -> SidebarSection? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = clean.isEmpty ? "New Section" : clean
        do {
            let section = try db.createSection(name: title, now: BackupService.isoNow())
            reloadSections()
            return section
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    func renameSection(_ id: String, name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        do { try db.renameSection(id: id, name: clean); reloadSections() }
        catch { errorMessage = error.localizedDescription }
    }

    func deleteSection(_ id: String) {
        do {
            try db.deleteSection(id: id)
            reloadSections()
            reloadScanRoots()   // its roots fell back to the default group
        } catch { errorMessage = error.localizedDescription }
    }

    /// Move a root into a section (nil = default group), appending it to that group's end.
    func assignRoot(_ path: String, toSection sectionId: String?) {
        do { try db.setScanRootSection(path: path, sectionId: sectionId); reloadScanRoots() }
        catch { errorMessage = error.localizedDescription }
    }

    /// Drag-and-drop a root into `sectionId`'s group, positioned just before `beforePath`
    /// (or appended when `beforePath` is nil / not found). Handles both reordering within a
    /// group and moving between groups: the root's `section_id` is set, then the target group
    /// is renumbered so the dropped order sticks. A no-op if the drop wouldn't change anything.
    func moveRoot(_ path: String, toSection sectionId: String?, before beforePath: String?) {
        guard path != beforePath else { return }
        // Target group's current order, minus the dragged root (it may already live here).
        var paths = (sidebarGroups.first { $0.id == sectionId }?.roots.map(\.path) ?? []).filter { $0 != path }
        let insertAt = beforePath.flatMap { paths.firstIndex(of: $0) } ?? paths.count
        paths.insert(path, at: min(insertAt, paths.count))

        // Skip the write if nothing actually changes (same group, same position).
        let current = sidebarGroups.first { $0.id == sectionId }?.roots.map(\.path)
        let movedRoot = scanRoots.first { $0.path == path }
        if movedRoot?.sectionId == sectionId, current == paths { return }

        do {
            try db.setScanRootSectionId(path: path, sectionId: sectionId)
            try db.reorderScanRoots(orderedPaths: paths)
            reloadScanRoots()
        } catch { errorMessage = error.localizedDescription }
    }

    func cleanupOldScanRoots(announce: Bool = true) {
        let days = max(settings.scanRootAutoCleanupDays, 1)
        let cutoff = Self.isoString(Date().addingTimeInterval(-Double(days) * 86400))
        do {
            let removed = try db.deleteScanRootsOlderThan(cutoff: cutoff)
            reloadScanRoots()
            if let root = selectedRootPath, !scanRoots.contains(where: { $0.path == root }) {
                selectedRootPath = nil; mediaFiles = []
            }
            if announce { statusMessage = "Removed \(removed) scan root\(removed == 1 ? "" : "s") older than \(days) days." }
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Backup

    func backupNow() {
        do {
            let url = try BackupService.doBackup(settingsStore: settingsStore)
            statusMessage = "Backup written: \(url.lastPathComponent)"
        } catch { errorMessage = error.localizedDescription }
    }

    func recentBackups() -> [(url: URL, modified: Date, size: Int)] {
        BackupService.listBackups(in: settingsStore.resolvedBackupPath)
    }

    // MARK: - Helpers

    private static func isoString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.string(from: date)
    }
}

/// Lightweight error wrapper so `importOneFile` can return a `Result` carrying a message.
struct ImportFailure: Error { let message: String }
