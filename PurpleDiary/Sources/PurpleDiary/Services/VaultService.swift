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
    static func seal(_ text: String, key: SymmetricKey) -> String {
        guard let ct = try? Crypto.encrypt(Data(text.utf8), using: key) else { return text }
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

    // MARK: - Persistence

    static func saveEnvelope(_ env: VaultEnvelope) throws {
        try DatabaseService.shared.saveVaultEnvelope(env)
    }
    static func loadEnvelope(journalId: String) throws -> VaultEnvelope? {
        try DatabaseService.shared.vaultEnvelope(journalId: journalId)
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
