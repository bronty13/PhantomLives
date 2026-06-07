import SwiftUI
import ArchiveKit

/// Browse an opened archive's contents in a table, with an Extract action.
/// Encryption prompts for a password before extracting.
struct ArchiveBrowserView: View {
    @EnvironmentObject var model: AppModel
    @State private var password = ""
    @State private var remember = false
    @State private var revealPassword = false
    @State private var showingPasswordSheet = false
    @State private var pendingAction: PendingAction = .extractAll
    /// Selected node ids (full paths within the archive).
    @State private var selection = Set<String>()
    @State private var renaming: ArchiveEntry?
    @State private var newName = ""

    /// What the password sheet should do once a password is supplied (for
    /// encrypted archives with no Keychain-remembered password).
    private enum PendingAction {
        case extractAll
        case extractSelected([ArchiveEntry])
        case test
    }

    var body: some View {
        if model.openedURL == nil {
            emptyState
        } else {
            VStack(spacing: 0) {
                header
                Divider()
                columnHeader
                Divider()
                // Multi-level outline: folders expand to show their contents n
                // levels deep. Native disclosure + Finder-style multi-selection
                // (click / ⌘-click / ⇧-click / ⌘A).
                List(model.entryNodes, children: \.childrenOrNil, selection: $selection) { node in
                    row(node)
                        .contextMenu { contextMenu(for: node) }
                }
                .spaceToQuickLook(enabled: selectedFileEntry != nil) {
                    if let entry = selectedFileEntry { model.quickLook(entry) }
                }
            }
            .sheet(isPresented: $showingPasswordSheet) { passwordSheet }
            .sheet(item: $renaming) { entry in renameSheet(entry) }
            .sheet(item: $model.preview) { item in
                QuickLookSheet(item: item) { model.preview = nil }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.openedURL?.lastPathComponent ?? "")
                    .font(.headline).lineLimit(1).truncationMode(.middle)
                if let info = model.info {
                    Text("\(info.fileCount) files · \(ByteFormat.string(info.totalUncompressedSize))"
                         + (info.isEncrypted ? " · 🔒 encrypted" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !selection.isEmpty {
                Text("\(selection.count) selected")
                    .font(.caption).foregroundStyle(.purple)
            }
            Spacer()
            Button { if let entry = selectedFileEntry { model.quickLook(entry) } } label: {
                Image(systemName: "eye")
            }
            .help("Quick Look the selected file (Space)")
            .disabled(selectedFileEntry == nil || model.busy)
            Divider().frame(height: 16)
            if model.canEdit {
                Button { addFiles() } label: { Image(systemName: "plus") }
                    .help("Add files to this archive").disabled(model.busy)
                Button { deleteSelected(selection) } label: { Image(systemName: "trash") }
                    .help("Delete selected entries").disabled(model.busy || selection.isEmpty)
                Divider().frame(height: 16)
            }
            Menu {
                ForEach(model.availableEncodings) { enc in
                    Button {
                        model.selectedEncoding = enc
                    } label: {
                        if enc == model.selectedEncoding { Label(enc.label, systemImage: "checkmark") }
                        else { Text(enc.label) }
                    }
                }
            } label: {
                Label(model.selectedEncoding.label, systemImage: "textformat")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 200)
            .help("Filename text encoding — fix mojibake from Windows/Linux archives")

            Button { beginTest() } label: {
                Label("Test", systemImage: "checkmark.seal")
            }
            .disabled(model.busy)
            .help("Verify every entry decompresses correctly (integrity check)")

            // Primary extract: prompt for a destination folder first (so you
            // see/choose where files go before extracting), then extract the
            // selection — or everything when nothing is selected.
            Button { extractToFolder() } label: {
                Label(selection.isEmpty ? "Extract All…" : "Extract \(selection.count) Selected…",
                      systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent).tint(.purple)
            .disabled(model.busy || model.entries.isEmpty)
            .help(selection.isEmpty
                  ? "Choose a folder, then extract everything there"
                  : "Choose a folder, then extract the \(selection.count) selected item(s) there")

            // Secondary, quicker choices that skip the folder prompt.
            Menu {
                Button(selection.isEmpty
                       ? "Extract All to \(model.extractDestinationLabel)"
                       : "Extract Selected to \(model.extractDestinationLabel)") { beginExtract() }
                Button("Extract All Items to \(model.extractDestinationLabel)") { beginExtractAll() }
                    .disabled(model.entries.isEmpty)
                Divider()
                Button("Set Default Destination…") { chooseDestination() }
                if model.sessionExtractRoot != nil {
                    Button("Reset Default to \(model.settings.resolvedExtractRoot.lastPathComponent)") {
                        model.sessionExtractRoot = nil
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Other extract options & default destination")
            .disabled(model.busy)
        }
        .padding(12)
    }

    /// A lightweight column-title strip above the outline (List has no built-in
    /// column headers); the Size/Modified widths match the row trailing columns.
    private var columnHeader: some View {
        HStack(spacing: 6) {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Size").frame(width: 86, alignment: .trailing)
            Text("Modified").frame(width: 140, alignment: .trailing)
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 16).padding(.vertical, 4)
    }

    /// One outline row: name (indented by the List for depth) plus size and
    /// modified date right-aligned.
    private func row(_ node: ArchiveEntryNode) -> some View {
        HStack(spacing: 6) {
            Image(systemName: nodeIcon(node))
                .foregroundStyle(node.isDirectory ? Color.secondary : Color.blue)
                .frame(width: 18)
            Text(node.name).lineLimit(1).truncationMode(.middle)
            if node.entry?.isEncrypted == true {
                Image(systemName: "lock.fill").foregroundStyle(.orange).font(.caption)
            }
            Spacer(minLength: 12)
            Text(sizeText(node))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .frame(width: 86, alignment: .trailing)
            Text(node.entry?.modified.map { Self.dateFormatter.string(from: $0) } ?? "—")
                .font(.caption).foregroundStyle(.tertiary)
                .frame(width: 140, alignment: .trailing)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func contextMenu(for node: ArchiveEntryNode) -> some View {
        // Act on the whole selection if this row is part of it, else just it.
        let ids: Set<String> = selection.contains(node.id) ? selection : [node.id]
        if ids.count == 1, let entry = node.entry, !entry.isDirectory {
            Button { model.quickLook(entry) } label: { Label("Quick Look", systemImage: "eye") }
        }
        // Destination shown right here so it's clear where files will land.
        Section("Extract to  \(model.extractDestinationLabel)") {
            Button { beginExtractSelected(ids) } label: {
                Label(ids.count == 1 ? "Extract Here" : "Extract \(ids.count) Items Here",
                      systemImage: "arrow.down.circle")
            }
            Button { chooseDestinationThenExtract(ids) } label: {
                Label("Extract to Folder…", systemImage: "folder")
            }
        }
        if model.canEdit {
            Divider()
            if ids.count == 1, let entry = node.entry {
                Button("Rename…") { renaming = entry; newName = entry.displayPath }
            }
            Button("Delete", role: .destructive) { deleteSelected(ids) }
        }
    }

    private func sizeText(_ node: ArchiveEntryNode) -> String {
        if node.isDirectory {
            let n = node.fileCount
            return "\(n) item" + (n == 1 ? "" : "s")
        }
        return ByteFormat.string(node.entry?.uncompressedSize ?? 0)
    }

    private func nodeIcon(_ node: ArchiveEntryNode) -> String {
        if node.isDirectory { return "folder.fill" }
        if node.entry?.isSymlink == true { return "arrow.up.forward.app" }
        return "doc"
    }

    /// Find a node by its id (full path) anywhere in the tree.
    private func node(for id: String) -> ArchiveEntryNode? {
        func find(_ nodes: [ArchiveEntryNode]) -> ArchiveEntryNode? {
            for n in nodes {
                if n.id == id { return n }
                if let hit = find(n.children) { return hit }
            }
            return nil
        }
        return find(model.entryNodes)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 54)).foregroundStyle(.purple.opacity(0.5))
            Text("Drop an archive here").font(.title3)
            Text("ZIP · 7z · RAR · TAR · gz · bz2 · xz · zst · cab · iso · StuffIt · BinHex · and more")
                .font(.caption).foregroundStyle(.secondary)
            Button("Open Archive…") {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url { model.open(url) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var passwordSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This archive is encrypted").font(.headline)
            HStack(spacing: 8) {
                RevealableSecureField("Password", text: $password, reveal: $revealPassword)
                    .frame(width: 260)
                RevealToggle(reveal: $revealPassword)
            }
            Toggle("Remember in Keychain", isOn: $remember)
            HStack {
                Spacer()
                Button("Cancel") { showingPasswordSheet = false }
                Button(passwordSheetConfirmLabel) {
                    showingPasswordSheet = false
                    runPendingAction(password: password, remember: remember)
                    password = ""
                }
                .keyboardShortcut(.defaultAction).tint(.purple)
                .disabled(password.isEmpty)
            }
        }
        .padding(20)
    }

    private var passwordSheetConfirmLabel: String {
        if case .test = pendingAction { return "Test" }
        return "Extract"
    }

    private func renameSheet(_ entry: ArchiveEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename entry").font(.headline)
            TextField("New path", text: $newName)
                .textFieldStyle(.roundedBorder).frame(width: 320)
            HStack {
                Spacer()
                Button("Cancel") { renaming = nil }
                Button("Rename") {
                    model.rename(entry.displayPath, to: newName)
                    renaming = nil
                }.keyboardShortcut(.defaultAction).tint(.purple)
            }
        }.padding(20)
    }

    // MARK: - Extract / test routing

    /// Primary Extract: prompt for a destination folder, then extract there
    /// (the chosen folder also becomes the session default).
    private func extractToFolder() {
        if pickDestination() { beginExtract() }
    }

    /// Extract to the current default without prompting — selection drives it
    /// (all when nothing is selected, just the selected rows otherwise).
    private func beginExtract() {
        if selection.isEmpty { beginExtractAll() }
        else { beginExtractSelected(selection) }
    }

    /// Pick a destination folder. The choice is session-sticky
    /// (`AppModel.sessionExtractRoot`) — every later extract goes there until
    /// the app relaunches, when it falls back to the Settings default. Returns
    /// true if the user chose a folder.
    @discardableResult
    private func pickDestination() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Extract Here"
        panel.message = "Choose where extracted files should go (for this session)"
        panel.directoryURL = model.extractDestinationRoot
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        model.sessionExtractRoot = url
        model.status = "Extract destination → \(model.extractDestinationLabel)"
        return true
    }

    /// Toolbar "Choose Destination Folder…" — just set the sticky destination.
    private func chooseDestination() { pickDestination() }

    /// Right-click "Extract to Folder…" — pick a destination, then extract the
    /// given selection there.
    private func chooseDestinationThenExtract(_ ids: Set<String>) {
        if pickDestination() { beginExtractSelected(ids) }
    }

    /// Run the action straight away when the archive is plaintext (or its
    /// password is remembered); otherwise stash the action and prompt.
    private func beginExtractAll() {
        if needsPasswordPrompt { pendingAction = .extractAll; showingPasswordSheet = true }
        else { model.extractOpened() }
    }

    private func beginExtractSelected(_ ids: Set<String>) {
        let entries = entriesToExtract(ids)
        guard !entries.isEmpty else { return }
        if needsPasswordPrompt { pendingAction = .extractSelected(entries); showingPasswordSheet = true }
        else { model.extractEntries(entries) }
    }

    private func beginTest() {
        if needsPasswordPrompt { pendingAction = .test; showingPasswordSheet = true }
        else { model.testOpened() }
    }

    /// Encrypted with no Keychain-remembered password → we must ask first.
    private var needsPasswordPrompt: Bool {
        model.isEncrypted && model.vaultPassword == nil
    }

    private func runPendingAction(password: String, remember: Bool) {
        switch pendingAction {
        case .extractAll:           model.extractOpened(password: password, remember: remember)
        case .extractSelected(let e): model.extractEntries(e, password: password, remember: remember)
        case .test:                 model.testOpened(password: password)
        }
    }

    /// The concrete files to extract for a selection of nodes: each selected
    /// folder expands to every file beneath it (n levels deep); files as-is.
    private func entriesToExtract(_ ids: Set<String>) -> [ArchiveEntry] {
        var result: [ArchiveEntry] = []
        var seen = Set<Int>()
        for id in ids {
            guard let node = node(for: id) else { continue }
            for entry in node.fileEntries where seen.insert(entry.id).inserted {
                result.append(entry)
            }
        }
        return result
    }

    /// The single selected non-directory entry, if exactly one file is selected
    /// (Quick Look only makes sense for one previewable file at a time).
    private var selectedFileEntry: ArchiveEntry? {
        guard selection.count == 1, let id = selection.first,
              let node = node(for: id), let entry = node.entry, !entry.isDirectory
        else { return nil }
        return entry
    }

    /// Delete every entry under the selected nodes (folders included).
    private func deleteSelected(_ ids: Set<String>) {
        var seen = Set<Int>()
        var paths: [String] = []
        for id in ids {
            guard let node = node(for: id) else { continue }
            for entry in node.allEntries where seen.insert(entry.id).inserted {
                paths.append(entry.displayPath)
            }
        }
        model.deleteEntries(paths)
        selection.removeAll()
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { model.addFiles(panel.urls) }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f
    }()
}

private extension ArchiveEntryNode {
    /// Children for `List(children:)` — nil for leaves/empty folders so no
    /// disclosure triangle is drawn on them.
    var childrenOrNil: [ArchiveEntryNode]? { children.isEmpty ? nil : children }

    /// Every real file entry at and below this node (folders expanded deep).
    var fileEntries: [ArchiveEntry] {
        var out: [ArchiveEntry] = []
        if let e = entry, !e.isDirectory { out.append(e) }
        for c in children { out.append(contentsOf: c.fileEntries) }
        return out
    }

    /// Every real entry at and below this node, directories included.
    var allEntries: [ArchiveEntry] {
        var out: [ArchiveEntry] = []
        if let e = entry { out.append(e) }
        for c in children { out.append(contentsOf: c.allEntries) }
        return out
    }
}

private extension View {
    /// Trigger Quick Look on the spacebar (Finder-style), matching the header
    /// button. `onKeyPress` is macOS 14+; on macOS 13 the button and context
    /// menu remain the way in.
    @ViewBuilder
    func spaceToQuickLook(enabled: Bool, action: @escaping () -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self.onKeyPress(.space) {
                guard enabled else { return .ignored }
                action()
                return .handled
            }
        } else {
            self
        }
    }
}
