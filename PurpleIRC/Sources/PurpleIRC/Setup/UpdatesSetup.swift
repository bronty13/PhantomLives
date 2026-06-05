import SwiftUI

// MARK: - Updates

/// Software-update controls for the Sparkle auto-updater. The toggle and
/// "Check Now" button talk to `UpdaterController.shared`; the feed URL +
/// public EdDSA key are baked into Info.plist at build time (see build-app.sh /
/// RELEASING.md). PurpleIRC updates itself in place under /Applications.
struct UpdatesSetup: View {
    @ObservedObject private var updater = UpdaterController.shared

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        Form {
            Section("Software updates") {
                Toggle(isOn: $updater.automaticallyChecksForUpdates) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatically check for updates")
                        Text("PurpleIRC checks its release feed on launch and roughly every 24 hours when this is on. Even with it off, you can check any time with **Check Now** or the PurpleIRC menu's **Check for Updates…**.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                    Spacer()
                    if let last = updater.lastUpdateCheckDate {
                        Text("Last checked \(Self.relativeFormatter.localizedString(for: last, relativeTo: Date()))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("Not checked yet")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Section("This build") {
                LabeledContent("Version", value: AppVersion.display)
                Text("Updates are cryptographically signed (EdDSA) and verified against a key embedded in this app before installing — an update that doesn't verify is refused.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }
}
