import SwiftUI
import AppKit

/// Make an existing journal into a vault: set a passphrase, and save the fresh
/// 24-word recovery key PurpleDiary generates for *this* vault (so a forgotten
/// passphrase isn't permanent lockout). Sealing every existing entry happens in
/// `AppState.makeVault`.
struct MakeVaultSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let journal: Journal

    /// Generated once for the sheet's lifetime — this vault's recovery key.
    @State private var words: [String] = RecoveryKey.generate()
    @State private var passphrase = ""
    @State private var confirm = ""
    @State private var savedConfirmed = false
    @State private var copied = false
    @State private var savedToFileAt: URL?
    @State private var error: String?
    @State private var working = false

    private var passphraseOK: Bool { !passphrase.isEmpty && passphrase == confirm }
    private var canSeal: Bool { passphraseOK && savedConfirmed && !working }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill").font(.title2).foregroundStyle(.purple)
                    Text("Make “\(journal.name)” a Vault").font(.title3).bold()
                }
                Text("Every entry's title, text, and attached photos in this journal will be sealed under your passphrase — unreadable even with PurpleDiary open, until you enter this passphrase for the session. Nothing leaves your Mac.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose a vault passphrase").font(.subheadline).bold()
                    SecureField("Passphrase", text: $passphrase).textFieldStyle(.roundedBorder)
                    SecureField("Confirm passphrase", text: $confirm).textFieldStyle(.roundedBorder)
                    if !confirm.isEmpty && passphrase != confirm {
                        Text("Passphrases don't match.").font(.caption).foregroundStyle(.red)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Save this vault's recovery key").font(.subheadline).bold()
                    Text("If you ever forget the passphrase, these 24 words are the only other way in. Save them somewhere safe — **anyone with this key can open the vault**, so treat it like a seed phrase.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    wordsGrid
                    HStack(spacing: 10) {
                        Button { copyToClipboard() } label: {
                            Label(copied ? "Copied" : "Copy to clipboard", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                        Button { saveToFile() } label: {
                            Label("Save to file…", systemImage: "square.and.arrow.down")
                        }
                        if let url = savedToFileAt {
                            Text("Saved to \(url.lastPathComponent)").font(.caption).foregroundStyle(.green)
                        }
                    }
                    Toggle("I've saved this recovery key somewhere safe", isOn: $savedConfirmed)
                        .toggleStyle(.checkbox)
                        .padding(.top, 2)
                }

                if let error { Text(error).font(.caption).foregroundStyle(.red) }

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button { seal() } label: { Label("Seal Journal", systemImage: "lock.fill") }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSeal)
                }
            }
            .padding(24)
            .frame(width: 480, alignment: .leading)
        }
        .frame(width: 480, height: 560)
    }

    private var wordsGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                HStack(spacing: 6) {
                    Text("\(idx + 1).").font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary).frame(width: 22, alignment: .trailing)
                    Text(word).font(.system(.callout, design: .monospaced).bold()).textSelection(.enabled)
                }
                .padding(.vertical, 3).padding(.horizontal, 6)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.06)))
            }
        }
    }

    private func copyToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(RecoveryKey.format(words), forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }

    /// Write the recovery key to `~/Downloads/PurpleDiary/…-vault-recovery-key.txt`
    /// per the default-output convention.
    private func saveToFile() {
        let panel = NSSavePanel()
        panel.title = "Save vault recovery key"
        panel.message = "Anyone with this file can open the “\(journal.name)” vault — store it like a password."
        panel.allowedContentTypes = [.plainText]
        let safeName = journal.name.replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = "PurpleDiary-\(safeName)-vault-recovery-key.txt"
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            let dir = downloads.appendingPathComponent("PurpleDiary", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            panel.directoryURL = dir
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let body =
            "PurpleDiary — recovery key for the “\(journal.name)” vault\n" +
            "Generated \(ISO8601DateFormatter().string(from: Date()))\n\n" +
            "Anyone holding this key can open this vault. Store it as carefully as a seed phrase.\n\n" +
            RecoveryKey.formatNumbered(words) + "\n"
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            savedToFileAt = url
        } catch {
            NSLog("PurpleDiary: vault recovery-key save failed — \(error.localizedDescription)")
        }
    }

    private func seal() {
        error = nil
        working = true
        do {
            try appState.makeVault(journalId: journal.id, passphrase: passphrase, recoveryWords: words)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            working = false
        }
    }
}

/// Unlock a vault for the session — passphrase first, with a forgot-passphrase
/// path that takes the 24-word recovery key.
struct VaultUnlockSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let journal: Journal

    @State private var passphrase = ""
    @State private var recovery = ""
    @State private var showRecovery = false
    @State private var error: String?

    /// Checksum-valid phrases extracted from the recovery field — tolerant of a
    /// pasted-back saved key file (numbering + prose) or a clean line.
    private var recoveryCandidates: [[String]] {
        RecoveryKey.candidatePhrases(in: recovery)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill").font(.title2).foregroundStyle(.purple)
                Text("Unlock “\(journal.name)”").font(.title3).bold()
            }
            Text("Enter this vault's passphrase to read its entries for this session.")
                .font(.callout).foregroundStyle(.secondary)

            if showRecovery {
                Text("Enter this vault's 24-word recovery key").font(.subheadline).bold()
                Text("Numbering, line breaks, and surrounding text are fine — paste the whole saved key file if you like.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextEditor(text: $recovery)
                    .font(.system(.callout, design: .monospaced))
                    .frame(height: 72)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))
                HStack {
                    Button { readFromFile() } label: {
                        Label("Read from file…", systemImage: "doc.text")
                    }
                    if !recovery.isEmpty {
                        Text(recoveryCandidates.isEmpty ? "Enter all 24 words" : "✓ recovery key detected")
                            .font(.caption2)
                            .foregroundStyle(recoveryCandidates.isEmpty ? Color.secondary : Color.green)
                    }
                }
            } else {
                SecureField("Passphrase", text: $passphrase)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(unlock)
            }

            if let error { Text(error).font(.caption).foregroundStyle(.red) }

            HStack {
                Button(showRecovery ? "Use passphrase" : "Forgot passphrase?") {
                    showRecovery.toggle(); error = nil
                }
                .buttonStyle(.link)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Unlock") { unlock() }
                    .buttonStyle(.borderedProminent)
                    .disabled(showRecovery ? recoveryCandidates.isEmpty : passphrase.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    /// Load a saved recovery-key file into the field; `candidatePhrases` then
    /// pulls the 24 words out of whatever formatting it has.
    private func readFromFile() {
        if let text = RecoveryKeyFile.read() { recovery = text; error = nil }
    }

    private func unlock() {
        error = nil
        var ok = false
        if showRecovery {
            // Try each checksum-valid candidate; the right one unwraps the vault.
            for words in recoveryCandidates where appState.unlockVault(journalId: journal.id, recoveryWords: words) {
                ok = true
                break
            }
        } else {
            ok = appState.unlockVault(journalId: journal.id, passphrase: passphrase)
        }
        if ok {
            appState.selectedJournalId = journal.id
            dismiss()
        } else {
            error = showRecovery ? "That recovery key didn't unlock this vault."
                                 : "Wrong passphrase. Try again, or use your recovery key."
        }
    }
}

/// Change an unlocked vault's passphrase (re-wraps the content key; the recovery
/// key wrap is untouched).
struct ChangeVaultPassphraseSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let journal: Journal

    @State private var passphrase = ""
    @State private var confirm = ""
    @State private var error: String?

    private var canSave: Bool { !passphrase.isEmpty && passphrase == confirm }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Change Passphrase — “\(journal.name)”").font(.title3).bold()
            SecureField("New passphrase", text: $passphrase).textFieldStyle(.roundedBorder)
            SecureField("Confirm passphrase", text: $confirm).textFieldStyle(.roundedBorder)
            if !confirm.isEmpty && passphrase != confirm {
                Text("Passphrases don't match.").font(.caption).foregroundStyle(.red)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    do {
                        try appState.changeVaultPassphrase(journalId: journal.id, newPassphrase: passphrase)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
