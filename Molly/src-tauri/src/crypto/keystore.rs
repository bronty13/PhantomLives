// Phase 10 keystore.
//
// Lifecycle:
//   1. init(passphrase)  → generate 16-byte salt + 32-byte DEK, derive
//      KEK from passphrase via PBKDF2-HMAC-SHA256 (300k iter), wrap DEK
//      with KEK via AES-GCM, store (salt, wrapped_dek) in the singleton
//      `crypto_keystore` row.
//   2. unlock(passphrase) → re-derive KEK, unwrap DEK, hold in
//      Arc<Mutex<Option<SessionState>>> for the session.
//   3. encrypt_field / decrypt_field → use the in-session DEK (no
//      passphrase prompt per operation).
//   4. lock() → drop the cached DEK; zeroize on drop ensures the key
//      material is wiped from memory.
//   5. change_passphrase(old, new) → re-derive KEK from new passphrase,
//      re-wrap the SAME DEK with the new KEK + fresh salt. No bulk
//      re-encryption of user data.
//   6. export_mnemonic / import_mnemonic → see crypto/mnemonic.rs.
//
// Threading: the session state is shared via Arc<Mutex<...>> behind
// the Tauri `tauri::State`. Locks are short-lived (single-method
// scope); no async work happens while a lock is held.

use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use aes_gcm::{
    aead::{Aead, KeyInit},
    Aes256Gcm, Nonce,
};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use pbkdf2::pbkdf2_hmac;
use rand::RngCore;
use rusqlite::{params, Connection};
use serde::Serialize;
use sha2::Sha256;
use zeroize::{Zeroize, ZeroizeOnDrop};

use super::errors::CryptoError;

const SALT_LEN: usize = 16;
const DEK_LEN: usize = 32;
const NONCE_LEN: usize = 12;
const PBKDF2_ITER: u32 = 300_000;
pub const MIN_PASSPHRASE_LEN: usize = 10;
pub const IDLE_LOCK_SECONDS: u64 = 8 * 60 * 60; // 8 hours
const WRONG_PASSPHRASE_SLEEP: Duration = Duration::from_millis(500);

/// 256-bit data-encryption key. Newtype so callers can't accidentally
/// pass arbitrary `[u8; 32]` (e.g. a hash) where a DEK is expected.
/// `ZeroizeOnDrop` clears the key material when this value goes out
/// of scope — important to limit how long the secret lives in RAM.
#[derive(Clone, ZeroizeOnDrop)]
pub struct Dek(pub(super) [u8; DEK_LEN]);

impl Dek {
    pub fn from_bytes(b: [u8; DEK_LEN]) -> Self {
        Self(b)
    }
    pub fn as_bytes(&self) -> &[u8; DEK_LEN] {
        &self.0
    }
    fn random() -> Self {
        let mut b = [0u8; DEK_LEN];
        rand::thread_rng().fill_bytes(&mut b);
        Self(b)
    }
}

impl std::fmt::Debug for Dek {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // Never print key material.
        write!(f, "Dek(<redacted>)")
    }
}

/// What we cache in the Tauri `State` between unlock and lock.
pub struct SessionState {
    pub dek: Dek,
    pub version: i32,
    pub unlocked_at: Instant,
}

impl SessionState {
    pub fn is_idle(&self) -> bool {
        self.unlocked_at.elapsed() > Duration::from_secs(IDLE_LOCK_SECONDS)
    }
}

#[derive(Default)]
pub struct KeystoreState(pub Mutex<Option<SessionState>>);

impl KeystoreState {
    pub fn new_arc() -> Arc<Self> {
        Arc::new(Self::default())
    }
}

/// Snapshot of the persisted row used by both reads and writes.
#[derive(Debug, Clone)]
pub struct KeystoreRecord {
    pub initialized: bool,
    pub salt_b64: Option<String>,
    pub kdf_iterations: u32,
    pub wrapped_dek_b64: Option<String>,
    pub version: i32,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct KeystoreStatus {
    pub initialized: bool,
    pub unlocked: bool,
    pub version: i32,
    /// Seconds elapsed since unlock; None when locked.
    pub unlocked_secs: Option<u64>,
}

// ----- Persistence helpers (pure; take `&Connection`) -----------------------

pub(crate) fn load(conn: &Connection) -> Result<KeystoreRecord, CryptoError> {
    let (salt_b64, kdf_iterations, wrapped_dek_b64, version): (
        Option<String>,
        i64,
        Option<String>,
        i64,
    ) = conn.query_row(
        "SELECT salt_b64, kdf_iterations, wrapped_dek_b64, dek_version
         FROM crypto_keystore WHERE id = 1",
        [],
        |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
    )?;
    Ok(KeystoreRecord {
        initialized: salt_b64.is_some() && wrapped_dek_b64.is_some(),
        salt_b64,
        kdf_iterations: kdf_iterations as u32,
        wrapped_dek_b64,
        version: version as i32,
    })
}

fn save_wrapped(
    conn: &Connection,
    salt_b64: &str,
    wrapped_dek_b64: &str,
) -> Result<(), CryptoError> {
    conn.execute(
        "UPDATE crypto_keystore
         SET salt_b64 = ?1, wrapped_dek_b64 = ?2, updated_at = datetime('now')
         WHERE id = 1",
        params![salt_b64, wrapped_dek_b64],
    )?;
    Ok(())
}

fn bump_version(conn: &Connection) -> Result<i32, CryptoError> {
    conn.execute(
        "UPDATE crypto_keystore SET dek_version = dek_version + 1, updated_at = datetime('now')
         WHERE id = 1",
        [],
    )?;
    let v: i64 = conn.query_row(
        "SELECT dek_version FROM crypto_keystore WHERE id = 1",
        [],
        |row| row.get(0),
    )?;
    Ok(v as i32)
}

// ----- KEK derivation + DEK wrap/unwrap --------------------------------------

fn derive_kek(passphrase: &str, salt: &[u8], iterations: u32) -> [u8; 32] {
    let mut kek = [0u8; 32];
    pbkdf2_hmac::<Sha256>(passphrase.as_bytes(), salt, iterations, &mut kek);
    kek
}

fn wrap_dek(kek: &[u8; 32], dek: &Dek) -> Result<String, CryptoError> {
    let cipher = Aes256Gcm::new_from_slice(kek)
        .map_err(|e| CryptoError::Internal(format!("kek cipher init: {e}")))?;
    let mut nonce_bytes = [0u8; NONCE_LEN];
    rand::thread_rng().fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);
    let ct = cipher
        .encrypt(nonce, dek.as_bytes().as_slice())
        .map_err(|_| CryptoError::Internal("wrap failed".into()))?;
    // Wrapped format: nonce (12) || ciphertext (32 + 16 tag = 48) — total 60 bytes.
    let mut blob = Vec::with_capacity(NONCE_LEN + ct.len());
    blob.extend_from_slice(&nonce_bytes);
    blob.extend_from_slice(&ct);
    Ok(STANDARD.encode(&blob))
}

fn unwrap_dek(kek: &[u8; 32], wrapped_b64: &str) -> Result<Dek, CryptoError> {
    let blob = STANDARD
        .decode(wrapped_b64)
        .map_err(|_| CryptoError::Unauthorized)?;
    if blob.len() <= NONCE_LEN {
        return Err(CryptoError::Unauthorized);
    }
    let nonce = Nonce::from_slice(&blob[..NONCE_LEN]);
    let ct = &blob[NONCE_LEN..];
    let cipher = Aes256Gcm::new_from_slice(kek)
        .map_err(|e| CryptoError::Internal(format!("kek cipher init: {e}")))?;
    let pt = cipher
        .decrypt(nonce, ct)
        .map_err(|_| CryptoError::Unauthorized)?;
    if pt.len() != DEK_LEN {
        return Err(CryptoError::Unauthorized);
    }
    let mut bytes = [0u8; DEK_LEN];
    bytes.copy_from_slice(&pt);
    Ok(Dek::from_bytes(bytes))
}

// ----- Public operations -----------------------------------------------------

pub fn init(conn: &Connection, passphrase: &str) -> Result<i32, CryptoError> {
    if passphrase.len() < MIN_PASSPHRASE_LEN {
        return Err(CryptoError::PassphraseTooShort);
    }
    let rec = load(conn)?;
    if rec.initialized {
        return Err(CryptoError::AlreadyInitialized);
    }
    let mut salt = [0u8; SALT_LEN];
    rand::thread_rng().fill_bytes(&mut salt);
    let mut kek = derive_kek(passphrase, &salt, PBKDF2_ITER);
    let dek = Dek::random();
    let wrapped_b64 = wrap_dek(&kek, &dek)?;
    save_wrapped(conn, &STANDARD.encode(&salt), &wrapped_b64)?;
    kek.zeroize();
    Ok(rec.version)
}

/// Validate a passphrase by attempting to unwrap the DEK. Returns the
/// unwrapped DEK on success. On failure, sleeps ~500ms before returning
/// `Unauthorized` to rate-limit guessing.
pub fn unlock(conn: &Connection, passphrase: &str) -> Result<(Dek, i32), CryptoError> {
    let rec = load(conn)?;
    let salt_b64 = rec.salt_b64.as_ref().ok_or(CryptoError::NotInitialized)?;
    let wrapped_b64 = rec.wrapped_dek_b64.as_ref().ok_or(CryptoError::NotInitialized)?;
    let salt = STANDARD
        .decode(salt_b64)
        .map_err(|_| CryptoError::Internal("salt not base64".into()))?;
    let mut kek = derive_kek(passphrase, &salt, rec.kdf_iterations);
    let result = unwrap_dek(&kek, wrapped_b64);
    kek.zeroize();
    match result {
        Ok(dek) => Ok((dek, rec.version)),
        Err(_) => {
            std::thread::sleep(WRONG_PASSPHRASE_SLEEP);
            Err(CryptoError::Unauthorized)
        }
    }
}

/// Re-wrap the existing DEK with a new passphrase + fresh salt. Caller
/// must have already validated `old` via `unlock` and pass the same
/// `dek` here. Returns the same `version` (rotation doesn't bump
/// version — that's reserved for DEK rotation, not passphrase change).
pub fn change_passphrase(
    conn: &Connection,
    dek: &Dek,
    new_passphrase: &str,
) -> Result<(), CryptoError> {
    if new_passphrase.len() < MIN_PASSPHRASE_LEN {
        return Err(CryptoError::PassphraseTooShort);
    }
    let mut salt = [0u8; SALT_LEN];
    rand::thread_rng().fill_bytes(&mut salt);
    let mut kek = derive_kek(new_passphrase, &salt, PBKDF2_ITER);
    let wrapped_b64 = wrap_dek(&kek, dek)?;
    save_wrapped(conn, &STANDARD.encode(&salt), &wrapped_b64)?;
    kek.zeroize();
    Ok(())
}

/// Import an externally-supplied DEK (e.g. from a BIP-39 mnemonic),
/// generating a fresh salt and wrapping with the new passphrase. The
/// version is BUMPED so existing ciphertext that was written under a
/// different DEK can be identified (e.g. for a future re-key migration).
pub fn import(
    conn: &Connection,
    dek: &Dek,
    new_passphrase: &str,
) -> Result<i32, CryptoError> {
    if new_passphrase.len() < MIN_PASSPHRASE_LEN {
        return Err(CryptoError::PassphraseTooShort);
    }
    let mut salt = [0u8; SALT_LEN];
    rand::thread_rng().fill_bytes(&mut salt);
    let mut kek = derive_kek(new_passphrase, &salt, PBKDF2_ITER);
    let wrapped_b64 = wrap_dek(&kek, dek)?;
    save_wrapped(conn, &STANDARD.encode(&salt), &wrapped_b64)?;
    kek.zeroize();
    bump_version(conn)
}

/// Wipe the keystore back to uninitialized state. The DEK is gone; any
/// data still encrypted with the old DEK becomes unrecoverable. Caller
/// is responsible for also wiping that data if desired.
pub fn wipe(conn: &Connection) -> Result<(), CryptoError> {
    conn.execute(
        "UPDATE crypto_keystore
         SET salt_b64 = NULL, wrapped_dek_b64 = NULL,
             dek_version = dek_version + 1,
             updated_at = datetime('now')
         WHERE id = 1",
        [],
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;

    fn fresh_db() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        // Just the bits this module touches — load only migration 001 + 018.
        conn.execute_batch(include_str!("../../migrations/001_init.sql")).unwrap();
        conn.execute_batch(include_str!("../../migrations/018_crypto_keystore.sql")).unwrap();
        conn
    }

    #[test]
    fn init_then_unlock_happy_path() {
        let conn = fresh_db();
        init(&conn, "correct horse battery staple").unwrap();
        let (dek, version) = unlock(&conn, "correct horse battery staple").unwrap();
        assert_eq!(version, 1);
        // Sanity: encrypting + decrypting a field round-trips.
        let blob = super::super::wrap::encrypt_field(&dek, "hello").unwrap();
        assert_eq!(super::super::wrap::decrypt_field(&dek, &blob).unwrap(), "hello");
    }

    #[test]
    fn wrong_passphrase_is_rate_limited() {
        // Note: in debug builds the 300k-iter PBKDF2 itself takes
        // ~1-2 seconds, so the elapsed time includes both KDF +
        // sleep. The assertion checks the lower bound (the 500ms
        // sleep fires) but tolerates whatever the KDF adds. Release
        // builds run PBKDF2 in ~80ms so the total is closer to ~600ms.
        let conn = fresh_db();
        init(&conn, "correct horse battery staple").unwrap();
        let start = std::time::Instant::now();
        let err = unlock(&conn, "wrong horse battery staple").unwrap_err();
        let elapsed = start.elapsed();
        assert!(matches!(err, CryptoError::Unauthorized));
        assert!(
            elapsed >= Duration::from_millis(450),
            "expected ≥500ms rate-limit delay on wrong passphrase, got {elapsed:?}"
        );
        // Don't assert an upper bound — debug-mode PBKDF2 dominates
        // and varies machine-to-machine.
    }

    #[test]
    fn init_twice_rejected() {
        let conn = fresh_db();
        init(&conn, "correct horse battery staple").unwrap();
        let err = init(&conn, "different passphrase here").unwrap_err();
        assert!(matches!(err, CryptoError::AlreadyInitialized));
    }

    #[test]
    fn passphrase_too_short_rejected() {
        let conn = fresh_db();
        let err = init(&conn, "tooshort").unwrap_err();
        assert!(matches!(err, CryptoError::PassphraseTooShort));
    }

    #[test]
    fn change_passphrase_preserves_dek() {
        let conn = fresh_db();
        init(&conn, "first passphrase here").unwrap();
        let (dek_a, _) = unlock(&conn, "first passphrase here").unwrap();
        let blob = super::super::wrap::encrypt_field(&dek_a, "secret data").unwrap();

        change_passphrase(&conn, &dek_a, "second passphrase here").unwrap();
        // Old passphrase no longer works.
        assert!(matches!(
            unlock(&conn, "first passphrase here"),
            Err(CryptoError::Unauthorized)
        ));
        // New passphrase yields the SAME DEK (proven by decrypting the
        // ciphertext encrypted under the original).
        let (dek_b, _) = unlock(&conn, "second passphrase here").unwrap();
        assert_eq!(dek_a.as_bytes(), dek_b.as_bytes());
        assert_eq!(
            super::super::wrap::decrypt_field(&dek_b, &blob).unwrap(),
            "secret data"
        );
    }

    #[test]
    fn import_rotates_and_bumps_version() {
        let conn = fresh_db();
        // No previous init — import bootstraps with a foreign DEK.
        let imported = Dek::from_bytes([7u8; 32]);
        let new_version = import(&conn, &imported, "imported passphrase").unwrap();
        assert_eq!(new_version, 2); // bumped from initial 1
        let (loaded, v) = unlock(&conn, "imported passphrase").unwrap();
        assert_eq!(v, 2);
        assert_eq!(loaded.as_bytes(), imported.as_bytes());
    }

    #[test]
    fn wipe_returns_to_uninitialized() {
        let conn = fresh_db();
        init(&conn, "correct horse battery staple").unwrap();
        wipe(&conn).unwrap();
        let rec = load(&conn).unwrap();
        assert!(!rec.initialized);
        assert!(rec.salt_b64.is_none());
        assert!(rec.wrapped_dek_b64.is_none());
        assert!(matches!(
            unlock(&conn, "correct horse battery staple"),
            Err(CryptoError::NotInitialized)
        ));
    }

    #[test]
    fn dek_debug_does_not_leak_bytes() {
        let dek = Dek::from_bytes([0xAA; DEK_LEN]);
        let s = format!("{:?}", dek);
        assert!(!s.contains("AA"));
        assert!(!s.contains("170"));
        assert!(s.contains("redacted"));
    }

    #[test]
    fn session_state_idle_check() {
        let session = SessionState {
            dek: Dek::from_bytes([0u8; DEK_LEN]),
            version: 1,
            unlocked_at: Instant::now(),
        };
        assert!(!session.is_idle());
    }
}
