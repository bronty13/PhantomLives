import Foundation
import CryptoKit

/// Holds the data-encryption key (DEK) used to seal PurpleDiary's at-rest data
/// — the SQLCipher DB key and `settings.json`.
///
/// PurpleDiary is local-first: the DEK lives only in this Mac's login Keychain
/// (no iCloud mirror, no cloud backup). The user-held BIP39 recovery key is the
/// one cross-machine / lost-Keychain recovery path.
///
/// Two operating modes — both keep data encrypted at rest; the difference is
/// how the DEK is protected:
///
/// **Keychain-managed (default for new installs).** A 256-bit DEK is generated
/// on first launch and stored in the Keychain. The app opens silently on
/// subsequent launches. No `keystore.json` is written. Defends against bare-file
/// exfiltration (the DB file is SQLCipher ciphertext); Keychain ACLs gate
/// access on the running Mac.
///
/// **Passphrase-protected.** Same DEK, additionally wrapped under a KEK derived
/// from the user's passphrase via PBKDF2-HMAC-SHA256 (300k iterations, 16-byte
/// salt). Wrapped DEK + salt + KDF params live in `keystore.json`. The Keychain
/// still caches the unwrapped DEK after a successful unlock; "Lock now" clears
/// the cache so the next launch demands the passphrase again.
///
/// Either way, every fresh keystore also writes a `recovery_envelope.json`
/// holding the DEK wrapped under a KEK derived from a 24-word BIP39 phrase —
/// so a lost Keychain entry (and forgotten/absent passphrase) is still
/// recoverable from the phrase the user wrote down.
@MainActor
final class KeyStore: ObservableObject {

    enum UnlockState: Equatable {
        case notSetup        // no keystore.json, no Keychain entry
        case locked          // an unlock envelope exists, DEK not in memory
        case unlocked        // DEK is available; encrypt/decrypt works
    }

    enum KeyStoreError: Error {
        case alreadySetup
        case notSetup
        case locked
        case passphraseMismatch
        case corrupt
        case noPassphraseSet
        /// `setupKeychainManaged` aborted because a Keychain slot for our DEK
        /// already exists — we can't read it (so we'd silently overwrite it
        /// without this guard), but its presence means there's encrypted data
        /// on disk that belongs to it.
        case keychainEntryAlreadyExists
        /// `setupKeychainManaged` aborted because the per-install
        /// `boot_state.json` marker exists but the Keychain slot is empty: the
        /// install has launched successfully before (data written under some
        /// prior DEK) yet that DEK is gone. Minting a fresh DEK here would make
        /// every byte on disk unreadable forever. The keystore refuses;
        /// AppState surfaces the recovery screen without creating a new DEK.
        case everBootedButKeychainGone
    }

    @Published private(set) var state: UnlockState = .notSetup

    /// True when `keystore.json` exists on disk (passphrase-protected mode).
    @Published private(set) var hasPassphrase: Bool = false

    private let fileURL: URL
    /// Current DEK. Non-nil iff state == .unlocked. Never serialised directly.
    private var dek: SymmetricKey?

    /// Per-install Keychain account. Derived from the support dir path so
    /// separate installs (including test temp directories) don't share a DEK
    /// cache slot.
    private let keychainDEKAccount: String
    private static let kdfIterations = 300_000
    private static let saltLength = 16

    // MARK: - On-disk representation

    /// `keystore.json` contents (passphrase wrap).
    private struct Envelope: Codable {
        var version: Int = 1
        var salt: Data
        var iterations: Int
        var wrappedDEK: Data
    }

    /// `recovery_envelope.json` contents — the DEK wrapped under a KEK derived
    /// from the 24-word recovery phrase. Independent of `keystore.json`.
    private struct RecoveryEnvelope: Codable {
        var version: Int = 1
        var salt: Data
        var iterations: Int
        var wrappedDEK: Data
    }

    private let recoveryFileURL: URL

    // MARK: - Init

    init(supportDirectoryURL: URL) {
        self.fileURL = supportDirectoryURL.appendingPathComponent("keystore.json")
        self.recoveryFileURL = supportDirectoryURL.appendingPathComponent("recovery_envelope.json")
        // Full SHA-256 hex of the support-directory path. No length pressure on
        // the Keychain account name, so don't truncate.
        let pathHash = SHA256.hash(data: Data(supportDirectoryURL.path.utf8))
            .map { String(format: "%02x", $0) }.joined()
        self.keychainDEKAccount = "dek-v1-\(pathHash)"
        refreshState()
    }

    /// True iff a recovery-envelope file exists on disk. Used by `AppState` to
    /// decide whether the recovery screen should expose "Enter recovery key".
    var hasRecoveryEnvelope: Bool {
        FileManager.default.fileExists(atPath: recoveryFileURL.path)
    }

    /// Recompute `state` and `hasPassphrase`, then try a silent unlock via the
    /// Keychain cache so the rest of the app can decide whether to prompt.
    func refreshState() {
        let envelopeExists = FileManager.default.fileExists(atPath: fileURL.path)
        hasPassphrase = envelopeExists

        if let cached = KeychainStore.getData(for: keychainDEKAccount),
           cached.count >= 16 {
            self.dek = SymmetricKey(data: cached)
            self.state = .unlocked
            return
        }

        // No Keychain cache. State depends on whether *any* unlock envelope is
        // on disk: a passphrase envelope or a recovery envelope. Only when
        // neither is present is this a genuine fresh install.
        self.dek = nil
        if envelopeExists || hasRecoveryEnvelope {
            self.state = .locked
        } else {
            self.state = .notSetup
        }
    }

    // MARK: - First-launch setup

    /// First-launch path A: generate a DEK and store it in the Keychain only
    /// (no passphrase). Returns the 24-word recovery phrase the caller MUST
    /// show the user before proceeding.
    @discardableResult
    func setupKeychainManaged() throws -> [String] {
        guard state == .notSetup else { throw KeyStoreError.alreadySetup }
        // Refuse to overwrite an existing slot. `entryStatus` distinguishes a
        // definite "absent" from a transient read failure — without this we
        // could silently overwrite the existing DEK and brick the on-disk DB.
        let status = KeychainStore.entryStatus(for: keychainDEKAccount)
        if status != .absent {
            throw KeyStoreError.keychainEntryAlreadyExists
        }
        // Second guard: even when the slot is definitively absent, refuse to
        // create a fresh DEK if the ever-booted marker says this install ran
        // before. Absent slot + present marker ⇒ the Keychain entry was
        // destroyed out-of-band; a fresh DEK would foreclose recovery (Time
        // Machine restore of the Keychain item, the user's recovery key).
        if BootState.everBooted(in: supportDirectory) {
            throw KeyStoreError.everBootedButKeychainGone
        }
        let newDEK = SymmetricKey(size: .bits256)
        self.dek = newDEK
        self.state = .unlocked
        self.hasPassphrase = false
        cacheDEKInKeychain()
        return try writeRecoveryEnvelope(for: newDEK)
    }

    private var supportDirectory: URL {
        fileURL.deletingLastPathComponent()
    }

    /// First-launch path B: generate a DEK and wrap it under a passphrase.
    /// Returns the recovery phrase (MUST be surfaced to the user).
    @discardableResult
    func setupWithPassphrase(_ passphrase: String) throws -> [String] {
        guard state == .notSetup else { throw KeyStoreError.alreadySetup }
        let newDEK = SymmetricKey(size: .bits256)
        let salt = Crypto.randomBytes(Self.saltLength)
        let kek = try Crypto.deriveKey(passphrase: passphrase, salt: salt, iterations: Self.kdfIterations)
        let wrapped = try Crypto.encrypt(newDEK.rawData, using: kek)
        try persist(Envelope(salt: salt, iterations: Self.kdfIterations, wrappedDEK: wrapped))
        self.dek = newDEK
        self.state = .unlocked
        self.hasPassphrase = true
        cacheDEKInKeychain()
        return try writeRecoveryEnvelope(for: newDEK)
    }

    /// Migration: if unlocked (silent fast-path) but no recovery envelope
    /// exists, generate one now from the live DEK. Returns the phrase; the
    /// caller must surface it. No-op (returns nil) when an envelope exists, so
    /// it's safe to call on every launch.
    func ensureRecoveryEnvelope() throws -> [String]? {
        guard state == .unlocked, let dek else { return nil }
        if hasRecoveryEnvelope { return nil }
        return try writeRecoveryEnvelope(for: dek)
    }

    /// Generate a brand-new recovery envelope (new 24-word phrase), replacing
    /// any existing one. Requires the keystore to be unlocked. Returns the new
    /// words for the UX to show. Use when the old key may have been exposed.
    func regenerateRecoveryEnvelope() throws -> [String] {
        guard let dek else { throw KeyStoreError.locked }
        return try writeRecoveryEnvelope(for: dek)
    }

    /// Recovery unlock: derive the KEK from a recovery phrase, unwrap the DEK,
    /// cache in Keychain so subsequent launches are silent again. Reuses
    /// `.passphraseMismatch` for "wrong recovery key" (the AES-GCM tag check is
    /// the same). `RecoveryKey.entropy(from:)` upstream catches typos first.
    func unlockWithRecoveryKey(phrase: String) throws {
        guard hasRecoveryEnvelope else { throw KeyStoreError.notSetup }
        let env = try loadRecoveryEnvelope()
        let kek = try RecoveryKey.deriveKEK(phrase: phrase, salt: env.salt, iterations: env.iterations)
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

    /// Verify `phrase` is this install's recovery phrase **without** changing
    /// state. Used when creating a vault — whose content key is also wrapped
    /// under the master recovery phrase — so we never seal under a phrase the
    /// user can't reproduce. Returns false for typos, the wrong phrase, or when
    /// there's no recovery envelope.
    func verifyRecoveryPhrase(_ phrase: String) -> Bool {
        guard hasRecoveryEnvelope,
              (try? RecoveryKey.entropy(from: phrase)) != nil,
              let env = try? loadRecoveryEnvelope(),
              let kek = try? RecoveryKey.deriveKEK(phrase: phrase, salt: env.salt, iterations: env.iterations),
              (try? Crypto.decrypt(env.wrappedDEK, using: kek)) != nil
        else { return false }
        return true
    }

    // MARK: - Recovery envelope helpers

    /// Generate a fresh 24-word phrase, wrap the supplied DEK, persist the
    /// envelope atomically. Returns the words for the UX to show. **Never**
    /// logs or stores the phrase outside the returned value.
    private func writeRecoveryEnvelope(for dek: SymmetricKey) throws -> [String] {
        let words = RecoveryKey.generate()
        let phrase = RecoveryKey.format(words)
        let salt = Crypto.randomBytes(Self.saltLength)
        let kek = try RecoveryKey.deriveKEK(phrase: phrase, salt: salt, iterations: Self.kdfIterations)
        let wrapped = try Crypto.encrypt(dek.rawData, using: kek)
        let env = RecoveryEnvelope(salt: salt, iterations: Self.kdfIterations, wrappedDEK: wrapped)
        let data = try JSONEncoder().encode(env)
        try data.write(to: recoveryFileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recoveryFileURL.path)
        return words
    }

    private func loadRecoveryEnvelope() throws -> RecoveryEnvelope {
        let data = try Data(contentsOf: recoveryFileURL)
        return try JSONDecoder().decode(RecoveryEnvelope.self, from: data)
    }

    // MARK: - Unlock / lock

    /// Derive KEK from `passphrase`, unwrap DEK, store in memory. Throws
    /// `.passphraseMismatch` on wrong passphrase (AES-GCM tag check fails).
    func unlock(passphrase: String) throws {
        let env = try loadEnvelope()
        let kek = try Crypto.deriveKey(passphrase: passphrase, salt: env.salt, iterations: env.iterations)
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
    /// when a passphrase is set — without one there's nothing to re-prompt for,
    /// so `lock()` is a no-op and returns false in Keychain-managed mode.
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
    func addPassphrase(_ passphrase: String) throws {
        guard let dek else { throw KeyStoreError.locked }
        guard !hasPassphrase else { throw KeyStoreError.alreadySetup }
        let salt = Crypto.randomBytes(Self.saltLength)
        let kek = try Crypto.deriveKey(passphrase: passphrase, salt: salt, iterations: Self.kdfIterations)
        let wrapped = try Crypto.encrypt(dek.rawData, using: kek)
        try persist(Envelope(salt: salt, iterations: Self.kdfIterations, wrappedDEK: wrapped))
        self.hasPassphrase = true
    }

    /// Swap the wrapping passphrase without touching the DEK (no user data
    /// re-encryption). Requires unlocked + a passphrase already set.
    func changePassphrase(oldPassphrase: String, newPassphrase: String) throws {
        guard hasPassphrase else { throw KeyStoreError.noPassphraseSet }
        let env = try loadEnvelope()
        let oldKEK = try Crypto.deriveKey(passphrase: oldPassphrase, salt: env.salt, iterations: env.iterations)
        let verified: Data
        do {
            verified = try Crypto.decrypt(env.wrappedDEK, using: oldKEK)
        } catch {
            throw KeyStoreError.passphraseMismatch
        }
        let dekKey = SymmetricKey(data: verified)
        let newSalt = Crypto.randomBytes(Self.saltLength)
        let newKEK = try Crypto.deriveKey(passphrase: newPassphrase, salt: newSalt, iterations: Self.kdfIterations)
        let newWrapped = try Crypto.encrypt(dekKey.rawData, using: newKEK)
        try persist(Envelope(salt: newSalt, iterations: Self.kdfIterations, wrappedDEK: newWrapped))
        self.dek = dekKey
        self.state = .unlocked
        self.hasPassphrase = true
        cacheDEKInKeychain()
    }

    /// Remove the passphrase wrapping, falling back to Keychain-managed mode.
    /// Verifies the current passphrase first. Requires unlocked.
    func removePassphrase(currentPassphrase: String) throws {
        guard hasPassphrase else { throw KeyStoreError.noPassphraseSet }
        guard let dek else { throw KeyStoreError.locked }
        let env = try loadEnvelope()
        let kek = try Crypto.deriveKey(passphrase: currentPassphrase, salt: env.salt, iterations: env.iterations)
        let verified: Data
        do {
            verified = try Crypto.decrypt(env.wrappedDEK, using: kek)
        } catch {
            throw KeyStoreError.passphraseMismatch
        }
        guard verified == dek.rawData else { throw KeyStoreError.corrupt }
        try FileManager.default.removeItem(at: fileURL)
        self.hasPassphrase = false
        // DEK stays in memory + Keychain — the install keeps opening silently.
    }

    /// Obliterate the keystore + all Keychain items so the user can start from
    /// scratch (forgot passphrase + lost recovery key, accepts data loss). Any
    /// encrypted files on disk become unreadable after this — callers delete
    /// those separately. Also clears the ever-booted marker so the next launch
    /// is treated as fresh rather than bouncing back into recovery.
    func resetAndWipe() {
        dek = nil
        state = .notSetup
        hasPassphrase = false
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: recoveryFileURL)
        try? FileManager.default.removeItem(at: BootState.markerURL(in: supportDirectory))
        KeychainStore.deleteAll()
    }

    /// Test-only escape hatch to override `state`/`dek` so a test can exercise
    /// the "looks like first launch even though the Keychain entry exists"
    /// scenario `setupKeychainManaged` guards against.
    func test_forceState(_ newState: UnlockState) {
        state = newState
        if newState != .unlocked { dek = nil }
    }

    // MARK: - Encrypt / decrypt passthroughs

    func encrypt(_ plaintext: Data) throws -> Data {
        guard let dek else { throw KeyStoreError.locked }
        return try Crypto.encrypt(plaintext, using: dek)
    }

    func decrypt(_ ciphertext: Data) throws -> Data {
        guard let dek else { throw KeyStoreError.locked }
        return try Crypto.decrypt(ciphertext, using: dek)
    }

    var isUnlocked: Bool { state == .unlocked }

    /// The current DEK. `SymmetricKey` is `Sendable`, so this is safe to ferry
    /// across isolation boundaries (SQLCipher needs it on GRDB's queues).
    var currentKey: SymmetricKey? { dek }

    // MARK: - Disk / keychain

    private func persist(_ env: Envelope) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(env)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func loadEnvelope() throws -> Envelope {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw KeyStoreError.notSetup
        }
        let data = try Data(contentsOf: fileURL)
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw KeyStoreError.corrupt
        }
        return env
    }

    private func cacheDEKInKeychain() {
        guard let dek else { return }
        try? KeychainStore.setData(dek.rawData, for: keychainDEKAccount)
    }
}
