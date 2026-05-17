import SwiftUI

/// Settings → Security tab. Surfaces the `KeyStore` state and exposes the
/// passphrase-management actions that go with each mode.
///
/// State matrix:
///   * Keychain-managed (no passphrase): "Add passphrase" + "Reset".
///   * Passphrase-protected, unlocked: "Change passphrase" + "Remove
///     passphrase" + "Lock now" + "Reset".
///   * Passphrase-protected, locked: "Unlock" form (one field).
struct SecuritySettingsTab: View {
    @EnvironmentObject private var appState: AppState

    @State private var newPassphrase: String = ""
    @State private var confirmPassphrase: String = ""
    @State private var currentPassphrase: String = ""
    @State private var unlockPassphrase: String = ""

    @State private var statusMessage: String?
    @State private var errorMessage: String?

    @State private var showAddSheet = false
    @State private var showChangeSheet = false
    @State private var showRemoveSheet = false
    @State private var showResetConfirm = false

    private var store: KeyStore { appState.keyStore }

    var body: some View {
        Form {
            Section("Status") {
                statusRow
                Text(statusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.state == .locked {
                lockedSection
            } else if store.isUnlocked {
                unlockedSection
            }

            if let statusMessage {
                Section { Text(statusMessage).foregroundStyle(.green) }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showAddSheet)    { addPassphraseSheet }
        .sheet(isPresented: $showChangeSheet) { changePassphraseSheet }
        .sheet(isPresented: $showRemoveSheet) { removePassphraseSheet }
        .alert("Erase all data?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Erase and Reset", role: .destructive) { performReset() }
        } message: {
            Text("This deletes the keystore and the Keychain DEK. Any data on disk encrypted with the current key becomes unreadable. This cannot be undone.")
        }
    }

    // MARK: - Status row

    @ViewBuilder
    private var statusRow: some View {
        switch (store.state, store.hasPassphrase) {
        case (.unlocked, false):
            Label("Encrypted at rest — Keychain-managed", systemImage: "lock.shield")
                .foregroundStyle(.green)
        case (.unlocked, true):
            Label("Encrypted at rest — protected by passphrase", systemImage: "lock.fill")
                .foregroundStyle(.green)
        case (.locked, _):
            Label("Locked — passphrase required", systemImage: "lock.rotation")
                .foregroundStyle(.orange)
        case (.notSetup, _):
            Label("Not yet initialized", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    private var statusDescription: String {
        switch (store.state, store.hasPassphrase) {
        case (.unlocked, false):
            return "Your data is encrypted on disk with a key stored in the macOS Keychain. The app opens silently because the Keychain has the key. Add a passphrase below to require it on every launch."
        case (.unlocked, true):
            return "Your data is encrypted on disk with a key wrapped by your passphrase. The Keychain caches the unlocked key for this session — Lock now to clear it and require the passphrase on next access."
        case (.locked, _):
            return "Enter your passphrase to unlock."
        case (.notSetup, _):
            return "Something went wrong during first-launch setup. Try restarting the app, or use Reset below if you want to start over."
        }
    }

    // MARK: - Locked

    @ViewBuilder
    private var lockedSection: some View {
        Section("Unlock") {
            SecureField("Passphrase", text: $unlockPassphrase)
                .textFieldStyle(.roundedBorder)
                .onSubmit { performUnlock() }
            HStack {
                Button("Unlock") { performUnlock() }
                    .buttonStyle(.borderedProminent)
                    .disabled(unlockPassphrase.isEmpty)
                Spacer()
                Button("Reset (destroys all data)…", role: .destructive) {
                    showResetConfirm = true
                }
            }
        }
    }

    // MARK: - Unlocked

    @ViewBuilder
    private var unlockedSection: some View {
        Section("Passphrase") {
            if store.hasPassphrase {
                HStack {
                    Button("Change passphrase…") { showChangeSheet = true }
                    Button("Remove passphrase…", role: .destructive) {
                        showRemoveSheet = true
                    }
                }
            } else {
                Button("Add passphrase…") { showAddSheet = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        Section("Session") {
            if store.hasPassphrase {
                Button("Lock now") {
                    _ = store.lock()
                    statusMessage = "Locked. The next read will prompt for your passphrase."
                    errorMessage = nil
                }
                Text("Lock clears the in-memory key and the Keychain cache. The next launch (or unlock) will require your passphrase.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Lock is only available when a passphrase is set.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            // Vault auto-lock. 0 = never; otherwise the Vault
            // closes after this many seconds with no keyboard /
            // mouse / scroll input. Persisted in settings.json so
            // the choice survives relaunches.
            vaultAutoLockStepper
            Divider()
            Button("Reset (destroys all data)…", role: .destructive) {
                showResetConfirm = true
            }
            Text("Use Reset if you forget your passphrase. There is no recovery — the data becomes unreadable.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Inactivity threshold for Vault auto-lock. Bound directly to
    /// `appState.settings.vaultAutoLockAfterSeconds`; the
    /// AppState-side polling timer reads the live value each tick
    /// so changes take effect immediately without a relaunch.
    @ViewBuilder
    private var vaultAutoLockStepper: some View {
        let value = Binding(
            get: { appState.settings.vaultAutoLockAfterSeconds },
            set: {
                var s = appState.settings
                s.vaultAutoLockAfterSeconds = $0
                appState.settings = s
            }
        )
        VStack(alignment: .leading, spacing: 6) {
            Stepper(value: value, in: 0...3600, step: 15) {
                if value.wrappedValue == 0 {
                    Text("Auto-lock Vault: never")
                } else {
                    Text("Auto-lock Vault after \(autoLockLabel(value.wrappedValue))")
                }
            }
            Text("When the Vault is open, idle keyboard / mouse / scroll input longer than this triggers an instant re-lock. Set to 0 to disable.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// `120` → "2 minutes", `45` → "45 seconds", `90` → "1 minute, 30 seconds".
    /// Conservative formatting — Foundation's `DateComponentsFormatter`
    /// has a much richer abbreviation set, but for the narrow band
    /// (15s … 1h, step 15s) the manual formatting reads better.
    private func autoLockLabel(_ s: Int) -> String {
        if s < 60 { return "\(s) second\(s == 1 ? "" : "s")" }
        let minutes = s / 60
        let seconds = s % 60
        if seconds == 0 { return "\(minutes) minute\(minutes == 1 ? "" : "s")" }
        return "\(minutes) minute\(minutes == 1 ? "" : "s"), \(seconds) second\(seconds == 1 ? "" : "s")"
    }

    // MARK: - Sheets

    private var addPassphraseSheet: some View {
        passphraseSheet(title: "Add passphrase") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Wraps your encryption key under a passphrase. After this you'll need to enter it whenever you 'Lock now'.")
                    .font(.callout)
                SecureField("New passphrase", text: $newPassphrase)
                    .textFieldStyle(.roundedBorder)
                SecureField("Confirm", text: $confirmPassphrase)
                    .textFieldStyle(.roundedBorder)
            }
        } commit: {
            performAddPassphrase()
        }
    }

    private var changePassphraseSheet: some View {
        passphraseSheet(title: "Change passphrase") {
            VStack(alignment: .leading, spacing: 12) {
                SecureField("Current passphrase", text: $currentPassphrase)
                    .textFieldStyle(.roundedBorder)
                SecureField("New passphrase", text: $newPassphrase)
                    .textFieldStyle(.roundedBorder)
                SecureField("Confirm new", text: $confirmPassphrase)
                    .textFieldStyle(.roundedBorder)
            }
        } commit: {
            performChangePassphrase()
        }
    }

    private var removePassphraseSheet: some View {
        passphraseSheet(title: "Remove passphrase") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Reverts to Keychain-only protection. The app will open silently on future launches. Your data stays encrypted on disk.")
                    .font(.callout)
                SecureField("Current passphrase", text: $currentPassphrase)
                    .textFieldStyle(.roundedBorder)
            }
        } commit: {
            performRemovePassphrase()
        }
    }

    @ViewBuilder
    private func passphraseSheet<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content,
        commit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.bold())
            content()
            HStack {
                Button("Cancel") { dismissSheets() }
                Spacer()
                Button("OK") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    // MARK: - Actions

    private func performUnlock() {
        do {
            try store.unlock(passphrase: unlockPassphrase)
            unlockPassphrase = ""
            statusMessage = "Unlocked."
            errorMessage = nil
        } catch KeyStore.KeyStoreError.passphraseMismatch {
            errorMessage = "That passphrase didn't match. Try again."
            statusMessage = nil
        } catch {
            errorMessage = "Unlock failed: \(error.localizedDescription)"
            statusMessage = nil
        }
    }

    private func performAddPassphrase() {
        guard newPassphrase.count >= 4 else {
            errorMessage = "Pick a passphrase of at least 4 characters."
            return
        }
        guard newPassphrase == confirmPassphrase else {
            errorMessage = "The two passphrase fields don't match."
            return
        }
        do {
            try store.addPassphrase(newPassphrase)
            dismissSheets()
            statusMessage = "Passphrase added. The Keychain still has your key for this session — Lock now to clear it."
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't add passphrase: \(error.localizedDescription)"
        }
    }

    private func performChangePassphrase() {
        guard newPassphrase.count >= 4 else {
            errorMessage = "Pick a new passphrase of at least 4 characters."
            return
        }
        guard newPassphrase == confirmPassphrase else {
            errorMessage = "The two new-passphrase fields don't match."
            return
        }
        do {
            try store.changePassphrase(oldPassphrase: currentPassphrase,
                                       newPassphrase: newPassphrase)
            dismissSheets()
            statusMessage = "Passphrase changed."
            errorMessage = nil
        } catch KeyStore.KeyStoreError.passphraseMismatch {
            errorMessage = "Current passphrase incorrect."
        } catch {
            errorMessage = "Couldn't change passphrase: \(error.localizedDescription)"
        }
    }

    private func performRemovePassphrase() {
        do {
            try store.removePassphrase(currentPassphrase: currentPassphrase)
            dismissSheets()
            statusMessage = "Passphrase removed. App reverts to Keychain-managed protection."
            errorMessage = nil
        } catch KeyStore.KeyStoreError.passphraseMismatch {
            errorMessage = "Current passphrase incorrect."
        } catch {
            errorMessage = "Couldn't remove passphrase: \(error.localizedDescription)"
        }
    }

    private func performReset() {
        store.resetAndWipe()
        // Re-bootstrap into Keychain-managed mode so the SQLCipher path
        // always has a DEK to open against. Without this, post-reset
        // state is .notSetup and would block all reads. The generated
        // 24-word recovery key is the Phase B contract: the user needs
        // to save it before resuming the app, so route it through
        // AppState the same way the first-launch path does.
        do {
            let phrase = try store.setupKeychainManaged()
            appState.pendingRecoveryKey = phrase
            statusMessage = "Reset complete. Save your new recovery key to finish."
        } catch {
            statusMessage = "Reset complete, but couldn't generate a new key: \(error.localizedDescription)"
        }
        errorMessage = nil
    }

    private func dismissSheets() {
        showAddSheet = false
        showChangeSheet = false
        showRemoveSheet = false
        newPassphrase = ""
        confirmPassphrase = ""
        currentPassphrase = ""
    }
}
