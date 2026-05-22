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
use super::keychain;
use super::keystore::{self, KeystoreState, KeystoreStatus, SessionState};
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
    // idle window passed AND stay_unlocked is OFF, we clear the
    // session so the UI flips to "locked" immediately. With
    // stay_unlocked ON, idle never closes the session.
    let mut guard = state.0.lock().expect("keystore lock poisoned");
    if !rec.stay_unlocked {
        if let Some(sess) = guard.as_ref() {
            if sess.is_idle() {
                *guard = None;
            }
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
        stay_unlocked: rec.stay_unlocked,
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
    let rec = keystore::load(&conn)?;
    // Persist to keychain so the next launch auto-unlocks. Keychain
    // failures are logged but not fatal — the unlock itself succeeded.
    if rec.stay_unlocked {
        if let Err(e) = keychain::save(&dek, version) {
            eprintln!("[molly] keychain save failed (continuing): {e}");
        }
    }
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
        stay_unlocked: rec.stay_unlocked,
    })
}

#[tauri::command]
pub fn lock_keystore<R: Runtime>(
    handle: AppHandle<R>,
    state: State<Arc<KeystoreState>>,
) -> Result<(), CryptoError> {
    let mut guard = state.0.lock().expect("keystore lock poisoned");
    *guard = None;
    // Manual lock means "next time, ask for the passphrase." Always
    // clear the keychain entry; if the user re-enables stay_unlocked
    // after the next manual unlock, we'll re-save it then.
    let _ = keychain::clear();
    // Emit so other windows / the React context refresh immediately.
    let _ = handle.emit("keystore-locked", ());
    Ok(())
}

#[tauri::command]
pub fn set_keystore_stay_unlocked<R: Runtime>(
    handle: AppHandle<R>,
    state: State<Arc<KeystoreState>>,
    enabled: bool,
) -> Result<KeystoreStatus, CryptoError> {
    let conn = open_conn(&handle)?;
    keystore::set_stay_unlocked(&conn, enabled)?;
    let rec = keystore::load(&conn)?;
    let guard = state.0.lock().expect("keystore lock poisoned");
    if enabled {
        if let Some(sess) = guard.as_ref() {
            if let Err(e) = keychain::save(&sess.dek, sess.version) {
                eprintln!("[molly] keychain save on opt-in failed: {e}");
            }
        }
    } else {
        let _ = keychain::clear();
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
        stay_unlocked: rec.stay_unlocked,
    })
}

/// Called once at app launch from `lib.rs::setup`. If stay_unlocked is
/// on and the keychain has a matching DEK for the current dek_version,
/// hydrate the in-memory session so the user lands in Molly already
/// unlocked. Silently no-ops on any mismatch / read failure.
pub fn try_restore_from_keychain<R: Runtime>(handle: &AppHandle<R>) {
    let conn = match open_conn(handle) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("[molly] launch keychain restore: open_conn failed: {e}");
            return;
        }
    };
    let rec = match keystore::load(&conn) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("[molly] launch keychain restore: load failed: {e}");
            return;
        }
    };
    if !rec.initialized || !rec.stay_unlocked {
        return;
    }
    let (dek, kc_version) = match keychain::load() {
        Ok(Some(pair)) => pair,
        Ok(None) => return,
        Err(e) => {
            eprintln!("[molly] launch keychain restore: read failed: {e}");
            return;
        }
    };
    if kc_version != rec.version {
        // Stale entry — keystore was re-imported / wiped on this
        // install since the keychain was written. Discard and force a
        // passphrase prompt.
        let _ = keychain::clear();
        return;
    }
    let state: State<Arc<KeystoreState>> = match handle.try_state() {
        Some(s) => s,
        None => return,
    };
    let mut guard = state.0.lock().expect("keystore lock poisoned");
    *guard = Some(SessionState {
        dek,
        version: kc_version,
        unlocked_at: Instant::now(),
    });
    let _ = handle.emit("keystore-unlocked", ());
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
    let rec = keystore::load(&conn)?;
    // Refresh the cached session so existing decryptions keep working
    // without a re-prompt.
    let mut guard = state.0.lock().expect("keystore lock poisoned");
    *guard = Some(SessionState {
        dek: dek.clone(),
        version: rec.version,
        unlocked_at: Instant::now(),
    });
    drop(guard);
    // Re-write keychain with the (unchanged) DEK so it stays in sync.
    if rec.stay_unlocked {
        let _ = keychain::save(&dek, rec.version);
    }
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
    let rec = keystore::load(&conn)?;
    let mut guard = state.0.lock().expect("keystore lock poisoned");
    *guard = Some(SessionState {
        dek: dek.clone(),
        version: new_version,
        unlocked_at: Instant::now(),
    });
    drop(guard);
    // Import bumps the dek_version, so any stale keychain entry for
    // the previous version is now wrong — wipe it. If the user has
    // stay_unlocked on, write the new DEK so the next launch works.
    if rec.stay_unlocked {
        let _ = keychain::save(&dek, new_version);
    } else {
        let _ = keychain::clear();
    }
    Ok(KeystoreStatus {
        initialized: true,
        unlocked: true,
        version: new_version,
        unlocked_secs: Some(0),
        stay_unlocked: rec.stay_unlocked,
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
    // Also reset the stay_unlocked flag — a wipe is a "back to zero"
    // operation; we shouldn't silently re-arm autounlock after the
    // user sets up a fresh keystore.
    let _ = keystore::set_stay_unlocked(&conn, false);
    let mut guard = state.0.lock().expect("keystore lock poisoned");
    *guard = None;
    let _ = keychain::clear();
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
/// cached DEK if it's been idle past IDLE_LOCK_SECONDS — but ONLY
/// when stay_unlocked is OFF. With stay_unlocked ON, the idle check
/// is a no-op and the session persists until manual lock.
pub async fn idle_check_loop<R: Runtime>(handle: AppHandle<R>) {
    let mut interval = tokio::time::interval(Duration::from_secs(60));
    interval.tick().await; // skip the immediate tick
    loop {
        interval.tick().await;
        // Check stay_unlocked fresh each tick — the user may flip the
        // setting at any time, and we don't want to require a relaunch
        // for it to take effect.
        let stay_unlocked = open_conn(&handle)
            .and_then(|c| keystore::load(&c))
            .map(|r| r.stay_unlocked)
            .unwrap_or(false);
        if stay_unlocked {
            continue;
        }
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
