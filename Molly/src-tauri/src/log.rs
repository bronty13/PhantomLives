use rusqlite::{params, Connection};
use serde::Serialize;
use std::fs;
use std::path::PathBuf;
use std::time::Duration;
use tauri::{AppHandle, Manager, Runtime};

// Mirrors history.rs but writes to the `mollys_log` table (global journal
// — no customer FK, no persona binding). Kept in a parallel module
// rather than parameterizing history.rs because the SQL is shorter to
// read alongside its data layer than as a generic dispatch.

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LogEntryRef {
    pub id: i64,
}

fn db_path<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, String> {
    handle
        .path()
        .app_data_dir()
        .map(|p| p.join("molly.db"))
        .map_err(|e| format!("app_data_dir: {e}"))
}

fn open_conn<R: Runtime>(handle: &AppHandle<R>) -> Result<Connection, String> {
    let path = db_path(handle)?;
    let conn = Connection::open(&path).map_err(|e| format!("open {}: {e}", path.display()))?;
    conn.busy_timeout(Duration::from_secs(5))
        .map_err(|e| format!("busy_timeout: {e}"))?;
    Ok(conn)
}

fn guess_mime(filename: &str) -> String {
    let lower = filename.to_lowercase();
    let ext = lower.rsplit('.').next().unwrap_or("");
    match ext {
        "png"             => "image/png".into(),
        "jpg" | "jpeg"    => "image/jpeg".into(),
        "gif"             => "image/gif".into(),
        "webp"            => "image/webp".into(),
        "heic" | "heif"   => "image/heic".into(),
        "bmp"             => "image/bmp".into(),
        "tiff" | "tif"    => "image/tiff".into(),
        "pdf"             => "application/pdf".into(),
        "txt" | "log"     => "text/plain".into(),
        "md" | "markdown" => "text/markdown".into(),
        "csv"             => "text/csv".into(),
        "json"            => "application/json".into(),
        "mp4"             => "video/mp4".into(),
        "mov"             => "video/quicktime".into(),
        "mp3"             => "audio/mpeg".into(),
        "m4a"             => "audio/mp4".into(),
        "wav"             => "audio/wav".into(),
        "zip"             => "application/zip".into(),
        _                 => "application/octet-stream".into(),
    }
}

// ---------- Pure SQL helpers (testable) ----------------------------------

pub fn insert_log_row(
    conn: &Connection,
    body: &str,
    filename: &str,
    mime: &str,
    bytes: &[u8],
) -> rusqlite::Result<i64> {
    conn.execute(
        "INSERT INTO mollys_log
            (body, attachment_filename, attachment_mime, attachment_size, attachment_data)
         VALUES (?1, ?2, ?3, ?4, ?5)",
        params![body, filename, mime, bytes.len() as i64, bytes],
    )?;
    Ok(conn.last_insert_rowid())
}

pub fn read_log_blob(conn: &Connection, log_id: i64) -> rusqlite::Result<Vec<u8>> {
    conn.query_row(
        "SELECT attachment_data FROM mollys_log WHERE id = ?1",
        params![log_id],
        |row| row.get::<_, Vec<u8>>(0),
    )
}

#[tauri::command]
pub fn add_log_entry_with_attachment<R: Runtime>(
    handle: AppHandle<R>,
    body: String,
    src_path: String,
) -> Result<LogEntryRef, String> {
    let bytes = fs::read(&src_path).map_err(|e| format!("read {src_path}: {e}"))?;
    let filename = PathBuf::from(&src_path)
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_default();
    let mime = guess_mime(&filename);

    let conn = open_conn(&handle)?;
    let id = insert_log_row(&conn, &body, &filename, &mime, &bytes)
        .map_err(|e| format!("insert: {e}"))?;
    Ok(LogEntryRef { id })
}

#[tauri::command]
pub fn download_log_attachment<R: Runtime>(
    handle: AppHandle<R>,
    log_id: i64,
    target_path: String,
) -> Result<(), String> {
    let conn = open_conn(&handle)?;
    let bytes = read_log_blob(&conn, log_id)
        .map_err(|e| format!("read row {log_id}: {e}"))?;
    fs::write(&target_path, &bytes).map_err(|e| format!("write {target_path}: {e}"))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;

    fn fresh_db() -> Connection {
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
        ] {
            conn.execute_batch(sql).unwrap();
        }
        conn
    }

    #[test]
    fn blob_round_trips_exactly() {
        let conn = fresh_db();
        let original: &[u8] = &[
            0x00, 0xFF, 0xAB, 0xCD,
            b'%', b'P', b'D', b'F', b'-',
        ];
        let id = insert_log_row(&conn, "Log with attachment", "doc.pdf", "application/pdf", original)
            .expect("insert");
        assert!(id > 0);
        let read_back = read_log_blob(&conn, id).expect("read");
        assert_eq!(read_back.as_slice(), original);
    }

    #[test]
    fn read_log_blob_returns_error_for_missing_id() {
        let conn = fresh_db();
        assert!(read_log_blob(&conn, 9999).is_err());
    }

    /// Empty body + empty bytes is a valid edge case (e.g. user attaches a
    /// 0-byte file for some reason) — should still insert cleanly.
    #[test]
    fn empty_body_and_zero_byte_blob_are_allowed() {
        let conn = fresh_db();
        let id = insert_log_row(&conn, "", "empty.txt", "text/plain", &[])
            .expect("insert");
        assert!(id > 0);
        assert_eq!(read_log_blob(&conn, id).unwrap(), Vec::<u8>::new());
    }
}
