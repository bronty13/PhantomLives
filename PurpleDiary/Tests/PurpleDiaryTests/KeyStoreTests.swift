import XCTest
import CryptoKit
@testable import PurpleDiary

@MainActor
final class KeyStoreTests: XCTestCase {

    /// A fresh, isolated support directory per test so keystore.json /
    /// recovery_envelope.json / the path-derived Keychain account never collide
    /// with another test or the user's real install.
    private func freshDir() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pd-keystore-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    override func tearDown() {
        // Wipe the per-pid test Keychain service so cached DEKs don't leak
        // between test methods.
        KeychainStore.deleteAll()
        super.tearDown()
    }

    func testSetupKeychainManagedGeneratesKeyAndRecoveryPhrase() throws {
        let ks = KeyStore(supportDirectoryURL: freshDir())
        XCTAssertEqual(ks.state, .notSetup)
        let phrase = try ks.setupKeychainManaged()
        XCTAssertEqual(phrase.count, 24)
        XCTAssertTrue(ks.isUnlocked)
        XCTAssertNotNil(ks.currentKey)
        XCTAssertTrue(ks.hasRecoveryEnvelope)
        XCTAssertFalse(ks.hasPassphrase)
    }

    func testPassphraseUnlockRoundTripAndWrongPassphraseFails() throws {
        let dir = freshDir()
        let ks = KeyStore(supportDirectoryURL: dir)
        _ = try ks.setupWithPassphrase("correct horse")
        XCTAssertTrue(ks.hasPassphrase)
        let dek = ks.currentKey?.rawData
        XCTAssertNotNil(dek)

        // Drop the Keychain cache so the next instance must use the passphrase.
        KeychainStore.deleteAll()
        let ks2 = KeyStore(supportDirectoryURL: dir)
        XCTAssertEqual(ks2.state, .locked)
        XCTAssertThrowsError(try ks2.unlock(passphrase: "wrong")) { err in
            XCTAssertEqual(err as? KeyStore.KeyStoreError, .passphraseMismatch)
        }
        try ks2.unlock(passphrase: "correct horse")
        XCTAssertEqual(ks2.currentKey?.rawData, dek, "unlock must recover the same DEK")
    }

    func testRecoveryKeyUnlockRecoversSameDEK() throws {
        let dir = freshDir()
        let ks = KeyStore(supportDirectoryURL: dir)
        let phrase = try ks.setupKeychainManaged()
        let dek = ks.currentKey?.rawData
        XCTAssertNotNil(dek)

        // Simulate a total Keychain loss; only the recovery envelope remains.
        KeychainStore.deleteAll()
        let ks2 = KeyStore(supportDirectoryURL: dir)
        XCTAssertEqual(ks2.state, .locked)
        try ks2.unlockWithRecoveryKey(phrase: RecoveryKey.format(phrase))
        XCTAssertEqual(ks2.currentKey?.rawData, dek, "recovery key must recover the same DEK")
    }

    func testWrongRecoveryKeyThrows() throws {
        let dir = freshDir()
        let ks = KeyStore(supportDirectoryURL: dir)
        _ = try ks.setupKeychainManaged()
        KeychainStore.deleteAll()
        let ks2 = KeyStore(supportDirectoryURL: dir)
        // A different, checksum-valid phrase — decrypt must fail the GCM tag.
        let wrong = RecoveryKey.format(RecoveryKey.generate())
        XCTAssertThrowsError(try ks2.unlockWithRecoveryKey(phrase: wrong)) { err in
            XCTAssertEqual(err as? KeyStore.KeyStoreError, .passphraseMismatch)
        }
    }
}
