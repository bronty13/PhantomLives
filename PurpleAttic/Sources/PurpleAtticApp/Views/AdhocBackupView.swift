import SwiftUI
import AppKit
import PurpleAtticCore

/// Ad-hoc B2 pane — Phase 1 (Setup & Connect). Configure the *second*, file-level Backblaze B2
/// account end to end **without Terminal**: bucket + prefix, B2 application key, and the client-side
/// **crypt** passphrase (the only key — gated behind a recovery-sheet save), then a live
/// Test Connection. Browse / backup / manage / diff arrive in later phases.
struct AdhocBackupView: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var model = AdhocModel()
    @State private var showPassphraseSheet = false

    private var config: AdhocBackupConfig? { store.profile.adhocBackup }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ad-hoc B2 backup").font(.title3.weight(.semibold))
                Text("A **second, separate** Backblaze B2 account for ad-hoc files — browse, rename, delete, and diff individual items, all **client-side encrypted** (only this Mac holds the key). Distinct from your photos off-site, which stores opaque restic packs you can't manage per file.")
                    .font(.callout).foregroundStyle(.secondary)

                if config == nil {
                    setupPromptCard
                } else {
                    if !model.rcloneAvailable { rcloneWarningCard }
                    guidanceCard
                    destinationCard
                    credentialsCard
                    passphraseCard
                    testCard
                    sourcesCard
                    backupCard
                    syncCard
                }
            }
            .padding(20)
        }
        .onAppear { if let c = config { model.refreshPresence(config: c) } }
        .sheet(isPresented: $showPassphraseSheet) {
            if let c = config {
                AdhocPassphraseSheet(model: model, config: c,
                                     alreadySet: model.presence.cryptPass,
                                     isPresented: $showPassphraseSheet)
            }
        }
    }

    // MARK: - Not set up yet

    private var setupPromptCard: some View {
        Card(title: "Set up Ad-hoc B2") {
            Text("Create the store, then add your B2 bucket, application key, and an encryption passphrase below.")
                .font(.callout).foregroundStyle(.secondary)
            Button {
                var c = AdhocBackupConfig()
                c.enabled = false   // off until configured + secrets saved
                store.profile.adhocBackup = c
                store.save()
                model.refreshPresence(config: c)
            } label: { Label("Set up Ad-hoc B2", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - rclone prerequisite

    private var rcloneWarningCard: some View {
        Card(title: "rclone is required") {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("rclone drives every ad-hoc operation (including encrypting the passphrase). Install it, then reopen this pane.")
                    .font(.callout)
            }
            HStack(spacing: 8) {
                Text("brew install rclone")
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("brew install rclone", forType: .string)
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(.borderless).font(.caption)
            }
        }
    }

    // MARK: - B2 account guidance

    private var guidanceCard: some View {
        Card(title: "1 · Create the B2 bucket & application key") {
            Text("In the Backblaze console (a separate account from your photos archive):")
                .font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                step(1, "**Buckets → Create a Bucket** — name it, set **Files are Private**.")
                step(2, "**App Keys → Add a New Application Key** — scope it to *that one bucket* (least privilege), with read & write.")
                step(3, "Copy the **keyID** and the **applicationKey** — the applicationKey is shown **once**.")
                step(4, "Paste them into *Credentials* below, set an *encryption passphrase*, then *Test connection*.")
            }
            Button {
                if let url = URL(string: "https://secure.backblaze.com/b2_buckets.htm") {
                    NSWorkspace.shared.open(url)
                }
            } label: { Label("Open Backblaze B2 console", systemImage: "safari") }
                .buttonStyle(.bordered)
        }
    }

    private func step(_ n: Int, _ markdown: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n).").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            Text(.init(markdown)).font(.callout)
        }
    }

    // MARK: - Destination

    private var destinationCard: some View {
        Card(title: "2 · Destination") {
            TextField("Name", text: bind(\.name)).textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 4) {
                Text("B2 bucket").font(.subheadline.weight(.medium))
                TextField("my-adhoc-bucket", text: bind(\.bucket))
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Path within bucket (optional)").font(.subheadline.weight(.medium))
                TextField("files", text: bind(\.prefix))
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
            }
            if let c = config {
                Text("Encrypted remote:  \(RcloneService.cryptPath()) → \(RcloneService.baseRemotePath(config: c))")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            Divider()
            Toggle("Enabled", isOn: bind(\.enabled))
            HStack {
                Spacer()
                Button("Save") { store.save() }.buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Credentials

    private var credentialsCard: some View {
        Card(title: "3 · Credentials (stored in your macOS Keychain)") {
            credRow("B2 key ID", present: model.presence.b2Id)
            credRow("B2 application key", present: model.presence.b2Key)
            Divider()
            if let c = config {
                Text("Keychain service: \(c.keychainService)")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("B2 key ID").font(.subheadline.weight(.medium))
                TextField("0011aabb…", text: $model.b2KeyId)
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("B2 application key").font(.subheadline.weight(.medium))
                SecureField("shown only once in the B2 console", text: $model.b2AppKey)
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
            }
            HStack {
                if let m = model.credsMessage { Text(m).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button {
                    if let c = config { model.saveCredentials(config: c) }
                } label: {
                    if model.isSavingCreds { ProgressView().controlSize(.small) }
                    else { Text("Save to Keychain") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isSavingCreds)
            }
        }
    }

    private func credRow(_ label: String, present: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: present ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(present ? .green : .red)
            Text(label)
            Spacer()
            Text(present ? "stored" : "missing").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Encryption passphrase

    private var passphraseCard: some View {
        Card(title: "4 · Encryption passphrase (the only key — back it up!)") {
            HStack(spacing: 6) {
                Image(systemName: model.presence.cryptPass ? "checkmark.seal.fill" : "exclamationmark.shield.fill")
                    .foregroundStyle(model.presence.cryptPass ? .green : .orange)
                Text(model.presence.cryptPass ? "An encryption passphrase is set." : "No encryption passphrase yet.")
                    .font(.callout)
                Spacer()
            }
            Text("Files are encrypted **before upload** (rclone crypt) — names and contents. This passphrase is the **only** key: if it's lost, the B2 data is unrecoverable. It's stored in your Keychain; keep a written copy in your safe.")
                .font(.caption).foregroundStyle(.secondary)
            if model.presence.cryptPass {
                Text("⚠️ Changing it makes any files already in B2 unreadable — only change it before your first backup.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let m = model.passphraseMessage { Text(m).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Spacer()
                Button {
                    showPassphraseSheet = true
                } label: {
                    Label(model.presence.cryptPass ? "Change passphrase…" : "Set passphrase…",
                          systemImage: "key.horizontal.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.rcloneAvailable)
            }
        }
    }

    // MARK: - Test connection

    private var testCard: some View {
        Card(title: "5 · Test connection") {
            switch model.testResult {
            case .none:
                Text("Verify the bucket is reachable with your saved credentials.")
                    .font(.callout).foregroundStyle(.secondary)
            case .some(.ok(let d)):
                Label(d, systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout)
            case .some(.failed(let d)):
                Label(d, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.callout)
            }
            Text("This proves connectivity to the bucket. Whether the passphrase is right is confirmed the first time a backup round-trips (a later phase).")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button {
                    if let c = config { model.testConnection(config: c) }
                } label: {
                    if model.isTesting { ProgressView().controlSize(.small) }
                    else { Label("Test connection", systemImage: "bolt.horizontal.circle") }
                }
                .buttonStyle(.bordered)
                .disabled(model.isTesting || !(config?.isConfigured ?? false) || !model.presence.b2Id || !model.presence.b2Key)
            }
        }
    }

    // MARK: - Sources

    private var sourcesCard: some View {
        Card(title: "6 · Files to back up") {
            if let c = config, !c.sources.isEmpty {
                ForEach(c.sources, id: \.self) { src in
                    HStack(spacing: 8) {
                        Image(systemName: iconFor(src)).foregroundStyle(.secondary)
                        Text(src).font(.system(.caption, design: .monospaced))
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(role: .destructive) { removeSource(src) } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } else {
                Text("No files or folders selected yet.").font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button { addSources() } label: { Label("Add files or folders…", systemImage: "plus") }
                    .buttonStyle(.bordered)
                Spacer()
            }
            Text("Each item is uploaded under its own name (a folder keeps its structure). One-way and additive — removing something here never deletes it from B2.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Backup

    private var canBackup: Bool {
        (config?.isConfigured ?? false) && !(config?.sources.isEmpty ?? true) && model.presence.allReady
    }

    private var backupCard: some View {
        Card(title: "7 · Back up") {
            if model.isBackingUp {
                if let p = model.backupProgress, let frac = p.fraction {
                    ProgressView(value: frac) {
                        Text("\(human(p.bytes)) / \(human(p.totalBytes)) · \(p.transfers)/\(p.totalTransfers) files")
                            .font(.caption)
                    }
                    Text("\(human(Int64(p.speed)))/s").font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Starting…").font(.caption).foregroundStyle(.secondary) }
                }
            } else if let s = model.backupStatus {
                Text(s).font(.callout)
                    .foregroundStyle(s.hasPrefix("✓") ? .green : (s.hasPrefix("✗") ? .red : .secondary))
            } else {
                Text("Upload the selected files to your encrypted B2 store.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            if !model.backupLog.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(model.backupLog.suffix(8).enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(.caption2, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(height: 90)
                .padding(8)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
            }

            if !canBackup && !model.isBackingUp {
                Text("Add at least one source and finish credentials + passphrase first.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button {
                    if let c = config { store.save(); model.runBackup(config: c) }
                } label: {
                    if model.isBackingUp { ProgressView().controlSize(.small) }
                    else { Label("Back up now", systemImage: "arrow.up.circle.fill") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBackingUp || !canBackup)
            }
        }
    }

    // MARK: - Sync (diff + upload changes)

    private var syncCard: some View {
        Card(title: "8 · Sync — what's changed since last backup") {
            if model.isDiffing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Comparing your sources with B2…").font(.caption).foregroundStyle(.secondary)
                }
            } else if let entries = model.diffEntries {
                let uploads = entries.filter { $0.needsUpload }
                if uploads.isEmpty {
                    Label("Up to date — nothing to upload.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.callout)
                } else {
                    let news = uploads.filter { $0.change == .onlyLocal }.count
                    let changed = uploads.filter { $0.change == .differ }.count
                    Text("\(uploads.count) change(s) to upload — \(news) new, \(changed) changed.").font(.callout)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(uploads.prefix(60).enumerated()), id: \.offset) { _, e in
                                let icon = diffIcon(e.change)
                                HStack(spacing: 6) {
                                    Image(systemName: icon.0).foregroundStyle(icon.1)
                                    Text(e.path).font(.system(.caption, design: .monospaced))
                                        .lineLimit(1).truncationMode(.middle)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if uploads.count > 60 {
                                Text("+ \(uploads.count - 60) more…").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(height: 120).padding(8)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                    Button {
                        if let c = config { store.save(); model.runBackup(config: c) }
                    } label: { Label("Upload these changes", systemImage: "arrow.up.circle.fill") }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBackingUp)
                }
            } else {
                Text("Compare your selected sources against B2 to see exactly what a backup would upload (new + changed files) — without uploading anything.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let s = model.diffStatus { Text(s).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Spacer()
                Button {
                    if let c = config { store.save(); model.checkDiff(config: c) }
                } label: {
                    if model.isDiffing { ProgressView().controlSize(.small) }
                    else { Label("Check for changes", systemImage: "arrow.triangle.2.circlepath") }
                }
                .buttonStyle(.bordered)
                .disabled(model.isDiffing || !canBackup)
            }
        }
    }

    /// SF Symbol + tint for a diff change.
    private func diffIcon(_ c: DiffEntry.Change) -> (String, Color) {
        switch c {
        case .onlyLocal: return ("plus.circle.fill", .green)
        case .differ:    return ("pencil.circle.fill", .orange)
        case .onlyRemote: return ("minus.circle", .secondary)
        case .same:      return ("equal.circle", .secondary)
        case .error:     return ("exclamationmark.triangle.fill", .red)
        }
    }

    private func addSources() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.title = "Choose files or folders to back up"
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        var c = store.profile.adhocBackup ?? AdhocBackupConfig()
        for url in panel.urls where !c.sources.contains(url.path) { c.sources.append(url.path) }
        store.profile.adhocBackup = c
        store.save()
    }

    private func removeSource(_ s: String) {
        guard var c = store.profile.adhocBackup else { return }
        c.sources.removeAll { $0 == s }
        store.profile.adhocBackup = c
        store.save()
    }

    private func iconFor(_ path: String) -> String {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return isDir.boolValue ? "folder" : "doc"
    }

    private func human(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Binding helper

    /// Two-way binding into the optional `adhocBackup`, lazily creating it from defaults so an edit
    /// never hits a nil. Writes go straight to the profile; the user presses Save to persist.
    private func bind<V>(_ kp: WritableKeyPath<AdhocBackupConfig, V>) -> Binding<V> {
        Binding(
            get: { (store.profile.adhocBackup ?? AdhocBackupConfig())[keyPath: kp] },
            set: { v in
                var c = store.profile.adhocBackup ?? AdhocBackupConfig()
                c[keyPath: kp] = v
                store.profile.adhocBackup = c
            })
    }
}

// MARK: - Passphrase recovery sheet

/// Generate (or type) the crypt passphrase, force the user to confirm they've saved it, then store
/// it. The crypt passphrase is the only key to the data, so this mirrors the restic recovery-key
/// gate: shown once, copyable, and saveable to a recovery sheet before it's accepted.
private struct AdhocPassphraseSheet: View {
    @ObservedObject var model: AdhocModel
    let config: AdhocBackupConfig
    let alreadySet: Bool
    @Binding var isPresented: Bool

    @State private var phrase = ""
    @State private var entropyNote = ""
    @State private var genError: String? = nil
    @State private var savedIt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Encryption passphrase").font(.title2.weight(.semibold))

            if alreadySet {
                Label("This replaces the current passphrase. Files already in B2 will become unreadable — only do this before your first backup.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }

            Text("Generate a strong passphrase, **write it on paper and store it in your safe**. It is the only key to your encrypted files — shown here once. You can also type your own.")
                .font(.callout).foregroundStyle(.secondary)

            HStack {
                Button { generate() } label: { Label("Generate", systemImage: "die.face.5") }
                if !entropyNote.isEmpty { Text(entropyNote).font(.caption).foregroundStyle(.secondary) }
            }
            if let genError { Text(genError).font(.caption).foregroundStyle(.red) }

            TextField("eight-or-more random words…", text: $phrase, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(.title3, design: .monospaced))
                .lineLimit(2...3)

            if !phrase.isEmpty {
                HStack {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(phrase, forType: .string)
                    } label: { Label("Copy", systemImage: "doc.on.doc") }
                        .buttonStyle(.borderless).font(.caption)
                    Button { saveRecoverySheet() } label: { Label("Save recovery copy…", systemImage: "square.and.arrow.down") }
                        .buttonStyle(.borderless).font(.caption)
                }
            }

            Toggle("I have saved this passphrase somewhere safe. I understand it cannot be recovered.", isOn: $savedIt)

            if let m = model.passphraseMessage { Text(m).font(.caption).foregroundStyle(.secondary) }

            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button {
                    model.savePassphrase(config: config, passphrase: phrase) { ok in
                        if ok { isPresented = false }
                    }
                } label: {
                    if model.isSavingPassphrase { ProgressView().controlSize(.small) }
                    else { Text("Set encryption passphrase") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!savedIt || phrase.count < 8 || model.isSavingPassphrase)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func generate() {
        genError = nil
        do {
            let g = try RecoveryPassphrase.generate(targetBits: 100)
            phrase = g.phrase
            entropyNote = "\(g.words.count) words · ~\(g.bits) bits"
        } catch {
            genError = (error as? RecoveryPassphrase.GenError)?.description ?? error.localizedDescription
        }
    }

    /// Write a plain-text recovery sheet to ~/Downloads/PurpleAttic/ (the PhantomLives output
    /// convention) so the user has an off-Keychain copy.
    private func saveRecoverySheet() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/PurpleAttic")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Ad-hoc B2 recovery passphrase.txt")
        let body = """
        PurpleAttic — Ad-hoc B2 encryption passphrase
        ==============================================

        Bucket:  \(config.bucket)
        Keychain service:  \(config.keychainService)

        Passphrase (the ONLY key to your encrypted files — keep it secret and safe):

            \(phrase)

        If this passphrase is lost, the encrypted files in B2 cannot be recovered.
        Store this somewhere safe and offline.
        """
        try? body.write(to: url, atomically: true, encoding: .utf8)
        model.passphraseMessage = "Recovery copy saved to \(url.path)"
    }
}
