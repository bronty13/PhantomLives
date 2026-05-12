import SwiftUI
import MasterClipperCore

struct SyncSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var publisher = SnapshotPublisher.shared

    var body: some View {
        Form {
            Section("iCloud snapshot") {
                Toggle("Publish snapshot to iCloud", isOn: Binding(
                    get: { appState.settings.iCloudPublishEnabled },
                    set: { newVal in
                        var s = appState.settings
                        s.iCloudPublishEnabled = newVal
                        appState.settings = s
                    }
                ))

                Text("When on, MasterClipper writes a read-only snapshot of your library into iCloud Drive 30 seconds after each change. The iOS app reads from that snapshot — it never touches your live database.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let url = publisher.ubiquityContainer {
                    LabeledContent("Container") {
                        Text(url.path)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                } else {
                    Text("⚠︎ iCloud container not available. Confirm you're signed in to iCloud and that this app has iCloud Drive access in System Settings.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Last publish") {
                LabeledContent("Status") {
                    if publisher.isPublishing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Publishing…")
                        }
                    } else if let when = publisher.lastPublishedAt {
                        Text(when.formatted(date: .abbreviated, time: .shortened))
                    } else {
                        Text("Never").foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Clips") {
                    Text("\(publisher.lastClipCount)")
                }

                LabeledContent("Thumbnails") {
                    Text("\(publisher.lastThumbnailCount)")
                }

                if let size = publisher.lastSnapshotSize {
                    LabeledContent("Snapshot size") {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    }
                }

                if let err = publisher.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            Section {
                HStack {
                    Button {
                        Task { await publisher.publishNow() }
                    } label: {
                        Label("Publish now", systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(publisher.isPublishing || publisher.ubiquityContainer == nil)

                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
    }
}
