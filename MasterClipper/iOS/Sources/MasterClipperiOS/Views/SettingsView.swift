import SwiftUI
import MasterClipperCore

/// iOS-side settings + sync diagnostics. Surfaces the snapshot manifest
/// (clip count, when it was published, which Mac wrote it), lets the user
/// trigger a manual reload, and edits the operator name that appears on
/// notes added from the phone.
struct SettingsView: View {
    @EnvironmentObject private var appState: iOSAppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                snapshotSection
                identitySection
                pendingSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var snapshotSection: some View {
        Section("Snapshot") {
            if let manifest = appState.snapshotReader.manifest {
                LabeledContent("Clips", value: "\(manifest.clipCount)")
                LabeledContent("Thumbnails", value: "\(manifest.thumbnailCount)")
                LabeledContent("Published") {
                    Text(formatGeneratedAt(manifest.generatedAt))
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("From Mac", value: manifest.publisherDeviceId)
                    .font(.callout)
            } else {
                Text("No snapshot loaded yet.")
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await appState.snapshotReader.reload() }
            } label: {
                Label("Reload from iCloud", systemImage: "arrow.clockwise")
            }
            .disabled(appState.snapshotReader.isLoading)

            if let err = appState.snapshotReader.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    private var identitySection: some View {
        Section {
            TextField("Operator name", text: $appState.operatorName)
                .textInputAutocapitalization(.words)
        } header: {
            Text("Identity")
        } footer: {
            Text("Notes you add from this iPhone are stamped with this name when they sync to your Mac.")
        }
    }

    private var pendingSection: some View {
        let totalPending = appState.outbox.pendingByClipId.values.reduce(0) { $0 + $1.count }
        return Group {
            if totalPending > 0 {
                Section("Pending sync") {
                    LabeledContent("Waiting for Mac", value: "\(totalPending)")
                        .foregroundStyle(.orange)
                    Text("These changes are queued in iCloud. They apply automatically once your Mac picks them up.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Bundle", value: Bundle.main.bundleIdentifier ?? "—")
                .font(.caption.monospaced())
            LabeledContent("Version", value: Self.version)
                .font(.caption)
        }
    }

    private static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }

    private func formatGeneratedAt(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .short
        return out.string(from: date)
    }
}
