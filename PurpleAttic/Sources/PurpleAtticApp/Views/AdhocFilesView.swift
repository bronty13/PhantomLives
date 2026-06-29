import SwiftUI
import PurpleAtticCore

/// Ad-hoc Files pane — Phase 3 (browse). A sortable, searchable table of the encrypted store's
/// contents, served instantly from the local cache and reconciled with B2 on Refresh. Names shown
/// here are the *decrypted* names (rclone lists through the crypt remote). Rename / delete / reports
/// (Phase 4) and diff/sync (Phase 5) build on this view.
struct AdhocFilesView: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var model = AdhocFilesModel()
    @State private var sortOrder = [KeyPathComparator(\AdhocFile.path)]

    private var config: AdhocBackupConfig? { store.profile.adhocBackup }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if config?.isConfigured != true {
                notConfigured
                Spacer()
            } else {
                searchBar
                table
                footer
            }
        }
        .padding(20)
        .onAppear { model.loadCached() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ad-hoc Files").font(.title3.weight(.semibold))
                Text("Browse your encrypted B2 store. Names shown are decrypted; the raw B2 console shows scrambled names.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                if let c = config { model.refresh(config: c) }
            } label: {
                if model.isRefreshing { ProgressView().controlSize(.small) }
                else { Label("Refresh", systemImage: "arrow.clockwise") }
            }
            .disabled(model.isRefreshing || config?.isConfigured != true)
        }
    }

    private var notConfigured: some View {
        Card(title: "Not set up yet") {
            Text("Configure the ad-hoc B2 store in the **Ad-hoc B2** tab (bucket, credentials, encryption passphrase), then come back here to browse it.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter by name or path…", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Table

    private var table: some View {
        Table(model.filtered.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { f in
                HStack(spacing: 6) {
                    Image(systemName: f.isDir ? "folder" : "doc").foregroundStyle(.secondary)
                    Text(f.name).lineLimit(1).truncationMode(.middle)
                }
            }
            TableColumn("Path", value: \.path) { f in
                Text(f.path).font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            TableColumn("Size", value: \.size) { f in
                Text(f.isDir ? "—" : human(f.size)).monospacedDigit()
            }
            TableColumn("Modified", value: \.modTime) { f in
                Text(f.modTime, format: .dateTime.year().month().day().hour().minute())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            let shown = model.filtered.count
            let total = model.files.count
            Text(shown == total ? "\(total) item(s)" : "\(shown) of \(total) item(s)")
                .font(.caption).foregroundStyle(.secondary)
            Text("·").foregroundStyle(.secondary)
            Text(human(model.totalBytes)).font(.caption).foregroundStyle(.secondary)
            Spacer()
            if let m = model.statusMessage {
                Label(m, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
            }
            if let e = model.lastError {
                Label(e, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
            if model.files.isEmpty && model.statusMessage == nil && model.lastError == nil {
                Text("Empty — hit Refresh after a backup.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func human(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
