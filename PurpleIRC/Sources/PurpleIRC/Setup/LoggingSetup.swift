import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Logging

/// Persistent chat-log toggles, retention policy, and the legacy plaintext
/// conversion path. Lifted out of Behavior so a user worried about disk
/// usage or compliance has a single tab to audit.
struct LoggingSetup: View {
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject var model: ChatModel
    @State private var legacyLogCount: Int = 0
    @State private var showConvertConfirm: Bool = false
    @State private var convertResultMessage: String? = nil

    var body: some View {
        Form {
            Section("Persistent logs") {
                Toggle("Enable persistent logs",
                       isOn: $settings.settings.enablePersistentLogs)
                Toggle("Include server MOTD and info lines",
                       isOn: $settings.settings.logMotdAndNumerics)
                LabeledContent("Log directory") {
                    Text(settings.logsDirectoryURL.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text("Logs rotate at 4 MB per channel. File names are SHA-256 hashes of the network and channel/nick, so someone browsing the folder can't tell which channels you log.")
                    .font(.caption).foregroundStyle(.tertiary)
                if legacyLogCount > 0 {
                    HStack {
                        Label("\(legacyLogCount) plaintext log file\(legacyLogCount == 1 ? "" : "s") left over from before encryption was on.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Convert and delete originals…") {
                            showConvertConfirm = true
                        }
                    }
                }
                if let msg = convertResultMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Retention") {
                Toggle("Auto-delete logs older than N days",
                       isOn: $settings.settings.purgeLogsEnabled)
                Stepper(value: $settings.settings.purgeLogsAfterDays, in: 1...3650) {
                    HStack {
                        Text("Days to keep")
                        Spacer()
                        TextField("",
                                  value: $settings.settings.purgeLogsAfterDays,
                                  format: .number.grouping(.never))
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .disabled(!settings.settings.purgeLogsEnabled)
                HStack {
                    Button("Purge now") { model.purgeLogsNow() }
                    Spacer()
                    Text("Runs at app launch when the toggle is on. Off by default; suggested value is 90 days.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.trailing)
                }
            }
            Section("Diagnostic log") {
                Text("App-level events (debug → critical) live in the in-app diagnostic log, encrypted on disk. Open it via /log, the Help menu, or the Files menu. Useful for bug reports.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshLegacyLogCount() }
        .confirmationDialog(
            "Convert \(legacyLogCount) plaintext log file\(legacyLogCount == 1 ? "" : "s")?",
            isPresented: $showConvertConfirm,
            titleVisibility: .visible
        ) {
            Button("Convert and delete originals", role: .destructive) {
                model.convertLegacyPlaintextLogs { count in
                    convertResultMessage = "Converted \(count) file\(count == 1 ? "" : "s") and removed the plaintext originals."
                    refreshLegacyLogCount()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Each plaintext log will be re-encrypted into the matching encrypted file. The original plaintext file is deleted only after every record is written successfully.")
        }
    }

    private func refreshLegacyLogCount() {
        model.legacyPlaintextLogCount { n in legacyLogCount = n }
    }
}

