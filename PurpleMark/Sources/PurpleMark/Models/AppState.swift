import SwiftUI
import PurpleMarkRenderCore

enum SidebarTab: String { case outline, files }

/// Window/app-scope state: the open documents (tabs) + which is active, plus
/// the sidebar, folder, and find UI state shared across documents.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var documents: [Document]
    @Published var activeID: Document.ID

    @Published var sidebarVisible = true
    @Published var sidebarTab: SidebarTab = .outline

    @Published var folder: URL?
    @Published var folderFiles: [URL] = []

    /// Find & Replace bar (operates on the active document's Markdown view).
    @Published var findVisible = false
    @Published var findShowReplace = false

    init() {
        let first = Document()
        documents = [first]
        activeID = first.id
    }

    /// The active document. Always valid — `documents` is never empty.
    var active: Document {
        documents.first { $0.id == activeID } ?? documents[0]
    }

    // MARK: - Tabs / documents

    func newDocument() {
        let doc = Document()
        documents.append(doc)
        activeID = doc.id
    }

    func activate(_ doc: Document) { activeID = doc.id }

    /// Open files dropped onto the window from Finder. Accepts regular files
    /// whose extension we recognize as markdown/text (directories and unknown
    /// types are ignored). Returns `true` if at least one file was opened so the
    /// drop is accepted; the last opened file becomes the active tab.
    @discardableResult
    func openDroppedFiles(_ urls: [URL]) -> Bool {
        let openable = urls.filter { url in
            guard url.isFileURL else { return false }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  !isDir.boolValue else { return false }
            return FileService.markdownExtensions.contains(url.pathExtension.lowercased())
        }
        guard !openable.isEmpty else { return false }
        for url in openable { open(url) }
        return true
    }

    func open(_ url: URL) {
        // If the file is already open, just focus its tab.
        if let existing = documents.first(where: { $0.fileURL?.standardizedFileURL == url.standardizedFileURL }) {
            activeID = existing.id
            return
        }
        let doc = Document.opening(url)
        // A synchronous (small-file) load failure gets an alert and no tab;
        // async failures surface in the tab's failed-state pane.
        if case .failed(let message) = doc.loadState {
            let alert = NSAlert()
            alert.messageText = "Couldn't open “\(url.lastPathComponent)”"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        // Replace a single pristine untitled tab instead of stacking a blank one.
        if documents.count == 1, documents[0].fileURL == nil, !documents[0].isDirty,
           documents[0].storage.length == 0 {
            documents[0] = doc
        } else {
            documents.append(doc)
        }
        activeID = doc.id
        if folder == nil { setFolder(url.deletingLastPathComponent()) }
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    func closeDocument(_ doc: Document) {
        guard let index = documents.firstIndex(where: { $0.id == doc.id }) else { return }
        if doc.isDirty, !confirmClose(doc) { return }
        documents.remove(at: index)
        if documents.isEmpty {
            newDocument()
        } else if doc.id == activeID {
            activeID = documents[min(index, documents.count - 1)].id
        }
    }

    func closeActiveDocument() { closeDocument(active) }

    private func confirmClose(_ doc: Document) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Close “\(doc.title)” without saving?"
        alert.informativeText = "It has unsaved changes."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:  return doc.save()
        case .alertSecondButtonReturn: return true
        default:                       return false
        }
    }

    // MARK: - Convenience forwarding to the active document

    @discardableResult func save() -> Bool { active.save() }
    @discardableResult func saveAs() -> Bool { active.saveAs() }

    func openDialog() {
        guard let url = FileService.runOpenPanel() else { return }
        open(url)
    }

    func showFind(replace: Bool) {
        active.viewMode = .markdown
        findShowReplace = replace
        findVisible = true
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
}
