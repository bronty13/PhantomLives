import AppKit
import SwiftUI

/// Settings → Export. Two sections:
///
///   • **Default export directory** — overrides where the
///     Records → Export menu and Purple Export's default-mode
///     destinations write files. Per the PhantomLives convention,
///     unset means `~/Downloads/PurpleLife/`. Persists in
///     `settings.json`.
///
///   • **Saved export configurations** — the Purple Export
///     equivalent of Settings → Import's saved mappings list.
///     Each config lives as its own `.purpleexport.json` file
///     under `~/Library/Application Support/PurpleLife/export-configs/`.
struct ExportSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    @State private var wizardModel: ExportWizardModel?
    @State private var importError: String?

    var body: some View {
        Form {
            // Saved configs first — that's the high-leverage surface
            // for repeat use. Default-dir picker moves below it.
            Section("Saved export configurations") {
                Text("Purple Export — pick a type, choose fields, output to CSV / JSON / XML / Markdown / HTML / PDF. Save configurations here to re-run them later, or share them as `.purpleexport.json` files.")
                    .font(.caption).foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button {
                        startNewWizard()
                    } label: {
                        Label("New config…", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        importConfigFromFile()
                    } label: {
                        Label("Import config…", systemImage: "square.and.arrow.down")
                    }

                    Spacer()

                    Button {
                        appState.exportConfigStore.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Reload from disk")
                }

                if appState.exportConfigStore.configs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No saved configurations yet.")
                            .font(.callout).foregroundStyle(.secondary)
                        Text("Pick **New config…** to walk the wizard and save the result.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                } else {
                    ForEach(appState.exportConfigStore.configs) { c in
                        configRow(c)
                    }
                }

                if let err = importError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Default export directory") {
                Text("Where the Records → Export menu writes files when invoked without a Purple Export config, and where Purple Export's default destination mode lands.")
                    .font(.caption).foregroundStyle(.secondary)

                HStack {
                    TextField("(default: ~/Downloads/PurpleLife)", text: Binding(
                        get: { appState.settings.defaultExportDirectory },
                        set: { var s = appState.settings; s.defaultExportDirectory = $0; appState.settings = s }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Button("Choose…") { chooseDir() }
                    Button("Reveal") { reveal() }
                        .disabled(!FileManager.default.fileExists(atPath: appState.settingsStore.resolvedExportDirectory.path))
                }

                Text("Resolved: \(appState.settingsStore.resolvedExportDirectory.path)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .sheet(item: $wizardModel) { m in
            ExportWizardSheet(model: m)
                .environmentObject(appState)
        }
    }

    // MARK: - Rows

    private func configRow(_ config: SavedExportConfig) -> some View {
        HStack(spacing: 10) {
            Image(systemName: config.format.systemImage)
                .frame(width: 18).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(config.name).font(.body)
                Text("\(typeLabel(for: config)) → \(config.format.displayName)")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                runSaved(config)
            } label: {
                Label("Run", systemImage: "play.fill")
            }
            Menu {
                Button("Edit…") { editSaved(config) }
                Button("Duplicate") { _ = try? appState.exportConfigStore.duplicate(id: config.id) }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([
                        appState.exportConfigStore.fileURL(for: config.id)
                    ])
                }
                Button("Export Config…") { exportConfig(config) }
                Divider()
                Button("Delete", role: .destructive) {
                    appState.exportConfigStore.delete(id: config.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
    }

    private func typeLabel(for config: SavedExportConfig) -> String {
        if let id = config.typeId, let t = appState.schema.type(id: id) { return t.name }
        return "—"
    }

    // MARK: - Wizard launchers

    private func startNewWizard() {
        wizardModel = ExportWizardModel(
            draft: .newDraft(),
            source: appState.purpleExportSource,
            configStore: appState.exportConfigStore,
            defaultDirectory: appState.settingsStore.resolvedExportDirectory
        )
    }

    private func runSaved(_ config: SavedExportConfig) {
        wizardModel = ExportWizardModel(
            draft: config,
            source: appState.purpleExportSource,
            configStore: appState.exportConfigStore,
            defaultDirectory: appState.settingsStore.resolvedExportDirectory
        )
    }

    private func editSaved(_ config: SavedExportConfig) { runSaved(config) }

    // MARK: - File pickers

    private func importConfigFromFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let config = try ExportConfigStore.decodeFile(at: url, key: appState.keyStore.currentKey)
            _ = try appState.exportConfigStore.save(config)
            importError = nil
        } catch {
            importError = "Couldn't import config: \(error.localizedDescription)"
        }
    }

    private func exportConfig(_ config: SavedExportConfig) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(config.name).purpleexport.json"
        panel.directoryURL = appState.settingsStore.resolvedExportDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let envelope = SavedExportConfigEnvelope(config)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(envelope)
            try data.write(to: url, options: .atomic)
        } catch {
            importError = "Couldn't export config: \(error.localizedDescription)"
        }
    }

    private func chooseDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            var s = appState.settings
            s.defaultExportDirectory = url.path
            appState.settings = s
        }
    }

    private func reveal() {
        let url = appState.settingsStore.resolvedExportDirectory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
