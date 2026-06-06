import SwiftUI
import PurpleMarkRenderCore

/// One open document (one tab). Owns its own text, file URL, dirty state, view
/// mode, and scroll position so multiple documents can be open at once.
@MainActor
final class Document: ObservableObject, Identifiable {
    let id = UUID()

    @Published var text: String {
        didSet {
            guard text != oldValue else { return }
            isDirty = (text != savedText)
            scheduleAutoSave()
        }
    }
    @Published var fileURL: URL?
    @Published var isDirty = false
    @Published var viewMode: ViewMode
    /// Last scroll fraction (0…1), carried across the Document⇄Markdown toggle.
    @Published var scrollFraction: Double = 0

    private var savedText: String
    private var autoSaveTask: Task<Void, Never>?
    private let settings = AppSettings.shared

    var title: String { fileURL?.lastPathComponent ?? "Untitled" }
    var outline: [OutlineItem] { OutlineParser.outline(from: text) }
    var stats: DocStats { OutlineParser.stats(from: text) }

    /// A fresh, empty untitled document.
    init() {
        self.text = ""
        self.savedText = ""
        self.fileURL = nil
        self.viewMode = AppSettings.shared.defaultView
    }

    /// Loads an existing file. Returns nil if it can't be read.
    convenience init?(contentsOf url: URL) {
        self.init()
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        self.savedText = contents
        self.text = contents
        self.fileURL = url
        self.isDirty = false
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
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { _ = self?.save() }
        }
    }
}
