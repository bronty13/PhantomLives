import SwiftUI
import AppKit

/// Whole-journal export sheet. Presented from File → Export Journal… (⇧⌘E) and
/// from Settings → General. Pick a format, hit Export, and the file is written
/// to the resolved export directory (default `~/Downloads/PurpleDiary/`), then
/// offered for Reveal in Finder. Runs the export on the main actor (WKWebView
/// for PDF needs it) but off the synchronous UI path via a `Task`.
struct ExportSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var format: ExportService.Format = .markdown
    @State private var isExporting = false
    @State private var resultURL: URL?
    @State private var errorText: String?

    private var exportDir: URL { appState.settingsStore.resolvedExportDirectory }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Export Journal")
                    .font(.title2.weight(.semibold))
                Text("^[\(appState.entries.count) entry](inflect: true) · saved to the folder below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Picker("Format", selection: $format) {
                ForEach(ExportService.Format.allCases) { f in
                    Label(f.displayName, systemImage: f.systemImage).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(isExporting)

            Text(formatBlurb(format))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(exportDir.path)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(exportDir.path)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if let resultURL {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Exported **\(resultURL.lastPathComponent)**")
                        .font(.callout)
                    Spacer()
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([resultURL])
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    runExport()
                } label: {
                    if isExporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Export")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isExporting)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func runExport() {
        errorText = nil
        resultURL = nil
        isExporting = true
        Task {
            do {
                let url = try await ExportService.export(
                    format: format,
                    // visibleEntries excludes locked vault journals (so their
                    // sealed ciphertext never lands in an export) and carries
                    // unlocked vault entries as in-memory plaintext.
                    entries: appState.visibleEntries,
                    people: appState.people,
                    tagsByEntry: appState.tagsByEntry,
                    peopleByEntry: appState.peopleByEntry,
                    trackerTags: appState.trackerTags,
                    trackerValuesByEntry: appState.trackerValuesByEntry,
                    attachmentCountByEntry: appState.attachmentCountByEntry,
                    journals: appState.journals,
                    exportDir: exportDir
                )
                resultURL = url
            } catch {
                errorText = error.localizedDescription
            }
            isExporting = false
        }
    }

    private func formatBlurb(_ f: ExportService.Format) -> String {
        switch f {
        case .markdown: return "A single Markdown document, entries grouped by month — opens in any text editor or note vault."
        case .html:     return "A self-contained styled web page (no external files) you can open in any browser."
        case .pdf:      return "A paginated PDF, same look as the HTML export — good for printing or archiving."
        case .json:     return "A complete, structured dump of every entry, tag, and person — for backup or re-import."
        }
    }
}
