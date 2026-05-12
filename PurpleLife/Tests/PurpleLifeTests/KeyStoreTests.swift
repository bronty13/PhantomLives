import XCTest
import CryptoKit
@testable import PurpleLife

@MainActor
final class KeyStoreTests: XCTestCase {

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("purplelife-keystore-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ store: KeyStore) {
        store.resetAndWipe()
    }

    // MARK: - Crypto primitives

    func test_aesGCMRoundtrip() throws {
        let key = SymmetricKey(size: .bits256)
        let plain = Data("hello purplelife".utf8)
        let cipher = try Crypto.encrypt(plain, using: key)
        XCTAssertNotEqual(cipher, plain)
        let back = try Crypto.decrypt(cipher, using: key)
        XCTAssertEqual(back, plain)
    }

    func test_aesGCMRejectsWrongKey() throws {
        let k1 = SymmetricKey(size: .bits256)
        let k2 = SymmetricKey(size: .bits256)
        let cipher = try Crypto.encrypt(Data("secret".utf8), using: k1)
        XCTAssertThrowsError(try Crypto.decrypt(cipher, using: k2))
    }

    func test_aesGCMDetectsTamper() throws {
        let key = SymmetricKey(size: .bits256)
        var cipher = try Crypto.encrypt(Data("payload".utf8), using: key)
        cipher[cipher.count - 1] ^= 0x01
        XCTAssertThrowsError(try Crypto.decrypt(cipher, using: key))
    }

    func test_pbkdf2ProducesStableKeyForSameInputs() throws {
        let salt = Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])
        // Low iteration count to keep the test fast — production uses 300_000.
        let a = try Crypto.deriveKey(passphrase: "hunter2", salt: salt, iterations: 1_000)
        let b = try Crypto.deriveKey(passphrase: "hunter2", salt: salt, iterations: 1_000)
        XCTAssertEqual(a.rawData, b.rawData)
    }

    func test_pbkdf2DiffersWhenPassphraseChanges() throws {
        let salt = Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])
        let a = try Crypto.deriveKey(passphrase: "hunter2",  salt: salt, iterations: 1_000)
        let b = try Crypto.deriveKey(passphrase: "hunter22", salt: salt, iterations: 1_000)
        XCTAssertNotEqual(a.rawData, b.rawData)
    }

    func test_randomBytesAreActuallyRandom() {
        let a = Crypto.randomBytes(32)
        let b = Crypto.randomBytes(32)
        XCTAssertEqual(a.count, 32)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - EncryptedJSON envelope

    func test_envelopeMagicRoundtrip() throws {
        let key = SymmetricKey(size: .bits256)
        let plain = Data("the body of a note".utf8)
        let wrapped = try EncryptedJSON.wrap(plain, key: key)
        XCTAssertTrue(EncryptedJSON.hasMagic(wrapped))
        XCTAssertFalse(EncryptedJSON.hasMagic(plain))
        let unwrapped = try EncryptedJSON.unwrap(wrapped, key: key)
        XCTAssertEqual(unwrapped, plain)
    }

    func test_envelopePlaintextPassthroughWhenKeyIsNil() throws {
        let plain = Data("{\"foo\":\"bar\"}".utf8)
        let written = try EncryptedJSON.wrap(plain, key: nil)
        XCTAssertEqual(written, plain) // no magic added
        let read = try EncryptedJSON.unwrap(plain, key: nil)
        XCTAssertEqual(read, plain) // passes through unchanged
    }

    func test_envelopeUnwrapEncryptedWithNilKeyThrows() throws {
        let key = SymmetricKey(size: .bits256)
        let wrapped = try EncryptedJSON.wrap(Data("secret".utf8), key: key)
        XCTAssertThrowsError(try EncryptedJSON.unwrap(wrapped, key: nil)) { error in
            guard case EncryptedJSON.EnvelopeError.lockedButEncrypted = error else {
                return XCTFail("expected lockedButEncrypted, got \(error)")
            }
        }
    }

    func test_envelopeSafeWriteRefusesToDowngrade() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("test.json")
        let key = SymmetricKey(size: .bits256)
        // First write is encrypted.
        _ = try EncryptedJSON.safeWrite(Data("v1".utf8), to: url, key: key)
        // Subsequent write with key == nil must refuse — never silently
        // downgrade ciphertext to plaintext.
        let result = try EncryptedJSON.safeWrite(Data("v2".utf8), to: url, key: nil)
        XCTAssertEqual(result, .skippedLockedEncrypted)
        // Original ciphertext is intact.
        let onDisk = try Data(contentsOf: url)
        XCTAssertTrue(EncryptedJSON.hasMagic(onDisk))
        XCTAssertEqual(try EncryptedJSON.unwrap(onDisk, key: key), Data("v1".utf8))
    }

    // MARK: - KeyStore lifecycle: passphrase-protected mode

    func test_setupWithPassphraseThenEncryptRoundtrip() throws {
        let store = KeyStore(supportDirectoryURL: tempDir())
        defer { cleanup(store) }
        XCTAssertEqual(store.state, .notSetup)
        try store.setupWithPassphrase("correct horse battery staple")
        XCTAssertEqual(store.state, .unlocked)
        XCTAssertTrue(store.hasPassphrase)
        let plain = Data("note body".utf8)
        let cipher = try store.encrypt(plain)
        XCTAssertNotEqual(cipher, plain)
        XCTAssertEqual(try store.decrypt(cipher), plain)
    }

    func test_unlockFromDiskWithRightPassphrase() throws {
        let dir = tempDir()
        let cipher: Data
        // Inner scope: no cleanup here — that would wipe keystore.json
        // before the second instance below has a chance to load it.
        do {
            let store = KeyStore(supportDirectoryURL: dir)
            try store.setupWithPassphrase("pw")
            cipher = try store.encrypt(Data("persisted".utf8))
            XCTAssertTrue(store.lock())
        }
        // Fresh instance against the same directory — must unlock and
        // decrypt the cipher produced above.
        let store2 = KeyStore(supportDirectoryURL: dir)
        defer { cleanup(store2) }
        if store2.state == .locked {
            try store2.unlock(passphrase: "pw")
        }
        XCTAssertTrue(store2.isUnlocked)
        XCTAssertEqual(try store2.decrypt(cipher), Data("persisted".utf8))
    }

    func test_unlockRejectsWrongPassphrase() throws {
        let store = KeyStore(supportDirectoryURL: tempDir())
        defer { cleanup(store) }
        try store.setupWithPassphrase("right")
        _ = store.lock()
        XCTAssertThrowsError(try store.unlock(passphrase: "wrong")) { error in
            guard case KeyStore.KeyStoreError.passphraseMismatch = error else {
                return XCTFail("expected passphraseMismatch, got \(error)")
            }
        }
    }

    func test_changePassphraseKeepsDataReadable() throws {
        let store = KeyStore(supportDirectoryURL: tempDir())
        defer { cleanup(store) }
        try store.setupWithPassphrase("old")
        let cipher = try store.encrypt(Data("preserved".utf8))
        try store.changePassphrase(oldPassphrase: "old", newPassphrase: "new")
        // Same DEK — no re-encrypt needed.
        XCTAssertEqual(try store.decrypt(cipher), Data("preserved".utf8))
        _ = store.lock()
        XCTAssertThrowsError(try store.unlock(passphrase: "old"))
        try store.unlock(passphrase: "new")
        XCTAssertEqual(try store.decrypt(cipher), Data("preserved".utf8))
    }

    func test_encryptWhileLockedThrows() throws {
        let store = KeyStore(supportDirectoryURL: tempDir())
        defer { cleanup(store) }
        try store.setupWithPassphrase("pw")
        _ = store.lock()
        XCTAssertThrowsError(try store.encrypt(Data())) { error in
            guard case KeyStore.KeyStoreError.locked = error else {
                return XCTFail("expected .locked, got \(error)")
            }
        }
    }

    // MARK: - KeyStore lifecycle: Keychain-managed mode

    func test_setupKeychainManagedOpensSilentlyOnReopen() throws {
        let dir = tempDir()
        let cipher: Data
        do {
            let store = KeyStore(supportDirectoryURL: dir)
            try store.setupKeychainManaged()
            XCTAssertEqual(store.state, .unlocked)
            XCTAssertFalse(store.hasPassphrase)
            cipher = try store.encrypt(Data("kc-only".utf8))
        }
        // No keystore.json on disk, but the Keychain still has the DEK.
        let store2 = KeyStore(supportDirectoryURL: dir)
        defer { cleanup(store2) }
        XCTAssertEqual(store2.state, .unlocked)
        XCTAssertFalse(store2.hasPassphrase)
        XCTAssertEqual(try store2.decrypt(cipher), Data("kc-only".utf8))
    }

    func test_keychainManagedLockIsNoOp() throws {
        let store = KeyStore(supportDirectoryURL: tempDir())
        defer { cleanup(store) }
        try store.setupKeychainManaged()
        XCTAssertFalse(store.lock())   // refuses — no passphrase to unlock with
        XCTAssertEqual(store.state, .unlocked)
    }

    func test_addPassphraseLayersOntoKeychainManaged() throws {
        let dir = tempDir()
        let store = KeyStore(supportDirectoryURL: dir)
        defer { cleanup(store) }
        try store.setupKeychainManaged()
        let cipher = try store.encrypt(Data("upgraded".utf8))
        try store.addPassphrase("new-pw")
        XCTAssertTrue(store.hasPassphrase)
        // Same DEK still in memory — ciphertext from before still works.
        XCTAssertEqual(try store.decrypt(cipher), Data("upgraded".utf8))
        // Now lock() is meaningful, and re-unlock requires the passphrase.
        XCTAssertTrue(store.lock())
        XCTAssertEqual(store.state, .locked)
        try store.unlock(passphrase: "new-pw")
        XCTAssertEqual(try store.decrypt(cipher), Data("upgraded".utf8))
    }

    func test_addPassphraseRefusesWhenAlreadySet() throws {
        let store = KeyStore(supportDirectoryURL: tempDir())
        defer { cleanup(store) }
        try store.setupWithPassphrase("first")
        XCTAssertThrowsError(try store.addPassphrase("second")) { error in
            guard case KeyStore.KeyStoreError.alreadySetup = error else {
                return XCTFail("expected .alreadySetup, got \(error)")
            }
        }
    }

    func test_removePassphraseFallsBackToKeychainManaged() throws {
        let store = KeyStore(supportDirectoryURL: tempDir())
        defer { cleanup(store) }
        try store.setupWithPassphrase("pw")
        let cipher = try store.encrypt(Data("preserved".utf8))
        try store.removePassphrase(currentPassphrase: "pw")
        XCTAssertFalse(store.hasPassphrase)
        XCTAssertEqual(store.state, .unlocked)
        XCTAssertEqual(try store.decrypt(cipher), Data("preserved".utf8))
        // lock() is once again a no-op.
        XCTAssertFalse(store.lock())
    }

    func test_removePassphraseRejectsWrongCurrent() throws {
        let store = KeyStore(supportDirectoryURL: tempDir())
        defer { cleanup(store) }
        try store.setupWithPassphrase("right")
        XCTAssertThrowsError(try store.removePassphrase(currentPassphrase: "wrong")) { error in
            guard case KeyStore.KeyStoreError.passphraseMismatch = error else {
                return XCTFail("expected passphraseMismatch, got \(error)")
            }
        }
        XCTAssertTrue(store.hasPassphrase) // still protected
    }

    func test_resetAndWipeClearsEverything() throws {
        let dir = tempDir()
        let store = KeyStore(supportDirectoryURL: dir)
        try store.setupWithPassphrase("pw")
        store.resetAndWipe()
        XCTAssertEqual(store.state, .notSetup)
        XCTAssertFalse(store.hasPassphrase)
        // Fresh instance against the same dir sees nothing.
        let fresh = KeyStore(supportDirectoryURL: dir)
        XCTAssertEqual(fresh.state, .notSetup)
        XCTAssertFalse(fresh.hasPassphrase)
    }
}
