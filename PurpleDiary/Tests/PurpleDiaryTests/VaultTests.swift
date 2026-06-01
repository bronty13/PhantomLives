import XCTest
import CryptoKit
@testable import PurpleDiary

/// Phase-9 vault cryptographic core: dual-wrap envelope (passphrase + 24-word
/// recovery), seal/unseal round-trips, wrong-key rejection, and envelope
/// persistence. The transparent-sealing data path and UI are built on top of
/// this verified core.
@MainActor
final class VaultTests: XCTestCase {

    private let recovery = RecoveryKey.generate()   // a valid 24-word phrase

    func testEnvelopeUnwrapsWithPassphrase() throws {
        let (ck, env) = try VaultService.makeEnvelope(journalId: "J1", passphrase: "correct horse",
                                                      recoveryWords: recovery)
        let viaPass = try XCTUnwrap(VaultService.unwrap(env, passphrase: "correct horse"))
        XCTAssertEqual(ckData(viaPass), ckData(ck), "passphrase unwraps the same content key")
    }

    func testEnvelopeUnwrapsWithRecoveryKey() throws {
        let (ck, env) = try VaultService.makeEnvelope(journalId: "J1", passphrase: "pw",
                                                      recoveryWords: recovery)
        let viaRec = try XCTUnwrap(VaultService.unwrap(env, recoveryWords: recovery),
                                   "the 24-word key also recovers the content key")
        XCTAssertEqual(ckData(viaRec), ckData(ck))
    }

    func testWrongPassphraseAndWrongRecoveryFail() throws {
        let (_, env) = try VaultService.makeEnvelope(journalId: "J1", passphrase: "pw",
                                                     recoveryWords: recovery)
        XCTAssertNil(VaultService.unwrap(env, passphrase: "nope"))
        XCTAssertNil(VaultService.unwrap(env, recoveryWords: RecoveryKey.generate()))  // a different phrase
    }

    func testSealUnsealRoundTrip() throws {
        let (ck, _) = try VaultService.makeEnvelope(journalId: "J1", passphrase: "pw", recoveryWords: recovery)
        let secret = "Dear diary — today was *private*.\n\nWith newlines."
        let sealed = try VaultService.seal(secret, key: ck)
        XCTAssertTrue(VaultService.isSealed(sealed))
        XCTAssertFalse(sealed.contains("private"), "ciphertext doesn't expose the plaintext")
        XCTAssertEqual(VaultService.unseal(sealed, key: ck), secret)
    }

    func testUnsealWithWrongKeyFailsAndPlaintextPassesThrough() throws {
        let (ck, _) = try VaultService.makeEnvelope(journalId: "J1", passphrase: "pw", recoveryWords: recovery)
        let other = SymmetricKey(size: .bits256)
        let sealed = try VaultService.seal("secret", key: ck)
        XCTAssertNil(VaultService.unseal(sealed, key: other), "wrong key can't unseal")
        // Non-sentinel text is treated as plaintext and returned unchanged.
        XCTAssertEqual(VaultService.unseal("just plain text", key: ck), "just plain text")
    }

    func testEnvelopePersistenceRoundTrip() throws {
        // The journal must exist (FK) before storing its envelope.
        let j = Journal.newDraft(name: "Secret")
        try DatabaseService.shared.insertJournal(j)
        defer { try? DatabaseService.shared.deleteJournal(id: j.id, deleteEntries: true) }

        let (ck, env) = try VaultService.makeEnvelope(journalId: j.id, passphrase: "pw", recoveryWords: recovery)
        try VaultService.saveEnvelope(env)

        let loaded = try XCTUnwrap(VaultService.loadEnvelope(journalId: j.id))
        let viaPass = try XCTUnwrap(VaultService.unwrap(loaded, passphrase: "pw"))
        XCTAssertEqual(ckData(viaPass), ckData(ck), "envelope survives a DB round-trip")
    }

    func testSessionUnlockLockViaPassphrase() throws {
        let j = Journal.newDraft(name: "Vault J")
        try DatabaseService.shared.insertJournal(j)
        defer { try? DatabaseService.shared.deleteJournal(id: j.id, deleteEntries: true) }
        let (_, env) = try VaultService.makeEnvelope(journalId: j.id, passphrase: "open sesame", recoveryWords: recovery)
        try VaultService.saveEnvelope(env)

        XCTAssertFalse(VaultService.isUnlocked(j.id))
        XCTAssertFalse(VaultService.unlock(journalId: j.id, passphrase: "wrong"))
        XCTAssertTrue(VaultService.unlock(journalId: j.id, passphrase: "open sesame"))
        XCTAssertTrue(VaultService.isUnlocked(j.id))
        XCTAssertNotNil(VaultService.key(for: j.id))
        VaultService.lock(j.id)
        XCTAssertFalse(VaultService.isUnlocked(j.id))
    }

    private func ckData(_ k: SymmetricKey) -> Data { k.withUnsafeBytes { Data($0) } }
}
