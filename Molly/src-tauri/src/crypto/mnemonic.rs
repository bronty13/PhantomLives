// BIP-39 mnemonic wrapper. 32 bytes of DEK → 24 English words and
// back. Uses tiny-bip39 so we don't ship our own word list (the crate
// bundles the standard 2048-word English list + checksum validation).
//
// Why 24 words: 32 bytes (256 bits) of entropy + 8 bits of checksum =
// 264 bits = 24 words × 11 bits/word. This is the same shape Bitcoin
// wallets use, so users may already be familiar with the format.

use bip39::{Language, Mnemonic, MnemonicType, Seed as _Seed};

use super::errors::CryptoError;
use super::keystore::Dek;

/// Encode a 32-byte DEK as 24 BIP-39 English words.
pub fn dek_to_words(dek: &Dek) -> Result<Vec<String>, CryptoError> {
    let mnem = Mnemonic::from_entropy(dek.as_bytes(), Language::English)
        .map_err(|e| CryptoError::Internal(format!("bip39 encode: {e}")))?;
    Ok(mnem
        .phrase()
        .split_whitespace()
        .map(|s| s.to_string())
        .collect())
}

/// Decode 24 BIP-39 English words back to a 32-byte DEK. Verifies the
/// BIP-39 checksum (catches typos before any decryption attempt) and
/// returns specific errors for the common failure modes so the UI can
/// be helpful.
pub fn words_to_dek(words: &[String]) -> Result<Dek, CryptoError> {
    if words.len() != 24 {
        return Err(CryptoError::MnemonicWrongLength);
    }

    // Pre-check each word against the wordlist so we can point at the
    // exact bad index — tiny-bip39's own error doesn't carry the index.
    let wordlist = Language::English.wordlist();
    for (idx, w) in words.iter().enumerate() {
        let normalized = w.trim().to_lowercase();
        if wordlist.get_words_by_prefix(&normalized).iter().any(|c| **c == normalized) {
            continue;
        }
        return Err(CryptoError::MnemonicWordUnknown {
            idx: idx + 1,
            word: w.clone(),
        });
    }

    let phrase = words
        .iter()
        .map(|s| s.trim().to_lowercase())
        .collect::<Vec<_>>()
        .join(" ");
    let mnem = Mnemonic::from_phrase(&phrase, Language::English)
        .map_err(|_| CryptoError::ChecksumInvalid)?;

    // Defensive: BIP-39 entropy bytes match the original DEK exactly.
    let entropy = mnem.entropy();
    if entropy.len() != 32 {
        return Err(CryptoError::Internal(format!(
            "expected 32-byte entropy from 24 words, got {}",
            entropy.len()
        )));
    }
    let mut bytes = [0u8; 32];
    bytes.copy_from_slice(entropy);
    Ok(Dek::from_bytes(bytes))
}

/// Convenience: 24-word mnemonic given a length helper for the UI.
pub fn expected_word_count() -> usize {
    // Hard-coded but exposed via fn so the UI doesn't drift from us.
    let _ = MnemonicType::Words24; // sanity touch
    24
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_identity() {
        let dek = Dek::from_bytes([0xAB; 32]);
        let words = dek_to_words(&dek).unwrap();
        assert_eq!(words.len(), 24);
        let back = words_to_dek(&words).unwrap();
        assert_eq!(back.as_bytes(), dek.as_bytes());
    }

    #[test]
    fn round_trip_random_deks() {
        use rand::RngCore;
        let mut rng = rand::thread_rng();
        for _ in 0..32 {
            let mut bytes = [0u8; 32];
            rng.fill_bytes(&mut bytes);
            let dek = Dek::from_bytes(bytes);
            let words = dek_to_words(&dek).unwrap();
            let back = words_to_dek(&words).unwrap();
            assert_eq!(back.as_bytes(), dek.as_bytes());
        }
    }

    #[test]
    fn rejects_wrong_length() {
        let too_short: Vec<String> = (0..20).map(|_| "abandon".into()).collect();
        assert!(matches!(words_to_dek(&too_short), Err(CryptoError::MnemonicWrongLength)));
        let too_long: Vec<String> = (0..25).map(|_| "abandon".into()).collect();
        assert!(matches!(words_to_dek(&too_long), Err(CryptoError::MnemonicWrongLength)));
    }

    #[test]
    fn rejects_unknown_word() {
        let dek = Dek::from_bytes([1u8; 32]);
        let mut words = dek_to_words(&dek).unwrap();
        words[7] = "snorfblat".into();
        match words_to_dek(&words) {
            Err(CryptoError::MnemonicWordUnknown { idx, word }) => {
                assert_eq!(idx, 8); // 1-indexed
                assert_eq!(word, "snorfblat");
            }
            other => panic!("expected MnemonicWordUnknown, got {other:?}"),
        }
    }

    #[test]
    fn rejects_bad_checksum() {
        let dek = Dek::from_bytes([1u8; 32]);
        let mut words = dek_to_words(&dek).unwrap();
        // Swap two valid words to break the checksum without making
        // any individual word invalid.
        words.swap(3, 17);
        assert!(matches!(words_to_dek(&words), Err(CryptoError::ChecksumInvalid)));
    }

    #[test]
    fn case_and_whitespace_insensitive() {
        let dek = Dek::from_bytes([42u8; 32]);
        let words = dek_to_words(&dek).unwrap();
        let messy: Vec<String> = words.iter().enumerate().map(|(i, w)| {
            if i % 2 == 0 { format!("  {}  ", w.to_uppercase()) } else { w.clone() }
        }).collect();
        let back = words_to_dek(&messy).unwrap();
        assert_eq!(back.as_bytes(), dek.as_bytes());
    }
}
