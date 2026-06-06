import SwiftUI
import PurpleMarkRenderCore

enum SidebarTab: String { case outline, files }

/// The single source of truth for the editor window: the current document,
/// the opened folder, view mode, and sidebar state. One instance is shared via
/// `@EnvironmentObject` and also reached by the AppDelegate when Finder asks the
/// app to open a `.md` file.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var text: String = "" {
        didSet {
            guard text != oldValue else { return }
            isDirty = (text != savedText)
            scheduleAutoSave()
        }
    }
    @Published var fileURL: URL?
    @Published var isDirty = false

    @Published var viewMode: ViewMode = .document
    @Published var sidebarVisible = true
    @Published var sidebarTab: SidebarTab = .outline

    @Published var folder: URL?
    @Published var folderFiles: [URL] = []

    /// Find & Replace bar visibility, and whether to open it with the replace
    /// row expanded. The bar only operates on the Markdown (source) view, so
    /// showing it forces `viewMode = .markdown`.
    @Published var findVisible = false
    @Published var findShowReplace = false

    func showFind(replace: Bool) {
        viewMode = .markdown
        findShowReplace = replace
        findVisible = true
    }

    /// Last vertical scroll fraction (0…1). Carried across the Document⇄Markdown
    /// toggle so the reading position is preserved when sync-scroll is enabled.
    @Published var scrollFraction: Double = 0

    private var savedText: String = ""
    private let settings = AppSettings.shared
    private var autoSaveTask: Task<Void, Never>?

    var title: String { fileURL?.lastPathComponent ?? "Untitled" }

    var outline: [OutlineItem] { OutlineParser.outline(from: text) }
    var stats: DocStats { OutlineParser.stats(from: text) }

    init() {
        viewMode = settings.defaultView
    }

    // MARK: - Document lifecycle

    func newDocument() {
        text = ""
        savedText = ""
        fileURL = nil
        isDirty = false
        viewMode = settings.defaultView
    }

    func open(_ url: URL) {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            NSSound.beep()
            return
        }
        savedText = contents
        text = contents
        fileURL = url
        isDirty = false
        viewMode = settings.defaultView
        // Opening a file inside the current folder keeps the Files sidebar; if
        // it's elsewhere and no folder is set, adopt its parent as the folder.
        if folder == nil {
            setFolder(url.deletingLastPathComponent())
        }
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    @discardableResult
    func save() -> Bool {
        guard let url = fileURL else { return saveAs() }
        return write(to: url)
    }

    @discardableResult
    func saveAs() -> Bool {
        guard let url = FileService.runSavePanel(suggestedName: fileURL?.lastPathComponent ?? "Untitled.md") else {
            return false
        }
        let ok = write(to: url)
        if ok {
            fileURL = url
            if folder == nil { setFolder(url.deletingLastPathComponent()) }
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            reloadFolderFiles()
        }
        return ok
    }

    private func write(to url: URL) -> Bool {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            savedText = text
            isDirty = false
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        guard settings.autoSave, fileURL != nil else { return }
        autoSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s debounce
            guard !Task.isCancelled else { return }
            await MainActor.run { _ = self?.save() }
        }
    }

    // MARK: - Folder browsing

    func setFolder(_ url: URL) {
        folder = url
        reloadFolderFiles()
    }

    func openFolderDialog() {
        guard let url = FileService.runOpenFolderPanel() else { return }
        setFolder(url)
    }

    func reloadFolderFiles() {
        guard let folder else { folderFiles = []; return }
        folderFiles = FileService.markdownFiles(in: folder)
    }

    // MARK: - Open dialog

    func openDialog() {
        guard let url = FileService.runOpenPanel() else { return }
        open(url)
    }
}
