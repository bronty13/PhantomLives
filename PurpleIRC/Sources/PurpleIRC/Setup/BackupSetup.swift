import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Backup

/// Lifts BackupSettingsRow + FactoryResetRow into their own tab so the
/// "I want to safeguard / reset my data" task is one click from Setup
/// instead of buried under Behavior.
struct BackupSetup: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Backups") {
                BackupSettingsRow(settings: settings)
            }
            Section("Factory reset") {
                FactoryResetRow()
                Text("Use the destructive `/nuke` slash command (or PurpleIRC menu → Reset Everything…) when you're sure: it wipes every file PurpleIRC has on disk plus every Keychain item, then quits.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }
}

