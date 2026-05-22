// OS keychain helper for the "Stay unlocked across restarts" feature.
//
// Stores the raw 32-byte DEK in the platform-native credential store
// (macOS Keychain, Windows Credential Manager, Linux Secret Service)
// via the `keyring` crate. The entry is keyed by (service, account):
//   service = "com.phantomlives.molly"
//   account = "keystore-dek-v1"
//
// Format stored: base64(DEK) preceded by "v<version>:". Including the
// version lets us detect a stale keychain entry (e.g. another machine
// re-imported the keystore via mnemonic and bumped dek_version) and
// discard it instead of restoring the wrong key.
//
// Only written when the user opts in via `stay_unlocked = 1` in
// crypto_keystore. Manual `lock_keystore`, `wipe_keystore`, and
// `set_stay_unlocked(false)` always purge the entry.

use base64::{engine::general_purpose::STANDARD, Engine as _};
use keyring::Entry;
use zeroize::Zeroize;

use super::errors::CryptoError;
use super::keystore::Dek;

const SERVICE: &str = "com.phantomlives.molly";
const ACCOUNT: &str = "keystore-dek-v1";

fn entry() -> Result<Entry, CryptoError> {
    Entry::new(SERVICE, ACCOUNT)
        .map_err(|e| CryptoError::Internal(format!("keychain entry: {e}")))
}

/// Save the unlocked DEK to the OS keychain. Overwrites any prior
/// entry. Caller is responsible for only invoking when stay_unlocked
/// is enabled.
pub fn save(dek: &Dek, version: i32) -> Result<(), CryptoError> {
    let encoded = format!("v{}:{}", version, STANDARD.encode(dek.as_bytes()));
    let result = entry()?
        .set_password(&encoded)
        .map_err(|e| CryptoError::Internal(format!("keychain set: {e}")));
    // Don't leave the base64-encoded secret sitting in our String heap
    // any longer than necessary.
    let mut clear = encoded.into_bytes();
    clear.zeroize();
    result
}

/// Try to load a previously-saved DEK. Returns:
/// - `Ok(Some((dek, version)))` if the entry exists and parses.
/// - `Ok(None)` if no entry exists (the common "user hasn't opted in
///   yet, or just wiped" case).
/// - `Err(_)` only on unexpected keychain or decoding errors.
pub fn load() -> Result<Option<(Dek, i32)>, CryptoError> {
    let e = entry()?;
    match e.get_password() {
        Ok(s) => parse_payload(&s).map(Some),
        Err(keyring::Error::NoEntry) => Ok(None),
        // Treat all other read failures (locked keychain, ambiguous,
        // platform errors) as "no usable entry" so a flaky keychain
        // never blocks the user from typing their passphrase manually.
        Err(_) => Ok(None),
    }
}

/// Best-effort delete. Missing entries are not an error.
pub fn clear() -> Result<(), CryptoError> {
    match entry()?.delete_credential() {
        Ok(()) => Ok(()),
        Err(keyring::Error::NoEntry) => Ok(()),
        Err(e) => Err(CryptoError::Internal(format!("keychain clear: {e}"))),
    }
}

fn parse_payload(s: &str) -> Result<(Dek, i32), CryptoError> {
    // Format: v<version>:<base64-of-32-bytes>
    let rest = s
        .strip_prefix('v')
        .ok_or_else(|| CryptoError::Internal("keychain payload missing v prefix".into()))?;
    let (ver_str, b64) = rest
        .split_once(':')
        .ok_or_else(|| CryptoError::Internal("keychain payload missing :".into()))?;
    let version: i32 = ver_str
        .parse()
        .map_err(|_| CryptoError::Internal("keychain payload bad version".into()))?;
    let bytes = STANDARD
        .decode(b64)
        .map_err(|_| CryptoError::Internal("keychain payload bad base64".into()))?;
    if bytes.len() != 32 {
        return Err(CryptoError::Internal("keychain payload wrong length".into()));
    }
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&bytes);
    Ok((Dek::from_bytes(arr), version))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_payload_round_trip() {
        let original = Dek::from_bytes([0xAB; 32]);
        let s = format!("v7:{}", STANDARD.encode(original.as_bytes()));
        let (parsed, v) = parse_payload(&s).unwrap();
        assert_eq!(v, 7);
        assert_eq!(parsed.as_bytes(), original.as_bytes());
    }

    #[test]
    fn parse_payload_rejects_garbage() {
        assert!(parse_payload("not-a-version").is_err());
        assert!(parse_payload("v1").is_err()); // no colon
        assert!(parse_payload("vX:abc").is_err()); // bad version
        assert!(parse_payload("v1:not-base64!!!").is_err());
        assert!(parse_payload("v1:dGlueQ==").is_err()); // wrong length
    }
}
