import SwiftUI
import AppKit

/// Full-window screen lock shown when `AppState.appLocked` is true.
///
/// Two unlock paths, chosen by the keystore's state:
/// - **Keychain-managed** (DEK still cached): the lock is a screen gate.
///   Re-authenticate with Touch ID / device password to dismiss it; the DB is
///   already open.
/// - **Passphrase mode after a lock** (DEK wiped from memory + Keychain): the
///   passphrase is required to restore the key and reopen the database. Touch
///   ID can't recover a passphrase-wiped key, so it isn't offered there.
///
/// In either case a "Use recovery key" path is available when a recovery
/// envelope exists, so a forgotten passphrase / lost biometrics never bricks
/// access.
struct AppLockScreen: View {
    @EnvironmentObject private var appState: AppState

    @State private var attempting = false
    @State private var passphrase = ""
    @State private var errorMessage: String?
    @State private var showRecovery = false

    /// Passphrase entry is required when a passphrase is set and the DEK is not
    /// currently in memory (a prior lock wiped it). Otherwise the screen is a
    /// Touch ID / device-password gate.
    private var needsPassphrase: Bool {
        appState.keyStore.hasPassphrase && !appState.keyStore.isUnlocked
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: errorMessage == nil ? "lock.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(errorMessage == nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.orange))
            Text("PurpleDiary is locked")
                .font(.title2).bold()
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if needsPassphrase {
                passphraseField
            } else {
                Button {
                    Task { await biometricUnlock() }
                } label: {
                    Label("Unlock", systemImage: "touchid")
                        .padding(.horizontal, 18).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(attempting)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            if appState.keyStore.hasRecoveryEnvelope {
                Button("Use recovery key…") { showRecovery = true }
                    .buttonStyle(.link)
                    .padding(.top, 4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            // Auto-prompt Touch ID in the common keychain-managed case so the
            // user doesn't have to click. Passphrase mode waits for typing.
            if !needsPassphrase {
                Task { await biometricUnlock() }
            }
        }
        .sheet(isPresented: $showRecovery) {
            RecoveryUnlockView(
                title: "Unlock with recovery key",
                onUnlock: { phrase in appState.tryRecoveryKeyUnlock(phrase: phrase) },
                onSuccess: { showRecovery = false; appState.unlockApp() },
                onCancel: { showRecovery = false }
            )
            .environmentObject(appState)
        }
    }

    private var caption: String {
        if needsPassphrase {
            return "Enter your passphrase to unlock your journal."
        }
        return appState.settings.biometryOnlyMode
            ? "Re-authenticate with Touch ID to continue. (Password fallback is off.)"
            : "Re-authenticate with Touch ID or your device password to continue."
    }

    private var passphraseField: some View {
        HStack(spacing: 8) {
            SecureField("Passphrase", text: $passphrase)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onSubmit { submitPassphrase() }
            Button("Unlock") { submitPassphrase() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(passphrase.isEmpty || attempting)
        }
    }

    private func submitPassphrase() {
        guard !passphrase.isEmpty else { return }
        attempting = true
        defer { attempting = false }
        if appState.unlockWithPassphrase(passphrase) {
            passphrase = ""
            errorMessage = nil
        } else {
            errorMessage = "That passphrase didn't work. Try again, or use your recovery key."
            passphrase = ""
        }
    }

    private func biometricUnlock() async {
        guard !attempting else { return }
        attempting = true
        defer { attempting = false }
        if await appState.attemptBiometricUnlock() {
            errorMessage = nil
        } else {
            errorMessage = "Authentication didn't complete. Tap Unlock to try again."
        }
    }
}
