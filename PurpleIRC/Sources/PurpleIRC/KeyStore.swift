import Foundation
import CryptoKit
import LocalAuthentication

/// Holds the data-encryption key (DEK) used to seal `settings.json` and log
/// files. Passphrase-based unlock uses the classic KEK/DEK split:
///
///   1. On setup, generate a random 256-bit DEK.
///   2. Derive a KEK from the user's passphrase (PBKDF2-HMAC-SHA256, random
///      16-byte salt, 300k iterations).
///   3. Wrap (AES-GCM) the DEK with the KEK; store the wrapped DEK + salt +
///      KDF params on disk as `keystore.json`.
///   4. Stash the unwrapped DEK in the Keychain so subsequent launches don't
///      need to prompt (user can opt out via Security settings).
///
/// Changing the passphrase only re-wraps the DEK (milliseconds); it doesn't
/// re-encrypt any data.
///
/// Lock vs. unlock:
///   * `unlock(passphrase:)` puts the DEK in memory; encrypt/decrypt work.
///   * `lock()` clears the DEK + removes the Keychain cache; the user must
///     supply the passphrase again to read anything.
///
/// Forgot-passphrase: there is no recovery. That's the whole point.
@MainActor
final class KeyStore: ObservableObject {

    enum UnlockState: Equatable {
        case notSetup        // no keystore.json on disk yet
        case locked          // keystore exists but DEK is not in memory
        case unlocked        // DEK is available; encrypt/decrypt works
    }

    enum KeyStoreError: Error {
        case alreadySetup
        case notSetup
        case locked
        case passphraseMismatch
        case corrupt
    }

    @Published private(set) var state: UnlockState = .notSetup

    /// True when a DEK cache exists that needs a user-presence prompt to
    /// read (the "Require Touch ID" gate is active). Set by `refreshState`
    /// via a non-interactive Keychain probe, so it's known at launch
    /// BEFORE any encrypted settings are decrypted — the launch UI keys the
    /// biometric-unlock flow off this rather than the (still-encrypted)
    /// `requireBiometricsOnLaunch` preference.
    @Published private(set) var hasBiometricCache: Bool = false

    /// When true, `cacheDEKInKeychain` stores the DEK behind a user-presence
    /// ACL. Pushed by ChatModel from `requireBiometricsOnLaunch` via
    /// `applyBiometricPreference`.
    private(set) var requireBiometricGate = false

    private let fileURL: URL
    /// Current DEK. Non-nil iff state == .unlocked. Never serialised directly.
    private var dek: SymmetricKey?

    /// Per-install Keychain account. Derived from the support dir path so
    /// separate installs (including test temp directories) don't share a
    /// DEK cache slot. Hash-truncated so the account name stays short.
    private let keychainDEKAccount: String
    private static let kdfIterations = 300_000
    private static let saltLength = 16

    // MARK: - On-disk representation

    /// `keystore.json` contents. Bumping `version` lets us migrate wrap
    /// formats later without breaking existing files.
    private struct Envelope: Codable {
        var version: Int = 1
        var salt: Data                // passphrase KDF salt
        var iterations: Int           // KDF iterations (future-proofing)
        var wrappedDEK: Data          // AES-GCM combined-format sealed box
    }

    // MARK: - Init

    init(supportDirectoryURL: URL) {
        self.fileURL = supportDirectoryURL.appendingPathComponent("keystore.json")
        // Full SHA-256 hex of the support-directory path. Truncating to
        // 48 bits added no value and made colliding-path attacks plausible
        // (2^24 expected attempts) — there's no length pressure on the
        // Keychain account name.
        let pathHash = SHA256.hash(data: Data(supportDirectoryURL.path.utf8))
            .map { String(format: "%02x", $0) }.joined()
        self.keychainDEKAccount = "dek-v1-\(pathHash)"
        refreshState()
    }

    /// Recompute `state` and try a silent unlock via the Keychain cache so
    /// the rest of the app can decide whether it needs to prompt.
    func refreshState() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            state = .notSetup
            hasBiometricCache = false
            return
        }
        // Probe the Keychain WITHOUT prompting so we can pick the right
        // unlock path before decrypting anything.
        switch KeychainStore.probe(account: keychainDEKAccount) {
        case .readable:
            // Ungated (or device-allowed) cache — silent unlock, as before.
            if let cached = KeychainStore.getData(for: keychainDEKAccount),
               cached.count >= 16 {
                self.dek = SymmetricKey(data: cached)
                self.state = .unlocked
                self.hasBiometricCache = false
                // Re-stamp so a DEK written by an older build (plain
                // `WhenUnlocked`, sync/migration-eligible) is upgraded to
                // device-only. Idempotent.
                cacheDEKInKeychain()
            } else {
                self.state = .locked
                self.hasBiometricCache = false
            }
        case .requiresAuth:
            // A user-presence-gated cache exists; stay locked until the UI
            // runs the biometric unlock (`unlockWithCachedKey`).
            self.state = .locked
            self.hasBiometricCache = true
        case .absent:
            self.state = .locked
            self.hasBiometricCache = false
        }
    }

    /// Read the gated DEK cache using an already-authenticated `LAContext`
    /// (reused from the launch Touch ID prompt so the user isn't asked
    /// twice). Returns true on success; on failure the caller falls back to
    /// the passphrase. Never a lockout — the envelope + passphrase always
    /// recover the DEK.
    @discardableResult
    func unlockWithCachedKey(context: LAContext) -> Bool {
        guard let cached = KeychainStore.getData(for: keychainDEKAccount, context: context),
              cached.count >= 16 else { return false }
        self.dek = SymmetricKey(data: cached)
        self.state = .unlocked
        self.hasBiometricCache = false
        return true
    }

    /// Apply the user's "Require Touch ID" preference. Flips the gate flag
    /// and, when the preference actually changed while unlocked, re-stamps
    /// the cached DEK with or without the user-presence ACL so the next
    /// launch behaves accordingly. Called by ChatModel as settings load and
    /// whenever the toggle changes.
    func applyBiometricPreference(_ on: Bool) {
        let changed = (on != requireBiometricGate)
        requireBiometricGate = on
        if changed, state == .unlocked {
            cacheDEKInKeychain()
            // Reflect the new gate immediately for any UI observing it.
            hasBiometricCache = on
        }
    }

    // MARK: - Setup / unlock / lock

    /// Create the keystore with a brand-new DEK wrapped by `passphrase`.
    /// Fails if a keystore already exists — caller should route through
    /// `changePassphrase` instead.
    func setup(passphrase: String) throws {
        guard state == .notSetup else { throw KeyStoreError.alreadySetup }
        let newDEK = SymmetricKey(size: .bits256)
        let salt = Crypto.randomBytes(Self.saltLength)
        let kek = try Crypto.deriveKey(passphrase: passphrase,
                                       salt: salt,
                                       iterations: Self.kdfIterations)
        let wrapped = try Crypto.encrypt(newDEK.rawData, using: kek)
        let env = Envelope(salt: salt,
                           iterations: Self.kdfIterations,
                           wrappedDEK: wrapped)
        try persist(env)
        self.dek = newDEK
        self.state = .unlocked
        cacheDEKInKeychain()
    }

    /// Derive KEK from `passphrase`, unwrap DEK, store in memory. Throws
    /// `.passphraseMismatch` on wrong passphrase (AES-GCM tag check fails).
    func unlock(passphrase: String) throws {
        let env = try loadEnvelope()
        let kek = try Crypto.deriveKey(passphrase: passphrase,
                                       salt: env.salt,
                                       iterations: env.iterations)
        let rawDEK: Data
        do {
            rawDEK = try Crypto.decrypt(env.wrappedDEK, using: kek)
        } catch {
            throw KeyStoreError.passphraseMismatch
        }
        self.dek = SymmetricKey(data: rawDEK)
        self.state = .unlocked
        cacheDEKInKeychain()
    }

    /// Drop the in-memory DEK and remove the Keychain cache. Next launch
    /// will require the passphrase again.
    func lock() {
        dek = nil
        state = FileManager.default.fileExists(atPath: fileURL.path) ? .locked : .notSetup
        try? KeychainStore.delete(account: keychainDEKAccount)
    }

    /// Swap the wrapping passphrase without touching the DEK, so no user
    /// data needs re-encryption. Requires the keystore to be unlocked.
    func changePassphrase(oldPassphrase: String, newPassphrase: String) throws {
        // Verify old via a fresh unlock pass (doesn't mutate state beyond
        // confirming the current DEK matches).
        let env = try loadEnvelope()
        let oldKEK = try Crypto.deriveKey(passphrase: oldPassphrase,
                                          salt: env.salt,
                                          iterations: env.iterations)
        let verified: Data
        do {
            verified = try Crypto.decrypt(env.wrappedDEK, using: oldKEK)
        } catch {
            throw KeyStoreError.passphraseMismatch
        }
        // Re-wrap the same DEK with the new passphrase + fresh salt.
        let dekKey = SymmetricKey(data: verified)
        let newSalt = Crypto.randomBytes(Self.saltLength)
        let newKEK = try Crypto.deriveKey(passphrase: newPassphrase,
                                          salt: newSalt,
                                          iterations: Self.kdfIterations)
        let newWrapped = try Crypto.encrypt(dekKey.rawData, using: newKEK)
        let newEnv = Envelope(salt: newSalt,
                              iterations: Self.kdfIterations,
                              wrappedDEK: newWrapped)
        try persist(newEnv)
        // Keep current session unlocked; refresh the Keychain cache too.
        self.dek = dekKey
        self.state = .unlocked
        cacheDEKInKeychain()
    }

    /// Obliterate the keystore and all Keychain items so the user can start
    /// from scratch (e.g. if they forgot their passphrase and accept data loss).
    /// Any encrypted files on disk become unreadable garbage after this —
    /// callers should delete those separately.
    func resetAndWipe() {
        dek = nil
        state = .notSetup
        try? FileManager.default.removeItem(at: fileURL)
        KeychainStore.deleteAll()
    }

    // MARK: - Encrypt / decrypt passthroughs

    /// Encrypt arbitrary data with the current DEK. Throws `.locked` when
    /// the keystore isn't open.
    func encrypt(_ plaintext: Data) throws -> Data {
        guard let dek else { throw KeyStoreError.locked }
        return try Crypto.encrypt(plaintext, using: dek)
    }

    /// Decrypt data produced by `encrypt`. Throws on wrong key or tamper.
    func decrypt(_ ciphertext: Data) throws -> Data {
        guard let dek else { throw KeyStoreError.locked }
        return try Crypto.decrypt(ciphertext, using: dek)
    }

    var isUnlocked: Bool { state == .unlocked }

    /// The current DEK, for subsystems that need to encrypt on a non-main
    /// actor (e.g. `LogStore`). `SymmetricKey` is `Sendable`, so this is safe
    /// to ferry across isolation boundaries — and the DEK is going to be in
    /// the logger's address space anyway as soon as it starts sealing lines.
    var currentKey: SymmetricKey? { dek }

    // MARK: - Disk / keychain

    private func persist(_ env: Envelope) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(env)
        try data.write(to: fileURL, options: .atomic)
        // Owner-only perms — the wrapped DEK is useless without the
        // passphrase, but tightening the file mode is cheap defence.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private func loadEnvelope() throws -> Envelope {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw KeyStoreError.notSetup
        }
        let data = try Data(contentsOf: fileURL)
        let dec = JSONDecoder()
        guard let env = try? dec.decode(Envelope.self, from: data) else {
            throw KeyStoreError.corrupt
        }
        return env
    }

    private func cacheDEKInKeychain() {
        guard let dek else { return }
        try? KeychainStore.setData(dek.rawData, for: keychainDEKAccount,
                                   requireBiometry: requireBiometricGate)
    }
}
