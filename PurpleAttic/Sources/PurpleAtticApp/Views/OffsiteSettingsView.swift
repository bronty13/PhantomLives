import SwiftUI
import AppKit
import PurpleAtticCore

/// Settings → Off-site: configure the client-side-E2EE restic copy (Backblaze B2 today) end to
/// end **without Terminal** — add/enable the destination, store credentials in the Keychain, see
/// live repo status, and set up + test the written-on-paper recovery key.
struct OffsiteSettingsView: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var model = OffsiteModel()
    @State private var showRecoverySheet = false
    @State private var recoveryStartAtVerify = false

    /// The B2 destination we manage in this pane (first one, or none yet).
    private var b2Index: Int? {
        store.profile.cloudDestinations.firstIndex { $0.kind == .resticB2 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Off-site backup").font(.title3.weight(.semibold))
                Text("An encrypted, off-site copy of the archive via **restic → Backblaze B2**. End-to-end encrypted (only this Mac holds the keys), resumable, and unattended — it replaces the old Cryptomator vault. Everything below is configurable here; you never need Terminal.")
                    .font(.callout).foregroundStyle(.secondary)

                if let i = b2Index {
                    destinationCard(i)
                    credentialsCard(store.profile.cloudDestinations[i])
                    statusCard(store.profile.cloudDestinations[i])
                    recoveryCard(store.profile.cloudDestinations[i])
                } else {
                    addDestinationCard
                }
            }
            .padding(20)
        }
        .onAppear { if let i = b2Index { model.refresh(dest: store.profile.cloudDestinations[i]) } }
        .sheet(isPresented: $showRecoverySheet) {
            if let i = b2Index {
                RecoveryKeySheet(model: model,
                                 dest: store.profile.cloudDestinations[i],
                                 sourceRoot: store.profile.primaryArchiveRoot,
                                 startAtVerify: recoveryStartAtVerify,
                                 isPresented: $showRecoverySheet)
            }
        }
    }

    // MARK: - No destination yet

    private var addDestinationCard: some View {
        Card(title: "Set up Backblaze B2") {
            Text("No off-site destination configured yet. Create a private B2 bucket + application key in the Backblaze console, then add it here.")
                .font(.callout).foregroundStyle(.secondary)
            Button {
                var dest = CloudDestination(name: "Backblaze B2", kind: .resticB2,
                                            repo: "b2:CHANGE_ME:photos",
                                            keychainService: "PurpleAttic Restic B2")
                dest.enabled = false   // off until configured + credentials saved
                store.profile.cloudDestinations.append(dest)
                store.save()
            } label: { Label("Add Backblaze B2 destination", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Destination

    private func destinationCard(_ i: Int) -> some View {
        Card(title: "Destination") {
            TextField("Name", text: bind(i, \.name))
                .textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 4) {
                Text("B2 bucket").font(.subheadline.weight(.medium))
                TextField("vortex-photos-archive", text: bucketBinding(i))
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Path within bucket").font(.subheadline.weight(.medium))
                TextField("photos", text: pathBinding(i))
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
            }
            Text("Repository:  \(store.profile.cloudDestinations[i].repo)")
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            Divider()
            Toggle("Enabled (included in each archive run)", isOn: bind(i, \.enabled))
            Toggle("Run an integrity check after every backup", isOn: bind(i, \.checkAfterBackup))
            HStack {
                Button(role: .destructive) {
                    store.profile.cloudDestinations.remove(at: i); store.save()
                } label: { Label("Remove destination", systemImage: "trash") }
                    .buttonStyle(.borderless)
                Spacer()
                Button("Save") { store.save(); model.refresh(dest: store.profile.cloudDestinations[i]) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Credentials

    private func credentialsCard(_ dest: CloudDestination) -> some View {
        Card(title: "Credentials (stored in your macOS Keychain)") {
            if let p = model.presence {
                credRow("Runtime passphrase", present: p.resticPassword)
                credRow("B2 key ID", present: p.b2AccountId)
                credRow("B2 application key", present: p.b2AccountKey)
            } else {
                Text("Checking…").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text("Keychain service: \(dest.keychainService)")
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
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
            Text("The runtime passphrase is generated automatically (and kept only in the Keychain) the first time you save credentials for a brand-new repository. Don't regenerate it for a repository that already has backups — it must match what the repo was created with.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if let m = model.credsMessage {
                    Text(m).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    let needsRuntime = !(model.presence?.resticPassword ?? false)
                    model.saveCredentials(dest: dest, generateRuntimeIfMissing: needsRuntime)
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

    // MARK: - Repo status

    private func statusCard(_ dest: CloudDestination) -> some View {
        Card(title: "Repository status") {
            switch model.overview {
            case .none:
                Text("Checking…").font(.caption).foregroundStyle(.secondary)
            case .some(.unreachable(let why)):
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(why).font(.callout).foregroundStyle(.secondary)
                }
            case .some(.ready(let keys, let snaps)):
                statusRow("Snapshots", "\(snaps.count)" + (snaps.latest.map { " · latest \(friendly($0))" } ?? ""))
                statusRow("Keys", "\(keys.count) (\(keys.count >= 2 ? "runtime + recovery" : "runtime only"))")
            }
            HStack {
                Spacer()
                Button { model.refresh(dest: dest) } label: {
                    if model.isRefreshing { ProgressView().controlSize(.small) }
                    else { Label("Refresh", systemImage: "arrow.clockwise") }
                }
                .disabled(model.isRefreshing)
            }
        }
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value) }
            .font(.callout)
    }

    // MARK: - Recovery key

    private func recoveryCard(_ dest: CloudDestination) -> some View {
        let keyCount: Int = {
            if case .ready(let keys, _) = model.overview { return keys.count }
            return 0
        }()
        let hasRecovery = keyCount >= 2
        return Card(title: "Recovery key (paper copy for your safe)") {
            HStack(spacing: 6) {
                Image(systemName: hasRecovery ? "checkmark.seal.fill" : "exclamationmark.shield.fill")
                    .foregroundStyle(hasRecovery ? .green : .orange)
                Text(hasRecovery
                     ? "A recovery key is set up. Keep your paper copy safe."
                     : (keyCount == 1 ? "No recovery key yet — only the Keychain (runtime) key exists."
                                      : "Repository not reachable yet — set up credentials first."))
                    .font(.callout)
            }
            Text("A second, independent key derived from a passphrase you **write on paper and store in a safe**. It can restore the whole archive from B2 even if this Mac and its Keychain are gone. True end-to-end encryption means if every key is lost, the cloud copy is unrecoverable — the paper copy is your guarantee against that.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                if hasRecovery {
                    Button {
                        model.recoveryResult = nil; model.recoveryLog = []
                        recoveryStartAtVerify = false; showRecoverySheet = true
                    } label: { Label("Add another recovery key", systemImage: "key.horizontal") }
                        .buttonStyle(.bordered)
                    Button {
                        model.recoveryResult = nil; model.recoveryLog = []
                        recoveryStartAtVerify = true; showRecoverySheet = true
                    } label: { Label("Test recovery key", systemImage: "checkmark.shield.fill") }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        model.recoveryResult = nil; model.recoveryLog = []
                        recoveryStartAtVerify = false; showRecoverySheet = true
                    } label: { Label("Set up recovery key", systemImage: "key.horizontal.fill") }
                        .buttonStyle(.borderedProminent)
                        .disabled(keyCount == 0)   // need a reachable repo (runtime key works) first
                }
            }
        }
    }

    // MARK: - Bindings & helpers

    private func bind<V>(_ i: Int, _ kp: WritableKeyPath<CloudDestination, V>) -> Binding<V> {
        Binding(get: { store.profile.cloudDestinations[i][keyPath: kp] },
                set: { store.profile.cloudDestinations[i][keyPath: kp] = $0 })
    }

    /// Parse `b2:<bucket>:<path>` → bucket. Empty if not a B2 repo string.
    private func parseB2(_ repo: String) -> (bucket: String, path: String) {
        guard repo.hasPrefix("b2:") else { return ("", "") }
        let rest = String(repo.dropFirst(3))
        let parts = rest.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        return (parts.first ?? "", parts.count > 1 ? parts[1] : "")
    }
    private func composeB2(bucket: String, path: String) -> String {
        path.isEmpty ? "b2:\(bucket)" : "b2:\(bucket):\(path)"
    }
    private func bucketBinding(_ i: Int) -> Binding<String> {
        Binding(get: { parseB2(store.profile.cloudDestinations[i].repo).bucket },
                set: { store.profile.cloudDestinations[i].repo =
                        composeB2(bucket: $0, path: parseB2(store.profile.cloudDestinations[i].repo).path) })
    }
    private func pathBinding(_ i: Int) -> Binding<String> {
        Binding(get: { parseB2(store.profile.cloudDestinations[i].repo).path },
                set: { store.profile.cloudDestinations[i].repo =
                        composeB2(bucket: parseB2(store.profile.cloudDestinations[i].repo).bucket, path: $0) })
    }

    private func friendly(_ iso: String) -> String {
        // restic emits RFC3339; show date + short time, fall back to the raw string.
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let d else { return String(iso.prefix(16)) }
        let out = DateFormatter(); out.dateStyle = .medium; out.timeStyle = .short
        return out.string(from: d)
    }
}

// MARK: - Recovery-key sheet

/// Guided flow: generate (or type) a passphrase → confirm it's written down → add it to the repo →
/// re-type it from paper and run the Keychain-bypassed drill that proves the paper copy restores.
private struct RecoveryKeySheet: View {
    @ObservedObject var model: OffsiteModel
    let dest: CloudDestination
    let sourceRoot: String
    var startAtVerify: Bool = false
    @Binding var isPresented: Bool

    private enum Step { case create, added, verify, done }
    @State private var step: Step = .create
    @State private var phrase: String = ""
    @State private var entropyNote: String = ""
    @State private var wroteItDown = false
    @State private var typedToVerify = ""
    @State private var genError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recovery key").font(.title2.weight(.semibold))

            switch step {
            case .create: createStep
            case .added, .verify: verifyStep
            case .done: doneStep
            }

            if !model.recoveryLog.isEmpty {
                HStack {
                    Text("Log").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.recoveryLog.joined(separator: "\n"), forType: .string)
                    } label: { Label("Copy log", systemImage: "doc.on.doc") }
                        .buttonStyle(.borderless).font(.caption)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(model.recoveryLog.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(.caption2, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .textSelection(.enabled)   // allow selecting/copying error text directly
                }
                .frame(height: 110)
                .padding(8)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Button("Close") { isPresented = false }
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear { if startAtVerify { step = .verify } }
        .onChange(of: model.recoveryResult) { _, result in
            switch result {
            case .added: step = .verify
            case .verifiedPass: step = .done
            default: break
            }
        }
    }

    // Step 1 — generate / type, write down, add.
    private var createStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generate a strong passphrase, **write it on paper, and store it in your safe**. It is shown here once. You can also type your own.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button { generate() } label: { Label("Generate", systemImage: "die.face.5") }
                if !entropyNote.isEmpty {
                    Text(entropyNote).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let genError { Text(genError).font(.caption).foregroundStyle(.red) }
            TextField("eight-or-more random words…", text: $phrase, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(.title3, design: .monospaced))
                .lineLimit(2...3)
            if !phrase.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(phrase, forType: .string)
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(.borderless).font(.caption)
            }
            Toggle("I have written this passphrase on paper and stored it safely.", isOn: $wroteItDown)
            Button {
                model.addRecoveryKey(dest: dest, passphrase: phrase)
            } label: {
                if model.recoveryBusy { ProgressView().controlSize(.small) }
                else { Text("Add recovery key to repository") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!wroteItDown || phrase.count < 8 || model.recoveryBusy)
            if case .failed(let d) = model.recoveryResult {
                Text(d).font(.caption).foregroundStyle(.red)
            }
        }
    }

    // Step 2 — re-type from paper, run the drill.
    private var verifyStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.recoveryResult == .added {
                Label("Recovery key added. Now prove your paper copy works.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Test your recovery key.", systemImage: "checkmark.shield")
            }
            Text("Type the passphrase **from your paper** (not copy-paste). This runs a restore with the Keychain bypassed — proving the written copy alone can recover the archive.")
                .font(.callout).foregroundStyle(.secondary)
            SecureField("type it from paper…", text: $typedToVerify)
                .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
            Button {
                model.verifyRecoveryKey(dest: dest, typed: typedToVerify, sourceRoot: sourceRoot)
            } label: {
                if model.recoveryBusy { ProgressView().controlSize(.small) }
                else { Text("Verify recovery key (restore drill)") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(typedToVerify.count < 8 || model.recoveryBusy)
            if case .failed(let d) = model.recoveryResult {
                Text(d).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recovery key verified", systemImage: "checkmark.seal.fill")
                .font(.headline).foregroundStyle(.green)
            if case .verifiedPass(let d) = model.recoveryResult {
                Text(d).font(.callout).foregroundStyle(.secondary)
            }
            Text("Your written-down passphrase provably restores the archive from B2 without this Mac's Keychain. Keep the paper copy in your safe.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Done") { isPresented = false }.buttonStyle(.borderedProminent)
        }
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
}
