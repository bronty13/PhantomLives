// Phase — per-persona intro / outro clips (YouTube master assembly).
//
// Sallie uploads one intro and/or one outro video per persona; each is
// independently enable/disable-able and defaults OFF. When a YouTube
// bundle is auto-assembled, `auto_assemble::enqueue_auto_assemble` calls
// `enabled_clip_path` to fetch the active intro/outro and bookends the
// master with them (the intro replaces the generated title card).
//
// The uploaded video is copied to ~/Downloads/SideMolly/persona-clips/
// (sibling of work/, kept out of the App-Support launch-backup zip). Only
// the path + enabled flag live in the DB (table `persona_clips`, keyed by
// (persona_code, role)). '' is the no-persona default, matching the
// Watermark settings convention.

use std::fs;
use std::path::{Path, PathBuf};

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, Runtime};

use crate::bundles::BundleError;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PersonaClipRow {
    pub persona_code: String,
    /// "intro" | "outro".
    pub role: String,
    /// Absolute path of the copied clip on disk; "" when none uploaded.
    pub clip_path: String,
    pub enabled: bool,
    pub updated_at: String,
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn open_conn<R: Runtime>(handle: &AppHandle<R>) -> Result<Connection, BundleError> {
    let dir = handle
        .path()
        .resolve("", tauri::path::BaseDirectory::AppLocalData)
        .map_err(|e| BundleError::Io(std::io::Error::other(format!("appdata path: {e}"))))?;
    Ok(Connection::open(dir.join("sidemolly.db"))?)
}

/// Directory holding uploaded intro/outro clips. Sibling of work/, under
/// ~/Downloads/SideMolly/ — reachable in Finder and excluded from the
/// App-Support launch-backup zip (same rationale as `bundles::work_root`).
fn clips_dir() -> PathBuf {
    crate::fsutil::downloads_subdir("SideMolly").join("persona-clips")
}

fn validate_role(role: &str) -> Result<(), BundleError> {
    match role {
        "intro" | "outro" => Ok(()),
        _ => Err(BundleError::NotFound(format!(
            "invalid persona-clip role {role:?} (expected 'intro' or 'outro')"
        ))),
    }
}

/// Filesystem-safe stem for a persona code ('' → "default").
fn persona_slug(persona_code: &str) -> String {
    if persona_code.trim().is_empty() {
        "default".to_string()
    } else {
        persona_code
            .chars()
            .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
            .collect()
    }
}

/// The active clip path for a persona+role: returns the path only when the
/// row is enabled AND the file still exists on disk. Used by the assembly
/// pipeline. `None` for any other state (disabled, never uploaded, file
/// gone), which the caller treats as "no intro/outro".
pub fn enabled_clip_path(
    conn: &Connection,
    persona_code: Option<&str>,
    role: &str,
) -> rusqlite::Result<Option<String>> {
    let persona = persona_code.unwrap_or("");
    let path: Option<String> = conn
        .query_row(
            "SELECT clip_path FROM persona_clips
              WHERE persona_code = ?1 AND role = ?2 AND enabled = 1",
            params![persona, role],
            |r| r.get(0),
        )
        .optional()?;
    Ok(path.filter(|p| !p.is_empty() && Path::new(p).exists()))
}

fn fetch_row(conn: &Connection, persona: &str, role: &str) -> Result<PersonaClipRow, BundleError> {
    conn.query_row(
        "SELECT persona_code, role, clip_path, enabled, updated_at
           FROM persona_clips WHERE persona_code = ?1 AND role = ?2",
        params![persona, role],
        |r| {
            Ok(PersonaClipRow {
                persona_code: r.get(0)?,
                role: r.get(1)?,
                clip_path: r.get(2)?,
                enabled: r.get::<_, i64>(3)? != 0,
                updated_at: r.get(4)?,
            })
        },
    )
    .map_err(BundleError::from)
}

// ---------------------------------------------------------------------------
// Tauri commands
// ---------------------------------------------------------------------------

#[tauri::command]
pub fn list_persona_clips<R: Runtime>(
    handle: AppHandle<R>,
) -> Result<Vec<PersonaClipRow>, BundleError> {
    let conn = open_conn(&handle)?;
    let mut stmt = conn.prepare(
        "SELECT persona_code, role, clip_path, enabled, updated_at
           FROM persona_clips ORDER BY persona_code, role",
    )?;
    let rows = stmt
        .query_map([], |r| {
            Ok(PersonaClipRow {
                persona_code: r.get(0)?,
                role: r.get(1)?,
                clip_path: r.get(2)?,
                enabled: r.get::<_, i64>(3)? != 0,
                updated_at: r.get(4)?,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

/// Copy a chosen video into the persona-clips dir and record its path.
/// Upload alone does NOT enable the clip (per spec — Sallie turns it on
/// separately); the `enabled` flag is preserved (defaults to 0 for a new
/// row).
#[tauri::command]
pub fn upload_persona_clip<R: Runtime>(
    handle: AppHandle<R>,
    persona_code: String,
    role: String,
    source_path: String,
) -> Result<PersonaClipRow, BundleError> {
    validate_role(&role)?;
    let src = Path::new(&source_path);
    if !src.is_file() {
        return Err(BundleError::NotFound(format!(
            "source clip not found: {source_path}"
        )));
    }

    let dir = clips_dir();
    fs::create_dir_all(&dir)?;
    let ext = src
        .extension()
        .and_then(|e| e.to_str())
        .filter(|e| !e.is_empty())
        .unwrap_or("mp4");
    let dest = dir.join(format!("{}_{}.{ext}", persona_slug(&persona_code), role));
    // Stable name per (persona, role): overwrite any previous upload.
    if dest.exists() {
        fs::remove_file(&dest)?;
    }
    fs::copy(src, &dest)?;
    let dest_str = dest.to_string_lossy().to_string();

    let conn = open_conn(&handle)?;
    conn.execute(
        "INSERT INTO persona_clips (persona_code, role, clip_path, enabled, updated_at)
         VALUES (?1, ?2, ?3, 0, datetime('now'))
         ON CONFLICT(persona_code, role) DO UPDATE SET
             clip_path  = excluded.clip_path,
             updated_at = datetime('now')",
        params![persona_code, role, dest_str],
    )?;
    fetch_row(&conn, &persona_code, &role)
}

#[tauri::command]
pub fn set_persona_clip_enabled<R: Runtime>(
    handle: AppHandle<R>,
    persona_code: String,
    role: String,
    enabled: bool,
) -> Result<PersonaClipRow, BundleError> {
    validate_role(&role)?;
    let conn = open_conn(&handle)?;
    // Upsert so toggling a never-uploaded row is harmless (stays path-empty).
    conn.execute(
        "INSERT INTO persona_clips (persona_code, role, clip_path, enabled, updated_at)
         VALUES (?1, ?2, '', ?3, datetime('now'))
         ON CONFLICT(persona_code, role) DO UPDATE SET
             enabled    = excluded.enabled,
             updated_at = datetime('now')",
        params![persona_code, role, if enabled { 1 } else { 0 }],
    )?;
    fetch_row(&conn, &persona_code, &role)
}

/// Remove a persona's clip: delete the file and clear the row (path → '',
/// enabled → 0).
#[tauri::command]
pub fn clear_persona_clip<R: Runtime>(
    handle: AppHandle<R>,
    persona_code: String,
    role: String,
) -> Result<(), BundleError> {
    validate_role(&role)?;
    let conn = open_conn(&handle)?;
    if let Some(p) = conn
        .query_row(
            "SELECT clip_path FROM persona_clips WHERE persona_code = ?1 AND role = ?2",
            params![persona_code, role],
            |r| r.get::<_, String>(0),
        )
        .optional()?
    {
        if !p.is_empty() {
            let _ = fs::remove_file(&p);
        }
    }
    conn.execute(
        "UPDATE persona_clips SET clip_path = '', enabled = 0, updated_at = datetime('now')
          WHERE persona_code = ?1 AND role = ?2",
        params![persona_code, role],
    )?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn db() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(include_str!("../migrations/019_persona_clips.sql"))
            .unwrap();
        conn
    }

    #[test]
    fn enabled_clip_path_requires_enabled_and_existing_file() {
        let conn = db();
        let dir = tempfile::TempDir::new().unwrap();
        let clip = dir.path().join("intro.mp4");
        std::fs::write(&clip, b"x").unwrap();
        let path = clip.to_string_lossy().to_string();

        // Uploaded but disabled → None.
        conn.execute(
            "INSERT INTO persona_clips (persona_code, role, clip_path, enabled)
             VALUES ('CoC','intro', ?1, 0)",
            params![path],
        )
        .unwrap();
        assert_eq!(enabled_clip_path(&conn, Some("CoC"), "intro").unwrap(), None);

        // Enabled + file present → Some(path).
        conn.execute(
            "UPDATE persona_clips SET enabled = 1 WHERE persona_code='CoC' AND role='intro'",
            [],
        )
        .unwrap();
        assert_eq!(
            enabled_clip_path(&conn, Some("CoC"), "intro").unwrap(),
            Some(path.clone())
        );

        // Enabled but file gone → None.
        std::fs::remove_file(&clip).unwrap();
        assert_eq!(enabled_clip_path(&conn, Some("CoC"), "intro").unwrap(), None);

        // Unknown persona → None.
        assert_eq!(enabled_clip_path(&conn, Some("PoA"), "intro").unwrap(), None);
        // None persona maps to '' default.
        assert_eq!(enabled_clip_path(&conn, None, "outro").unwrap(), None);
    }

    #[test]
    fn role_check_rejects_bad_role() {
        let conn = db();
        let bad = conn.execute(
            "INSERT INTO persona_clips (persona_code, role) VALUES ('CoC','sidebar')",
            [],
        );
        assert!(bad.is_err(), "CHECK should reject role 'sidebar'");
    }

    #[test]
    fn persona_slug_is_filesystem_safe() {
        assert_eq!(persona_slug(""), "default");
        assert_eq!(persona_slug("CoC"), "CoC");
        assert_eq!(persona_slug("a/b c"), "a-b-c");
    }
}
