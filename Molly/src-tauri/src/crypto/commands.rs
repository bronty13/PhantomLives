// Tauri commands for the keystore. Thin wrappers around the pure
// helpers in `keystore`, `wrap`, `mnemonic`. All commands open their
// own rusqlite connection (same pattern as bundles.rs, c4s.rs) and
// share a `KeystoreState` via `tauri::State`.

use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};

use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager, Runtime, State};

use super::errors::CryptoError;
use super::keystore::{self, Dek, KeystoreState, KeystoreStatus, SessionState};
use super::mnemonic;
use super::wrap;

fn app_data_dir<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, CryptoError> {
    handle
        .path()
        .app_data_dir()
        .map_err(|e| CryptoError::Internal(format!("app_data_dir: {e}")))
}

fn open_conn<R: Runtime>(handle: &AppHandle<R>) -> Result<Connection, CryptoError> {
    let db_path = app_data_dir(handle)?.join("molly.db");
    let conn = Connection::open(&db_path)
        .map_err(|e| CryptoError::Db(format!("open {}: {e}", db_path.display())))?;
    conn.busy_timeout(Duration::from_secs(5))?;
    conn.execute_batch("PRAGMA foreign_keys = ON;")?;
    Ok(conn)
}

// ----- status / lock / unlock --------------------------------------------------

#[tauri::command]
pub fn keystore_status<R: Runtime>(
    handle: AppHandle<R>,
    state: State<Arc<KeystoreState>>,
) -> Result<KeystoreStatus, CryptoError> {
    let conn = open_conn(&handle)?;
    let rec = keystore::load(&conn)?;
    // Apply idle-lock here too — if anyone polls status after the
    // idle window passed, we clear the session so the UI flips to
    // "locked" immediately rather than waiting for the next ticker.
    let mut guard = state.0.lock().expect("keystore lock poisoned");
    if let Some(sess) = guard.as_ref() {
        if sess.is_idle() {
            *guard = None;
        }
    }
    let (unlocked, unlocked_secs) = match guard.as_ref() {
        Some(sess) => (true, Some(sess.unlocked_at.elapsed().as_secs())),
        None => (false, None),
    };
    Ok(KeystoreStatus {
        initialized: rec.initialized,
        unlocked,
        version: rec.version,
        unlocked_secs,
    })
}

#[tauri::command]
pub fn init_keystore<R: Runtime>(
    handle: AppHandle<R>,
    passphrase: String,
) -> Result<(), CryptoError> {
    let conn = open_conn(&handle)?;
    keystore::init(&conn, &passphrase)?;
    Ok(())
}

#[tauri::command]
pub fn unlock_keystore<R: Runtime>(
    handle: AppHandle<R>,
    state: State<Arc<KeystoreState>>,
    passphrase: String,
) -> Result<KeystoreStatus, CryptoError> {
    let conn = open_conn(&handle)?;
    let (dek, version) = keystore::unlock(&conn, &passphrase)?;
    let mut guard = state.0.lock().expect("keystore lock poisoned");
    *guard = Some(SessionState {
        dek,
        version,
        unlocked_at: Instant::now(),
    });
    Ok(KeystoreStatus {
        initialized: true,
        unlocked: true,
        version,
        unlocked_secs: Some(0),
    })
}

#[tauri::command]
pub fn lock_keystore<R: Runtime>(
    handle: AppHandle<R>,
    state: State<Arc<KeystoreState>>,
) -> Result<(), CryptoError> {
    let mut guard = state.0.lock().expect("keystore lock poisoned");
    *guard = None;
    // Emit so other windows / the React context refresh immediately.
    let _ = handle.emit("keystore-locked", ());
    Ok(())
}

#[tauri::command]
pub fn change_passphrase<R: Runtime>(
    handle: AppHandle<R>,
    state: State<Arc<KeystoreState>>,
    old_passphrase: String,
    new_passphrase: String,
) -> Result<(), CryptoError> {
    let conn = open_conn(&handle)?;
    // Validate old by attempting an unlock (rate-limits a guesser).
    let (dek, _v) = keystore::unlock(&conn, &old_passphrase)?;
    keystore::change_passphrase(&conn, &dek, &new_passphrase)?;
    // Refresh the cached session so existing decryptions keep working
    // without a re-prompt.
    let mut guard = state.0.lock().expect("keystore lock poisoned");
    *guard = Some(SessionState {
        dek,
        version: keystore::load(&conn)?.version,
        unlocked_at: Instant::now(),
    });
    Ok(())
}

// ----- field-level encrypt / decrypt ------------------------------------------

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EncryptedField {
    pub ciphertext: String,
    pub dek_version: i32,
}

fn require_unlocked<'a>(
    state: &'a State<Arc<KeystoreState>>,
) -> Result<std::sync::MutexGuard<'a, Option<SessionState>>, CryptoError> {
    let guard = state.0.lock().expect("keystore lock poisoned");
    if guard.is_none() {
        return Err(CryptoError::Locked);
    }
    if guard.as_ref().map(|s| s.is_idle()).unwrap_or(false) {
        return Err(CryptoError::Locked);
    }
    Ok(guard)
}

#[tauri::command]
pub fn encrypt_field(
    state: State<Arc<KeystoreState>>,
    plaintext: String,
) -> Result<EncryptedField, CryptoError> {
    let guard = require_unlocked(&state)?;
    let session = guard.as_ref().unwrap();
    let ciphertext = wrap::encrypt_field(&session.dek, &plaintext)?;
    Ok(EncryptedField {
        ciphertext,
        dek_version: session.version,
    })
}

#[tauri::command]
pub fn decrypt_field(
    state: State<Arc<KeystoreState>>,
    ciphertext: String,
    dek_version: i32,
) -> Result<String, CryptoError> {
    let guard = require_unlocked(&state)?;
    let session = guard.as_ref().unwrap();
    if session.version != dek_version {
        // Caller has stale ciphertext written under a previous DEK
        // generation. We can't decrypt — surface a distinct error so
        // the UI can suggest "re-enter this password."
        return Err(CryptoError::DecryptionFailed);
    }
    wrap::decrypt_field(&session.dek, &ciphertext)
}

// ----- mnemonic export / import -----------------------------------------------

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MnemonicWords {
    pub words: Vec<String>,
}

#[tauri::command]
pub fn export_keystore_mnemonic(
    state: State<Arc<KeystoreState>>,
) -> Result<MnemonicWords, CryptoError> {
    let guard = require_unlocked(&state)?;
    let session = guard.as_ref().unwrap();
    Ok(MnemonicWords {
        words: mnemonic::dek_to_words(&session.dek)?,
    })
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportPayload {
    pub words: Vec<String>,
    pub new_passphrase: String,
}

#[tauri::command]
pub fn import_keystore_from_mnemonic<R: Runtime>(
    handle: AppHandle<R>,
    state: State<Arc<KeystoreState>>,
    payload: ImportPayload,
) -> Result<KeystoreStatus, CryptoError> {
    let conn = open_conn(&handle)?;
    let dek = mnemonic::words_to_dek(&payload.words)?;
    let new_version = keystore::import(&conn, &dek, &payload.new_passphrase)?;
    let mut guard = state.0.lock().expect("keystore lock poisoned");
    *guard = Some(SessionState {
        dek,
        version: new_version,
        unlocked_at: Instant::now(),
    });
    Ok(KeystoreStatus {
        initialized: true,
        unlocked: true,
        version: new_version,
        unlocked_secs: Some(0),
    })
}

// ----- wipe -------------------------------------------------------------------

#[tauri::command]
pub fn wipe_keystore<R: Runtime>(
    handle: AppHandle<R>,
    state: State<Arc<KeystoreState>>,
    also_wipe_data: bool,
) -> Result<(), CryptoError> {
    let conn = open_conn(&handle)?;
    keystore::wipe(&conn)?;
    let mut guard = state.0.lock().expect("keystore lock poisoned");
    *guard = None;
    if also_wipe_data {
        // Best-effort wipe of every column that currently holds
        // ciphertext keyed to this keystore. We deliberately leave
        // rows in place — only the encrypted bytes go.
        // (Phase 11 will add `sites.password_encrypted` etc. here.)
    }
    let _ = handle.emit("keystore-locked", ());
    Ok(())
}

// ----- background idle-checker ------------------------------------------------

/// Spawned from `lib.rs::run()::setup`. Polls every 60s; clears the
/// cached DEK if it's been idle past IDLE_LOCK_SECONDS.
pub async fn idle_check_loop<R: Runtime>(handle: AppHandle<R>) {
    let mut interval = tokio::time::interval(Duration::from_secs(60));
    interval.tick().await; // skip the immediate tick
    loop {
        interval.tick().await;
        let state: State<Arc<KeystoreState>> = match handle.try_state() {
            Some(s) => s,
            None => continue,
        };
        let was_locked = {
            let mut guard = state.0.lock().expect("keystore lock poisoned");
            if guard.as_ref().map(|s| s.is_idle()).unwrap_or(false) {
                *guard = None;
                true
            } else {
                false
            }
        };
        if was_locked {
            let _ = handle.emit("keystore-locked", ());
        }
    }
}
