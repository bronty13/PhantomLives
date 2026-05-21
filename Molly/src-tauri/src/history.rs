use rusqlite::{params, Connection};
use serde::Serialize;
use std::fs;
use std::path::PathBuf;
use std::time::Duration;
use tauri::{AppHandle, Manager, Runtime};

// Why rusqlite alongside tauri-plugin-sql:
// We share the same molly.db file but BLOB-bind directly here rather than
// round-trip raw bytes through the JS layer. The SQL plugin's JSON
// parameter marshaller has no clean BLOB binding for Vec<u8>, so a 4 MB
// screenshot would either inflate ~33% (base64 TEXT) or balloon as an
// integer array (~30 MB JSON). Two connections to one SQLite file are
// fine — WAL serializes writes and busy_timeout absorbs the rare clash.

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryEntryRef {
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
    // Wait up to 5s if the SQL plugin happens to hold the write lock.
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

// ---------- Pure SQL helpers (testable; the Tauri commands wrap these) ----

/// Insert a history row with the bytes stored inline as a BLOB; returns
/// the new row id. Extracted from the Tauri command so it can be tested
/// against an in-memory SQLite without needing a `tauri::AppHandle`.
pub fn insert_history_row(
    conn: &Connection,
    customer_uid: &str,
    body: &str,
    filename: &str,
    mime: &str,
    bytes: &[u8],
) -> rusqlite::Result<i64> {
    conn.execute(
        "INSERT INTO customer_history
            (customer_uid, body, attachment_filename, attachment_mime,
             attachment_size, attachment_data)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![customer_uid, body, filename, mime, bytes.len() as i64, bytes],
    )?;
    Ok(conn.last_insert_rowid())
}

/// Read just the BLOB for a given history row. Returns `Err(QueryReturnedNoRows)`
/// when the id doesn't exist — callers translate to a user-facing string.
pub fn read_history_blob(conn: &Connection, history_id: i64) -> rusqlite::Result<Vec<u8>> {
    conn.query_row(
        "SELECT attachment_data FROM customer_history WHERE id = ?1",
        params![history_id],
        |row| row.get::<_, Vec<u8>>(0),
    )
}

/// Inserts a history row with the file at `src_path` stored inline as a
/// SQLite BLOB. Returns the new row id so the frontend can refresh.
#[tauri::command]
pub fn add_history_entry_with_attachment<R: Runtime>(
    handle: AppHandle<R>,
    customer_uid: String,
    body: String,
    src_path: String,
) -> Result<HistoryEntryRef, String> {
    let bytes = fs::read(&src_path).map_err(|e| format!("read {src_path}: {e}"))?;
    let filename = PathBuf::from(&src_path)
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_default();
    let mime = guess_mime(&filename);

    let conn = open_conn(&handle)?;
    let id = insert_history_row(&conn, &customer_uid, &body, &filename, &mime, &bytes)
        .map_err(|e| format!("insert: {e}"))?;
    Ok(HistoryEntryRef { id })
}

/// Streams the BLOB for a given history row out to `target_path`. The
/// frontend opens a save dialog beforehand to choose the destination.
#[tauri::command]
pub fn download_history_attachment<R: Runtime>(
    handle: AppHandle<R>,
    history_id: i64,
    target_path: String,
) -> Result<(), String> {
    let conn = open_conn(&handle)?;
    let bytes = read_history_blob(&conn, history_id)
        .map_err(|e| format!("read row {history_id}: {e}"))?;
    fs::write(&target_path, &bytes).map_err(|e| format!("write {target_path}: {e}"))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;

    /// Open an in-memory DB with every migration up through 013 applied
    /// (so the customer_history table exists) and one customer row to
    /// satisfy the FK. Returns (conn, customer_uid).
    fn fresh_db_with_customer() -> (Connection, &'static str) {
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
        ] {
            conn.execute_batch(sql).unwrap();
        }
        let uid = "2026-05-21-test1";
        conn.execute(
            "INSERT INTO customers (uid) VALUES (?1)",
            params![uid],
        ).unwrap();
        (conn, uid)
    }

    /// The whole point of inline BLOB attachments: bytes-in == bytes-out,
    /// including null bytes and high bytes that would otherwise be mangled
    /// by a TEXT column or base64 round-trip.
    #[test]
    fn blob_round_trips_exactly() {
        let (conn, uid) = fresh_db_with_customer();
        let original: &[u8] = &[
            0x00, 0x01, 0x02, 0x7F, 0x80, 0xFE, 0xFF,
            b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A,
        ];
        let id = insert_history_row(&conn, uid, "round-trip test", "test.bin", "application/octet-stream", original)
            .expect("insert");
        assert!(id > 0);
        let read_back = read_history_blob(&conn, id).expect("read");
        assert_eq!(read_back.as_slice(), original);
    }

    #[test]
    fn read_history_blob_returns_error_for_missing_id() {
        let (conn, _) = fresh_db_with_customer();
        assert!(read_history_blob(&conn, 9999).is_err());
    }

    /// FK enforcement should reject orphan history entries — confirms the
    /// schema matches what the data layer expects (customer_uid REFERENCES
    /// customers(uid) ON DELETE CASCADE).
    #[test]
    fn insert_with_unknown_customer_uid_fails() {
        let (conn, _) = fresh_db_with_customer();
        let result = insert_history_row(&conn, "nobody-here", "note", "f.txt", "text/plain", b"x");
        assert!(result.is_err(), "expected FK violation; got {result:?}");
    }
}
