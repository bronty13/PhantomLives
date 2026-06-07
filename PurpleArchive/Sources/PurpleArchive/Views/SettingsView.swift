import SwiftUI
import ArchiveKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            BackupSettingsView()
                .tabItem { Label("Backup", systemImage: "externaldrive.badge.timemachine") }
        }
        .frame(width: 520, height: 380)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Compression defaults") {
                Picker("Default format", selection: Binding(
                    get: { settings.defaultFormat },
                    set: { settings.settings.defaultFormatRaw = $0.rawValue })) {
                    ForEach(ArchiveFormat.allCases.filter { $0.canCreate }, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                Stepper("Level: \(settings.settings.defaultLevel)",
                        value: $settings.settings.defaultLevel, in: 0...22)
                Toggle("Strip .DS_Store / __MACOSX (cross-platform clean)",
                       isOn: $settings.settings.stripMacMetadata)
            }
            Section("Locations") {
                LabeledContent("Extract to") {
                    Text(settings.resolvedExtractRoot.path)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Button("Choose Extract Folder…") {
                    if let url = pickFolder() {
                        settings.settings.defaultExtractPath = url.path
                    }
                }
            }
        }
        .formStyle(.grouped).padding()
    }
}

struct BackupSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var backups: [(url: URL, modified: Date, size: Int)] = []
    @State private var statusLine = ""

    var body: some View {
        Form {
            Section("Automatic backup") {
                Toggle("Back up on launch", isOn: $settings.settings.autoBackupEnabled)
                Stepper("Keep for \(settings.settings.backupRetentionDays) days",
                        value: $settings.settings.backupRetentionDays, in: 0...365)
                LabeledContent("Location") {
                    Text(settings.resolvedBackupPath.path)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                HStack {
                    Button("Choose Folder…") {
                        if let url = pickFolder() { settings.settings.customBackupPath = url.path; refresh() }
                    }
                    Button("Back Up Now") { backupNow() }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([settings.resolvedBackupPath])
                    }
                }
                if let last = settings.settings.lastBackupAt {
                    Text("Last backup: \(last)").font(.caption).foregroundStyle(.tertiary)
                }
                if !statusLine.isEmpty {
                    Text(statusLine).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Recent backups") {
                if backups.isEmpty {
                    Text("No backups yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(backups, id: \.url) { b in
                        HStack {
                            Text(b.url.lastPathComponent).font(.caption).lineLimit(1)
                            Spacer()
                            Text(ByteFormat.string(Int64(b.size))).font(.caption).foregroundStyle(.secondary)
                            Button("Reveal") {
                                NSWorkspace.shared.activateFileViewerSelecting([b.url])
                            }.controlSize(.small)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped).padding()
        .onAppear(perform: refresh)
    }

    private func refresh() { backups = BackupService.listBackups(in: settings.resolvedBackupPath) }

    private func backupNow() {
        do {
            let url = try BackupService.doBackup(settingsStore: settings)
            statusLine = "Wrote \(url.lastPathComponent)"
            refresh()
        } catch {
            statusLine = "Backup failed: \(error.localizedDescription)"
        }
    }
}

func pickFolder() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    return panel.runModal() == .OK ? panel.url : nil
}
