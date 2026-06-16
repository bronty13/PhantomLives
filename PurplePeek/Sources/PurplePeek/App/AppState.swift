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
    @Published var mediaFiles: [MediaFile] = []
    @Published var keywords: [Keyword] = []

    // Metadata for the currently selected file (loaded on selection).
    @Published var selectedKeywordIds: Set<String> = []
    @Published var selectedAlbums: [String] = []

    // MARK: - Selection
    @Published var selectedRootPath: String?
    @Published var selectedFolderPath: String?   // nil ⇒ show the whole root
    @Published var selectedFileId: String?
    @Published var previewIndex: Int = 0
    @Published var showAllInPreview: Bool = false

    // MARK: - Scan progress
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0
    @Published var scanMessage: String = ""

    // MARK: - Import
    @Published var importProgress: ImportProgress?

    /// Path to exiftool if installed (enables embedding title/caption/keywords into imports).
    let exiftoolPath: String?

    // MARK: - Status / errors
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    // MARK: - Sub-stores / services
    let settingsStore = SettingsStore()
    private let db = DatabaseService.shared
    private var settingsObserver: AnyCancellable?

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
        // Bubble nested settings changes up so views observing AppState (theme, appearance,
        // default mode) re-render live.
        settingsObserver = settingsStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        // PhantomLives auto-backup-on-launch standard — runs first, never throws.
        BackupService.runOnLaunchIfDue(settingsStore: settingsStore)
        // Honor the user's default mode for a fresh launch.
        appMode = settings.defaultMode
        if settings.scanRootAutoCleanupEnabled { cleanupOldScanRoots(announce: false) }
        reloadAll()
    }

    // MARK: - Reload helpers

    func reloadAll() {
        reloadScanRoots()
        reloadKeywords()
        reloadMediaFiles()
    }

    func reloadScanRoots() {
        do { scanRoots = try db.fetchAllScanRoots() }
        catch { errorMessage = error.localizedDescription }
    }

    func reloadKeywords() {
        do { keywords = try db.fetchAllKeywords() }
        catch { errorMessage = error.localizedDescription }
    }

    func reloadMediaFiles() {
        guard let root = selectedRootPath else { mediaFiles = []; return }
        do { mediaFiles = try db.fetchMediaFiles(scanRoot: root) }
        catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Derived views of the data

    /// Files shown in the grid: active (non-deleted) files for the selected root, optionally
    /// narrowed to the selected folder subtree.
    var visibleMediaFiles: [MediaFile] {
        let active = mediaFiles.filter { $0.deletedAt == nil }
        guard let folder = selectedFolderPath else { return active }
        return active.filter { file in
            let dir = (file.filePath as NSString).deletingLastPathComponent
            return dir == folder || file.filePath.hasPrefix(folder + "/")
        }
    }

    /// The folder tree for the selected root, rebuilt from the current media files.
    var folderTree: FolderTreeNode? {
        guard let root = selectedRootPath else { return nil }
        return FolderTree.build(rootPath: root, files: mediaFiles)
    }

    /// Items shown in Preview mode: active (non-deleted) files, optionally filtered to the
    /// still-undecided ones. Audio is included — Preview can play and decide it too.
    var previewQueue: [MediaFile] {
        let active = mediaFiles.filter { $0.deletedAt == nil }
        return showAllInPreview ? active : active.filter { $0.keep == nil }
    }

    /// The file currently shown in Preview mode (index clamped into the queue).
    var currentPreviewFile: MediaFile? {
        let q = previewQueue
        guard !q.isEmpty else { return nil }
        return q[min(max(previewIndex, 0), q.count - 1)]
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

    /// Apply a keep/skip decision to the current preview item and advance. In undecided
    /// mode the decided item drops out of the queue (so clamping lands on the next one); in
    /// show-all mode we advance explicitly.
    func decidePreview(keep: Bool) {
        guard let file = currentPreviewFile else { return }
        let showAll = showAllInPreview
        setKeep(file.id, keep)
        if showAll {
            nextPreview()
        } else {
            clampPreviewIndex()
            syncSelectionToPreview()
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

        Task {
            let scanned = await Task.detached(priority: .userInitiated) {
                MediaDiscoveryService.scan(root: dir)
            }.value
            await self.persistScan(rootPath: rootPath, files: scanned)
        }
    }

    private func persistScan(rootPath: String, files: [ScannedFile]) async {
        let now = BackupService.isoNow()
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
            try db.updateScanRootStats(path: rootPath, totalFiles: files.count, now: now)
        } catch {
            errorMessage = error.localizedDescription
        }

        selectedRootPath = rootPath
        selectedFolderPath = nil
        selectedFileId = nil
        reloadScanRoots()
        reloadMediaFiles()

        isScanning = false
        scanProgress = 1
        statusMessage = "Scanned \(files.count) item\(files.count == 1 ? "" : "s") in \((rootPath as NSString).lastPathComponent)."
    }

    /// Select a scan root (from the sidebar) and load its files.
    func selectRoot(_ path: String) {
        selectedRootPath = path
        selectedFolderPath = nil
        selectedFileId = nil
        selectedKeywordIds = []
        selectedAlbums = []
        reloadMediaFiles()
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
        do {
            selectedKeywordIds = Set(try db.keywordIds(forFile: id))
            selectedAlbums = try db.albums(forFile: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Mutate one row in `mediaFiles` in place — republishes for the grid badge without a
    /// full refetch (which would disturb a focused text field in the detail panel).
    private func patchLocal(_ id: String, _ transform: (inout MediaFile) -> Void) {
        guard let idx = mediaFiles.firstIndex(where: { $0.id == id }) else { return }
        transform(&mediaFiles[idx])
    }

    func setKeep(_ id: String, _ keep: Bool?) {
        let now = BackupService.isoNow()
        do {
            try db.updateKeep(id: id, keep: keep.map { $0 ? 1 : 0 }, now: now)
            patchLocal(id) { $0.keepDecision = keep }
        } catch { errorMessage = error.localizedDescription }

        // Keeping an audio file copies it to the Kept Audio Export folder (once).
        if keep == true, let f = mediaFiles.first(where: { $0.id == id }),
           f.mediaType == .audio, f.exportedAt == nil {
            exportAudio(id)
        }
    }

    func setFavorite(_ id: String, _ value: Bool) {
        let now = BackupService.isoNow()
        do {
            try db.updateFavorite(id: id, isFavorite: value, now: now)
            patchLocal(id) { $0.isFavorite = value }
        } catch { errorMessage = error.localizedDescription }
    }

    func setHidden(_ id: String, _ value: Bool) {
        let now = BackupService.isoNow()
        do {
            try db.updateHidden(id: id, isHidden: value, now: now)
            patchLocal(id) { $0.isHidden = value }
        } catch { errorMessage = error.localizedDescription }
    }

    func setTitle(_ id: String, _ value: String?) {
        let now = BackupService.isoNow()
        let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = (clean?.isEmpty ?? true) ? nil : clean
        do {
            try db.updateTitle(id: id, title: stored, now: now)
            patchLocal(id) { $0.title = stored }
        } catch { errorMessage = error.localizedDescription }
    }

    func setCaption(_ id: String, _ value: String?) {
        let now = BackupService.isoNow()
        let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = (clean?.isEmpty ?? true) ? nil : clean
        do {
            try db.updateCaption(id: id, caption: stored, now: now)
            patchLocal(id) { $0.caption = stored }
        } catch { errorMessage = error.localizedDescription }
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
        do { try db.setKeywords(fileId: fileId, keywordIds: Array(selectedKeywordIds)) }
        catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Albums

    func distinctAlbumNames() -> [String] {
        (try? db.distinctAlbumNames()) ?? []
    }

    func addAlbum(_ name: String) {
        guard let fileId = selectedFileId else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !selectedAlbums.contains(trimmed) else { return }
        selectedAlbums.append(trimmed)
        selectedAlbums.sort()
        do { try db.setAlbums(fileId: fileId, albumNames: selectedAlbums) }
        catch { errorMessage = error.localizedDescription }
    }

    func removeAlbum(_ name: String) {
        guard let fileId = selectedFileId else { return }
        selectedAlbums.removeAll { $0 == name }
        do { try db.setAlbums(fileId: fileId, albumNames: selectedAlbums) }
        catch { errorMessage = error.localizedDescription }
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
                statusMessage = "Imported \(file.fileName) to Photos."
            case .failure(let err):
                errorMessage = "Import failed: \(err.message)"
            }
        }
    }

    /// Stage (photos only) + import one file. Returns the asset id or an error message.
    private func importOneFile(_ file: MediaFile, exiftoolPath: String?) async -> Result<String, ImportFailure> {
        let type: PHAssetResourceType = (file.mediaType == .photo) ? .photo : .video
        let albums = (try? db.albums(forFile: file.id)) ?? []

        var importURL = file.fileURL
        var stagedURL: URL?
        if file.mediaType == .photo, let ep = exiftoolPath {
            let keywords = (try? db.keywordNames(forFile: file.id)) ?? []
            let meta = MetadataStagingService.Metadata(title: file.title, caption: file.caption, keywords: keywords)
            if !meta.isEmpty {
                let original = file.fileURL
                stagedURL = try? await Task.detached(priority: .userInitiated) {
                    try MetadataStagingService.stage(original: original, metadata: meta, exiftoolPath: ep)
                }.value
                if let stagedURL { importURL = stagedURL }
            }
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
