import Foundation
import CryptoKit
import Testing
@testable import PurpleIRC

/// Cover the `EncryptedJSON` envelope — the wrap/unwrap round-trip, the
/// plaintext passthrough, the refuse-to-clobber `safeWrite` guard, and the
/// 0600 perms it sets. This path seals every persistent store, so a
/// regression here is a confidentiality / data-loss risk.
@Suite("EncryptedJSON")
struct EncryptedJSONTests {

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("EncJSONTests-\(UUID().uuidString).bin")
    }

    @Test func plaintextPassthroughWhenNoKey() throws {
        let plain = Data("{\"a\":1}".utf8)
        let wrapped = try EncryptedJSON.wrap(plain, key: nil)
        #expect(wrapped == plain)                       // no magic, unchanged
        #expect(!EncryptedJSON.hasMagic(wrapped))
        #expect(try EncryptedJSON.unwrap(wrapped, key: nil) == plain)
    }

    @Test func encryptedRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let plain = Data("the quick brown fox".utf8)
        let wrapped = try EncryptedJSON.wrap(plain, key: key)
        #expect(EncryptedJSON.hasMagic(wrapped))
        #expect(wrapped != plain)
        #expect(try EncryptedJSON.unwrap(wrapped, key: key) == plain)
    }

    @Test func unwrapEncryptedWithoutKeyThrows() throws {
        let key = SymmetricKey(size: .bits256)
        let wrapped = try EncryptedJSON.wrap(Data("x".utf8), key: key)
        #expect(throws: (any Error).self) {
            _ = try EncryptedJSON.unwrap(wrapped, key: nil)
        }
    }

    @Test func safeWriteRefusesToClobberEncryptedWithoutKey() throws {
        let url = tempFile()
        let key = SymmetricKey(size: .bits256)
        // Lay down an encrypted file.
        _ = try EncryptedJSON.safeWrite(Data("secret".utf8), to: url, key: key)
        let encrypted = try Data(contentsOf: url)
        #expect(EncryptedJSON.hasMagic(encrypted))

        // A keyless write must NOT overwrite it with plaintext.
        let result = try EncryptedJSON.safeWrite(Data("plaintext".utf8), to: url, key: nil)
        #expect(result == .skippedLockedEncrypted)
        #expect(try Data(contentsOf: url) == encrypted)   // untouched

        try? FileManager.default.removeItem(at: url)
    }

    @Test func safeWriteSetsOwnerOnlyPerms() throws {
        let url = tempFile()
        _ = try EncryptedJSON.safeWrite(Data("hi".utf8), to: url, key: nil)
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
        try? FileManager.default.removeItem(at: url)
    }
}
