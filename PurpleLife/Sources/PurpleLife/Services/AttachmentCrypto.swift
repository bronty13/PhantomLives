import CryptoKit
import Foundation

/// Per-attachment AES-256-GCM seal/open for the CKAsset sync path.
///
/// **Why a separate helper from `EncryptedJSON`.** `EncryptedJSON` wraps
/// every file under the local DEK — that's the at-rest encryption layer.
/// For CloudKit sync, each Mac has its own DEK (the 2026-05-15
/// resilience design deliberately doesn't share DEKs between Macs to
/// keep the recovery story tight), so a Mac-A-DEK-wrapped blob can't
/// be unwrapped by Mac B. Instead we generate a *per-attachment*
/// random AES-GCM key for the CKAsset content, then carry that wrap
/// key in the CKRecord's `encryptedValues` — which CloudKit encrypts
/// in transit using the user's iCloud Keychain trust circle (CKKS),
/// independent of either Mac's DEK.
///
/// **Threat model.** Apple sees the CKAsset as opaque bytes. The wrap
/// key never appears in plaintext to Apple — `encryptedValues` is
/// E2E-encrypted by CKKS. A compromise of either layer in isolation
/// reveals nothing: ciphertext-without-key from the asset side, or
/// key-without-ciphertext from the encryptedValues side. Both layers
/// have to fall for content to leak.
enum AttachmentCrypto {

    /// The seal output. Caller writes `ciphertext` to a temp file and
    /// hands it to CKAsset; `key` and `nonce` ride along in the
    /// CKRecord's `encryptedValues`.
    struct Sealed {
        let ciphertext: Data
        let key: Data    // 32 bytes
        let nonce: Data  // 12 bytes (AES-GCM standard)
    }

    enum CryptoError: Error, LocalizedError, Equatable {
        case invalidKey(Int)
        case invalidNonce(Int)
        case openFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidKey(let n):    return "Attachment wrap key must be 32 bytes (was \(n))."
            case .invalidNonce(let n):  return "Attachment nonce must be 12 bytes (was \(n))."
            case .openFailed(let msg):  return "Attachment open failed: \(msg)"
            }
        }
    }

    /// Encrypt `plaintext` with a freshly-generated 256-bit AES key and
    /// a random 96-bit nonce. The standard combined AEAD encoding (no
    /// extra framing) is what AES.GCM.SealedBox returns; we split out
    /// the components so the caller can route them through CloudKit's
    /// distinct delivery channels.
    static func seal(_ plaintext: Data) throws -> Sealed {
        let key = SymmetricKey(size: .bits256)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        // ciphertext = combined ciphertext + tag (no nonce prefix —
        // we send the nonce separately so the on-disk asset format
        // is the deterministic "ciphertext-then-tag" pair AES.GCM
        // produces).
        return Sealed(
            ciphertext: sealed.ciphertext + sealed.tag,
            key: key.withUnsafeBytes { Data($0) },
            nonce: sealed.nonce.withUnsafeBytes { Data($0) }
        )
    }

    /// Reverse of `seal`. Throws on tampered ciphertext (the GCM tag
    /// rejects any single-bit change), wrong key, or wrong nonce.
    static func open(ciphertext: Data, key: Data, nonce: Data) throws -> Data {
        guard key.count == 32 else { throw CryptoError.invalidKey(key.count) }
        guard nonce.count == 12 else { throw CryptoError.invalidNonce(nonce.count) }
        // AES.GCM.SealedBox wants ciphertext + tag split out. The tag
        // is always the last 16 bytes; everything before is the
        // ciphertext proper.
        guard ciphertext.count >= 16 else { throw CryptoError.openFailed("ciphertext too short for GCM tag") }
        let tagStart = ciphertext.index(ciphertext.endIndex, offsetBy: -16)
        let ctBytes = ciphertext[..<tagStart]
        let tag     = ciphertext[tagStart...]
        do {
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonce),
                ciphertext: ctBytes,
                tag: tag
            )
            return try AES.GCM.open(box, using: SymmetricKey(data: key))
        } catch {
            throw CryptoError.openFailed(error.localizedDescription)
        }
    }
}
