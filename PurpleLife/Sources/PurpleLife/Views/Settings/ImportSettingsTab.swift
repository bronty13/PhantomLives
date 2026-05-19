import SwiftUI

/// Phase 5 — Settings → Import. Surfaces Purple Import: the saved
/// mappings list (each mapping is a `.purplelifemapping.json` file
/// under `~/Library/Application Support/PurpleLife/mappings/`) plus
/// the launchers for "New mapping" and "Import from file…".
///
/// The legacy WeightTracker CSV one-shot lives below — it predates
/// Purple Import and still works without going through a saved
/// mapping. A Phase 6 follow-up will ship a built-in mapping that
/// supersedes it.
struct ImportSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    @State private var wizardModel: ImportWizardModel?
    @State private var legacyReport: WeightCSVImporter.Report?
    @State private var legacyError: String?

    var body: some View {
        Form {
            Section("Saved import mappings") {
                Text("Purple Import — bring data in from CSV / JSON files and graphically map columns to schema fields. Save mappings here to re-run them later, or share them as `.purplelifemapping.json` files.")
                    .font(.caption).foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button {
                        startNewWizard()
                    } label: {
                        Label("New mapping…", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        importMappingFromFile()
                    } label: {
                        Label("Import mapping…", systemImage: "square.and.arrow.down")
                    }

                    Spacer()

                    Button {
                        appState.mappingStore.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Reload from disk")
                }

                if appState.mappingStore.mappings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No saved mappings yet.")
                            .font(.callout).foregroundStyle(.secondary)
                        Text("Pick **New mapping…** to walk the wizard and save the result.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                } else {
                    ForEach(appState.mappingStore.mappings) { mapping in
                        mappingRow(mapping)
                    }
                }
            }

            Section("Legacy: WeightTracker CSV") {
                Text("Imports weight entries from a `WeightTracker` CSV export (Date, Weight, Notes columns). Each row becomes a new Weight record with source = Imported. Predates Purple Import; will be folded into a built-in mapping in a later release.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button {
                        runLegacyImport()
                    } label: {
                        Label("Pick CSV file…", systemImage: "square.and.arrow.down")
                    }
                    Spacer()
                }
                if let report = legacyReport {
                    HStack(spacing: 12) {
                        Label("\(report.imported) imported", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if report.skipped > 0 {
                            Label("\(report.skipped) skipped", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.body)
                }
                if let err = legacyError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        // .sheet(item:) instead of .sheet(isPresented:) + conditional
        // content — the isPresented variant occasionally rendered an
        // empty sheet body because the @State write ordering put the
        // sheet's content closure on a code path where wizardModel
        // was still nil. .sheet(item:) presents only when the
        // optional is non-nil and passes the non-nil value through.
        .sheet(item: $wizardModel) { m in
            ImportWizardSheet(model: m)
                .environmentObject(appState)
        }
    }

    // MARK: - Rows

    private func mappingRow(_ mapping: SavedImportMapping) -> some View {
        HStack(spacing: 10) {
            Image(systemName: mapping.sourceFormat.systemImage)
                .frame(width: 18).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(mapping.name).font(.body)
                Text("\(mapping.sourceFormat.displayName) → \(targetLabel(mapping))")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                runSaved(mapping)
            } label: {
                Label("Run", systemImage: "play.fill")
            }
            Menu {
                Button("Edit…") { editSaved(mapping) }
                Button("Duplicate") { _ = try? appState.mappingStore.duplicate(id: mapping.id) }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([
                        appState.mappingStore.fileURL(for: mapping.id)
                    ])
                }
                Button("Export Mapping…") { exportMapping(mapping) }
                Divider()
                Button("Delete", role: .destructive) {
                    appState.mappingStore.delete(id: mapping.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
    }

    private func targetLabel(_ mapping: SavedImportMapping) -> String {
        if let id = mapping.targetTypeId, let t = appState.schema.type(id: id) {
            return t.name
        }
        if let t = mapping.newTypeTemplate { return "\(t.name) (new)" }
        return "—"
    }

    // MARK: - Actions

    private func startNewWizard() {
        wizardModel = ImportWizardModel(
            draft: .newDraft(),
            sink: appState.purpleImportSink,
            mappingStore: appState.mappingStore
        )
    }

    private func runSaved(_ mapping: SavedImportMapping) {
        wizardModel = ImportWizardModel(
            draft: mapping,
            sink: appState.purpleImportSink,
            mappingStore: appState.mappingStore
        )
    }

    private func editSaved(_ mapping: SavedImportMapping) {
        runSaved(mapping)
    }

    private func importMappingFromFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let mapping = try MappingStore.decodeFile(at: url, key: appState.keyStore.currentKey)
            _ = try appState.mappingStore.save(mapping)
        } catch {
            legacyError = "Couldn't import mapping: \(error.localizedDescription)"
        }
    }

    private func exportMapping(_ mapping: SavedImportMapping) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(mapping.name).purplelifemapping.json"
        panel.directoryURL = appState.settingsStore.resolvedExportDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let envelope = SavedImportMappingEnvelope(mapping)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(envelope)
            try data.write(to: url, options: .atomic)
        } catch {
            legacyError = "Couldn't export mapping: \(error.localizedDescription)"
        }
    }

    private func runLegacyImport() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            legacyReport = try WeightCSVImporter.importCSV(from: url)
            legacyError = nil
            appState.reloadAll()
        } catch {
            legacyError = error.localizedDescription
            legacyReport = nil
        }
    }
}
