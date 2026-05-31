import XCTest
import CryptoKit
@testable import PurpleDiary

final class CryptoTests: XCTestCase {

    func testEncryptDecryptRoundTrips() throws {
        let key = SymmetricKey(size: .bits256)
        let plain = Data("a quiet entry about the sea".utf8)
        let sealed = try Crypto.encrypt(plain, using: key)
        XCTAssertNotEqual(sealed, plain, "ciphertext must differ from plaintext")
        let opened = try Crypto.decrypt(sealed, using: key)
        XCTAssertEqual(opened, plain)
    }

    func testWrongKeyFailsToDecrypt() throws {
        let key = SymmetricKey(size: .bits256)
        let other = SymmetricKey(size: .bits256)
        let sealed = try Crypto.encrypt(Data("secret".utf8), using: key)
        XCTAssertThrowsError(try Crypto.decrypt(sealed, using: other),
                             "decrypting with the wrong key must throw, never return garbage")
    }

    func testDeriveKeyIsDeterministicForSameSaltAndDiffersForDifferentSalt() throws {
        let salt1 = Crypto.randomBytes(16)
        let salt2 = Crypto.randomBytes(16)
        let k1a = try Crypto.deriveKey(passphrase: "open sesame", salt: salt1, iterations: 1000)
        let k1b = try Crypto.deriveKey(passphrase: "open sesame", salt: salt1, iterations: 1000)
        let k2  = try Crypto.deriveKey(passphrase: "open sesame", salt: salt2, iterations: 1000)
        XCTAssertEqual(k1a.rawData, k1b.rawData, "same passphrase+salt+iters → same key")
        XCTAssertNotEqual(k1a.rawData, k2.rawData, "different salt → different key")
    }

    func testRandomBytesLengthAndUniqueness() {
        let a = Crypto.randomBytes(32)
        let b = Crypto.randomBytes(32)
        XCTAssertEqual(a.count, 32)
        XCTAssertNotEqual(a, b)
    }
}
