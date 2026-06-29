import Foundation
import Combine
import PurpleAtticCore

/// View-model for the **Ad-hoc B2** pane (the second, file-level Backblaze account). Runs the
/// blocking rclone + Keychain operations off the main thread and republishes on main, mirroring
/// `OffsiteModel`. Secrets entered here live only in transient `@Published` fields until written to
/// the Keychain — they are never persisted to disk by the app.
final class AdhocModel: ObservableObject {

    /// Which secrets are present in the Keychain (attribute-only checks; never prompt).
    struct Presence: Equatable {
        var b2Id = false
        var b2Key = false
        var cryptPass = false
        /// Everything needed before a backup/list can run.
        var allReady: Bool { b2Id && b2Key && cryptPass }
    }

    @Published var presence = Presence()

    // Credential entry (transient — never written to disk, only to the Keychain).
    @Published var b2KeyId = ""
    @Published var b2AppKey = ""
    @Published var isSavingCreds = false
    @Published var credsMessage: String? = nil

    // Encryption passphrase (the crypt key).
    @Published var isSavingPassphrase = false
    @Published var passphraseMessage: String? = nil

    // Test connection.
    @Published var isTesting = false
    @Published var testResult: TestResult? = nil

    enum TestResult: Equatable {
        case ok(String)
        case failed(String)
    }

    // Backup (upload).
    @Published var isBackingUp = false
    @Published var backupProgress: RcloneProgress? = nil
    @Published var backupStatus: String? = nil
    @Published var backupLog: [String] = []

    // Diff (what a backup would upload).
    @Published var isDiffing = false
    @Published var diffEntries: [DiffEntry]? = nil   // nil = not checked yet
    @Published var diffStatus: String? = nil

    /// rclone must be installed (it drives every ad-hoc operation, including obscuring the passphrase).
    var rcloneAvailable: Bool { Tooling.rclone != nil }

    // MARK: - Presence

    func refreshPresence(config: AdhocBackupConfig) {
        let svc = config.keychainService
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let p = Self.readPresence(service: svc)
            DispatchQueue.main.async { self?.presence = p }
        }
    }

    private static func readPresence(service svc: String) -> Presence {
        Presence(
            b2Id: KeychainStore.exists(service: svc, account: RcloneService.KeychainAccount.b2AccountId),
            b2Key: KeychainStore.exists(service: svc, account: RcloneService.KeychainAccount.b2AccountKey),
            cryptPass: KeychainStore.exists(service: svc, account: RcloneService.KeychainAccount.cryptPassword))
    }

    // MARK: - B2 credentials → Keychain

    /// Store the entered B2 keyID / application key. Only non-empty fields are written, so one can be
    /// updated without clearing the other.
    func saveCredentials(config: AdhocBackupConfig) {
        guard !isSavingCreds else { return }
        isSavingCreds = true
        credsMessage = nil
        let svc = config.keychainService
        let id = b2KeyId.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = b2AppKey.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var wrote: [String] = []
            var failed: String? = nil
            do {
                if !id.isEmpty {
                    try KeychainStore.set(service: svc, account: RcloneService.KeychainAccount.b2AccountId, value: id)
                    wrote.append("B2 key ID")
                }
                if !key.isEmpty {
                    try KeychainStore.set(service: svc, account: RcloneService.KeychainAccount.b2AccountKey, value: key)
                    wrote.append("B2 application key")
                }
            } catch {
                failed = (error as? KeychainStore.KeychainError)?.description ?? error.localizedDescription
            }
            let presence = Self.readPresence(service: svc)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSavingCreds = false
                self.presence = presence
                if let failed {
                    self.credsMessage = "Keychain error: \(failed)"
                } else if wrote.isEmpty {
                    self.credsMessage = "Nothing to save — enter a value first."
                } else {
                    self.credsMessage = "Saved to Keychain: \(wrote.joined(separator: ", "))."
                    self.b2KeyId = ""; self.b2AppKey = ""
                }
            }
        }
    }

    // MARK: - Encryption passphrase → Keychain

    /// Obscure the passphrase (`rclone obscure`) and store it as the crypt key. The passphrase is the
    /// **only** key to the data — this is gated behind the recovery-sheet confirmation in the UI.
    /// `completion(true)` only on success (lets the sheet dismiss itself).
    func savePassphrase(config: AdhocBackupConfig, passphrase: String, completion: @escaping (Bool) -> Void) {
        guard !isSavingPassphrase else { return }
        isSavingPassphrase = true
        passphraseMessage = nil
        let svc = config.keychainService
        let plain = passphrase
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var ok = false
            let message: String
            if Tooling.rclone == nil {
                message = "rclone not found — install it with `brew install rclone`, then set the passphrase."
            } else if let obscured = RcloneService.obscure(plain) {
                do {
                    try KeychainStore.set(service: svc, account: RcloneService.KeychainAccount.cryptPassword, value: obscured)
                    ok = true
                    message = "Encryption passphrase saved to your Keychain."
                } catch {
                    message = "Keychain error: \((error as? KeychainStore.KeychainError)?.description ?? error.localizedDescription)"
                }
            } else {
                message = "Could not prepare the passphrase (rclone obscure failed)."
            }
            let presence = Self.readPresence(service: svc)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSavingPassphrase = false
                self.passphraseMessage = message
                self.presence = presence
                completion(ok)
            }
        }
    }

    // MARK: - Backup (upload)

    /// Run a one-way additive upload of the config's sources, streaming rclone's JSON-log lines into
    /// a live progress bar (`backupProgress`) + a compact message log (`backupLog`).
    func runBackup(config: AdhocBackupConfig) {
        guard !isBackingUp else { return }
        isBackingUp = true
        backupProgress = nil
        backupStatus = nil
        backupLog = []
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = RcloneService.backup(config: config) { line in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let p = RcloneParse.progress(line) {
                        self.backupProgress = p
                    } else if let m = RcloneParse.logMessage(line) {
                        self.backupLog.append(m)
                        if self.backupLog.count > 200 { self.backupLog.removeFirst(self.backupLog.count - 200) }
                    }
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isBackingUp = false
                switch outcome {
                case .ok(let d): self.backupStatus = "✓ \(d)"
                case .skipped(let r): self.backupStatus = "Skipped — \(r)"
                case .failed(let d): self.backupStatus = "✗ \(d)"
                }
            }
        }
    }

    // MARK: - Diff (preview what a backup would upload)

    /// Compare the configured sources against B2 (one-way) and publish the differences. Uploads
    /// nothing — `runBackup` does the actual additive upload.
    func checkDiff(config: AdhocBackupConfig) {
        guard !isDiffing else { return }
        isDiffing = true
        diffStatus = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (entries, outcome) = RcloneService.diff(config: config)
            var status: String? = nil
            switch outcome {
            case .ok(let d): status = d
            case .skipped(let r): status = "Can't compare — \(r)"
            case .failed(let d): status = d
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isDiffing = false
                self.diffEntries = entries
                self.diffStatus = status
            }
        }
    }

    // MARK: - Test connection

    func testConnection(config: AdhocBackupConfig) {
        guard !isTesting else { return }
        isTesting = true
        testResult = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = RcloneService.testConnection(config: config)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isTesting = false
                switch outcome {
                case .ok(let d): self.testResult = .ok(d)
                case .skipped(let r): self.testResult = .failed("can't test yet — \(r)")
                case .failed(let d): self.testResult = .failed(d)
                }
            }
        }
    }
}
