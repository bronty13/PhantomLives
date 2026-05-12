import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MasterClipperCore

/// Modal that pairs a file (XLSX or pipe-CSV from the Clips4Sale
/// "on demand" storefront export) with a store (CoC | PoA), then
/// replaces every row in `c4s_historical` for that store with the
/// parsed contents. Single transaction, single click.
struct C4SHistoricalImportSheet: View {
    /// Called with `(store, count)` on success, or `nil` on cancel.
    let onComplete: ((store: String, count: Int)?) -> Void

    @State private var pickedURL: URL? = nil
    @State private var store: String = "CoC"
    @State private var parsing: Bool = false
    @State private var preview: [C4SHistoricalRecord] = []
    @State private var error: String? = nil
    @State private var existingCount: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Clips4Sale historical export")
                .font(.title2.weight(.semibold))

            sourceRow

            storeRow

            if let error = error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            if !preview.isEmpty {
                previewBox
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onComplete(nil) }
                    .keyboardShortcut(.cancelAction)
                Button {
                    runImport()
                } label: {
                    Label("Replace \(store) rows", systemImage: "arrow.down.doc.fill")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(preview.isEmpty)
                .controlSize(.large)
            }
        }
        .padding(20)
        .onChange(of: store) { _, _ in refreshExistingCount() }
        .onAppear { refreshExistingCount() }
    }

    // MARK: - Source row

    private var sourceRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Source file").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack {
                if let url = pickedURL {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(url.lastPathComponent, systemImage: "doc.fill")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(url.path)
                        Text("type: \(url.pathExtension.lowercased().isEmpty ? "(no extension)" : url.pathExtension.lowercased())")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text("No file selected")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    pickFile()
                } label: {
                    Label(pickedURL == nil ? "Choose…" : "Change…", systemImage: "folder")
                }
            }
            Text("Accepts the .xlsx export, or the “.csv” export (which C4S writes as pipe-delimited).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Store row

    private var storeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Store").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Picker("", selection: $store) {
                Text("Curse Of Curves (CoC)").tag("CoC")
                Text("Princess Of Addiction (PoA)").tag("PoA")
            }
            .pickerStyle(.segmented)

            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                Text("All \(existingCount) existing \(store) row\(existingCount == 1 ? "" : "s") will be replaced.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Preview box

    private var previewBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Parsed \(preview.count) row\(preview.count == 1 ? "" : "s") — first 3 shown")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(preview.prefix(3).enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.clipId)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Text(row.title.isEmpty ? "—" : row.title)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text(row.priceDisplay).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private func pickFile() {
        let panel = NSOpenPanel()
        // Build the accepted-types list defensively. UTType.spreadsheet
        // covers most .xlsx files but some macOS releases hand them
        // back as `public.data`; UTType.commaSeparatedText covers .csv
        // (even though C4S writes pipe-delimited inside). We add the
        // raw extension-derived types AND fall back to allowing any
        // file so the picker never silently blocks a legitimate file.
        var types: [UTType] = []
        if let t = UTType(filenameExtension: "xlsx") { types.append(t) }
        if let t = UTType(filenameExtension: "csv")  { types.append(t) }
        types.append(contentsOf: [
            UTType.spreadsheet,
            UTType.commaSeparatedText,
            UTType.tabSeparatedText,
            UTType.plainText,
            UTType.text,
            UTType.data,
        ])
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a Clips4Sale storefront export (.xlsx or .csv)"
        if panel.runModal() == .OK, let url = panel.url {
            pickedURL = url
            // Preempt the store from the filename if it mentions one.
            let name = url.lastPathComponent.uppercased()
            if name.hasPrefix("COC") || name.contains("COC_") { store = "CoC" }
            else if name.hasPrefix("POA") || name.contains("POA_") { store = "PoA" }
            parseSelectedFile()
        }
    }

    private func parseSelectedFile() {
        guard let url = pickedURL else { return }
        error = nil
        preview = []
        parsing = true
        defer { parsing = false }
        do {
            preview = try C4SHistoricalImportService.parse(url: url, store: store)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func runImport() {
        guard let _ = pickedURL, !preview.isEmpty else { return }
        do {
            // Re-stamp every row with the current store choice in case the
            // user toggled the segmented control after parsing.
            let rows = preview.map { row -> C4SHistoricalRecord in
                var copy = row
                copy.store = store
                return copy
            }
            let count = try DatabaseService.shared.replaceC4SHistorical(store: store, with: rows)
            onComplete((store: store, count: count))
        } catch {
            self.error = "Import failed: \(error.localizedDescription)"
        }
    }

    private func refreshExistingCount() {
        existingCount = (try? DatabaseService.shared.c4sHistoricalCount(store: store)) ?? 0
    }
}
