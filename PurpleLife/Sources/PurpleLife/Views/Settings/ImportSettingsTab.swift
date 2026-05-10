import SwiftUI

/// Phase 5 — Settings → Import. Today: just WeightTracker CSV. As
/// other PhantomLives imports land (Timeliner CSV, photo libraries,
/// etc.) they slot into this same tab as distinct sections.
struct ImportSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    @State private var report: WeightCSVImporter.Report?
    @State private var error: String?

    var body: some View {
        Form {
            Section("WeightTracker CSV") {
                Text("Imports weight entries from a `WeightTracker` CSV export (Date, Weight, Notes columns). Each row becomes a new Weight record with source = Imported. Duplicates aren't detected — the importer is additive.")
                    .font(.caption).foregroundStyle(.secondary)

                HStack {
                    Button {
                        runImport()
                    } label: {
                        Label("Pick CSV file…", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }

                if let report {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 12) {
                            Label("\(report.imported) imported", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            if report.skipped > 0 {
                                Label("\(report.skipped) skipped", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .font(.body)
                        if !report.errors.isEmpty {
                            DisclosureGroup("Errors (\(report.errors.count))") {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(Array(report.errors.prefix(20)), id: \.self) { line in
                                        Text(line)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.red)
                                    }
                                    if report.errors.count > 20 {
                                        Text("+\(report.errors.count - 20) more")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                }

                if let error {
                    Text(error)
                        .font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private func runImport() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            report = try WeightCSVImporter.importCSV(from: url)
            error = nil
            appState.reloadAll()
        } catch {
            self.error = error.localizedDescription
            report = nil
        }
    }
}
