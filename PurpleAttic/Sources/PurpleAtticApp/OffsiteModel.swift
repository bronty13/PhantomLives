import Foundation
import Combine
import Security
import PurpleAtticCore

/// View-model for the Off-site (Backblaze B2 / restic) settings pane. Runs the blocking restic +
/// Keychain operations off the main thread and republishes results on main, mirroring `AppState`.
/// Secrets entered here live only in transient `@Published` fields until written to the Keychain —
/// they are never persisted to disk by the app.
final class OffsiteModel: ObservableObject {

    // Repo status
    @Published var overview: ResticService.RepoOverview? = nil
    @Published var presence: ResticService.CredentialPresence? = nil
    @Published var isRefreshing = false

    // Credential entry (transient)
    @Published var b2KeyId = ""
    @Published var b2AppKey = ""
    @Published var isSavingCreds = false
    @Published var credsMessage: String? = nil

    // Recovery-key flow
    @Published var recoveryBusy = false
    @Published var recoveryLog: [String] = []
    /// nil = idle; the last recovery operation's result otherwise.
    @Published var recoveryResult: RecoveryResult? = nil

    enum RecoveryResult: Equatable {
        case added
        case verifiedPass(String)
        case failed(String)
    }

    // MARK: - Status

    func refresh(dest: CloudDestination) {
        guard !isRefreshing else { return }
        isRefreshing = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ov = ResticService.overview(destination: dest)
            let pr = ResticService.credentialPresence(for: dest)
            DispatchQueue.main.async {
                self?.overview = ov
                self?.presence = pr
                self?.isRefreshing = false
            }
        }
    }

    // MARK: - Credentials → Keychain

    /// Store the entered B2 keyID / application key (and, if missing, a freshly generated runtime
    /// passphrase) into the Keychain via the `security` CLI. Only non-empty fields are written, so
    /// you can update one credential without clearing the others.
    func saveCredentials(dest: CloudDestination, generateRuntimeIfMissing: Bool) {
        guard !isSavingCreds else { return }
        isSavingCreds = true
        credsMessage = nil
        let svc = dest.keychainService
        let id = b2KeyId.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = b2AppKey.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var wrote: [String] = []
            var failed: String? = nil
            do {
                if !id.isEmpty {
                    try KeychainStore.set(service: svc, account: ResticService.KeychainAccount.b2AccountId, value: id)
                    wrote.append("B2 key ID")
                }
                if !key.isEmpty {
                    try KeychainStore.set(service: svc, account: ResticService.KeychainAccount.b2AccountKey, value: key)
                    wrote.append("B2 application key")
                }
                if generateRuntimeIfMissing,
                   !KeychainStore.exists(service: svc, account: ResticService.KeychainAccount.resticPassword) {
                    let token = Self.randomToken(bytes: 32)
                    try KeychainStore.set(service: svc, account: ResticService.KeychainAccount.resticPassword, value: token)
                    wrote.append("runtime passphrase (generated)")
                }
            } catch {
                failed = (error as? KeychainStore.KeychainError)?.description ?? error.localizedDescription
            }
            let presence = ResticService.credentialPresence(for: dest)
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

    // MARK: - Recovery key

    func addRecoveryKey(dest: CloudDestination, passphrase: String) {
        guard !recoveryBusy else { return }
        recoveryBusy = true
        recoveryResult = nil
        recoveryLog = ["Adding the recovery key to the repository… (if a backup is running, this waits for it to release the lock)"]
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = ResticService.addRecoveryKey(destination: dest, newPassphrase: passphrase) { line in
                DispatchQueue.main.async { self?.recoveryLog.append(line) }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.recoveryBusy = false
                switch outcome {
                case .checked, .restored, .backedUp:
                    self.recoveryResult = .added
                    self.recoveryLog.append("✓ Recovery key added.")
                case .failed(let d):
                    self.recoveryResult = .failed(d)
                    self.recoveryLog.append("✗ \(d)")
                case .skipped(let r):
                    self.recoveryResult = .failed(r)
                    self.recoveryLog.append("✗ \(r)")
                }
            }
        }
    }

    func verifyRecoveryKey(dest: CloudDestination, typed: String, sourceRoot: String) {
        guard !recoveryBusy else { return }
        recoveryBusy = true
        recoveryResult = nil
        recoveryLog = []
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = ResticService.verifyRecoveryKey(destination: dest, passphrase: typed,
                                                          sourceRoot: sourceRoot) { line in
                DispatchQueue.main.async { self?.recoveryLog.append(line) }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.recoveryBusy = false
                switch outcome {
                case .restored(let d), .checked(let d), .backedUp(let d):
                    self.recoveryResult = .verifiedPass(d)
                    self.recoveryLog.append("✓ \(d)")
                case .failed(let d):
                    self.recoveryResult = .failed(d)
                    self.recoveryLog.append("✗ \(d)")
                case .skipped(let r):
                    self.recoveryResult = .failed(r)
                    self.recoveryLog.append("✗ \(r)")
                }
            }
        }
    }

    // MARK: - Helpers

    /// A high-entropy base64 token from the system CSPRNG — used for the machine *runtime*
    /// passphrase (lives only in the Keychain; the human-held recovery key is generated separately
    /// and word-based via `RecoveryPassphrase`).
    static func randomToken(bytes: Int) -> String {
        var data = Data(count: bytes)
        let ok = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) == errSecSuccess }
        if !ok { return UUID().uuidString + UUID().uuidString }   // never reached in practice
        return data.base64EncodedString()
    }
}
