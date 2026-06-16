import SwiftUI

/// Manage the scanned-path store: rename or forget individual roots, and auto-clean old
/// ones. "Forget" removes the DB rows (decisions) — it never deletes files on disk.
struct ScanRootsSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scanned Folders").font(.headline)
            Text("Forgetting a folder clears its saved decisions. It never deletes files on disk.")
                .font(.caption).foregroundStyle(.secondary)

            if appState.scanRoots.isEmpty {
                Text("No folders scanned yet.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(appState.scanRoots) { root in
                            rootRow(root)
                            Divider().opacity(0.2)
                        }
                    }
                }
            }

            Divider()

            Toggle("Automatically forget folders not scanned in a while", isOn: $store.settings.scanRootAutoCleanupEnabled)
            HStack {
                Stepper("After \(store.settings.scanRootAutoCleanupDays) days",
                        value: $store.settings.scanRootAutoCleanupDays, in: 1...3650, step: 30)
                    .disabled(!store.settings.scanRootAutoCleanupEnabled)
                Spacer()
                Button("Clean Up Now") { appState.cleanupOldScanRoots() }
            }
        }
        .padding(20)
    }

    private func rootRow(_ root: ScanRoot) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                TextField("Label", text: Binding(
                    get: { root.label ?? "" },
                    set: { appState.renameScanRoot(root.path, label: $0) }
                ))
                .textFieldStyle(.plain)
                .font(.body)
                Text(root.path).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text("\(root.totalFiles)").font(.caption).foregroundStyle(.secondary)
            Button(role: .destructive) {
                appState.deleteScanRoot(root.path)
            } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .help("Forget this folder")
        }
        .padding(.vertical, 6)
    }
}
