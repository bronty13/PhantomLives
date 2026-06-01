import SwiftUI

/// Make an existing journal into a vault: set a passphrase and confirm the
/// master recovery phrase (so a forgotten passphrase isn't permanent lockout).
/// Sealing every existing entry happens in `AppState.makeVault`.
struct MakeVaultSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let journal: Journal

    @State private var passphrase = ""
    @State private var confirm = ""
    @State private var recovery = ""
    @State private var error: String?
    @State private var working = false

    private var recoveryWords: [String] {
        recovery.split { $0 == " " || $0 == "\n" || $0 == "\t" }.map { String($0).lowercased() }
    }
    private var passphraseOK: Bool { !passphrase.isEmpty && passphrase == confirm }
    private var canSeal: Bool { passphraseOK && recoveryWords.count == 24 && !working }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill").font(.title2).foregroundStyle(.purple)
                Text("Make “\(journal.name)” a Vault").font(.title3).bold()
            }
            Text("Every entry's title and text in this journal will be sealed under your passphrase — unreadable even with PurpleDiary open and the database unlocked, until you enter this passphrase for the session. Nothing leaves your Mac.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Vault passphrase").font(.subheadline).bold()
                SecureField("Passphrase", text: $passphrase).textFieldStyle(.roundedBorder)
                SecureField("Confirm passphrase", text: $confirm).textFieldStyle(.roundedBorder)
                if !confirm.isEmpty && passphrase != confirm {
                    Text("Passphrases don't match.").font(.caption).foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Your 24-word recovery key").font(.subheadline).bold()
                Text("So a forgotten passphrase never locks you out forever, the vault key is also wrapped under your PurpleDiary recovery key. Paste all 24 words.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextEditor(text: $recovery)
                    .font(.system(.callout, design: .monospaced))
                    .frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))
                Text("\(recoveryWords.count)/24 words")
                    .font(.caption2).foregroundStyle(recoveryWords.count == 24 ? .green : .secondary)
            }

            if let error { Text(error).font(.caption).foregroundStyle(.red) }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button {
                    seal()
                } label: { Label("Seal Journal", systemImage: "lock.fill") }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSeal)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func seal() {
        error = nil
        guard appState.verifyMasterRecoveryPhrase(RecoveryKey.format(recoveryWords)) else {
            error = "That's not your PurpleDiary recovery key. Check the 24 words and try again."
            return
        }
        working = true
        do {
            try appState.makeVault(journalId: journal.id, passphrase: passphrase, recoveryWords: recoveryWords)
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

    private var recoveryWords: [String] {
        recovery.split { $0 == " " || $0 == "\n" || $0 == "\t" }.map { String($0).lowercased() }
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
                Text("Enter your 24-word recovery key").font(.subheadline).bold()
                TextEditor(text: $recovery)
                    .font(.system(.callout, design: .monospaced))
                    .frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))
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
                    .disabled(showRecovery ? recoveryWords.count != 24 : passphrase.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func unlock() {
        error = nil
        let ok = showRecovery
            ? appState.unlockVault(journalId: journal.id, recoveryWords: recoveryWords)
            : appState.unlockVault(journalId: journal.id, passphrase: passphrase)
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
