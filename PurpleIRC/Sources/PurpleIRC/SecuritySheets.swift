import SwiftUI

// MARK: - Passphrase setup (opt-in to encryption)

/// First-time passphrase setup. Shown either via the Security tab
/// "Enable encryption" flow or auto-presented when the user has deleted the
/// keystore but kept the settings (recover-by-starting-over).
///
/// Explicit about forgot-passphrase data loss because that's the whole
/// point of a composite-key setup — there's no recovery.
struct PassphraseSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var keyStore: KeyStore
    /// Called after a successful setup so the caller can follow up (e.g.
    /// re-save settings so the freshly-encrypted envelope lands on disk).
    var onComplete: () -> Void = {}

    @State private var passphrase: String = ""
    @State private var confirm: String = ""
    @State private var errorMessage: String? = nil
    @State private var working: Bool = false

    private var canSubmit: Bool {
        !passphrase.isEmpty && passphrase.count >= 8 && passphrase == confirm && !working
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield").font(.title2)
                    .foregroundStyle(Color.purple)
                Text("Enable encryption").font(.title3.weight(.semibold))
            }
            Text("Choose a passphrase. It will be required whenever your Keychain can't silently unlock PurpleIRC — for example when this Mac's login changes, on a new device, or after you lock the app.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("Passphrase (at least 8 characters)", text: $passphrase)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canSubmit { submit() } }
            SecureField("Confirm passphrase", text: $confirm)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canSubmit { submit() } }

            if let err = errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).font(.callout)
            }

            VStack(alignment: .leading, spacing: 4) {
                Label("If you forget this passphrase, your encrypted settings and logs cannot be recovered — by design.",
                      systemImage: "exclamationmark.shield")
                    .foregroundStyle(.orange).font(.caption)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Enable encryption") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func submit() {
        working = true; errorMessage = nil
        do {
            try keyStore.setup(passphrase: passphrase)
            onComplete()
            dismiss()
        } catch {
            errorMessage = "Setup failed: \(error.localizedDescription)"
            working = false
        }
    }
}

// MARK: - Unlock (returning user)

/// Shown when the keystore exists but the Keychain couldn't silently unlock
/// it (fresh Mac, keychain cleared, explicit lock). Wrong passphrase lets the
/// user retry; the reset button exists so a forgotten passphrase isn't a
/// dead-end for the rest of the UI — they can wipe and start fresh.
struct PassphraseUnlockView: View {
    @ObservedObject var keyStore: KeyStore
    /// Called after a successful unlock so the caller can refresh state
    /// (e.g. reload settings from the encrypted envelope).
    var onUnlock: () -> Void = {}

    @State private var passphrase: String = ""
    @State private var errorMessage: String? = nil
    @State private var showResetConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "lock.rectangle").font(.title2)
                    .foregroundStyle(Color.purple)
                Text("Unlock PurpleIRC").font(.title3.weight(.semibold))
            }
            Text("Your settings and logs are encrypted with a passphrase you set up earlier. Enter it to continue.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("Passphrase", text: $passphrase)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submit() }

            if let err = errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).font(.callout)
            }

            HStack {
                Button("Forgot passphrase…", role: .destructive) {
                    showResetConfirm = true
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                Spacer()
                Button("Unlock") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(passphrase.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
        .confirmationDialog("Reset encryption?",
                            isPresented: $showResetConfirm,
                            titleVisibility: .visible) {
            Button("Erase encrypted data and reset", role: .destructive) {
                keyStore.resetAndWipe()
                // Also wipe the encrypted settings file so the app can
                // start from an empty state next launch.
                // (UI-side follow-up happens via SettingsStore.)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your encrypted settings and logs will be permanently erased. Credentials in the Keychain stay put (they aren't covered by this passphrase). This action cannot be undone.")
        }
    }

    private func submit() {
        errorMessage = nil
        do {
            try keyStore.unlock(passphrase: passphrase)
            onUnlock()
        } catch KeyStore.KeyStoreError.passphraseMismatch {
            errorMessage = "That passphrase is incorrect."
            passphrase = ""
        } catch {
            errorMessage = "Unlock failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Change passphrase

struct PassphraseChangeView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var keyStore: KeyStore

    @State private var oldPassphrase: String = ""
    @State private var newPassphrase: String = ""
    @State private var confirm: String = ""
    @State private var errorMessage: String? = nil

    private var canSubmit: Bool {
        !oldPassphrase.isEmpty
            && newPassphrase.count >= 8
            && newPassphrase == confirm
            && oldPassphrase != newPassphrase
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Change passphrase").font(.title3.weight(.semibold))
            Text("The data-encryption key is re-wrapped with the new passphrase — your existing encrypted settings and logs don't need to be re-encrypted.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("Current passphrase", text: $oldPassphrase)
                .textFieldStyle(.roundedBorder)
            SecureField("New passphrase (at least 8 characters)", text: $newPassphrase)
                .textFieldStyle(.roundedBorder)
            SecureField("Confirm new passphrase", text: $confirm)
                .textFieldStyle(.roundedBorder)

            if let err = errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).font(.callout)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Change passphrase") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func submit() {
        errorMessage = nil
        do {
            try keyStore.changePassphrase(oldPassphrase: oldPassphrase,
                                          newPassphrase: newPassphrase)
            dismiss()
        } catch KeyStore.KeyStoreError.passphraseMismatch {
            errorMessage = "Current passphrase is incorrect."
        } catch {
            errorMessage = "Change failed: \(error.localizedDescription)"
        }
    }
}
