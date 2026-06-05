import AppKit

/// Formatting actions broadcast from the toolbar / Format menu to whichever
/// source editor is active. The editor's coordinator listens for `.pmEditorAction`
/// and applies the transform to the current selection.
enum EditorAction: String {
    case bold, italic, strikethrough, inlineCode, link
    case unorderedList, orderedList, quote, codeBlock

    static let notification = Notification.Name("pm.editorAction")

    func post() {
        NotificationCenter.default.post(name: EditorAction.notification, object: self.rawValue)
    }
}

/// Glue for the Export menu items: runs the export and surfaces the result.
@MainActor
enum ExportCommands {
    static func exportHTML(state: AppState, settings: AppSettings) {
        do {
            let url = try ExportService.shared.exportHTML(
                markdown: state.text, baseName: state.title,
                theme: settings.theme, width: settings.readingWidth,
                to: settings.exportDirectory)
            reveal(url)
        } catch {
            present(error)
        }
    }

    static func exportPDF(state: AppState, settings: AppSettings) {
        ExportService.shared.exportPDF(
            markdown: state.text, baseName: state.title,
            theme: settings.theme, width: settings.readingWidth,
            to: settings.exportDirectory) { result in
            switch result {
            case .success(let url): reveal(url)
            case .failure(let error): present(error)
            }
        }
    }

    private static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private static func present(_ error: Error) {
        NSSound.beep()
        let alert = NSAlert()
        alert.messageText = "Export failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
