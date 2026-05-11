import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var assets: AssetResolver
    @EnvironmentObject var appState: AppState
    @State private var backupStatus: String = ""

    var body: some View {
        Form {
            Section("Console") {
                Picker("Transcription", selection: Binding(
                    get: { settings.transcriptionMode },
                    set: { settings.transcriptionMode = $0 }
                )) {
                    ForEach(TranscriptionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Picker("LED style", selection: Binding(
                    get: { settings.ledStyle },
                    set: { settings.ledStyle = $0 }
                )) {
                    ForEach(LEDStyle.allCases) { s in
                        Text(s.displayName).tag(s)
                    }
                }
            }

            Section("Audio") {
                Toggle("Sound effects",  isOn: $settings.audioEnabled)
                Toggle("Key clicks",     isOn: $settings.keyClickEnabled)
            }

            Section("Detective aids") {
                Toggle("Highlight unanswered notepad cells", isOn: $settings.showHints)
                Toggle("Reveal murderer on loss",             isOn: $settings.revealOnLoss)
            }

            Section("User assets") {
                Text(assets.assetsRoot.path)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                HStack {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([assets.assetsRoot])
                    }
                    Button("Refresh") { assets.refresh() }
                }
            }

            Section("Backup") {
                Toggle("Auto-backup on launch", isOn: $settings.autoBackupEnabled)
                Stepper("Retention: \(settings.backupRetentionDays) day\(settings.backupRetentionDays == 1 ? "" : "s")",
                        value: $settings.backupRetentionDays, in: 0...365)
                HStack {
                    Text("Last backup:")
                    Text(settings.lastBackupAt.isEmpty ? "never" : settings.lastBackupAt)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(BackupService.resolvedBackupPath().path)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                HStack {
                    Button("Run backup now") { runBackupNow() }
                    Button("Open backup folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([BackupService.resolvedBackupPath()])
                    }
                }
                if !backupStatus.isEmpty {
                    Text(backupStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Session") {
                Button("Forget current game", role: .destructive) {
                    appState.forgetCurrentSession()
                }
                .disabled(appState.session == nil)
            }

            Section {
                Text(AppVersion.display)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func runBackupNow() {
        do {
            let url = try BackupService.doBackup(settings: settings)
            backupStatus = "✓ Wrote \(url.lastPathComponent)"
        } catch {
            backupStatus = "✗ \(error.localizedDescription)"
        }
    }
}
