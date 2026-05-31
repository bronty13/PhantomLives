import Foundation
import CryptoKit
import CommonCrypto

/// Thin, deliberate wrapper around `CryptoKit` and `CommonCrypto` so the rest
/// of the app doesn't import either of them directly. Two primitives:
///
///   * `Crypto.encrypt(_:using:)` / `Crypto.decrypt(_:using:)` — AES-256-GCM.
///   * `Crypto.deriveKey(passphrase:salt:iterations:)` — PBKDF2-SHA256.
///
/// AES-GCM gives us authenticated encryption (integrity + confidentiality) with
/// a 12-byte nonce CryptoKit generates for us. PBKDF2 is old-school but it ships
/// in CommonCrypto without extra dependencies, and 300k iterations lines up
/// with what 1Password / Signal use today on desktop-class hardware.
enum Crypto {

    enum Error: Swift.Error {
        case kdfFailed(Int32)
        case sealFailed
        case openFailed
    }

    /// AES-GCM encrypt. Output is the CryptoKit "combined" format: nonce ||
    /// ciphertext || tag. Caller writes this as a single blob; decrypt parses
    /// it back automatically.
    static func encrypt(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw Error.sealFailed }
        return combined
    }

    /// AES-GCM decrypt. Expects the "combined" format produced by `encrypt`.
    /// A wrong key or tampered ciphertext throws — we never return garbage.
    static func decrypt(_ ciphertext: Data, using key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: key)
    }

    /// PBKDF2-HMAC-SHA256 passphrase → 256-bit key. `iterations` is tuned
    /// high enough to make brute force expensive on a copied disk image while
    /// still keeping interactive unlock under ~500 ms on Apple Silicon.
    static func deriveKey(passphrase: String,
                          salt: Data,
                          iterations: Int = 300_000) throws -> SymmetricKey {
        let passBytes = Array(passphrase.utf8)
        let keyLen = 32
        var derived = [UInt8](repeating: 0, count: keyLen)

        let status = salt.withUnsafeBytes { saltPtr -> Int32 in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passBytes, passBytes.count,
                saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &derived, keyLen
            )
        }
        guard status == kCCSuccess else { throw Error.kdfFailed(status) }
        return SymmetricKey(data: Data(derived))
    }

    /// Cryptographically-strong random bytes. Used for DEK generation and
    /// salts. `SymmetricKey(size:)` works for keys; this helper exists for
    /// non-key byte strings (salts, nonces before CryptoKit's randomness).
    static func randomBytes(_ count: Int) -> Data {
        var out = Data(count: count)
        let status = out.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, count, ptr.baseAddress!)
        }
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return out
    }
}

// MARK: - SymmetricKey convenience

extension SymmetricKey {
    /// Raw bytes of the key. Used when we need to serialise the DEK after
    /// wrapping it with the KEK.
    var rawData: Data {
        withUnsafeBytes { Data($0) }
    }
}
