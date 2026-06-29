import SwiftUI
import PurpleAtticCore

/// Ad-hoc Files pane — browse + manage & report. A **folder-tree** (outline) `Table` of the
/// encrypted store's contents: folders (derived from the decrypted paths) expand to reveal their
/// subfolders and files, n levels deep. Served from the local cache, reconciled with B2 on Refresh.
/// Select a *file* row to rename (server-side) or permanently delete (typed confirmation); export a
/// report (CSV / JSON / text). Searching flattens to matching files by full path.
struct AdhocFilesView: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var model = AdhocFilesModel()
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDelete = false
    @State private var deleteConfirmText = ""

    private var config: AdhocBackupConfig? { store.profile.adhocBackup }
    private var selectedFile: AdhocFile? { model.files.first { $0.id == model.selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if config?.isConfigured != true {
                notConfigured
                Spacer()
            } else {
                actionsBar
                searchBar
                table
                footer
            }
        }
        .padding(20)
        .onAppear { model.loadCached() }
        .sheet(isPresented: $showRename) { renameSheet }
        .sheet(isPresented: $showDelete) { deleteSheet }
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

    // MARK: - Actions

    private var actionsBar: some View {
        HStack(spacing: 8) {
            Button {
                renameText = selectedFile?.path ?? ""
                showRename = true
            } label: { Label("Rename", systemImage: "pencil") }
                .disabled(selectedFile == nil || model.isMutating)
            Button(role: .destructive) {
                deleteConfirmText = ""
                showDelete = true
            } label: { Label("Delete", systemImage: "trash") }
                .disabled(selectedFile == nil || model.isMutating)
            if model.isMutating { ProgressView().controlSize(.small) }
            Spacer()
            Menu {
                ForEach(AdhocReport.Format.allCases, id: \.self) { fmt in
                    Button(fmt.label) { model.exportReport(format: fmt) }
                }
            } label: { Label("Export report", systemImage: "square.and.arrow.up") }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(model.files.isEmpty)
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

    // MARK: - Tree table

    /// Outline nodes: empty search → the full folder hierarchy; active search → a flat list of
    /// matching files (full paths, so a match is locatable regardless of depth).
    private var nodes: [AdhocNode] {
        let q = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.isEmpty else {
            return model.files
                .filter { $0.path.lowercased().contains(q) || $0.name.lowercased().contains(q) }
                .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
                .map { AdhocNode(id: $0.path, name: $0.path, isDir: false, size: max(0, $0.size),
                                 fileCount: 1, modTime: $0.modTime, file: $0, children: nil) }
        }
        return AdhocTree.build(model.files)
    }

    private var table: some View {
        Table(nodes, children: \.children, selection: $model.selection) {
            TableColumn("Name") { node in
                HStack(spacing: 6) {
                    Image(systemName: node.isDir ? "folder.fill" : "doc")
                        .foregroundStyle(node.isDir ? Color.accentColor : .secondary)
                    Text(node.name).lineLimit(1).truncationMode(.middle)
                }
            }
            TableColumn("Size") { node in
                Text(human(node.size)).monospacedDigit()
                    .foregroundStyle(node.isDir ? .secondary : .primary)
            }
            TableColumn("Items / Modified") { node in
                if node.isDir {
                    Text("\(node.fileCount) item\(node.fileCount == 1 ? "" : "s")").foregroundStyle(.secondary)
                } else if let m = node.modTime {
                    Text(m, format: .dateTime.year().month().day().hour().minute()).foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
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
                    .lineLimit(1).truncationMode(.middle)
            }
            if let e = model.lastError {
                Label(e, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    .lineLimit(1).truncationMode(.middle)
            }
            if model.files.isEmpty && model.statusMessage == nil && model.lastError == nil {
                Text("Empty — hit Refresh after a backup.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Rename sheet

    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename").font(.title2.weight(.semibold))
            Text("Renaming moves the object within the store (server-side; no re-upload). Enter the new path relative to the store root.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("new/path/name.ext", text: $renameText)
                .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
            HStack {
                Button("Cancel") { showRename = false }
                Spacer()
                Button {
                    guard let c = config, let file = selectedFile else { return }
                    model.rename(config: c, file: file, toPath: renameText) { ok in if ok { showRename = false } }
                } label: {
                    if model.isMutating { ProgressView().controlSize(.small) } else { Text("Rename") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isMutating || renameText.trimmingCharacters(in: .whitespaces).isEmpty
                          || renameText == selectedFile?.path)
            }
        }
        .padding(20).frame(width: 520)
    }

    // MARK: - Delete sheet (typed confirmation)

    private var deleteSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Permanently delete", systemImage: "exclamationmark.octagon.fill")
                .font(.title2.weight(.semibold)).foregroundStyle(.red)
            if let f = selectedFile {
                Text("This **permanently** deletes the file from B2 — it cannot be recovered. To confirm, type its name:")
                    .font(.callout).foregroundStyle(.secondary)
                Text(f.name).font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                TextField("type the name to confirm", text: $deleteConfirmText)
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
            }
            HStack {
                Button("Cancel") { showDelete = false }
                Spacer()
                Button(role: .destructive) {
                    guard let c = config, let file = selectedFile else { return }
                    model.delete(config: c, file: file) { ok in if ok { showDelete = false } }
                } label: {
                    if model.isMutating { ProgressView().controlSize(.small) } else { Text("Delete permanently") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isMutating || deleteConfirmText != selectedFile?.name)
            }
        }
        .padding(20).frame(width: 520)
    }

    private func human(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
