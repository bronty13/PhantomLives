// AES-256-GCM field-level encryption.
//
// Wire format (single base64 string):
//   version_byte (0x01) || nonce (12 bytes) || ciphertext || tag (16 bytes)
//
// The version byte lets us migrate cipher choice later (e.g. v2 =
// XChaCha20-Poly1305 with 24-byte nonces). Parsers MUST reject
// unknown versions rather than guess.

use aes_gcm::{
    aead::{Aead, KeyInit},
    Aes256Gcm, Nonce,
};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use rand::RngCore;

use super::errors::CryptoError;
use super::keystore::Dek;

const VERSION_V1: u8 = 0x01;
const NONCE_LEN: usize = 12;
const TAG_LEN: usize = 16;

/// Encrypt `plaintext` with `dek`, return a base64-encoded versioned
/// blob suitable for SQLite TEXT storage. Each call uses a fresh random
/// nonce (AES-GCM nonce-reuse with the same key is catastrophic — never
/// derive the nonce from anything deterministic).
pub fn encrypt_field(dek: &Dek, plaintext: &str) -> Result<String, CryptoError> {
    let cipher = Aes256Gcm::new_from_slice(dek.as_bytes())
        .map_err(|e| CryptoError::Internal(format!("cipher init: {e}")))?;
    let mut nonce_bytes = [0u8; NONCE_LEN];
    rand::thread_rng().fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);
    let ciphertext = cipher
        .encrypt(nonce, plaintext.as_bytes())
        .map_err(|_| CryptoError::Internal("encrypt failed".into()))?;

    let mut blob = Vec::with_capacity(1 + NONCE_LEN + ciphertext.len());
    blob.push(VERSION_V1);
    blob.extend_from_slice(&nonce_bytes);
    blob.extend_from_slice(&ciphertext);
    Ok(STANDARD.encode(&blob))
}

/// Decrypt a base64-encoded versioned blob with `dek`. Returns
/// `DecryptionFailed` for any AEAD tag mismatch (tampered ciphertext OR
/// wrong DEK) — the caller must NOT distinguish these to the user.
pub fn decrypt_field(dek: &Dek, b64: &str) -> Result<String, CryptoError> {
    let blob = STANDARD
        .decode(b64)
        .map_err(|_| CryptoError::BadCiphertextFormat)?;
    // Need at minimum: version (1) + nonce (12) + tag (16) = 29 bytes.
    if blob.len() < 1 + NONCE_LEN + TAG_LEN {
        return Err(CryptoError::BadCiphertextFormat);
    }
    if blob[0] != VERSION_V1 {
        return Err(CryptoError::BadCiphertextFormat);
    }
    let nonce = Nonce::from_slice(&blob[1..1 + NONCE_LEN]);
    let ct = &blob[1 + NONCE_LEN..];

    let cipher = Aes256Gcm::new_from_slice(dek.as_bytes())
        .map_err(|e| CryptoError::Internal(format!("cipher init: {e}")))?;
    let plaintext = cipher
        .decrypt(nonce, ct)
        .map_err(|_| CryptoError::DecryptionFailed)?;
    String::from_utf8(plaintext)
        .map_err(|_| CryptoError::DecryptionFailed)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixed_dek() -> Dek {
        // Test vector — not used in production.
        Dek::from_bytes([7u8; 32])
    }

    #[test]
    fn roundtrip_ascii() {
        let dek = fixed_dek();
        let blob = encrypt_field(&dek, "hello molly").unwrap();
        assert_eq!(decrypt_field(&dek, &blob).unwrap(), "hello molly");
    }

    #[test]
    fn roundtrip_utf8_emoji() {
        let dek = fixed_dek();
        let blob = encrypt_field(&dek, "🌷 sparkly password 💕 with naïve unicode").unwrap();
        assert_eq!(
            decrypt_field(&dek, &blob).unwrap(),
            "🌷 sparkly password 💕 with naïve unicode"
        );
    }

    #[test]
    fn roundtrip_large_blob() {
        let dek = fixed_dek();
        let big = "x".repeat(1_000_000);
        let blob = encrypt_field(&dek, &big).unwrap();
        assert_eq!(decrypt_field(&dek, &blob).unwrap().len(), 1_000_000);
    }

    #[test]
    fn each_call_uses_fresh_nonce() {
        // Two encrypts of the same plaintext under the same key must
        // produce different ciphertexts — proves we're not derivating
        // the nonce deterministically.
        let dek = fixed_dek();
        let a = encrypt_field(&dek, "same plaintext").unwrap();
        let b = encrypt_field(&dek, "same plaintext").unwrap();
        assert_ne!(a, b, "identical plaintexts must produce different ciphertexts");
    }

    #[test]
    fn tampered_tag_fails() {
        let dek = fixed_dek();
        let blob = encrypt_field(&dek, "hello").unwrap();
        let mut bytes = STANDARD.decode(&blob).unwrap();
        // Flip last byte (in the AES-GCM tag).
        let n = bytes.len();
        bytes[n - 1] ^= 0x01;
        let tampered = STANDARD.encode(&bytes);
        match decrypt_field(&dek, &tampered) {
            Err(CryptoError::DecryptionFailed) => {}
            other => panic!("expected DecryptionFailed, got {other:?}"),
        }
    }

    #[test]
    fn tampered_nonce_fails() {
        let dek = fixed_dek();
        let blob = encrypt_field(&dek, "hello").unwrap();
        let mut bytes = STANDARD.decode(&blob).unwrap();
        bytes[2] ^= 0x01; // flip a bit in the nonce
        let tampered = STANDARD.encode(&bytes);
        assert!(matches!(decrypt_field(&dek, &tampered), Err(CryptoError::DecryptionFailed)));
    }

    #[test]
    fn tampered_body_fails() {
        let dek = fixed_dek();
        let blob = encrypt_field(&dek, "hello there friend").unwrap();
        let mut bytes = STANDARD.decode(&blob).unwrap();
        // Flip a bit in the middle of the ciphertext.
        let mid = 1 + NONCE_LEN + 3;
        bytes[mid] ^= 0x01;
        let tampered = STANDARD.encode(&bytes);
        assert!(matches!(decrypt_field(&dek, &tampered), Err(CryptoError::DecryptionFailed)));
    }

    #[test]
    fn wrong_key_fails() {
        let dek1 = Dek::from_bytes([1u8; 32]);
        let dek2 = Dek::from_bytes([2u8; 32]);
        let blob = encrypt_field(&dek1, "hello").unwrap();
        assert!(matches!(decrypt_field(&dek2, &blob), Err(CryptoError::DecryptionFailed)));
    }

    #[test]
    fn rejects_unknown_version() {
        let dek = fixed_dek();
        let blob = encrypt_field(&dek, "hello").unwrap();
        let mut bytes = STANDARD.decode(&blob).unwrap();
        bytes[0] = 0xFE; // unknown version
        let tampered = STANDARD.encode(&bytes);
        assert!(matches!(decrypt_field(&dek, &tampered), Err(CryptoError::BadCiphertextFormat)));
    }

    #[test]
    fn rejects_truncated_blob() {
        let dek = fixed_dek();
        // Only 10 bytes total — can't possibly contain version + nonce + tag.
        let tiny = STANDARD.encode(&[0u8; 10]);
        assert!(matches!(decrypt_field(&dek, &tiny), Err(CryptoError::BadCiphertextFormat)));
    }

    #[test]
    fn rejects_bad_base64() {
        let dek = fixed_dek();
        assert!(matches!(decrypt_field(&dek, "not!!!!base64$$$"), Err(CryptoError::BadCiphertextFormat)));
    }
}
