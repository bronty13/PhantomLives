import Foundation
import CryptoKit
import GRDB

/// Per-journal cryptographic vault (Phase 9). A vault journal's text is sealed
/// under a random 256-bit **content key (CK)** that is itself wrapped two ways
/// and stored in `vault_envelopes`:
///
/// 1. under a **passphrase-derived KEK** (PBKDF2-HMAC-SHA256 → AES-256-GCM), and
/// 2. under a **24-word-recovery-key-derived KEK**, so a lost passphrase isn't a
///    permanent lockout.
///
/// The CK lives in memory only while the journal is unlocked for the session, so
/// the text is ciphertext even when the database (SQLCipher) is open. This file
/// is the verified cryptographic core; the transparent-sealing data path and the
/// create/unlock UI are wired on top of it.
struct VaultEnvelope: Codable, FetchableRecord, MutablePersistableRecord {
    var journalId: String
    var passSalt: Data
    var passIters: Int
    var passWrap: Data
    var recoverySalt: Data
    var recoveryIters: Int
    var recoveryWrap: Data

    static let databaseTableName = "vault_envelopes"
    enum CodingKeys: String, CodingKey {
        case journalId = "journal_id"
        case passSalt = "pass_salt"
        case passIters = "pass_iters"
        case passWrap = "pass_wrap"
        case recoverySalt = "recovery_salt"
        case recoveryIters = "recovery_iters"
        case recoveryWrap = "recovery_wrap"
    }
}

@MainActor
enum VaultService {

    static let iterations = 300_000
    /// Sentinel prefixing sealed text in the DB, so reads can tell sealed from
    /// plaintext (e.g. a journal that isn't a vault, or pre-seal rows).
    static let sentinel = "pdvlt1:"

    enum VaultError: Error, LocalizedError {
        /// A dual-wrap failed to round-trip back to the content key before any
        /// entry was sealed — we refuse to create a vault we couldn't reopen.
        case wrapVerificationFailed
        /// An operation needs the vault unlocked (content key in the session).
        case locked
        /// No envelope on disk for this journal.
        case noEnvelope
        /// Encrypting content for a vault failed. We refuse to fall back to
        /// writing the plaintext into the vault — the caller must abort the write.
        case sealFailed
        var errorDescription: String? {
            switch self {
            case .wrapVerificationFailed:
                return "Could not verify the vault key wraps. The vault was not created and nothing was sealed."
            case .locked:
                return "The vault is locked. Unlock it first."
            case .noEnvelope:
                return "This journal has no vault envelope."
            case .sealFailed:
                return "Could not encrypt content for the vault. Nothing was written."
            }
        }
    }

    // MARK: - Session keys (in-memory only; cleared on relaunch / app-lock)

    private static var sessionKeys: [String: SymmetricKey] = [:]

    static func key(for journalId: String) -> SymmetricKey? { sessionKeys[journalId] }
    static func isUnlocked(_ journalId: String) -> Bool { sessionKeys[journalId] != nil }
    static func lock(_ journalId: String) { sessionKeys[journalId] = nil }
    static func lockAll() { sessionKeys.removeAll() }

    // MARK: - Pure crypto core (no DB; the unit of testable behavior)

    /// Generate a fresh content key and wrap it under both a passphrase and a
    /// 24-word recovery phrase, producing the envelope to persist.
    static func makeEnvelope(journalId: String, passphrase: String, recoveryWords: [String]) throws -> (key: SymmetricKey, envelope: VaultEnvelope) {
        let ck = SymmetricKey(size: .bits256)
        let ckData = ck.withUnsafeBytes { Data($0) }

        let passSalt = Crypto.randomBytes(16)
        let passKEK = try Crypto.deriveKey(passphrase: passphrase, salt: passSalt, iterations: iterations)
        let passWrap = try Crypto.encrypt(ckData, using: passKEK)

        let recSalt = Crypto.randomBytes(16)
        let recKEK = try RecoveryKey.deriveKEK(phrase: RecoveryKey.format(recoveryWords),
                                               salt: recSalt, iterations: iterations)
        let recWrap = try Crypto.encrypt(ckData, using: recKEK)

        let env = VaultEnvelope(journalId: journalId,
                                passSalt: passSalt, passIters: iterations, passWrap: passWrap,
                                recoverySalt: recSalt, recoveryIters: iterations, recoveryWrap: recWrap)
        return (ck, env)
    }

    /// Recover the content key from the envelope with the passphrase, or nil if
    /// it's wrong.
    static func unwrap(_ env: VaultEnvelope, passphrase: String) -> SymmetricKey? {
        guard let kek = try? Crypto.deriveKey(passphrase: passphrase, salt: env.passSalt, iterations: env.passIters),
              let ckData = try? Crypto.decrypt(env.passWrap, using: kek) else { return nil }
        return SymmetricKey(data: ckData)
    }

    /// Recover the content key from the envelope with the 24-word recovery key.
    static func unwrap(_ env: VaultEnvelope, recoveryWords: [String]) -> SymmetricKey? {
        guard RecoveryKey.isValid(RecoveryKey.format(recoveryWords)),
              let kek = try? RecoveryKey.deriveKEK(phrase: RecoveryKey.format(recoveryWords),
                                                   salt: env.recoverySalt, iterations: env.recoveryIters),
              let ckData = try? Crypto.decrypt(env.recoveryWrap, using: kek) else { return nil }
        return SymmetricKey(data: ckData)
    }

    /// Seal a string under the content key → `pdvlt1:<base64(AES-GCM)>`.
    /// Throws `VaultError.sealFailed` rather than silently returning the
    /// plaintext if encryption fails — a vault must never persist cleartext.
    static func seal(_ text: String, key: SymmetricKey) throws -> String {
        guard let ct = try? Crypto.encrypt(Data(text.utf8), using: key) else { throw VaultError.sealFailed }
        return sentinel + ct.base64EncodedString()
    }

    /// Unseal a `pdvlt1:` string under the content key, or nil if it's not sealed
    /// / the key is wrong. Non-sentinel input is returned unchanged (plaintext).
    static func unseal(_ text: String, key: SymmetricKey) -> String? {
        guard text.hasPrefix(sentinel) else { return text }
        let b64 = String(text.dropFirst(sentinel.count))
        guard let ct = Data(base64Encoded: b64),
              let pt = try? Crypto.decrypt(ct, using: key),
              let s = String(data: pt, encoding: .utf8) else { return nil }
        return s
    }

    static func isSealed(_ text: String) -> Bool { text.hasPrefix(sentinel) }

    /// Raw-bytes form of `sentinel`, prefixing sealed BLOBs (attachment `data` /
    /// `thumbnail_data`). Real media never begins with these bytes (JPEG/PNG/MP4/
    /// PDF magic numbers differ), so a prefix match reliably means "sealed".
    static let dataSentinel = Data(sentinel.utf8)

    /// Seal arbitrary bytes under the content key → `pdvlt1:` + AES-GCM blob.
    /// Throws `VaultError.sealFailed` rather than silently returning the
    /// plaintext bytes if encryption fails — a vault must never persist cleartext.
    static func sealData(_ data: Data, key: SymmetricKey) throws -> Data {
        guard let ct = try? Crypto.encrypt(data, using: key) else { throw VaultError.sealFailed }
        return dataSentinel + ct
    }

    /// Unseal a `pdvlt1:`-prefixed blob, or nil if the key is wrong. Non-sentinel
    /// input is returned unchanged (plaintext bytes).
    static func unsealData(_ data: Data, key: SymmetricKey) -> Data? {
        guard data.starts(with: dataSentinel) else { return data }
        let ct = Data(data.dropFirst(dataSentinel.count))
        return try? Crypto.decrypt(ct, using: key)
    }

    static func isSealedData(_ data: Data) -> Bool { data.starts(with: dataSentinel) }

    // MARK: - Persistence

    static func saveEnvelope(_ env: VaultEnvelope) throws {
        try DatabaseService.shared.saveVaultEnvelope(env)
    }
    static func loadEnvelope(journalId: String) throws -> VaultEnvelope? {
        try DatabaseService.shared.vaultEnvelope(journalId: journalId)
    }

    /// Create a vault for `journalId`: mint a content key, dual-wrap it
    /// (passphrase + recovery), **verify both wraps round-trip back to the same
    /// key before anything is persisted** (the all-or-nothing guardrail — a
    /// vault entry must be openable by passphrase *or* recovery before any
    /// encrypting write commits), save the envelope, and hold the key in the
    /// session. Returns the content key so the caller can seal existing entries.
    @discardableResult
    static func createVault(journalId: String, passphrase: String, recoveryWords: [String]) throws -> SymmetricKey {
        let (ck, env) = try makeEnvelope(journalId: journalId, passphrase: passphrase, recoveryWords: recoveryWords)
        let ckRaw = ck.withUnsafeBytes { Data($0) }
        guard let viaPass = unwrap(env, passphrase: passphrase),
              viaPass.withUnsafeBytes({ Data($0) }) == ckRaw,
              let viaRec = unwrap(env, recoveryWords: recoveryWords),
              viaRec.withUnsafeBytes({ Data($0) }) == ckRaw
        else { throw VaultError.wrapVerificationFailed }
        try saveEnvelope(env)
        sessionKeys[journalId] = ck
        return ck
    }

    /// Re-wrap the content key under a new passphrase, keeping the recovery wrap
    /// intact. Requires the vault to be unlocked (content key in the session).
    static func changePassphrase(journalId: String, newPassphrase: String) throws {
        guard let ck = sessionKeys[journalId] else { throw VaultError.locked }
        guard var env = (try? loadEnvelope(journalId: journalId)) ?? nil else { throw VaultError.noEnvelope }
        let ckData = ck.withUnsafeBytes { Data($0) }
        let salt = Crypto.randomBytes(16)
        let kek = try Crypto.deriveKey(passphrase: newPassphrase, salt: salt, iterations: iterations)
        env.passSalt = salt
        env.passIters = iterations
        env.passWrap = try Crypto.encrypt(ckData, using: kek)
        try saveEnvelope(env)
    }

    /// Unlock a vault for the session via passphrase; true on success.
    @discardableResult
    static func unlock(journalId: String, passphrase: String) -> Bool {
        guard let env = (try? loadEnvelope(journalId: journalId)) ?? nil,
              let ck = unwrap(env, passphrase: passphrase) else { return false }
        sessionKeys[journalId] = ck
        return true
    }

    /// Unlock a vault for the session via the 24-word recovery key; true on success.
    @discardableResult
    static func unlock(journalId: String, recoveryWords: [String]) -> Bool {
        guard let env = (try? loadEnvelope(journalId: journalId)) ?? nil,
              let ck = unwrap(env, recoveryWords: recoveryWords) else { return false }
        sessionKeys[journalId] = ck
        return true
    }
}
