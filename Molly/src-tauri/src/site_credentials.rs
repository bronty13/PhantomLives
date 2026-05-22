// Phase 11: site credentials (sub-credentials per site).
//
// Each `sites` row can have 1..N credential rows in `site_credentials`.
// Exactly one credential per site is `is_primary = 1`; the data layer
// enforces this invariant via single-transaction "clear then set"
// updates.
//
// The reveal path is the only place plaintext passwords cross the
// IPC boundary, and only TO the frontend (never back). The frontend
// uses the plaintext for clipboard-copy / temporary on-screen reveal
// and is responsible for clearing it. Setting a password takes
// plaintext FROM the frontend, encrypts it with the in-session DEK,
// stores the ciphertext.

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, Runtime, State};

use crate::crypto::commands as crypto_commands;
use crate::crypto::keystore::{KeystoreState, SessionState};
use crate::crypto::wrap;
use crate::crypto::CryptoError;

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

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SiteCredential {
    pub id: i64,
    pub site_id: i64,
    pub label: String,
    pub username: String,
    pub has_password: bool,
    pub password_dek_version: Option<i32>,
    pub password_updated_at: Option<String>,
    pub is_primary: bool,
    pub sort_order: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CredentialCreated {
    pub credential: SiteCredential,
}

// ----- Pure helpers (testable; take &Connection) -----------------------------

pub(crate) fn list_for_site(conn: &Connection, site_id: i64) -> Result<Vec<SiteCredential>, CryptoError> {
    let mut stmt = conn.prepare(
        "SELECT id, site_id, label, username,
                password_encrypted IS NOT NULL AS has_password,
                password_dek_version, password_updated_at,
                is_primary, sort_order
         FROM site_credentials
         WHERE site_id = ?1
         ORDER BY is_primary DESC, sort_order ASC, id ASC",
    )?;
    let rows = stmt
        .query_map(params![site_id], |r| {
            Ok(SiteCredential {
                id: r.get(0)?,
                site_id: r.get(1)?,
                label: r.get(2)?,
                username: r.get(3)?,
                has_password: r.get::<_, i64>(4)? != 0,
                password_dek_version: r.get(5)?,
                password_updated_at: r.get(6)?,
                is_primary: r.get::<_, i64>(7)? != 0,
                sort_order: r.get(8)?,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

pub(crate) fn pure_create(
    conn: &Connection,
    site_id: i64,
    label: &str,
) -> Result<SiteCredential, CryptoError> {
    // Check parent site exists (FK fires on INSERT but we want a
    // friendlier error here).
    let exists: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sites WHERE id = ?1",
            params![site_id],
            |r| r.get(0),
        )
        .unwrap_or(0);
    if exists == 0 {
        return Err(CryptoError::Db(format!("site {site_id} not found")));
    }
    // Next sort_order = current max + 1.
    let next_order: i64 = conn
        .query_row(
            "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM site_credentials WHERE site_id = ?1",
            params![site_id],
            |r| r.get(0),
        )
        .unwrap_or(0);
    conn.execute(
        "INSERT INTO site_credentials (site_id, label, sort_order) VALUES (?1, ?2, ?3)",
        params![site_id, label, next_order],
    )?;
    let id = conn.last_insert_rowid();
    let rows = list_for_site(conn, site_id)?;
    rows.into_iter()
        .find(|c| c.id == id)
        .ok_or_else(|| CryptoError::Internal("created credential not found".into()))
}

pub(crate) fn pure_update_username(
    conn: &mut Connection,
    cred_id: i64,
    new_username: &str,
) -> Result<(), CryptoError> {
    let tx = conn.transaction()?;
    // If this is the primary credential, also mirror to sites.username
    // so legacy read paths (Molly Helper's existing "Copy user") stay
    // correct without code changes.
    let (site_id, is_primary): (i64, i64) = tx.query_row(
        "SELECT site_id, is_primary FROM site_credentials WHERE id = ?1",
        params![cred_id],
        |r| Ok((r.get(0)?, r.get(1)?)),
    )?;
    tx.execute(
        "UPDATE site_credentials SET username = ?1, updated_at = datetime('now') WHERE id = ?2",
        params![new_username, cred_id],
    )?;
    if is_primary != 0 {
        tx.execute(
            "UPDATE sites SET username = ?1, updated_at = datetime('now') WHERE id = ?2",
            params![new_username, site_id],
        )?;
    }
    tx.commit()?;
    Ok(())
}

pub(crate) fn pure_update_label(
    conn: &Connection,
    cred_id: i64,
    new_label: &str,
) -> Result<(), CryptoError> {
    conn.execute(
        "UPDATE site_credentials SET label = ?1, updated_at = datetime('now') WHERE id = ?2",
        params![new_label, cred_id],
    )?;
    Ok(())
}

pub(crate) fn pure_set_password(
    conn: &Connection,
    cred_id: i64,
    ciphertext: &str,
    dek_version: i32,
) -> Result<(), CryptoError> {
    conn.execute(
        "UPDATE site_credentials
         SET password_encrypted = ?1, password_dek_version = ?2,
             password_updated_at = datetime('now'), updated_at = datetime('now')
         WHERE id = ?3",
        params![ciphertext, dek_version, cred_id],
    )?;
    Ok(())
}

pub(crate) fn pure_clear_password(
    conn: &Connection,
    cred_id: i64,
) -> Result<(), CryptoError> {
    conn.execute(
        "UPDATE site_credentials
         SET password_encrypted = NULL, password_dek_version = NULL,
             password_updated_at = NULL, updated_at = datetime('now')
         WHERE id = ?1",
        params![cred_id],
    )?;
    Ok(())
}

pub(crate) fn pure_set_primary(
    conn: &mut Connection,
    cred_id: i64,
) -> Result<(), CryptoError> {
    let tx = conn.transaction()?;
    let site_id: i64 = tx.query_row(
        "SELECT site_id FROM site_credentials WHERE id = ?1",
        params![cred_id],
        |r| r.get(0),
    )?;
    // Clear primary on every credential for this site, then set on the target.
    tx.execute(
        "UPDATE site_credentials SET is_primary = 0 WHERE site_id = ?1",
        params![site_id],
    )?;
    tx.execute(
        "UPDATE site_credentials SET is_primary = 1, updated_at = datetime('now') WHERE id = ?1",
        params![cred_id],
    )?;
    // Mirror the new primary's username to sites.username for legacy compat.
    let username: String = tx.query_row(
        "SELECT username FROM site_credentials WHERE id = ?1",
        params![cred_id],
        |r| r.get(0),
    )?;
    tx.execute(
        "UPDATE sites SET username = ?1, updated_at = datetime('now') WHERE id = ?2",
        params![username, site_id],
    )?;
    tx.commit()?;
    Ok(())
}

pub(crate) fn pure_delete(conn: &Connection, cred_id: i64) -> Result<(), CryptoError> {
    // Refuse to delete the last credential — that would orphan
    // sites.username and break backwards-compat paths.
    let site_id: i64 = conn.query_row(
        "SELECT site_id FROM site_credentials WHERE id = ?1",
        params![cred_id],
        |r| r.get(0),
    )?;
    let count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM site_credentials WHERE site_id = ?1",
        params![site_id],
        |r| r.get(0),
    )?;
    if count <= 1 {
        return Err(CryptoError::Db(
            "cannot delete the last credential on a site".into(),
        ));
    }
    conn.execute(
        "DELETE FROM site_credentials WHERE id = ?1",
        params![cred_id],
    )?;
    Ok(())
}

// ----- Tauri commands --------------------------------------------------------

#[tauri::command]
pub fn list_site_credentials<R: Runtime>(
    handle: AppHandle<R>,
    site_id: i64,
) -> Result<Vec<SiteCredential>, CryptoError> {
    let conn = open_conn(&handle)?;
    list_for_site(&conn, site_id)
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateCredentialPayload {
    pub site_id: i64,
    pub label: String,
}

#[tauri::command]
pub fn create_site_credential<R: Runtime>(
    handle: AppHandle<R>,
    payload: CreateCredentialPayload,
) -> Result<SiteCredential, CryptoError> {
    let conn = open_conn(&handle)?;
    pure_create(&conn, payload.site_id, &payload.label)
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateUsernamePayload {
    pub credential_id: i64,
    pub username: String,
}

#[tauri::command]
pub fn update_credential_username<R: Runtime>(
    handle: AppHandle<R>,
    payload: UpdateUsernamePayload,
) -> Result<(), CryptoError> {
    let mut conn = open_conn(&handle)?;
    pure_update_username(&mut conn, payload.credential_id, &payload.username)
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateLabelPayload {
    pub credential_id: i64,
    pub label: String,
}

#[tauri::command]
pub fn update_credential_label<R: Runtime>(
    handle: AppHandle<R>,
    payload: UpdateLabelPayload,
) -> Result<(), CryptoError> {
    let conn = open_conn(&handle)?;
    pure_update_label(&conn, payload.credential_id, &payload.label)
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SetPasswordPayload {
    pub credential_id: i64,
    pub plaintext: String,
}

#[tauri::command]
pub fn set_credential_password<R: Runtime>(
    handle: AppHandle<R>,
    state: State<Arc<KeystoreState>>,
    payload: SetPasswordPayload,
) -> Result<(), CryptoError> {
    // Borrow the in-session DEK to encrypt server-side. We never send
    // the wrapped DEK out of Rust.
    let guard = state.0.lock().expect("keystore lock poisoned");
    let session: &SessionState = guard.as_ref().ok_or(CryptoError::Locked)?;
    if session.is_idle() {
        return Err(CryptoError::Locked);
    }
    let ciphertext = wrap::encrypt_field(&session.dek, &payload.plaintext)?;
    let dek_version = session.version;
    drop(guard);
    let conn = open_conn(&handle)?;
    pure_set_password(&conn, payload.credential_id, &ciphertext, dek_version)
}

#[tauri::command]
pub fn clear_credential_password<R: Runtime>(
    handle: AppHandle<R>,
    credential_id: i64,
) -> Result<(), CryptoError> {
    let conn = open_conn(&handle)?;
    pure_clear_password(&conn, credential_id)
}

#[tauri::command]
pub fn reveal_credential_password<R: Runtime>(
    handle: AppHandle<R>,
    state: State<Arc<KeystoreState>>,
    credential_id: i64,
) -> Result<String, CryptoError> {
    let guard = state.0.lock().expect("keystore lock poisoned");
    let session: &SessionState = guard.as_ref().ok_or(CryptoError::Locked)?;
    if session.is_idle() {
        return Err(CryptoError::Locked);
    }
    let conn = open_conn(&handle)?;
    let row: (Option<String>, Option<i32>) = conn.query_row(
        "SELECT password_encrypted, password_dek_version
         FROM site_credentials WHERE id = ?1",
        params![credential_id],
        |r| Ok((r.get(0)?, r.get(1)?)),
    )?;
    let ciphertext = row.0.ok_or_else(|| CryptoError::Db("no password set".into()))?;
    let version = row.1.unwrap_or(session.version);
    if version != session.version {
        // Different DEK generation — surface as DecryptionFailed so the
        // UI can prompt "re-enter this password."
        return Err(CryptoError::DecryptionFailed);
    }
    wrap::decrypt_field(&session.dek, &ciphertext)
}

#[tauri::command]
pub fn set_credential_primary<R: Runtime>(
    handle: AppHandle<R>,
    credential_id: i64,
) -> Result<(), CryptoError> {
    let mut conn = open_conn(&handle)?;
    pure_set_primary(&mut conn, credential_id)
}

#[tauri::command]
pub fn delete_site_credential<R: Runtime>(
    handle: AppHandle<R>,
    credential_id: i64,
) -> Result<(), CryptoError> {
    let conn = open_conn(&handle)?;
    pure_delete(&conn, credential_id)
}

// Suppress unused warning — `crypto_commands` is imported only so the
// module compiles cleanly against the public surface (and so any future
// helper added here can reach for a Tauri command directly).
#[allow(dead_code)]
fn _ensure_crypto_link() {
    let _ = crypto_commands::keystore_status::<tauri::Wry>;
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_db_with_sites() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch("PRAGMA foreign_keys = ON;").unwrap();
        for sql in [
            include_str!("../migrations/001_init.sql"),
            include_str!("../migrations/002_sites.sql"),
            include_str!("../migrations/003_taxonomy.sql"),
            include_str!("../migrations/004_customers.sql"),
            include_str!("../migrations/005_clips.sql"),
            include_str!("../migrations/006_schedules.sql"),
            include_str!("../migrations/007_income.sql"),
            include_str!("../migrations/008_expenses.sql"),
            include_str!("../migrations/009_social.sql"),
            include_str!("../migrations/010_kinks.sql"),
            include_str!("../migrations/011_kinks_preload.sql"),
            include_str!("../migrations/012_products_and_customer_fields.sql"),
            include_str!("../migrations/013_customer_history.sql"),
            include_str!("../migrations/014_customer_sales.sql"),
            include_str!("../migrations/015_mollys_log.sql"),
            include_str!("../migrations/016_c4s_clips.sql"),
            include_str!("../migrations/017_bundles.sql"),
            include_str!("../migrations/018_crypto_keystore.sql"),
            include_str!("../migrations/019_site_credentials.sql"),
        ] {
            conn.execute_batch(sql).unwrap();
        }
        conn
    }

    fn insert_site(conn: &Connection, name: &str, username: &str) -> i64 {
        conn.execute(
            "INSERT INTO personas (code, display_name) VALUES ('CoC', 'CoC')",
            [],
        )
        .ok(); // ignore "already exists"
        conn.execute(
            "INSERT INTO sites (persona_code, name, short_code, url, username, note, color, sort_order)
             VALUES ('CoC', ?1, ?2, '', ?3, '', '#fff', 0)",
            params![name, name.to_lowercase(), username],
        )
        .unwrap();
        let id = conn.last_insert_rowid();
        // Backfill 019 only fires on initial migration; manually seed
        // a primary credential for this site to match production INSERT path.
        conn.execute(
            "INSERT INTO site_credentials (site_id, label, username, is_primary, sort_order)
             VALUES (?1, 'default', ?2, 1, 0)",
            params![id, username],
        )
        .unwrap();
        id
    }

    #[test]
    fn backfill_creates_one_primary_per_site() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch("PRAGMA foreign_keys = ON;").unwrap();
        // Apply migrations 001-018 only; insert 5 sites; then 019.
        for sql in [
            include_str!("../migrations/001_init.sql"),
            include_str!("../migrations/002_sites.sql"),
        ] {
            conn.execute_batch(sql).unwrap();
        }
        conn.execute(
            "INSERT INTO personas (code, display_name) VALUES ('CoC', 'CoC')",
            [],
        )
        .ok();
        for i in 0..5 {
            conn.execute(
                "INSERT INTO sites (persona_code, name, short_code, url, username, note, color, sort_order)
                 VALUES ('CoC', ?1, ?2, '', 'sallie', '', '#fff', 0)",
                params![format!("site{i}"), format!("s{i}")],
            )
            .unwrap();
        }
        // Now run the rest of the migrations (skipping the FK-dependent ones we don't need for this isolated test).
        for sql in [
            include_str!("../migrations/003_taxonomy.sql"),
            include_str!("../migrations/004_customers.sql"),
            include_str!("../migrations/005_clips.sql"),
            include_str!("../migrations/006_schedules.sql"),
            include_str!("../migrations/007_income.sql"),
            include_str!("../migrations/008_expenses.sql"),
            include_str!("../migrations/009_social.sql"),
            include_str!("../migrations/010_kinks.sql"),
            include_str!("../migrations/011_kinks_preload.sql"),
            include_str!("../migrations/012_products_and_customer_fields.sql"),
            include_str!("../migrations/013_customer_history.sql"),
            include_str!("../migrations/014_customer_sales.sql"),
            include_str!("../migrations/015_mollys_log.sql"),
            include_str!("../migrations/016_c4s_clips.sql"),
            include_str!("../migrations/017_bundles.sql"),
            include_str!("../migrations/018_crypto_keystore.sql"),
            include_str!("../migrations/019_site_credentials.sql"),
        ] {
            conn.execute_batch(sql).unwrap();
        }
        // Migration 002 also seeds Sallie's known sites, so the
        // actual count exceeds the 5 we added here. What matters is
        // that EVERY site gets exactly one primary credential.
        let creds: i64 = conn
            .query_row("SELECT COUNT(*) FROM site_credentials", [], |r| r.get(0))
            .unwrap();
        let sites: i64 = conn
            .query_row("SELECT COUNT(*) FROM sites", [], |r| r.get(0))
            .unwrap();
        assert!(sites >= 5, "expected at least our 5 inserted sites, got {sites}");
        assert_eq!(creds, sites, "every site should get exactly one credential row");
        let primary_count: i64 = conn
            .query_row("SELECT COUNT(*) FROM site_credentials WHERE is_primary = 1", [], |r| r.get(0))
            .unwrap();
        assert_eq!(primary_count, sites, "every site should have exactly one primary credential");
    }

    #[test]
    fn create_then_list() {
        let conn = fresh_db_with_sites();
        let site_id = insert_site(&conn, "MySite", "alice");
        let new_cred = pure_create(&conn, site_id, "backup login").unwrap();
        assert_eq!(new_cred.label, "backup login");
        assert!(!new_cred.is_primary);
        let creds = list_for_site(&conn, site_id).unwrap();
        assert_eq!(creds.len(), 2);
        // Primary sorts first.
        assert!(creds[0].is_primary);
        assert!(!creds[1].is_primary);
    }

    #[test]
    fn set_password_then_clear() {
        let conn = fresh_db_with_sites();
        let site_id = insert_site(&conn, "MySite", "alice");
        let creds = list_for_site(&conn, site_id).unwrap();
        let cred_id = creds[0].id;
        pure_set_password(&conn, cred_id, "ciphertext-blob", 1).unwrap();
        let reloaded = list_for_site(&conn, site_id).unwrap();
        assert!(reloaded[0].has_password);
        assert_eq!(reloaded[0].password_dek_version, Some(1));
        pure_clear_password(&conn, cred_id).unwrap();
        let final_state = list_for_site(&conn, site_id).unwrap();
        assert!(!final_state[0].has_password);
    }

    #[test]
    fn set_primary_clears_others_and_mirrors_username() {
        let mut conn = fresh_db_with_sites();
        let site_id = insert_site(&conn, "MySite", "alice");
        let new_cred = pure_create(&conn, site_id, "backup").unwrap();
        // Set the new (non-primary) cred's username, then promote it.
        pure_update_username(&mut conn, new_cred.id, "alice_alt").unwrap();
        pure_set_primary(&mut conn, new_cred.id).unwrap();
        let creds = list_for_site(&conn, site_id).unwrap();
        let primary = creds.iter().find(|c| c.is_primary).unwrap();
        assert_eq!(primary.id, new_cred.id);
        // Legacy sites.username should mirror the new primary's username.
        let sites_username: String = conn
            .query_row(
                "SELECT username FROM sites WHERE id = ?1",
                params![site_id],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(sites_username, "alice_alt");
        // Exactly one primary.
        let primary_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM site_credentials WHERE site_id = ?1 AND is_primary = 1",
                params![site_id],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(primary_count, 1);
    }

    #[test]
    fn update_primary_username_syncs_sites_username() {
        let mut conn = fresh_db_with_sites();
        let site_id = insert_site(&conn, "MySite", "alice");
        let creds = list_for_site(&conn, site_id).unwrap();
        let primary_id = creds[0].id;
        pure_update_username(&mut conn, primary_id, "alice_v2").unwrap();
        let sites_username: String = conn
            .query_row(
                "SELECT username FROM sites WHERE id = ?1",
                params![site_id],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(sites_username, "alice_v2");
    }

    #[test]
    fn update_secondary_username_does_not_touch_sites_username() {
        let mut conn = fresh_db_with_sites();
        let site_id = insert_site(&conn, "MySite", "alice");
        let new_cred = pure_create(&conn, site_id, "backup").unwrap();
        pure_update_username(&mut conn, new_cred.id, "alice_alt").unwrap();
        // The primary's username (sites.username) stays put.
        let sites_username: String = conn
            .query_row(
                "SELECT username FROM sites WHERE id = ?1",
                params![site_id],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(sites_username, "alice");
    }

    #[test]
    fn cannot_delete_last_credential() {
        let conn = fresh_db_with_sites();
        let site_id = insert_site(&conn, "MySite", "alice");
        let creds = list_for_site(&conn, site_id).unwrap();
        let err = pure_delete(&conn, creds[0].id).unwrap_err();
        assert!(matches!(err, CryptoError::Db(_)));
    }

    #[test]
    fn delete_works_when_more_than_one_exists() {
        let conn = fresh_db_with_sites();
        let site_id = insert_site(&conn, "MySite", "alice");
        let new_cred = pure_create(&conn, site_id, "backup").unwrap();
        pure_delete(&conn, new_cred.id).unwrap();
        let creds = list_for_site(&conn, site_id).unwrap();
        assert_eq!(creds.len(), 1);
    }

    #[test]
    fn deleting_site_cascades_credentials() {
        let conn = fresh_db_with_sites();
        let site_id = insert_site(&conn, "MySite", "alice");
        pure_create(&conn, site_id, "backup").unwrap();
        assert_eq!(list_for_site(&conn, site_id).unwrap().len(), 2);
        conn.execute("DELETE FROM sites WHERE id = ?1", params![site_id]).unwrap();
        assert_eq!(list_for_site(&conn, site_id).unwrap().len(), 0);
    }
}
