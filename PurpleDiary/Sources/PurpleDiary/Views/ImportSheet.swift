import SwiftUI
import UniformTypeIdentifiers

/// Import journals from another app's (or PurpleDiary's own) JSON export. Pick a
/// file, choose the format (auto-detect by default), and import. Everything is
/// local; entries are added (never overwritten) into a journal named for the
/// source. Reached from File → Import Journal… (⇧⌘I).
struct ImportSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var format: ImportService.Format = .auto
    @State private var pickedURL: URL?
    @State private var importing = false
    @State private var resultText: String?
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Journal").font(.title2.weight(.semibold))
            Text("Bring entries in from a JSON export. They're added to your journal — nothing is overwritten. For Day One, Journey, or Diarium, extract the export's `.zip` first and pick the `.json` inside.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Format", selection: $format) {
                ForEach(ImportService.Format.allCases) { f in Text(f.label).tag(f) }
            }
            .frame(maxWidth: 280)

            HStack {
                Button("Choose File…", action: chooseFile)
                if let pickedURL {
                    Text(pickedURL.lastPathComponent).font(.callout).lineLimit(1).truncationMode(.middle)
                }
            }

            if let resultText {
                Label(resultText, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.callout)
            }
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Button {
                    Task { await runImport() }
                } label: {
                    if importing { ProgressView().controlSize(.small) } else { Text("Import") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(importing || pickedURL == nil)
            }
        }
        .padding(20)
        .frame(width: 540, height: 380)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a JSON export to import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pickedURL = url
        resultText = nil; errorText = nil
    }

    private func runImport() async {
        guard let url = pickedURL else { return }
        importing = true; resultText = nil; errorText = nil
        defer { importing = false }
        do {
            let bundle = try ImportService.parse(contentsOf: url, format: format)
            let added = try await ImportService.apply(bundle)
            appState.reloadAll()
            resultText = "Imported \(added) " + (added == 1 ? "entry" : "entries") +
                " from \(bundle.sourceName)."
        } catch {
            errorText = error.localizedDescription
        }
    }
}
