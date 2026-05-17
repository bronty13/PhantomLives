import SwiftUI
import AppKit

struct SFTPDeliveryView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var destinations: [SFTPDestination] = SFTPDestinationStore.load()
    @State private var selectedID: SFTPDestination.ID?
    @State private var editing = SFTPDestination()
    @State private var pickedFiles: [URL] = []
    @State private var runningJob: SFTPJob?
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                destinationsList
                    .frame(width: 220)
                Divider()
                detailPane
            }
            Divider()
            footer
        }
        .frame(minWidth: 820, minHeight: 560)
        .onAppear(perform: hydrate)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Image(systemName: "network")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("SFTP Delivery").font(.title2.bold())
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    private var destinationsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selectedID) {
                Section("Destinations") {
                    ForEach(destinations) { dst in
                        HStack {
                            Image(systemName: "server.rack")
                                .foregroundStyle(.secondary)
                            Text(dst.displayName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .tag(Optional(dst.id))
                    }
                    .onDelete { idx in
                        destinations.remove(atOffsets: idx)
                        SFTPDestinationStore.save(destinations)
                    }
                }
            }
            Divider()
            HStack {
                Button {
                    addNew()
                } label: { Label("New", systemImage: "plus") }
                Spacer()
                Button {
                    duplicateSelected()
                } label: { Image(systemName: "doc.on.doc") }
                .disabled(selectedID == nil)
            }
            .padding(8)
        }
        .onChange(of: selectedID) { _, _ in loadSelectedIntoEditor() }
    }

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                editorForm
                Divider()
                filePickerSection
                if let job = runningJob {
                    Divider()
                    progressSection(job: job)
                }
            }
            .padding(16)
        }
    }

    private var editorForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Destination").font(.headline)
            Form {
                TextField("Nickname (optional)", text: $editing.nickname)
                TextField("Host", text: $editing.host)
                    .textContentType(.URL)
                HStack {
                    TextField("User", text: $editing.user)
                    Text("Port:")
                    TextField("22", value: $editing.port, format: .number)
                        .frame(width: 60)
                }
                TextField("Remote path", text: $editing.remotePath)
                    .help("e.g. /home/alice/deliveries — created with mkdir on connect")
                TextField("Identity file (optional)", text: $editing.identityFile)
                    .help("Absolute or ~/-prefixed path to a private key. Leave empty to use ssh-agent / ~/.ssh/config.")
                Toggle("Accept new host keys automatically",
                        isOn: $editing.acceptNewHostKeys)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Save Destination") { saveEditor() }
                    .disabled(!editing.isValid)
            }
        }
    }

    private var filePickerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Files to upload").font(.headline)
                Spacer()
                Button {
                    pickFiles()
                } label: { Label("Add Files…", systemImage: "plus") }
                Button {
                    pickFromCatalogue()
                } label: { Label("All catalogued", systemImage: "tray.full") }
                .disabled(appState.assets.isEmpty)
            }
            if pickedFiles.isEmpty {
                Text("Pick files to deliver — local clips, transcoded proxies, or anything else from disk.")
                    .foregroundStyle(.secondary).font(.caption)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(pickedFiles.enumerated()), id: \.offset) { idx, url in
                    HStack {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            pickedFiles.remove(at: idx)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func progressSection(job: SFTPJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Progress").font(.headline)
                Spacer()
                if job.isRunning {
                    ProgressView().controlSize(.small)
                }
                Text(job.summary).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(job.items) { item in
                SFTPFileRow(item: item)
            }
            DisclosureGroup("Raw sftp log", isExpanded: $showLog) {
                ScrollView {
                    Text(job.rawLog.isEmpty ? "(no output yet)" : job.rawLog)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Start Upload") { startUpload() }
                .keyboardShortcut(.defaultAction)
                .disabled(!editing.isValid || pickedFiles.isEmpty
                          || runningJob?.isRunning == true)
        }
        .padding(16)
    }

    // MARK: - Actions

    private func hydrate() {
        if selectedID == nil, let first = destinations.first {
            selectedID = first.id
            editing = first
        }
    }

    private func addNew() {
        var fresh = SFTPDestination()
        fresh.nickname = "New destination"
        destinations.append(fresh)
        SFTPDestinationStore.save(destinations)
        selectedID = fresh.id
        editing = fresh
    }

    private func duplicateSelected() {
        guard let id = selectedID,
              var copy = destinations.first(where: { $0.id == id }) else { return }
        copy.id = UUID()
        copy.nickname = (copy.nickname.isEmpty ? "Destination" : copy.nickname) + " (copy)"
        destinations.append(copy)
        SFTPDestinationStore.save(destinations)
        selectedID = copy.id
        editing = copy
    }

    private func loadSelectedIntoEditor() {
        guard let id = selectedID,
              let dst = destinations.first(where: { $0.id == id }) else { return }
        editing = dst
    }

    private func saveEditor() {
        if let idx = destinations.firstIndex(where: { $0.id == editing.id }) {
            destinations[idx] = editing
        } else {
            destinations.append(editing)
            selectedID = editing.id
        }
        SFTPDestinationStore.save(destinations)
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            pickedFiles.append(contentsOf: panel.urls.filter { !pickedFiles.contains($0) })
        }
    }

    private func pickFromCatalogue() {
        let urls = appState.assets.map { URL(fileURLWithPath: $0.path) }
        pickedFiles = urls
    }

    private func startUpload() {
        saveEditor()
        let items = pickedFiles.map { url -> SFTPFileItem in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            return SFTPFileItem(localURL: url, remoteName: url.lastPathComponent,
                                 sizeBytes: size ?? 0)
        }
        let job = SFTPJob(destination: editing, items: items)
        runningJob = job
        showLog = false
        Task { await SFTPService.run(job: job) }
    }
}

private struct SFTPFileRow: View {
    @ObservedObject var item: SFTPFileItem

    var body: some View {
        HStack(spacing: 8) {
            stateIcon
            Text(item.remoteName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(stateLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch item.state {
        case .queued:
            Image(systemName: "circle").foregroundStyle(.secondary)
        case .uploading:
            Image(systemName: "arrow.up.circle").foregroundStyle(.tint)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    private var stateLabel: String {
        switch item.state {
        case .queued: return "queued"
        case .uploading: return "uploading"
        case .done: return "done"
        case .failed(let msg): return msg
        }
    }
}
