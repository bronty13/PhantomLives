import SwiftUI
import AppKit

/// Reusable export-menu + reveal helper for every per-report header.
/// Each report passes a closure that produces the bytes for a chosen format;
/// this view drives the save panel, writes the file, and surfaces a "Reveal"
/// button next to the menu so the user can find what they just saved.
struct ReportExportMenu: View {
    /// Per-format payload. Only the formats with non-nil providers appear in
    /// the menu, so reports that don't have, say, a CSV view can omit it.
    struct Provider {
        var markdown: () -> Data
        var pdf:      () -> Data
        var csv:      () -> Data
    }

    let suggestedBaseName: String
    let provider: Provider

    @EnvironmentObject private var appState: AppState
    @State private var lastSavedURL: URL?

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Markdown…") { saveAs(.markdown) }
                Button("PDF…")      { saveAs(.pdf) }
                Button("CSV…")      { saveAs(.csv) }
            } label: {
                Label("Export this report…", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if lastSavedURL != nil {
                Button {
                    if let url = lastSavedURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                .buttonStyle(.borderless)
                .help(lastSavedURL?.lastPathComponent ?? "")
            }
        }
    }

    private enum Format { case markdown, pdf, csv
        var ext: String {
            switch self {
            case .markdown: return "md"
            case .pdf:      return "pdf"
            case .csv:      return "csv"
            }
        }
    }

    private func saveAs(_ fmt: Format) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(suggestedBaseName).\(fmt.ext)"
        panel.canCreateDirectories = true
        panel.directoryURL = appState.settingsStore.resolvedExportDirectory
        try? FileManager.default.createDirectory(
            at: appState.settingsStore.resolvedExportDirectory,
            withIntermediateDirectories: true
        )
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let data: Data
        switch fmt {
        case .markdown: data = provider.markdown()
        case .pdf:      data = provider.pdf()
        case .csv:      data = provider.csv()
        }
        do {
            try data.write(to: url)
            lastSavedURL = url
            // Auto-reveal so the user can immediately see where it landed.
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            // Surface via system alert — rare (disk full / permission)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn't save export"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
