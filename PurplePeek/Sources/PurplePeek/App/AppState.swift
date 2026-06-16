import SwiftUI
import Combine

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

    // MARK: - Status / errors
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    // MARK: - Sub-stores / services
    let settingsStore = SettingsStore()
    private let db = DatabaseService.shared

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
        // PhantomLives auto-backup-on-launch standard — runs first, never throws.
        BackupService.runOnLaunchIfDue(settingsStore: settingsStore)
        // Honor the user's default mode for a fresh launch.
        appMode = settings.defaultMode
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
    }

    func setFavorite(_ id: String, _ value: Bool) {
        let now = BackupService.isoNow()
        do {
            try db.updateFavorite(id: id, isFavorite: value, now: now)
            patchLocal(id) { $0.isFavorite = value }
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
}
