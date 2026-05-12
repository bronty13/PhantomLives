import Foundation
import CryptoKit

/// Holds the data-encryption key (DEK) used to seal every PurpleLife
/// persistence file (the SQLite DB key, settings.json, attachment files).
///
/// Two operating modes — both keep data encrypted at rest, the difference
/// is how the DEK is protected:
///
/// **Keychain-managed (default for new installs).** A 256-bit DEK is
/// generated on first launch and stored in the macOS Keychain. The app
/// opens silently on subsequent launches because the Keychain holds the
/// DEK. No `keystore.json` is written to disk. Defends against bare-file
/// exfiltration (the on-disk files are sealed AES-GCM); Keychain ACLs
/// gate access on the running Mac.
///
/// **Passphrase-protected.** Same DEK, additionally wrapped under a KEK
/// derived from the user's passphrase via PBKDF2-HMAC-SHA256 (300k
/// iterations, 16-byte random salt). Wrapped DEK + salt + KDF params
/// live in `keystore.json`. The Keychain still caches the unwrapped DEK
/// after a successful unlock so subsequent launches don't reprompt; the
/// "Lock now" action clears the cache so the next launch demands the
/// passphrase again.
///
/// Changing the passphrase re-wraps the same DEK (millisecond op); no
/// user data is re-encrypted. Removing the passphrase deletes
/// `keystore.json`, leaving the Keychain-only mode in place. Forgetting
/// the passphrase with no Keychain cache means data loss — there is no
/// recovery mechanism. That is the point.
@MainActor
final class KeyStore: ObservableObject {

    enum UnlockState: Equatable {
        case notSetup        // no keystore.json, no Keychain entry
        case locked          // keystore.json exists, DEK not in memory
        case unlocked        // DEK is available; encrypt/decrypt works
    }

    enum KeyStoreError: Error {
        case alreadySetup
        case notSetup
        case locked
        case passphraseMismatch
        case corrupt
        case noPassphraseSet
        /// `setupKeychainManaged` aborted because a Keychain slot for our
        /// DEK already exists — we can't read it (so we'd silently
        /// overwrite it without this guard), but its presence means
        /// there's encrypted data on disk somewhere that belongs to
        /// it. Surface the situation to the user instead of destroying
        /// the key.
        case keychainEntryAlreadyExists
    }

    @Published private(set) var state: UnlockState = .notSetup

    /// True when `keystore.json` exists on disk (passphrase-protected mode).
    /// When false, the DEK is held only by the Keychain.
    @Published private(set) var hasPassphrase: Bool = false

    private let fileURL: URL
    /// Current DEK. Non-nil iff state == .unlocked. Never serialised directly.
    private var dek: SymmetricKey?

    /// Per-install Keychain account. Derived from the support dir path so
    /// separate installs (including test temp directories) don't share a
    /// DEK cache slot.
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

    /// Recompute `state` and `hasPassphrase`, then try a silent unlock via
    /// the Keychain cache so the rest of the app can decide whether it
    /// needs to prompt.
    func refreshState() {
        let envelopeExists = FileManager.default.fileExists(atPath: fileURL.path)
        hasPassphrase = envelopeExists

        if let cached = KeychainStore.getData(for: keychainDEKAccount),
           cached.count >= 16 {
            self.dek = SymmetricKey(data: cached)
            self.state = .unlocked
            return
        }

        // No Keychain cache. State depends on whether a passphrase
        // envelope is on disk to unlock against.
        self.dek = nil
        self.state = envelopeExists ? .locked : .notSetup
    }

    // MARK: - First-launch setup

    /// First-launch path A: generate a DEK and store it in the Keychain only
    /// (no passphrase). Defends against bare-file exfiltration; subsequent
    /// launches open silently. The user can layer a passphrase on top later
    /// via `addPassphrase(_:)`.
    func setupKeychainManaged() throws {
        guard state == .notSetup else { throw KeyStoreError.alreadySetup }
        // Refuse to overwrite an existing slot. `KeychainStore.getData`
        // returns nil for "item not found" AND for any transient query
        // failure (locked Keychain, auth issue, …) — without this
        // check we silently overwrite the existing DEK with a fresh
        // one and the on-disk encrypted DB becomes unrecoverable.
        // Real incident: 2026-05-12 saw repeat data-loss because
        // refreshState misread a transient miss as "first launch".
        let status = KeychainStore.entryStatus(for: keychainDEKAccount)
        if status != .absent {
            throw KeyStoreError.keychainEntryAlreadyExists
        }
        let newDEK = SymmetricKey(size: .bits256)
        self.dek = newDEK
        self.state = .unlocked
        self.hasPassphrase = false
        cacheDEKInKeychain()
    }

    /// First-launch path B: generate a DEK and wrap it under a passphrase.
    /// Stricter than Keychain-managed mode — `lock()` forces a re-prompt on
    /// next access. The Keychain still caches the unwrapped DEK for the
    /// current session so subsequent reads stay snappy.
    func setupWithPassphrase(_ passphrase: String) throws {
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
        self.hasPassphrase = true
        cacheDEKInKeychain()
    }

    // MARK: - Unlock / lock

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
        self.hasPassphrase = true
        cacheDEKInKeychain()
    }

    /// Drop the in-memory DEK and remove the Keychain cache. Only meaningful
    /// when a passphrase is set — without one, there's nothing to re-prompt
    /// for, so `lock()` would brick the install. Returns `false` and is a
    /// no-op in Keychain-managed mode.
    @discardableResult
    func lock() -> Bool {
        guard hasPassphrase else { return false }
        dek = nil
        state = .locked
        try? KeychainStore.delete(account: keychainDEKAccount)
        return true
    }

    // MARK: - Passphrase management

    /// Layer a passphrase on top of an existing Keychain-managed install.
    /// Wraps the current DEK; the Keychain cache stays in place so this
    /// session doesn't suddenly re-prompt. `lock()` becomes meaningful
    /// after this call.
    func addPassphrase(_ passphrase: String) throws {
        guard let dek else { throw KeyStoreError.locked }
        guard !hasPassphrase else { throw KeyStoreError.alreadySetup }
        let salt = Crypto.randomBytes(Self.saltLength)
        let kek = try Crypto.deriveKey(passphrase: passphrase,
                                       salt: salt,
                                       iterations: Self.kdfIterations)
        let wrapped = try Crypto.encrypt(dek.rawData, using: kek)
        let env = Envelope(salt: salt,
                           iterations: Self.kdfIterations,
                           wrappedDEK: wrapped)
        try persist(env)
        self.hasPassphrase = true
    }

    /// Swap the wrapping passphrase without touching the DEK, so no user
    /// data needs re-encryption. Requires the keystore to be unlocked AND
    /// to have a passphrase already set.
    func changePassphrase(oldPassphrase: String, newPassphrase: String) throws {
        guard hasPassphrase else { throw KeyStoreError.noPassphraseSet }
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
        self.dek = dekKey
        self.state = .unlocked
        self.hasPassphrase = true
        cacheDEKInKeychain()
    }

    /// Remove the passphrase wrapping, falling back to Keychain-managed mode.
    /// Verifies the current passphrase first so a thief at an unlocked Mac
    /// can't strip protection without proving they know it. Requires the
    /// keystore to be currently unlocked.
    func removePassphrase(currentPassphrase: String) throws {
        guard hasPassphrase else { throw KeyStoreError.noPassphraseSet }
        guard let dek else { throw KeyStoreError.locked }
        let env = try loadEnvelope()
        let kek = try Crypto.deriveKey(passphrase: currentPassphrase,
                                       salt: env.salt,
                                       iterations: env.iterations)
        let verified: Data
        do {
            verified = try Crypto.decrypt(env.wrappedDEK, using: kek)
        } catch {
            throw KeyStoreError.passphraseMismatch
        }
        // Sanity: the unwrapped DEK had better match what's in memory.
        guard verified == dek.rawData else { throw KeyStoreError.corrupt }
        try FileManager.default.removeItem(at: fileURL)
        self.hasPassphrase = false
        // DEK stays in memory and in the Keychain — that's the whole point
        // of "remove passphrase": the install continues to open silently.
    }

    /// Obliterate the keystore and all Keychain items so the user can start
    /// from scratch (e.g. if they forgot their passphrase and accept data loss).
    /// Any encrypted files on disk become unreadable garbage after this —
    /// callers should delete those separately.
    func resetAndWipe() {
        dek = nil
        state = .notSetup
        hasPassphrase = false
        try? FileManager.default.removeItem(at: fileURL)
        KeychainStore.deleteAll()
    }

    /// Test-only escape hatch to override `state` and `dek` so a test
    /// can exercise the "looks like first launch even though the
    /// Keychain entry still exists" scenario that `setupKeychainManaged`
    /// guards against. Used by the regression test for the silent-
    /// data-loss bug; not exposed to production callers because the
    /// state machine wants to own its transitions.
    func test_forceState(_ newState: UnlockState) {
        state = newState
        if newState != .unlocked { dek = nil }
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

    /// The current DEK. `SymmetricKey` is `Sendable`, so this is safe to
    /// ferry across isolation boundaries (SQLCipher and AttachmentService
    /// both need it).
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
        try? KeychainStore.setData(dek.rawData, for: keychainDEKAccount)
    }
}
