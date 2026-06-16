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

    // MARK: - Selection
    @Published var selectedRootPath: String?
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

    // MARK: - Preview queue (derived)

    /// Items shown in Preview mode: active (non-deleted) files, optionally filtered to the
    /// still-undecided ones. Audio is included — Preview can play and decide it too.
    var previewQueue: [MediaFile] {
        let active = mediaFiles.filter { $0.deletedAt == nil }
        return showAllInPreview ? active : active.filter { $0.keep == nil }
    }
}
