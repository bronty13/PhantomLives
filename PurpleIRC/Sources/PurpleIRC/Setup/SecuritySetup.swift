import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Security

/// Manages encryption state: enable/disable, change passphrase, lock, reset.
/// Surfaces the composite-key design for the user so they understand what
/// protects what (credentials always via Keychain; metadata + logs only when
/// they enable encryption and pass an unlock).
struct SecuritySetup: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var keyStore: KeyStore

    @State private var showSetupSheet = false
    @State private var showChangeSheet = false
    @State private var showResetConfirm = false

    var body: some View {
        Form {
            Section("Credentials") {
                HStack {
                    Image(systemName: "key.horizontal.fill")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading) {
                        Text("Stored in macOS Keychain").bold()
                        Text("SASL, NickServ, server, and proxy passwords are moved out of settings.json into your login Keychain on save. No passphrase required — this protection is always on.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Encryption") {
                statusRow
                if keyStore.state == .notSetup {
                    Button("Enable encryption with a passphrase…") {
                        showSetupSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    Text("Encrypts settings.json and chat logs with AES-256-GCM. A data-encryption key is random; the passphrase wraps it. Forgotten passphrase = unrecoverable data.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    HStack {
                        Button("Change passphrase…") { showChangeSheet = true }
                            .disabled(!keyStore.isUnlocked)
                        Button("Lock now") {
                            keyStore.lock()
                        }
                        .disabled(!keyStore.isUnlocked)
                        Spacer()
                        Button("Disable encryption…", role: .destructive) {
                            showResetConfirm = true
                        }
                    }
                    Text("Lock now clears the Keychain-cached key on this Mac — next launch will require your passphrase. Disable erases the keystore and rewrites settings as plaintext.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("Biometrics") {
                if BiometricGate.isAvailable {
                    Toggle("Require Touch ID on launch",
                           isOn: $settings.settings.requireBiometricsOnLaunch)
                        .disabled(keyStore.state == .notSetup)
                    Text("When on, PurpleIRC's window is locked behind a Touch ID prompt at launch; cancelling falls back to your passphrase. This is a screen lock over the app UI — not a cryptographic gate on the stored key. The encryption key is cached in this Mac's Keychain marked device-only, so it never syncs to iCloud or migrates to another Mac, but a process already running as you can still read it. Your passphrase remains the real secret.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    // Surface the live availability diagnostic so a "ready"
                    // row reads as confidence and a transient failure
                    // (locked out, etc.) tells the user what to fix.
                    Label(BiometricGate.availabilityDetail, systemImage: "touchid")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Label(BiometricGate.availabilityDetail, systemImage: "touchid")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section("What this protects") {
                bulletRow("settings.json metadata (servers, channels, triggers, highlights) — encrypted on disk when the passphrase is set.")
                bulletRow("Chat logs — encrypted per-line when persistent logging is on (see Behavior tab).")
                bulletRow("Credentials — always in Keychain, regardless of passphrase state.")
                bulletRow("Not covered: running-memory state, a compromised logged-in session with both the Keychain and the passphrase.")
            }

            Section("Factory reset") {
                Text("Wiping all data (settings, keystore, logs, scripts) lives on the **Backup** tab next to the restore tools, so reset and recover sit side by side.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showSetupSheet) {
            PassphraseSetupView(keyStore: keyStore) {
                // Force a re-save so the first envelope lands on disk.
                settings.save()
            }
        }
        .sheet(isPresented: $showChangeSheet) {
            PassphraseChangeView(keyStore: keyStore)
        }
        .confirmationDialog("Disable encryption?",
                            isPresented: $showResetConfirm,
                            titleVisibility: .visible) {
            Button("Erase keystore and rewrite as plaintext", role: .destructive) {
                keyStore.resetAndWipe()
                settings.save()  // falls back to plaintext now that keystore is gone
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The data-encryption key will be destroyed. Existing encrypted log files become unreadable (delete them manually from Files → Open logs folder). Credentials in the Keychain stay put.")
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack {
            Image(systemName: keyStore.isUnlocked ? "lock.open.fill"
                             : keyStore.state == .locked ? "lock.fill"
                             : "lock.slash")
                .foregroundStyle(keyStore.isUnlocked ? Color.green
                                 : keyStore.state == .locked ? Color.orange
                                 : Color.secondary)
            VStack(alignment: .leading) {
                Text(statusTitle).bold()
                Text(statusDetail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var statusTitle: String {
        switch keyStore.state {
        case .notSetup: return "Not enabled"
        case .locked:   return "Locked"
        case .unlocked: return "Unlocked"
        }
    }

    private var statusDetail: String {
        switch keyStore.state {
        case .notSetup:
            return "settings.json is plaintext; chat logs are plaintext. Credentials still go to Keychain."
        case .locked:
            return "settings.json is encrypted on disk. Enter your passphrase to access it."
        case .unlocked:
            return settings.isEncryptedOnDisk
                ? "settings.json envelope is encrypted on disk; memory holds the decrypted copy."
                : "Keystore is ready. Save once to write the first encrypted envelope."
        }
    }

    @ViewBuilder
    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").foregroundStyle(.secondary)
            Text(text).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }
}

