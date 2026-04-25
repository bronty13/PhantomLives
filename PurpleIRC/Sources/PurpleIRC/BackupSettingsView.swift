import SwiftUI

/// Setup → Behavior → Backups subsection. Toggle, directory picker,
/// retention slider, "Run backup now" button, and a list of recent
/// backups so the user can see the safety net in action.
struct BackupSettingsRow: View {
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject var model: ChatModel

    /// Manual-backup status surfaced inline. The async runBackupNow
    /// returns the URL on success or throws; we render the most recent
    /// outcome so the user can confirm a click did something.
    @State private var lastResult: Result<URL, Error>?
    @State private var running: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Back up settings + data on every launch",
                   isOn: $settings.settings.backupEnabled)
            Text("Compresses the support folder into an encrypted archive at the path below. Each launch writes a fresh dated copy; older copies past the retention window are reaped automatically.")
                .font(.caption).foregroundStyle(.tertiary)

            HStack {
                Text("Directory").frame(width: 90, alignment: .trailing)
                TextField("~/Downloads/PurpleIRC backup/",
                          text: $settings.settings.backupDirectory)
                    .textFieldStyle(.roundedBorder)
                Button("Pick…") { pickDirectory() }
            }
            HStack {
                Text("Retention").frame(width: 90, alignment: .trailing)
                Stepper(value: $settings.settings.backupRetentionDays,
                        in: 0...365, step: 1) {
                    Text(settings.settings.backupRetentionDays == 0
                         ? "Keep forever"
                         : "Delete backups older than \(settings.settings.backupRetentionDays) day\(settings.settings.backupRetentionDays == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("").frame(width: 90)
                Button {
                    runNow()
                } label: {
                    if running {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Run backup now", systemImage: "tray.and.arrow.down")
                    }
                }
                .disabled(running || !settings.settings.backupEnabled)
                Button("Open backup folder") { revealInFinder() }
                Spacer()
            }

            if let result = lastResult {
                switch result {
                case .success(let url):
                    Label("Wrote \(url.lastPathComponent)", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(Color.green)
                case .failure(let err):
                    Label(err.localizedDescription, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                }
            }

            recentBackupsList
        }
        .padding(.vertical, 4)
    }

    // MARK: - Recent backups list

    private var recentBackupsList: some View {
        let entries = BackupService.listBackups(in: model.backupDirectoryURL)
        return Group {
            if !entries.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent backups")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(entries.prefix(5), id: \.url) { entry in
                        HStack(spacing: 6) {
                            Image(systemName: "archivebox")
                                .foregroundStyle(.tertiary)
                            Text(entry.url.lastPathComponent)
                                .font(.caption.monospaced())
                            Spacer()
                            Text(Self.relative(entry.modified))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    if entries.count > 5 {
                        Text("+ \(entries.count - 5) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Actions

    private func runNow() {
        running = true
        lastResult = nil
        Task { @MainActor in
            do {
                let url = try await model.runBackupNow()
                self.lastResult = .success(url)
            } catch {
                self.lastResult = .failure(error)
            }
            self.running = false
        }
    }

    private func revealInFinder() {
        let url = model.backupDirectoryURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }

    private func pickDirectory() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"
        panel.directoryURL = model.backupDirectoryURL
        if panel.runModal() == .OK, let url = panel.url {
            settings.settings.backupDirectory = url.path
        }
        #endif
    }
}

/// Setup → Security → Factory reset row. Typed-confirmation guard so a
/// stray click can't wipe a user's data. Surfaces what gets removed and
/// what survives (the backup directory). On confirm, calls
/// `ChatModel.performFactoryReset` which wipes the support dir and
/// terminates the app so the next launch is genuinely fresh.
struct FactoryResetRow: View {
    @EnvironmentObject var model: ChatModel
    @State private var typedConfirm: String = ""
    @State private var showSheet: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Factory reset wipes every PurpleIRC data file: settings, keystore, logs, seen tracker, history, scripts, channel cache. Backups survive.",
                  systemImage: "trash.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(role: .destructive) {
                typedConfirm = ""
                showSheet = true
            } label: {
                Label("Factory reset…", systemImage: "exclamationmark.triangle.fill")
            }
        }
        .sheet(isPresented: $showSheet) {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)
                        .font(.largeTitle)
                    VStack(alignment: .leading) {
                        Text("Factory reset PurpleIRC")
                            .font(.title3.weight(.semibold))
                        Text("This is irreversible. Your settings, identities, address book, scripts, logs, seen tracker, and chat history will be deleted. Backups in your backup folder are NOT touched.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 6)
                Text("To confirm, type: DELETE")
                    .font(.caption)
                TextField("DELETE", text: $typedConfirm)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) {
                        showSheet = false
                    }
                    .keyboardShortcut(.cancelAction)
                    Button(role: .destructive) {
                        showSheet = false
                        model.performFactoryReset()
                    } label: {
                        Text("Wipe and quit")
                    }
                    .disabled(typedConfirm != "DELETE")
                }
            }
            .padding(20)
            .frame(width: 480)
        }
    }
}
