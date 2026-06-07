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
    @State private var selection = Set<Int>()
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
                Table(model.entries, selection: $selection) {
                    TableColumn("Name") { entry in
                        HStack(spacing: 6) {
                            Image(systemName: icon(for: entry))
                                .foregroundStyle(entry.isDirectory ? Color.secondary : Color.blue)
                            Text(entry.displayPath).lineLimit(1).truncationMode(.middle)
                            if entry.isEncrypted { Image(systemName: "lock.fill").foregroundStyle(.orange) }
                        }
                        .contentShape(Rectangle())
                    }
                    TableColumn("Size") { entry in
                        Text(entry.isDirectory ? "—" : ByteFormat.string(entry.uncompressedSize))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }.width(90)
                    TableColumn("Modified") { entry in
                        Text(entry.modified.map { Self.dateFormatter.string(from: $0) } ?? "—")
                            .foregroundStyle(.secondary).font(.caption)
                    }.width(150)
                }
                .contextMenu(forSelectionType: Int.self) { ids in
                    if ids.count == 1,
                       let entry = model.entries.first(where: { $0.id == ids.first }),
                       !entry.isDirectory {
                        Button { model.quickLook(entry) } label: { Label("Quick Look", systemImage: "eye") }
                    }
                    if !ids.isEmpty {
                        // Show the destination right in the menu so it's clear
                        // where files will land before extracting.
                        Section("Extract to  \(model.extractDestinationLabel)") {
                            Button { beginExtractSelected(ids) } label: {
                                Label(ids.count == 1 ? "Extract Here" : "Extract \(ids.count) Items Here",
                                      systemImage: "arrow.down.circle")
                            }
                            Button { chooseDestinationThenExtract(ids) } label: {
                                Label("Extract to Folder…", systemImage: "folder")
                            }
                        }
                        Divider()
                    }
                    if model.canEdit {
                        if ids.count == 1, let entry = model.entries.first(where: { $0.id == ids.first }) {
                            Button("Rename…") { renaming = entry; newName = entry.displayPath }
                        }
                        Button("Delete", role: .destructive) { deleteSelected(ids) }
                    }
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

            // Primary extract: the whole archive when nothing is selected, or
            // just the selected rows when there's a selection.
            Button { beginExtract() } label: {
                Label(selection.isEmpty ? "Extract All" : "Extract \(selection.count) Selected",
                      systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent).tint(.purple)
            .disabled(model.busy || model.entries.isEmpty)
            .help(selection.isEmpty
                  ? "Extract everything to \(model.extractDestinationLabel)"
                  : "Extract the \(selection.count) selected item(s) to \(model.extractDestinationLabel)")

            // Destination & all-items options.
            Menu {
                Text("Extract to: \(model.extractDestinationLabel)")
                Button("Choose Destination Folder…") { chooseDestination() }
                if model.sessionExtractRoot != nil {
                    Button("Reset to Default (\(model.settings.resolvedExtractRoot.lastPathComponent))") {
                        model.sessionExtractRoot = nil
                    }
                }
                Divider()
                Button("Extract All Items") { beginExtractAll() }
                    .disabled(model.entries.isEmpty)
            } label: {
                Image(systemName: "folder")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Extract destination & options")
            .disabled(model.busy)
        }
        .padding(12)
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

    /// The primary Extract action: selection drives it — all when nothing is
    /// selected, just the selected rows otherwise.
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
    private func chooseDestinationThenExtract(_ ids: Set<Int>) {
        if pickDestination() { beginExtractSelected(ids) }
    }

    /// Run the action straight away when the archive is plaintext (or its
    /// password is remembered); otherwise stash the action and prompt.
    private func beginExtractAll() {
        if needsPasswordPrompt { pendingAction = .extractAll; showingPasswordSheet = true }
        else { model.extractOpened() }
    }

    private func beginExtractSelected(_ ids: Set<Int>) {
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

    /// The concrete files to extract for a selection: bare files as-is, and any
    /// selected directory expanded to every file beneath it.
    private func entriesToExtract(_ ids: Set<Int>) -> [ArchiveEntry] {
        let selected = model.entries.filter { ids.contains($0.id) }
        var result: [ArchiveEntry] = []
        var seen = Set<Int>()
        for entry in selected {
            if entry.isDirectory {
                let prefix = entry.displayPath   // directory displayPaths end in "/"
                for child in model.entries
                where !child.isDirectory && child.displayPath.hasPrefix(prefix) {
                    if seen.insert(child.id).inserted { result.append(child) }
                }
            } else if seen.insert(entry.id).inserted {
                result.append(entry)
            }
        }
        return result
    }

    /// The single selected non-directory entry, if exactly one file is selected
    /// (Quick Look only makes sense for one previewable file at a time).
    private var selectedFileEntry: ArchiveEntry? {
        guard selection.count == 1, let id = selection.first,
              let entry = model.entries.first(where: { $0.id == id }), !entry.isDirectory
        else { return nil }
        return entry
    }

    private func deleteSelected(_ ids: Set<Int>) {
        let paths = model.entries.filter { ids.contains($0.id) }.map(\.displayPath)
        model.deleteEntries(paths)
        selection.removeAll()
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { model.addFiles(panel.urls) }
    }

    private func icon(for entry: ArchiveEntry) -> String {
        if entry.isDirectory { return "folder.fill" }
        if entry.isSymlink { return "arrow.up.forward.app" }
        return "doc"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f
    }()
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
