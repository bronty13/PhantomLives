import SwiftUI
import PurpleMarkRenderCore

/// One open document (one tab). Owns its own text, file URL, dirty state, view
/// mode, and scroll position so multiple documents can be open at once.
///
/// Large-file design: the text lives in an `NSTextStorage` the source editor
/// attaches to directly, so a keystroke never copies the document. Whole-text
/// scans (outline, stats) run in a debounced background task; change tracking
/// is a cheap version counter, never a full-string compare.
@MainActor
final class Document: ObservableObject, Identifiable {
    let id = UUID()

    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    /// The text backing store. The source editor's layout manager attaches to
    /// this directly; everyone else materializes `text` only at debounced or
    /// user-initiated moments (save, export, preview push, find).
    let storage = NSTextStorage()

    /// Each document gets its own undo stack so undo survives tab switches and
    /// can never apply to another tab's text.
    let undoManager = UndoManager()

    /// Bumped on every edit — the cheap, SwiftUI-observable change signal.
    @Published private(set) var textVersion = 0
    @Published var fileURL: URL?
    @Published var isDirty = false
    @Published var viewMode: ViewMode
    @Published var loadState: LoadState = .ready
    /// Last scroll fraction (0…1), carried across the Document⇄Markdown toggle.
    @Published var scrollFraction: Double = 0
    /// User override of the large-file preview cap ("Render anyway").
    @Published var renderFullPreview = false

    /// Whole-document scan results, refreshed in a debounced background task.
    @Published private(set) var outline: [OutlineItem] = []
    @Published private(set) var stats = DocStats()
    private(set) var index = DocumentIndex.empty

    /// On-disk size at load (drives the large-file feature policy).
    private(set) var byteSize = 0

    private var savedVersion = 0
    private var autoSaveTask: Task<Void, Never>?
    private var indexTask: Task<Void, Never>?
    private let settings = AppSettings.shared

    var title: String { fileURL?.lastPathComponent ?? "Untitled" }

    /// Materializes the current text. O(1) bridge; pay the copy only where the
    /// string actually gets consumed.
    var text: String {
        get { storage.string }
        set { replaceAllText(with: newValue) }
    }

    /// A fresh, empty untitled document.
    init() {
        self.viewMode = AppSettings.shared.defaultView
    }

    /// For tests and programmatic construction: a ready document with content.
    init(text: String, fileURL: URL?) {
        self.viewMode = AppSettings.shared.defaultView
        self.fileURL = fileURL
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        byteSize = text.utf8.count
        refreshIndexNow()
    }

    /// Opens a file. Small files load synchronously (no overlay flash); large
    /// ones return immediately in `.loading` and populate in the background.
    static func opening(_ url: URL) -> Document {
        let doc = Document()
        doc.fileURL = url

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        if size <= FileLoader.syncLoadLimit {
            do {
                doc.apply(loaded: try FileLoader.load(url))
            } catch {
                doc.loadState = .failed(error.localizedDescription)
            }
            return doc
        }

        doc.loadState = .loading
        doc.byteSize = size
        Task.detached(priority: .userInitiated) { [weak doc] in
            do {
                let loaded = try FileLoader.load(url)
                await MainActor.run { doc?.apply(loaded: loaded) }
            } catch {
                let message = error.localizedDescription
                await MainActor.run { doc?.loadState = .failed(message) }
            }
        }
        return doc
    }

    private func apply(loaded: FileLoader.Loaded) {
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length),
                                  with: loaded.text)
        undoManager.removeAllActions()
        byteSize = loaded.byteSize
        textVersion += 1
        savedVersion = textVersion
        isDirty = false
        loadState = .ready
        if loaded.byteSize <= FileLoader.syncLoadLimit {
            refreshIndexNow()           // sidebar/status populate immediately
        } else {
            scheduleIndexRefresh()
        }
    }

    /// Replaces the whole text programmatically (load, external reload, tests).
    /// Does not mark the document dirty.
    private func replaceAllText(with newText: String) {
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length),
                                  with: newText)
        undoManager.removeAllActions()
        byteSize = newText.utf8.count
        textVersion += 1
        savedVersion = textVersion
        isDirty = false
        refreshIndexNow()
    }

    /// Called by the editor after every user edit (the storage already holds
    /// the new text). Cheap: bump, flag, schedule background work.
    func noteEdited() {
        textVersion += 1
        isDirty = textVersion != savedVersion
        scheduleAutoSave()
        scheduleIndexRefresh()
    }

    // MARK: - Whole-document index (outline, stats, line offsets)

    /// Debounce scaled by size: snappy for normal files, easy on 100MB ones.
    private var indexDebounce: Duration {
        .milliseconds(byteSize > LargeFilePolicy.thresholdBytes ? 900 : 300)
    }

    private func scheduleIndexRefresh() {
        indexTask?.cancel()
        let version = textVersion
        let debounce = indexDebounce
        indexTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            let snapshot = self.text
            let built = await Task.detached(priority: .utility) {
                DocumentIndex.build(from: snapshot)
            }.value
            guard !Task.isCancelled, self.textVersion == version else { return }
            self.index = built
            self.outline = built.outline
            self.stats = built.stats
        }
    }

    /// Synchronous index build — load time and tests only.
    private func refreshIndexNow() {
        index = DocumentIndex.build(from: storage.string)
        outline = index.outline
        stats = index.stats
    }

    // MARK: - Saving

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
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        }
        return ok
    }

    /// Synchronous write — explicit saves and the save-before-close flow, where
    /// the caller needs the result before proceeding.
    private func write(to url: URL) -> Bool {
        autoSaveTask?.cancel()
        do {
            let version = textVersion
            try text.write(to: url, atomically: true, encoding: .utf8)
            byteSize = storage.string.utf8.count
            savedVersion = version
            isDirty = textVersion != savedVersion
            return true
        } catch {
            presentSaveError(error, url: url)
            return false
        }
    }

    private func presentSaveError(_ error: Error, url: URL) {
        let alert = NSAlert()
        alert.messageText = "Couldn't save “\(url.lastPathComponent)”"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// Debounced autosave. The snapshot is taken on the main actor but encoded
    /// and written on a background task so a 100MB save never blocks typing.
    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        guard settings.autoSave, fileURL != nil else { return }
        let debounce: Duration = .milliseconds(
            byteSize > LargeFilePolicy.thresholdBytes ? 5000 : 800)
        autoSaveTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self, let url = self.fileURL else { return }
            let snapshot = self.text
            let version = self.textVersion
            let ok = await Task.detached(priority: .utility) {
                (try? snapshot.write(to: url, atomically: true, encoding: .utf8)) != nil
            }.value
            guard !Task.isCancelled, ok else { return }  // autosave failures stay silent; explicit save reports
            self.savedVersion = version
            self.isDirty = self.textVersion != version
        }
    }
}
