import Foundation
import CryptoKit
import Testing
@testable import PurpleIRC

@Suite("Crypto + KeyStore")
@MainActor
struct KeyStoreTests {

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("purpleirc-keystore-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Crypto primitives

    @Test func aesGCMRoundtrip() throws {
        let key = SymmetricKey(size: .bits256)
        let plain = Data("hello irc".utf8)
        let cipher = try Crypto.encrypt(plain, using: key)
        #expect(cipher != plain)
        let back = try Crypto.decrypt(cipher, using: key)
        #expect(back == plain)
    }

    @Test func aesGCMRejectsWrongKey() throws {
        let k1 = SymmetricKey(size: .bits256)
        let k2 = SymmetricKey(size: .bits256)
        let plain = Data("secret".utf8)
        let cipher = try Crypto.encrypt(plain, using: k1)
        #expect(throws: (any Error).self) {
            _ = try Crypto.decrypt(cipher, using: k2)
        }
    }

    @Test func aesGCMDetectsTamper() throws {
        let key = SymmetricKey(size: .bits256)
        var cipher = try Crypto.encrypt(Data("payload".utf8), using: key)
        // Flip a byte near the end (inside the auth tag or ciphertext).
        cipher[cipher.count - 1] ^= 0x01
        #expect(throws: (any Error).self) {
            _ = try Crypto.decrypt(cipher, using: key)
        }
    }

    @Test func pbkdf2ProducesStableKeyForSameInputs() throws {
        let salt = Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])
        // Low iteration count keeps the test fast — the production default
        // is 300_000 and lives in KeyStore, not here.
        let a = try Crypto.deriveKey(passphrase: "hunter2", salt: salt, iterations: 1_000)
        let b = try Crypto.deriveKey(passphrase: "hunter2", salt: salt, iterations: 1_000)
        #expect(a.rawData == b.rawData)
    }

    @Test func pbkdf2DiffersWhenPassphraseChanges() throws {
        let salt = Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])
        let a = try Crypto.deriveKey(passphrase: "hunter2",  salt: salt, iterations: 1_000)
        let b = try Crypto.deriveKey(passphrase: "hunter22", salt: salt, iterations: 1_000)
        #expect(a.rawData != b.rawData)
    }

    @Test func randomBytesAreActuallyRandom() {
        let a = Crypto.randomBytes(32)
        let b = Crypto.randomBytes(32)
        #expect(a.count == 32)
        #expect(a != b)
    }

    // MARK: - KeyStore lifecycle

    @Test func setupThenEncryptRoundtrip() throws {
        let store = KeyStore(supportDirectoryURL: tempDir())
        #expect(store.state == .notSetup)
        try store.setup(passphrase: "correct horse battery staple")
        #expect(store.state == .unlocked)
        let plain = Data("the topic is #swift".utf8)
        let cipher = try store.encrypt(plain)
        #expect(cipher != plain)
        #expect(try store.decrypt(cipher) == plain)
    }

    @Test func unlockFromDiskWithRightPassphrase() throws {
        let dir = tempDir()
        let plain = Data("persisted".utf8)
        var cipher = Data()
        do {
            let store = KeyStore(supportDirectoryURL: dir)
            try store.setup(passphrase: "pw")
            cipher = try store.encrypt(plain)
            store.lock()
        }
        // Fresh instance against the same directory — must unlock and
        // decrypt the cipher produced above.
        let store2 = KeyStore(supportDirectoryURL: dir)
        #expect(store2.state == .locked || store2.state == .unlocked)
        if store2.state == .locked {
            try store2.unlock(passphrase: "pw")
        }
        #expect(store2.isUnlocked)
        #expect(try store2.decrypt(cipher) == plain)
    }

    @Test func unlockRejectsWrongPassphrase() throws {
        let dir = tempDir()
        let store = KeyStore(supportDirectoryURL: dir)
        try store.setup(passphrase: "right")
        store.lock()
        #expect(throws: KeyStore.KeyStoreError.passphraseMismatch) {
            try store.unlock(passphrase: "wrong")
        }
    }

    @Test func changePassphraseKeepsDataReadable() throws {
        let dir = tempDir()
        let store = KeyStore(supportDirectoryURL: dir)
        try store.setup(passphrase: "old")
        let cipher = try store.encrypt(Data("preserved".utf8))
        try store.changePassphrase(oldPassphrase: "old", newPassphrase: "new")
        // Still unlocked with the same DEK — no re-encrypt needed.
        #expect(try store.decrypt(cipher) == Data("preserved".utf8))
        // Lock + unlock with the new passphrase.
        store.lock()
        #expect(throws: KeyStore.KeyStoreError.passphraseMismatch) {
            try store.unlock(passphrase: "old")
        }
        try store.unlock(passphrase: "new")
        #expect(try store.decrypt(cipher) == Data("preserved".utf8))
    }

    @Test func encryptWhileLockedThrows() throws {
        let store = KeyStore(supportDirectoryURL: tempDir())
        try store.setup(passphrase: "pw")
        store.lock()
        #expect(throws: KeyStore.KeyStoreError.locked) {
            _ = try store.encrypt(Data())
        }
    }

    // MARK: - CredentialRef

    @Test func credentialRefRoundtrip() {
        #expect(CredentialRef.isReference("kc:abc") == true)
        #expect(CredentialRef.isReference("plaintext") == false)
        #expect(CredentialRef.account(in: "kc:abc") == "abc")
        #expect(CredentialRef.account(in: "hunter2") == nil)
        #expect(CredentialRef.makeReference(for: "xyz") == "kc:xyz")
    }
}
