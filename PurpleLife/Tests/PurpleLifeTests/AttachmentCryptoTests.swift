import XCTest
import CryptoKit
@testable import PurpleLife

/// Locks the AES-256-GCM seal/open contract used by the CKAsset
/// attachment sync path. Round-trip, tampering rejection, wrong-key
/// rejection, wrong-nonce rejection — the four properties the cloud
/// transport relies on.
final class AttachmentCryptoTests: XCTestCase {

    func testSealOpenRoundTripsPlaintext() throws {
        let plain = Data("hello attachment world".utf8)
        let sealed = try AttachmentCrypto.seal(plain)
        XCTAssertEqual(sealed.key.count, 32, "AES-256 key must be 32 bytes")
        XCTAssertEqual(sealed.nonce.count, 12, "AES-GCM nonce must be 12 bytes")
        XCTAssertNotEqual(sealed.ciphertext, plain,
                          "Ciphertext must not equal plaintext (sanity)")

        let opened = try AttachmentCrypto.open(
            ciphertext: sealed.ciphertext,
            key: sealed.key,
            nonce: sealed.nonce
        )
        XCTAssertEqual(opened, plain)
    }

    func testSealProducesDifferentCiphertextEachCall() throws {
        // Random key + random nonce per call → identical plaintext
        // produces different ciphertext. Otherwise an attacker
        // watching CloudKit could correlate identical uploads.
        let plain = Data("same content twice".utf8)
        let a = try AttachmentCrypto.seal(plain)
        let b = try AttachmentCrypto.seal(plain)
        XCTAssertNotEqual(a.key, b.key, "Each seal must produce a fresh key")
        XCTAssertNotEqual(a.nonce, b.nonce, "Each seal must produce a fresh nonce")
        XCTAssertNotEqual(a.ciphertext, b.ciphertext,
                          "Same plaintext + fresh key/nonce must produce different ciphertext")
    }

    func testOpenRejectsTamperedCiphertext() throws {
        let plain = Data("integrity check".utf8)
        var sealed = try AttachmentCrypto.seal(plain)
        // Flip one bit in the ciphertext (not the tag — but AES-GCM's
        // tag covers the ciphertext so any bit-flip should reject).
        XCTAssertGreaterThan(sealed.ciphertext.count, 16)
        sealed = AttachmentCrypto.Sealed(
            ciphertext: Data(sealed.ciphertext.prefix(1).map { $0 ^ 0x01 }) + sealed.ciphertext.dropFirst(),
            key: sealed.key,
            nonce: sealed.nonce
        )
        XCTAssertThrowsError(try AttachmentCrypto.open(
            ciphertext: sealed.ciphertext, key: sealed.key, nonce: sealed.nonce))
    }

    func testOpenRejectsWrongKey() throws {
        let plain = Data("wrong-key test".utf8)
        let sealed = try AttachmentCrypto.seal(plain)
        let wrongKey = Data(repeating: 0xAB, count: 32)
        XCTAssertThrowsError(try AttachmentCrypto.open(
            ciphertext: sealed.ciphertext, key: wrongKey, nonce: sealed.nonce))
    }

    func testOpenRejectsWrongNonce() throws {
        let plain = Data("wrong-nonce test".utf8)
        let sealed = try AttachmentCrypto.seal(plain)
        let wrongNonce = Data(repeating: 0x00, count: 12)
        XCTAssertThrowsError(try AttachmentCrypto.open(
            ciphertext: sealed.ciphertext, key: sealed.key, nonce: wrongNonce))
    }

    func testOpenRejectsWrongKeyLength() {
        XCTAssertThrowsError(try AttachmentCrypto.open(
            ciphertext: Data(repeating: 0, count: 32),
            key: Data(repeating: 0, count: 16),  // AES-128 length — not allowed
            nonce: Data(repeating: 0, count: 12))
        ) { error in
            XCTAssertEqual(error as? AttachmentCrypto.CryptoError,
                           .invalidKey(16))
        }
    }

    func testOpenRejectsWrongNonceLength() {
        XCTAssertThrowsError(try AttachmentCrypto.open(
            ciphertext: Data(repeating: 0, count: 32),
            key: Data(repeating: 0, count: 32),
            nonce: Data(repeating: 0, count: 16))  // wrong nonce length
        ) { error in
            XCTAssertEqual(error as? AttachmentCrypto.CryptoError,
                           .invalidNonce(16))
        }
    }

    func testRoundTripsLargePayload() throws {
        // 1 MB random-ish payload — basic sanity that GCM handles
        // larger blobs (real attachments will often be 5-20 MB).
        var bytes = Data(count: 1_000_000)
        bytes.withUnsafeMutableBytes { buf in
            for i in 0..<buf.count { buf[i] = UInt8(i % 251) }
        }
        let sealed = try AttachmentCrypto.seal(bytes)
        let opened = try AttachmentCrypto.open(
            ciphertext: sealed.ciphertext, key: sealed.key, nonce: sealed.nonce)
        XCTAssertEqual(opened, bytes)
    }
}
