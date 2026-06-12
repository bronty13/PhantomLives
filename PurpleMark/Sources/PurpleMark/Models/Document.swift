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

    /// One-shot outline-jump requests; each view consumes the form it can act
    /// on exactly (source: line, preview: nth heading element).
    struct OutlineJump: Equatable {
        let line: Int
        let headingIndex: Int
        let token: UUID
    }
    @Published var outlineJump: OutlineJump?

    func requestOutlineJump(line: Int, headingIndex: Int) {
        outlineJump = OutlineJump(line: line, headingIndex: headingIndex, token: UUID())
    }

    /// Whole-document scan results, refreshed in a debounced background task.
    @Published private(set) var outline: [OutlineItem] = []
    @Published private(set) var stats = DocStats()
    /// Word/char counts of the editor selection (nil when nothing selected).
    @Published var selectionStats: DocStats?
    private(set) var index = DocumentIndex.empty

    /// On-disk size at load (drives the large-file feature policy).
    private(set) var byteSize = 0

    private var savedVersion = 0
    private var autoSaveTask: Task<Void, Never>?
    private var indexTask: Task<Void, Never>?
    private var fileMonitor: DispatchSourceFileSystemObject?
    /// When we last wrote the file ourselves — file-system events inside this
    /// window are our own atomic save, not an external change.
    private var lastSelfSaveAt = Date.distantPast
    private let settings = AppSettings.shared

    deinit {
        fileMonitor?.cancel()
    }

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
        startWatchingFile()
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
            startWatchingFile()
        }
        return ok
    }

    /// Synchronous write — explicit saves and the save-before-close flow, where
    /// the caller needs the result before proceeding.
    private func write(to url: URL) -> Bool {
        autoSaveTask?.cancel()
        do {
            let version = textVersion
            lastSelfSaveAt = Date()
            try text.write(to: url, atomically: true, encoding: .utf8)
            byteSize = storage.string.utf8.count
            savedVersion = version
            isDirty = textVersion != savedVersion
            startWatchingFile()   // atomic write replaced the inode — re-arm
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
            self.lastSelfSaveAt = Date()
            let ok = await Task.detached(priority: .utility) {
                (try? snapshot.write(to: url, atomically: true, encoding: .utf8)) != nil
            }.value
            guard !Task.isCancelled, ok else { return }  // autosave failures stay silent; explicit save reports
            self.lastSelfSaveAt = Date()
            self.savedVersion = version
            self.isDirty = self.textVersion != version
            self.startWatchingFile()   // atomic write replaced the inode — re-arm
        }
    }

    // MARK: - External-change watching

    /// Watches the open file for changes made by other apps (git checkout,
    /// another editor): a clean document reloads silently; a dirty one asks.
    private func startWatchingFile() {
        fileMonitor?.cancel()
        fileMonitor = nil
        guard let url = fileURL else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        source.setEventHandler { [weak self] in
            // Re-arm by path first: most editors save atomically (rename), so
            // this inode is dead after one event.
            self?.startWatchingFile()
            self?.fileChangedOnDisk()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileMonitor = source
    }

    private func fileChangedOnDisk() {
        guard let url = fileURL else { return }
        // Our own atomic save fires rename/delete events — ignore the window.
        guard Date().timeIntervalSince(lastSelfSaveAt) > 2.0 else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        if !isDirty {
            reloadFromDisk(url)
            return
        }
        let alert = NSAlert()
        alert.messageText = "“\(title)” changed on disk"
        alert.informativeText = "Another application modified this file, and you have unsaved changes here. Reloading will discard your changes."
        alert.addButton(withTitle: "Keep My Changes")
        alert.addButton(withTitle: "Reload From Disk")
        if alert.runModal() == .alertSecondButtonReturn {
            reloadFromDisk(url)
        }
    }

    private func reloadFromDisk(_ url: URL) {
        let fraction = scrollFraction
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let loaded = try? FileLoader.load(url) else { return }
            await MainActor.run {
                guard let self else { return }
                self.text = loaded.text       // not-dirty programmatic replace
                self.byteSize = loaded.byteSize
                self.scrollFraction = fraction
            }
        }
    }
}
