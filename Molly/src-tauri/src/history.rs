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
    let size = bytes.len() as i64;

    let conn = open_conn(&handle)?;
    conn.execute(
        "INSERT INTO customer_history
            (customer_uid, body, attachment_filename, attachment_mime,
             attachment_size, attachment_data)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![customer_uid, body, filename, mime, size, bytes],
    )
    .map_err(|e| format!("insert: {e}"))?;

    Ok(HistoryEntryRef { id: conn.last_insert_rowid() })
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
    let bytes: Vec<u8> = conn
        .query_row(
            "SELECT attachment_data FROM customer_history WHERE id = ?1",
            params![history_id],
            |row| row.get::<_, Vec<u8>>(0),
        )
        .map_err(|e| format!("read row {history_id}: {e}"))?;
    fs::write(&target_path, &bytes).map_err(|e| format!("write {target_path}: {e}"))?;
    Ok(())
}
