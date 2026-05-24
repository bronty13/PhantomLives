// Phase 1 — bundle ingest + persistence + read surface.
//
// Tauri command boundary for the Inbox + Bundle workspace:
//   - ingest_bundle(path) → IngestResult        (called from drag-drop)
//   - list_bundles()      → Vec<BundleSummary>  (Inbox rows)
//   - get_bundle(uid)     → BundleDetail        (Workspace Overview)
//
// All DB writes go through a rusqlite handle opened at the same
// `sidemolly.db` path tauri-plugin-sql uses. The plugin runs migrations
// at app startup; we just open the existing DB. This mirrors Molly's
// `history.rs` pattern for non-JS-friendly writes (here it's the
// multi-statement transactional UPSERT in `do_ingest`).
//
// Idempotency: re-ingesting the same UID UPSERTs bundles + DELETE+INSERTs
// bundle_files. User-side state on sibling tables (Phase 7+ postings,
// notes) is keyed on uid and survives re-import — that's the whole point
// of keying on UID instead of source_zip_path.
//
// Verify failures are NOT persisted in Phase 1.0 — the UI surfaces the
// error to the user (drag-drop status line), they can re-publish or
// fix. Phase 1.1 may grow a "broken bundles" surface if it turns out to
// be useful.

use std::fs;
use std::path::{Path, PathBuf};

use chrono::Local;
use rusqlite::{params, Connection, OptionalExtension};
use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, Runtime};

use crate::bundle_io::{
    classify_kind, parse_content_prefix, parse_fansite_prefix, verify_outer_zip,
    BundleIoError, ValidatedBundle,
};
use crate::extract::{bundle_workspace_dir, extract_inner_zip, ExtractError};
use crate::fsutil;
use crate::images::{
    output_path as image_output_path, process_image, ImageOps, ImageOpError,
    WatermarkPosition, WatermarkProfile,
};
use crate::manifest::{
    parse_manifest_json, parse_molly_log, BundleManifest, ManifestError,
};
use crate::thumbnails::{generate_for_file, is_thumbnailable_kind, ThumbnailError};

#[derive(Debug, thiserror::Error)]
pub enum BundleError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("verify: {0}")]
    Verify(#[from] BundleIoError),
    #[error("manifest: {0}")]
    Manifest(#[from] ManifestError),
    #[error("extract: {0}")]
    Extract(#[from] ExtractError),
    #[error("thumbnail: {0}")]
    Thumbnail(#[from] ThumbnailError),
    #[error("image: {0}")]
    Image(#[from] ImageOpError),
    #[error("db: {0}")]
    Db(#[from] rusqlite::Error),
    #[error("app data dir: {0}")]
    AppData(String),
    #[error("bundle not found: {0}")]
    NotFound(String),
}

impl serde::Serialize for BundleError {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.to_string())
    }
}

// ---------------------------------------------------------------------------
// Boundary types — every struct camelCase via #[serde(rename_all)].
// Contract tests live in lib.rs::camel_case_contract.
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct IngestResult {
    pub uid: String,
    pub bundle_type: String,
    pub persona_code: Option<String>,
    pub title: String,
    pub verify_status: String,
    pub file_count: i64,
    pub manifest_source: String,
    pub workspace_path: String,
    /// Files actually extracted to disk this call (idempotent skips don't count).
    pub extracted_count: i64,
    pub thumbnail_count: i64,
    pub export_thumb_count: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ExportThumb {
    pub position: i64,
    pub source_in_zip_path: String,
    pub thumbnail_path: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BundleSummary {
    pub uid: String,
    pub bundle_type: String,
    pub persona_code: Option<String>,
    pub title: String,
    pub ingested_at: String,
    pub verify_status: String,
    pub bundle_state: String,
    pub file_count: i64,
    pub source_zip_path: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BundleFileRow {
    pub in_zip_path: String,
    pub original_name: String,
    pub kind: String,
    pub position: i64,
    pub fansite_day_of_month: Option<i64>,
    pub sha256: String,
    pub size_bytes: i64,
    pub working_path: Option<String>,
    pub thumbnail_path: Option<String>,
    /// 0 / 90 / 180 / 270. Per-file rotation override applied during
    /// processing. Added in migration 009.
    pub rotation_degrees: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BundleDetail {
    pub summary: BundleSummary,
    pub manifest: BundleManifest,
    pub files: Vec<BundleFileRow>,
}

// ---------------------------------------------------------------------------
// DB helpers
// ---------------------------------------------------------------------------

fn app_data_dir<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, BundleError> {
    handle
        .path()
        .app_data_dir()
        .map_err(|e| BundleError::AppData(e.to_string()))
}

fn db_path<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, BundleError> {
    Ok(app_data_dir(handle)?.join("sidemolly.db"))
}

/// `~/Library/Application Support/com.phantomlives.sidemolly/work/` — root
/// of per-bundle extraction directories. Phase 3+ image/video ops will
/// write side files (thumbnails, processed variants) alongside.
pub fn work_root<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, BundleError> {
    let root = app_data_dir(handle)?.join("work");
    fs::create_dir_all(&root)?;
    Ok(root)
}

fn open_conn<R: Runtime>(handle: &AppHandle<R>) -> Result<Connection, BundleError> {
    let path = db_path(handle)?;
    let conn = Connection::open(&path)?;
    conn.execute_batch("PRAGMA foreign_keys = ON;")?;
    Ok(conn)
}

fn iso_now() -> String {
    Local::now().format("%Y-%m-%dT%H:%M:%S").to_string()
}

// ---------------------------------------------------------------------------
// Ingest
// ---------------------------------------------------------------------------

/// Pure helper — extracted so it can be unit-tested without an AppHandle.
/// Given an already-validated bundle + a fresh rusqlite Connection, run
/// the transactional UPSERT into bundles + DELETE+INSERT into bundle_files.
pub(crate) fn persist_validated(
    conn: &mut Connection,
    validated: &ValidatedBundle,
    manifest: &BundleManifest,
    manifest_source: &str,
    source_zip_path: &str,
) -> Result<i64, BundleError> {
    let manifest_json = serde_json::to_string(manifest).unwrap_or_else(|_| "{}".to_string());
    let now = iso_now();

    let tx = conn.transaction()?;

    // UPSERT bundles row. Re-ingest preserves created_at by using
    // INSERT ... ON CONFLICT(uid) DO UPDATE.
    tx.execute(
        "INSERT INTO bundles (
            uid, bundle_type, persona_code, title, source_zip_path,
            source_zip_sha256, ingested_at, verify_status, verify_error,
            manifest_source, manifest_json, bundle_state, created_at, updated_at
        ) VALUES (
            ?1, ?2, ?3, ?4, ?5,
            ?6, ?7, 'verified', NULL,
            ?8, ?9, 'new', ?10, ?10
        )
        ON CONFLICT(uid) DO UPDATE SET
            bundle_type      = excluded.bundle_type,
            persona_code     = excluded.persona_code,
            title            = excluded.title,
            source_zip_path  = excluded.source_zip_path,
            source_zip_sha256= excluded.source_zip_sha256,
            ingested_at      = excluded.ingested_at,
            verify_status    = 'verified',
            verify_error     = NULL,
            manifest_source  = excluded.manifest_source,
            manifest_json    = excluded.manifest_json,
            updated_at       = excluded.updated_at",
        params![
            manifest.uid,
            manifest.bundle_type,
            manifest.persona_code,
            manifest.title,
            source_zip_path,
            validated.source_zip_sha256,
            now,
            manifest_source,
            manifest_json,
            now,
        ],
    )?;

    // Replace the file rows wholesale — Phase 1 has no per-file user
    // state yet, so DELETE + INSERT is the simplest correct primitive.
    tx.execute(
        "DELETE FROM bundle_files WHERE bundle_uid = ?1",
        params![manifest.uid],
    )?;

    for f in &validated.hashes.files {
        let kind = classify_kind(&f.path);
        let (day, position, original_name) = if f.path.starts_with("FanSite/") {
            parse_fansite_prefix(&f.path)
        } else if f.path.starts_with("Video/") || f.path.starts_with("Photos/") || f.path.starts_with("Audio/") {
            let (pos, name) = parse_content_prefix(&f.path);
            (None, pos, name)
        } else {
            (None, 0, f.path.clone())
        };
        let size = *validated.file_sizes.get(&f.path).unwrap_or(&0) as i64;
        tx.execute(
            "INSERT INTO bundle_files (
                bundle_uid, in_zip_path, original_name, kind,
                position, fansite_day_of_month, sha256, size_bytes
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                manifest.uid,
                f.path,
                original_name,
                kind,
                position,
                day,
                f.sha256,
                size,
            ],
        )?;
    }

    let count: i64 = tx.query_row(
        "SELECT COUNT(*) FROM bundle_files WHERE bundle_uid = ?1",
        params![manifest.uid],
        |row| row.get(0),
    )?;

    tx.commit()?;
    Ok(count)
}

/// Borrow-flavoured ingest. Exists so the watched-folder watcher can
/// drive ingest in a loop without cloning the AppHandle each iteration.
/// The `#[tauri::command]` wrapper below just forwards.
pub fn ingest_bundle_inner<R: Runtime>(
    handle: &AppHandle<R>,
    path: &str,
) -> Result<IngestResult, BundleError> {
    let validated = verify_outer_zip(Path::new(path))?;

    // Manifest preference: manifest.json (Phase 2+) → Molly.log fallback.
    let (manifest, manifest_source) = if let Some(json) = &validated.manifest_json {
        match parse_manifest_json(json) {
            Ok(m) => (m, "manifest_json".to_string()),
            // If the new contract somehow fails to parse, fall back to log.
            Err(_) => (parse_molly_log(&validated.molly_log)?, "molly_log".to_string()),
        }
    } else {
        (parse_molly_log(&validated.molly_log)?, "molly_log".to_string())
    };

    let mut conn = open_conn(handle)?;
    let file_count = persist_validated(
        &mut conn,
        &validated,
        &manifest,
        &manifest_source,
        path,
    )?;

    // Phase 1b: extract the inner zip to work/<UID>/ and stamp each
    // bundle_files row with its absolute working_path so Phase 3+ ops
    // can locate files by SQL rather than re-extracting on demand.
    let work_root_dir = work_root(handle)?;
    let extracted = extract_inner_zip(
        &validated.inner_zip_bytes,
        &work_root_dir,
        &manifest.uid,
        &validated.file_sizes,
    )?;
    let extracted_count = extracted.iter().filter(|e| e.written).count() as i64;
    for e in &extracted {
        conn.execute(
            "UPDATE bundle_files
                SET working_path = ?1, size_bytes = ?2
              WHERE bundle_uid = ?3 AND in_zip_path = ?4",
            params![
                e.working_path.to_string_lossy().to_string(),
                e.size_bytes as i64,
                manifest.uid,
                e.in_zip_path,
            ],
        )?;
    }

    let workspace_path_buf = bundle_workspace_dir(&work_root_dir, &manifest.uid);
    let workspace_path = workspace_path_buf.to_string_lossy().to_string();

    // ---- Phase 1c thumbnails ----
    // Re-load extracted rows with their DB ids so we can reference them
    // from bundle_export_thumbs.
    let mut media: Vec<(i64, String, String, PathBuf)> = Vec::new();
    {
        let mut stmt = conn.prepare(
            "SELECT id, in_zip_path, kind, working_path
              FROM bundle_files WHERE bundle_uid = ?1",
        )?;
        let rows = stmt.query_map(params![manifest.uid], |row| {
            let id: i64 = row.get(0)?;
            let in_zip: String = row.get(1)?;
            let kind: String = row.get(2)?;
            let wp: Option<String> = row.get(3)?;
            Ok((id, in_zip, kind, PathBuf::from(wp.unwrap_or_default())))
        })?;
        for r in rows {
            let row = r?;
            if is_thumbnailable_kind(&row.2) {
                media.push(row);
            }
        }
    }

    let thumb_dir = workspace_path_buf.join(".thumbs");
    let mut thumb_rows: Vec<(i64, String, PathBuf)> = Vec::new();
    for (id, in_zip, kind, wp) in &media {
        if !wp.exists() { continue; }
        let made = generate_for_file(kind, in_zip, wp, &thumb_dir)?;
        if let Some(path) = made {
            conn.execute(
                "UPDATE bundle_files SET thumbnail_path = ?1 WHERE id = ?2",
                params![path.to_string_lossy().to_string(), id],
            )?;
            thumb_rows.push((*id, in_zip.clone(), path));
        }
    }
    let thumbnail_count = thumb_rows.len() as i64;

    // ---- 10 random export thumbnails ----
    // Selection is stable across re-ingests for the moment: DELETE +
    // INSERT replaces the picks each time. Phase 11 (post-bundle
    // composition) reads from bundle_export_thumbs.
    conn.execute(
        "DELETE FROM bundle_export_thumbs WHERE bundle_uid = ?1",
        params![manifest.uid],
    )?;
    let mut picks = thumb_rows.clone();
    pseudo_shuffle(&mut picks, &manifest.uid);
    picks.truncate(10);
    for (i, (id, _in_zip, path)) in picks.iter().enumerate() {
        conn.execute(
            "INSERT INTO bundle_export_thumbs
                (bundle_uid, bundle_file_id, position, thumbnail_path)
             VALUES (?1, ?2, ?3, ?4)",
            params![
                manifest.uid,
                id,
                (i + 1) as i64,
                path.to_string_lossy().to_string(),
            ],
        )?;
    }
    let export_thumb_count = picks.len() as i64;

    Ok(IngestResult {
        uid: manifest.uid,
        bundle_type: manifest.bundle_type,
        persona_code: manifest.persona_code,
        title: manifest.title,
        verify_status: "verified".to_string(),
        file_count,
        manifest_source,
        workspace_path,
        extracted_count,
        thumbnail_count,
        export_thumb_count,
    })
}

/// Deterministic shuffle keyed on the bundle UID. Avoids pulling the
/// `rand` crate just for this; the security of the selection doesn't
/// matter, only that it's evenly distributed and stable per-bundle.
fn pseudo_shuffle<T>(items: &mut Vec<T>, key: &str) {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(key.as_bytes());
    let seed = hasher.finalize();
    // xorshift64* seeded from the first 8 bytes of the SHA-256 digest.
    let mut state: u64 = u64::from_be_bytes([
        seed[0], seed[1], seed[2], seed[3], seed[4], seed[5], seed[6], seed[7],
    ]);
    if state == 0 { state = 1; }
    let n = items.len();
    for i in (1..n).rev() {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        let j = (state as usize) % (i + 1);
        items.swap(i, j);
    }
}

#[tauri::command]
pub fn ingest_bundle<R: Runtime>(
    handle: AppHandle<R>,
    path: String,
) -> Result<IngestResult, BundleError> {
    ingest_bundle_inner(&handle, &path)
}

/// Cap on text-doc reads from the workspace. Molly.log is typically
/// 5-20 KB; info.md similarly small. 256 KB is plenty of headroom and
/// keeps the frontend from accidentally pulling a 95 MB video into a
/// drawer.
const DOC_READ_CAP_BYTES: u64 = 256 * 1024;

#[tauri::command]
pub fn read_doc_text<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
    in_zip_path: String,
) -> Result<String, BundleError> {
    let conn = open_conn(&handle)?;
    let working_path: Option<String> = conn
        .query_row(
            "SELECT working_path FROM bundle_files
              WHERE bundle_uid = ?1 AND in_zip_path = ?2",
            params![uid, in_zip_path],
            |row| row.get::<_, Option<String>>(0),
        )
        .optional()?
        .flatten();
    let working_path = working_path
        .filter(|p| !p.is_empty())
        .ok_or_else(|| BundleError::NotFound(format!("{uid}::{in_zip_path}")))?;
    let meta = fs::metadata(&working_path)?;
    if meta.len() > DOC_READ_CAP_BYTES {
        return Err(BundleError::NotFound(format!(
            "file too large to read inline ({} bytes; cap is {DOC_READ_CAP_BYTES})",
            meta.len()
        )));
    }
    let bytes = fs::read(&working_path)?;
    Ok(String::from_utf8_lossy(&bytes).into_owned())
}

/// Bundle thumbnails as inline data URLs, keyed on `in_zip_path` so
/// the frontend can map files → src directly. We do this server-side
/// (instead of letting the webview load `asset://…` URLs) because
/// WKWebView on macOS 15 silently refuses our asset-protocol URLs even
/// with `assetProtocol.scope: ["**"]` + CSP wide open. Data URLs render
/// regardless of webview protocol handshakes — at the cost of one
/// 4/3 base64 expansion per JPEG (~13KB / image), bounded by the
/// 256-px thumbnails the ingest pipeline produces.
#[tauri::command]
pub fn get_bundle_thumbnails<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<std::collections::HashMap<String, String>, BundleError> {
    use base64::{engine::general_purpose::STANDARD, Engine as _};

    let conn = open_conn(&handle)?;
    let mut stmt = conn.prepare(
        "SELECT in_zip_path, thumbnail_path
           FROM bundle_files
          WHERE bundle_uid = ?1
            AND thumbnail_path IS NOT NULL
            AND thumbnail_path != ''",
    )?;
    let rows: Vec<(String, String)> = stmt
        .query_map(params![uid], |row| Ok((row.get(0)?, row.get(1)?)))?
        .collect::<rusqlite::Result<Vec<_>>>()?;

    let mut out = std::collections::HashMap::with_capacity(rows.len());
    for (in_zip, path) in rows {
        let Ok(bytes) = fs::read(&path) else { continue };
        // All thumbs are JPEG by construction (see thumbnails::generate_*).
        let encoded = STANDARD.encode(&bytes);
        out.insert(in_zip, format!("data:image/jpeg;base64,{encoded}"));
    }
    Ok(out)
}

#[tauri::command]
pub fn get_export_thumbnails<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<Vec<ExportThumb>, BundleError> {
    let conn = open_conn(&handle)?;
    let mut stmt = conn.prepare(
        "SELECT t.position, f.in_zip_path, t.thumbnail_path
           FROM bundle_export_thumbs t
           JOIN bundle_files f ON f.id = t.bundle_file_id
          WHERE t.bundle_uid = ?1
          ORDER BY t.position",
    )?;
    let rows = stmt
        .query_map(params![uid], |row| {
            Ok(ExportThumb {
                position: row.get(0)?,
                source_in_zip_path: row.get(1)?,
                thumbnail_path: row.get(2)?,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

#[tauri::command]
pub fn reveal_working_dir<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<(), BundleError> {
    let dir = bundle_workspace_dir(&work_root(&handle)?, &uid);
    if !dir.exists() {
        return Err(BundleError::NotFound(uid));
    }
    fsutil::reveal_in_file_browser(&dir)?;
    Ok(())
}

/// Per-file rotation override (0/90/180/270). 0 clears any prior
/// override. Applied at processing time by `process_bundle_images`
/// and `enqueue_bundle_video_ops`. Added 2026-05-24 to support
/// rotating individual files in a mixed bundle.
#[tauri::command]
pub fn set_bundle_file_rotation<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
    in_zip_path: String,
    degrees: i64,
) -> Result<(), BundleError> {
    if ![0, 90, 180, 270].contains(&degrees) {
        return Err(BundleError::Io(std::io::Error::other(
            format!("rotation must be 0/90/180/270, got {degrees}"),
        )));
    }
    let conn = open_conn(&handle)?;
    let n = conn.execute(
        "UPDATE bundle_files
            SET rotation_degrees = ?1
          WHERE bundle_uid = ?2 AND in_zip_path = ?3",
        params![degrees, uid, in_zip_path],
    )?;
    if n == 0 {
        return Err(BundleError::NotFound(format!("{uid}::{in_zip_path}")));
    }
    Ok(())
}

#[tauri::command]
pub fn reveal_working_file<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
    in_zip_path: String,
) -> Result<(), BundleError> {
    let conn = open_conn(&handle)?;
    // Outer Option = "no matching row"; inner Option = SQL NULL for an
    // un-extracted file. Both collapse to NotFound for the caller.
    let path: Option<String> = conn
        .query_row(
            "SELECT working_path FROM bundle_files
              WHERE bundle_uid = ?1 AND in_zip_path = ?2",
            params![uid, in_zip_path],
            |row| row.get::<_, Option<String>>(0),
        )
        .optional()?
        .flatten();
    let path = path
        .filter(|p| !p.is_empty())
        .ok_or_else(|| BundleError::NotFound(format!("{uid}::{in_zip_path}")))?;
    fsutil::reveal_in_file_browser(Path::new(&path))?;
    Ok(())
}

#[tauri::command]
pub fn list_bundles<R: Runtime>(handle: AppHandle<R>) -> Result<Vec<BundleSummary>, BundleError> {
    let conn = open_conn(&handle)?;
    let mut stmt = conn.prepare(
        "SELECT b.uid, b.bundle_type, b.persona_code, b.title, b.ingested_at,
                b.verify_status, b.bundle_state, b.source_zip_path,
                (SELECT COUNT(*) FROM bundle_files f WHERE f.bundle_uid = b.uid) AS file_count
         FROM bundles b
         ORDER BY b.ingested_at DESC",
    )?;
    let rows = stmt
        .query_map([], |row| {
            Ok(BundleSummary {
                uid: row.get(0)?,
                bundle_type: row.get(1)?,
                persona_code: row.get(2)?,
                title: row.get(3)?,
                ingested_at: row.get(4)?,
                verify_status: row.get(5)?,
                bundle_state: row.get(6)?,
                source_zip_path: row.get(7)?,
                file_count: row.get(8)?,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

#[tauri::command]
pub fn get_bundle<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<BundleDetail, BundleError> {
    let conn = open_conn(&handle)?;

    let (summary, manifest_json): (BundleSummary, String) = conn.query_row(
        "SELECT b.uid, b.bundle_type, b.persona_code, b.title, b.ingested_at,
                b.verify_status, b.bundle_state, b.source_zip_path,
                (SELECT COUNT(*) FROM bundle_files f WHERE f.bundle_uid = b.uid) AS file_count,
                b.manifest_json
         FROM bundles b
         WHERE b.uid = ?1",
        params![uid],
        |row| {
            Ok((
                BundleSummary {
                    uid: row.get(0)?,
                    bundle_type: row.get(1)?,
                    persona_code: row.get(2)?,
                    title: row.get(3)?,
                    ingested_at: row.get(4)?,
                    verify_status: row.get(5)?,
                    bundle_state: row.get(6)?,
                    source_zip_path: row.get(7)?,
                    file_count: row.get(8)?,
                },
                row.get(9)?,
            ))
        },
    )?;

    let manifest: BundleManifest =
        serde_json::from_str(&manifest_json).unwrap_or_default();

    let mut stmt = conn.prepare(
        "SELECT in_zip_path, original_name, kind, position,
                fansite_day_of_month, sha256, size_bytes,
                working_path, thumbnail_path, rotation_degrees
         FROM bundle_files
         WHERE bundle_uid = ?1
         ORDER BY
             CASE WHEN fansite_day_of_month IS NULL THEN 0 ELSE fansite_day_of_month END,
             position,
             in_zip_path",
    )?;
    let files = stmt
        .query_map(params![uid], |row| {
            Ok(BundleFileRow {
                in_zip_path: row.get(0)?,
                original_name: row.get(1)?,
                kind: row.get(2)?,
                position: row.get(3)?,
                fansite_day_of_month: row.get(4)?,
                sha256: row.get(5)?,
                size_bytes: row.get(6)?,
                working_path: row.get(7)?,
                thumbnail_path: row.get(8)?,
                rotation_degrees: row.get(9)?,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;

    Ok(BundleDetail { summary, manifest, files })
}

// ---------------------------------------------------------------------------
// Phase 3 image ops — watermark profiles + process_bundle_images.
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WatermarkProfileRow {
    pub persona_code: String,
    pub text: String,
    pub opacity_percent: i64,
    pub position: String,
    pub font_size_pct: f64,
    pub margin_pct: f64,
    /// Apply watermark to images of bundles with this persona. Default off
    /// (most photos are hand-edited downstream anyway).
    pub image_enabled: bool,
    /// Apply watermark to videos of bundles with this persona. Default on
    /// (videos are typically uploaded direct).
    pub video_enabled: bool,
}

/// Media kind the loader should check the per-media `enabled` flag for.
/// Image vs Video map to `image_enabled` / `video_enabled` columns on
/// `watermark_profiles` (added in migration 008).
#[derive(Debug, Clone, Copy)]
pub enum MediaKind {
    Image,
    Video,
}

#[derive(Debug, Clone, Serialize, serde::Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ImageOpsInput {
    #[serde(default)] pub watermark: bool,
    #[serde(default)] pub strip_exif: bool,
    #[serde(default)] pub rename: bool,
}

impl From<ImageOpsInput> for ImageOps {
    fn from(i: ImageOpsInput) -> Self {
        ImageOps { watermark: i.watermark, strip_exif: i.strip_exif, rename: i.rename }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProcessedFileRow {
    pub bundle_file_id: i64,
    pub in_zip_path: String,
    pub op_kind: String,
    pub output_path: String,
    pub created_at: String,
}

/// Per-image progress tick emitted on the `image-progress` channel
/// during `process_bundle_images`. Frontend subscribes and updates
/// the EditTab busy banner with the live "X of N" count + filename.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImageProgressEvent {
    pub bundle_uid: String,
    pub done: i64,
    pub total: i64,
    pub current_in_zip_path: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProcessImagesResult {
    pub bundle_uid: String,
    pub op_kind: String,
    pub processed: Vec<ProcessedFileRow>,
    pub skipped: i64,
    pub errors: Vec<String>,
}

/// macOS-stable lookup for the bundled font. Tauri's `resolve_resource`
/// returns the in-bundle path for production; in dev / tests it falls
/// back to the source-tree copy.
pub fn paper_daisy_bytes<R: Runtime>(handle: &AppHandle<R>) -> Result<Vec<u8>, BundleError> {
    let path = paper_daisy_path(handle)?;
    Ok(fs::read(path)?)
}

/// Same resource lookup as `paper_daisy_bytes`, returning the path —
/// needed by `video.rs` because ffmpeg's `drawtext` filter takes a
/// filename, not bytes.
pub fn paper_daisy_path<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, BundleError> {
    if let Ok(p) = handle.path().resolve(
        "resources/fonts/PaperDaisy.ttf",
        tauri::path::BaseDirectory::Resource,
    ) {
        if p.exists() {
            return Ok(p);
        }
    }
    let dev = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("resources/fonts/PaperDaisy.ttf");
    if dev.exists() {
        return Ok(dev);
    }
    Err(BundleError::NotFound("resources/fonts/PaperDaisy.ttf".into()))
}

#[tauri::command]
pub fn get_watermark_profiles<R: Runtime>(
    handle: AppHandle<R>,
) -> Result<Vec<WatermarkProfileRow>, BundleError> {
    let conn = open_conn(&handle)?;
    let mut stmt = conn.prepare(
        "SELECT persona_code, text, opacity_percent, position,
                font_size_pct, margin_pct, image_enabled, video_enabled
           FROM watermark_profiles
          ORDER BY CASE persona_code WHEN '' THEN 0 ELSE 1 END, persona_code",
    )?;
    let rows = stmt
        .query_map([], |row| {
            Ok(WatermarkProfileRow {
                persona_code: row.get(0)?,
                text: row.get(1)?,
                opacity_percent: row.get(2)?,
                position: row.get(3)?,
                font_size_pct: row.get(4)?,
                margin_pct: row.get(5)?,
                image_enabled: row.get::<_, i64>(6)? != 0,
                video_enabled: row.get::<_, i64>(7)? != 0,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

#[tauri::command]
pub fn set_watermark_profile<R: Runtime>(
    handle: AppHandle<R>,
    profile: WatermarkProfileRow,
) -> Result<(), BundleError> {
    // Validate position before touching the DB so we surface a clean
    // error instead of a CHECK constraint failure.
    WatermarkPosition::parse(&profile.position).map_err(ImageOpError::from)?;
    let conn = open_conn(&handle)?;
    conn.execute(
        "INSERT INTO watermark_profiles
            (persona_code, text, opacity_percent, position,
             font_size_pct, margin_pct, image_enabled, video_enabled, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, datetime('now'))
         ON CONFLICT(persona_code) DO UPDATE SET
            text             = excluded.text,
            opacity_percent  = excluded.opacity_percent,
            position         = excluded.position,
            font_size_pct    = excluded.font_size_pct,
            margin_pct       = excluded.margin_pct,
            image_enabled    = excluded.image_enabled,
            video_enabled    = excluded.video_enabled,
            updated_at       = datetime('now')",
        params![
            profile.persona_code,
            profile.text,
            profile.opacity_percent,
            profile.position,
            profile.font_size_pct,
            profile.margin_pct,
            if profile.image_enabled { 1 } else { 0 },
            if profile.video_enabled { 1 } else { 0 },
        ],
    )?;
    Ok(())
}

/// Public alias for `load_watermark_profile` so sibling modules
/// (`auto_assemble.rs`) can reuse the per-media profile lookup without
/// duplicating the SELECT.
pub fn load_watermark_profile_pub(
    conn: &Connection,
    persona_code: Option<&str>,
    media: MediaKind,
) -> Result<Option<WatermarkProfile>, BundleError> {
    load_watermark_profile(conn, persona_code, media)
}

fn load_watermark_profile(
    conn: &Connection,
    persona_code: Option<&str>,
    media: MediaKind,
) -> Result<Option<WatermarkProfile>, BundleError> {
    let lookup_key = persona_code.unwrap_or("");
    // Look up the bundle's persona first; fall back to the '' default
    // row when missing or disabled-for-this-media-kind. The per-media
    // flag (image_enabled / video_enabled) was added in migration 008
    // so images and videos can have independent defaults per persona.
    for key in [lookup_key, ""] {
        let row = conn
            .query_row(
                "SELECT text, opacity_percent, position, font_size_pct, margin_pct,
                        image_enabled, video_enabled
                   FROM watermark_profiles WHERE persona_code = ?1",
                params![key],
                |r| Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, i64>(1)?,
                    r.get::<_, String>(2)?,
                    r.get::<_, f64>(3)?,
                    r.get::<_, f64>(4)?,
                    r.get::<_, i64>(5)?,
                    r.get::<_, i64>(6)?,
                )),
            )
            .optional()?;
        let Some((text, opacity, position, font_size, margin, img_en, vid_en)) = row
            else { continue };
        let enabled_for_media = match media {
            MediaKind::Image => img_en != 0,
            MediaKind::Video => vid_en != 0,
        };
        if !enabled_for_media || text.is_empty() { continue; }
        return Ok(Some(WatermarkProfile {
            text,
            opacity_percent: opacity.clamp(0, 100) as u8,
            position: WatermarkPosition::parse(&position).map_err(ImageOpError::from)?,
            font_size_pct: font_size as f32,
            margin_pct: margin as f32,
        }));
    }
    Ok(None)
}

/// Async wrapper that offloads the CPU-heavy image loop onto
/// `tauri::async_runtime::spawn_blocking`. The earlier sync version
/// emitted `image-progress` events fine on paper, but the Tauri 2
/// IPC bus didn't reliably flush them to the renderer until the
/// command returned — making the UI look frozen for the entire run.
/// Spawning explicitly off the runtime thread lets emit() reach the
/// WebView in real time. Caught 2026-05-24.
#[tauri::command]
pub async fn process_bundle_images<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
    ops: ImageOpsInput,
) -> Result<ProcessImagesResult, BundleError> {
    let h = handle.clone();
    tauri::async_runtime::spawn_blocking(move || process_bundle_images_inner(h, uid, ops))
        .await
        .map_err(|e| BundleError::Io(std::io::Error::other(
            format!("spawn_blocking join: {e}"),
        )))?
}

fn process_bundle_images_inner<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
    ops: ImageOpsInput,
) -> Result<ProcessImagesResult, BundleError> {
    let typed_ops: ImageOps = ops.into();
    let op_kind = typed_ops.op_kind().to_string();
    let workspace = bundle_workspace_dir(&work_root(&handle)?, &uid);

    // Resolve the persona once + load its watermark profile.
    let conn = open_conn(&handle)?;
    let persona: Option<String> = conn
        .query_row(
            "SELECT persona_code FROM bundles WHERE uid = ?1",
            params![uid],
            |r| r.get(0),
        )
        .optional()?
        .flatten();
    let profile = if typed_ops.watermark {
        load_watermark_profile(&conn, persona.as_deref(), MediaKind::Image)?
    } else {
        None
    };

    let font_bytes = if typed_ops.watermark { paper_daisy_bytes(&handle)? } else { Vec::new() };

    // Walk every image-kind row that has a working path on disk.
    let mut stmt = conn.prepare(
        "SELECT id, in_zip_path, working_path, rotation_degrees
           FROM bundle_files
          WHERE bundle_uid = ?1 AND kind = 'image'
                AND working_path IS NOT NULL AND working_path != ''",
    )?;
    let candidates: Vec<(i64, String, String, i64)> = stmt
        .query_map(params![uid], |row| Ok((
            row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?,
        )))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    drop(stmt);

    let mut processed: Vec<ProcessedFileRow> = Vec::with_capacity(candidates.len());
    let mut skipped: i64 = 0;
    let mut errors: Vec<String> = Vec::new();

    let total = candidates.len() as i64;
    for (i, (id, in_zip, working, rot_deg)) in candidates.into_iter().enumerate() {
        // Emit progress before kicking off each image so the UI banner
        // updates with the current file name BEFORE the JPEG re-encode
        // (which is the slow part). The frontend listens for this on
        // the `image-progress` channel.
        let _ = handle.emit("image-progress", ImageProgressEvent {
            bundle_uid: uid.clone(),
            done: i as i64,
            total,
            current_in_zip_path: in_zip.clone(),
        });
        let src = PathBuf::from(&working);
        if !src.exists() {
            skipped += 1;
            errors.push(format!("{in_zip}: working file missing"));
            continue;
        }
        let dst = image_output_path(&workspace, &in_zip, &op_kind);
        match process_image(&src, &dst, typed_ops, profile.as_ref(), &font_bytes, rot_deg) {
            Ok(()) => {
                conn.execute(
                    "INSERT INTO processed_files
                        (bundle_file_id, op_kind, output_path)
                     VALUES (?1, ?2, ?3)
                     ON CONFLICT(bundle_file_id, op_kind) DO UPDATE SET
                        output_path = excluded.output_path,
                        created_at = datetime('now')",
                    params![id, op_kind, dst.to_string_lossy().to_string()],
                )?;
                let created_at: String = conn.query_row(
                    "SELECT created_at FROM processed_files
                      WHERE bundle_file_id = ?1 AND op_kind = ?2",
                    params![id, op_kind],
                    |r| r.get(0),
                )?;
                processed.push(ProcessedFileRow {
                    bundle_file_id: id,
                    in_zip_path: in_zip,
                    op_kind: op_kind.clone(),
                    output_path: dst.to_string_lossy().to_string(),
                    created_at,
                });
            }
            Err(e) => {
                skipped += 1;
                errors.push(format!("{in_zip}: {e}"));
            }
        }
    }

    // Final tick so the progress UI reads "N of N done" before the
    // IPC return lands.
    let _ = handle.emit("image-progress", ImageProgressEvent {
        bundle_uid: uid.clone(),
        done: total,
        total,
        current_in_zip_path: String::new(),
    });

    Ok(ProcessImagesResult {
        bundle_uid: uid,
        op_kind,
        processed,
        skipped,
        errors,
    })
}

#[tauri::command]
pub fn list_processed_files<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<Vec<ProcessedFileRow>, BundleError> {
    let conn = open_conn(&handle)?;
    let mut stmt = conn.prepare(
        "SELECT pf.bundle_file_id, bf.in_zip_path, pf.op_kind,
                pf.output_path, pf.created_at
           FROM processed_files pf
           JOIN bundle_files bf ON bf.id = pf.bundle_file_id
          WHERE bf.bundle_uid = ?1
          ORDER BY bf.in_zip_path, pf.op_kind",
    )?;
    let rows = stmt
        .query_map(params![uid], |row| {
            Ok(ProcessedFileRow {
                bundle_file_id: row.get(0)?,
                in_zip_path: row.get(1)?,
                op_kind: row.get(2)?,
                output_path: row.get(3)?,
                created_at: row.get(4)?,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

#[derive(Debug, Clone, Serialize, serde::Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct VideoOpsInput {
    #[serde(default)] pub watermark: bool,
    #[serde(default)] pub strip_metadata: bool,
    #[serde(default)] pub rename: bool,
}

impl VideoOpsInput {
    fn op_kind(&self) -> String {
        let parts = [
            (self.watermark, "watermark"),
            (self.strip_metadata, "strip"),
            (self.rename, "rename"),
        ];
        let on: Vec<&str> = parts.iter().filter(|(b, _)| *b).map(|(_, n)| *n).collect();
        if on.is_empty() { "video_clean".into() } else { format!("video_{}", on.join("_")) }
    }
}

/// Map a per-file rotation_degrees value (0/90/180/270) to the string
/// form `ProcessVideoParams.rotation` expects ("none" / "cw" / "180" / "ccw").
fn rotation_degrees_to_str(degrees: i64) -> &'static str {
    match degrees {
        90 => "cw",
        180 => "180",
        270 => "ccw",
        _ => "none",
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EnqueueVideoOpsResult {
    pub bundle_uid: String,
    pub op_kind: String,
    pub enqueued_count: i64,
    pub skipped: i64,
    pub job_ids: Vec<i64>,
    pub errors: Vec<String>,
}

#[tauri::command]
pub fn enqueue_bundle_video_ops<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
    ops: VideoOpsInput,
) -> Result<EnqueueVideoOpsResult, BundleError> {
    let op_kind = ops.op_kind();
    let workspace = bundle_workspace_dir(&work_root(&handle)?, &uid);

    let conn = open_conn(&handle)?;
    let persona: Option<String> = conn
        .query_row(
            "SELECT persona_code FROM bundles WHERE uid = ?1",
            params![uid],
            |r| r.get(0),
        )
        .optional()?
        .flatten();
    let profile = if ops.watermark {
        load_watermark_profile(&conn, persona.as_deref(), MediaKind::Video)?
    } else {
        None
    };
    // Phase 4.2 fix: probe each video for its actual height with
    // ffprobe and render the watermark PNG sized for that height (was
    // hardcoded to 1080 — fine for HD content, but 720p videos got
    // text ~1/3rd the size of iPhone-resolution images at the same
    // 4% font_size setting). Cache PNGs by (profile + height) so a
    // batch of identical-height clips reuses the same overlay file.
    let font_bytes: Option<Vec<u8>> = if profile.is_some() {
        Some(paper_daisy_bytes(&handle)?)
    } else {
        None
    };
    let wm_dir = workspace.join(".watermarks");
    if profile.is_some() { fs::create_dir_all(&wm_dir)?; }
    let mut wm_cache: std::collections::HashMap<u32, String> =
        std::collections::HashMap::new();

    let mut stmt = conn.prepare(
        "SELECT id, in_zip_path, working_path, rotation_degrees
           FROM bundle_files
          WHERE bundle_uid = ?1 AND kind = 'video'
                AND working_path IS NOT NULL AND working_path != ''",
    )?;
    let videos: Vec<(i64, String, String, i64)> = stmt
        .query_map(params![uid], |row| Ok((
            row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?,
        )))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    drop(stmt);

    let mut job_ids: Vec<i64> = Vec::with_capacity(videos.len());
    let mut skipped = 0i64;
    let mut errors: Vec<String> = Vec::new();

    for (id, in_zip, working, rot_deg) in videos {
        if !std::path::Path::new(&working).exists() {
            skipped += 1;
            errors.push(format!("{in_zip}: working file missing"));
            continue;
        }
        let stem = std::path::Path::new(&in_zip)
            .file_stem()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| in_zip.clone());
        let output_path = workspace
            .join("processed")
            .join(format!("{stem}__{op_kind}.mp4"))
            .to_string_lossy()
            .to_string();

        // Resolve (or reuse) the watermark PNG for this video.
        //
        // Resolution-agnostic sizing — works for anything from a
        // 240p webcam clip to 8K source:
        //   reference   = max(actual_height, 1440)   — floor so small
        //                                              videos still
        //                                              get legible text
        //   base_font   = reference * font_size_pct
        //   cap         = actual_height * 8%         — never let the
        //                                              watermark dominate
        //                                              a small frame
        //   font_size_px = clamp(base_font, 24, cap-or-base)
        //
        // Cache key is the resulting integer font_size_px so two
        // different videos at the same render height share a PNG.
        // (Caught 2026-05-24: hardcoded 1080 was small for iPhone-vs-
        //  image parity; naive per-video-height made 720p smaller still;
        //  this version is correct for any incoming resolution.)
        let watermark_png_path: Option<String> = match (&profile, &font_bytes) {
            (Some(p), Some(fb)) => {
                let actual_height = crate::thumbnails::probe_video_height(
                    std::path::Path::new(&working),
                ).unwrap_or(1080);
                let reference = std::cmp::max(actual_height, 1440) as f32;
                let base_font = reference * p.font_size_pct / 100.0;
                let cap = (actual_height as f32) * 0.08;
                let font_size_px = base_font.min(cap).max(24.0);
                let cache_key = font_size_px.round() as u32;
                if let Some(existing) = wm_cache.get(&cache_key) {
                    Some(existing.clone())
                } else {
                    // Video opacity boost (perceptual parity with images).
                // ffmpeg overlay with format=rgb already corrects the
                // chroma-loss issue, but at the same nominal alpha the
                // motion in the frame still makes the watermark read
                // ~20% lighter than a still photo's. 1.25× nudge —
                // 20% UI → 25% effective on video. Capped at 100.
                let boosted = WatermarkProfile {
                    opacity_percent: ((p.opacity_percent as f32 * 1.25).min(100.0)) as u8,
                    ..p.clone()
                };
                let png_bytes = crate::images::render_watermark_png(&boosted, fb, font_size_px)?;
                    let key = profile_cache_key(p);
                    let path = wm_dir.join(format!("{key}-f{cache_key}.png"));
                    let needs_write = match fs::read(&path) {
                        Ok(existing) => existing != png_bytes,
                        Err(_) => true,
                    };
                    if needs_write { fs::write(&path, &png_bytes)?; }
                    let s = path.to_string_lossy().to_string();
                    wm_cache.insert(cache_key, s.clone());
                    Some(s)
                }
            }
            _ => None,
        };

        let params_struct = crate::video::ProcessVideoParams {
            working_path: working,
            output_path,
            op_kind: op_kind.clone(),
            watermark: ops.watermark && profile.is_some(),
            strip_metadata: ops.strip_metadata,
            rename: ops.rename,
            position: profile
                .as_ref()
                .map(|p| watermark_position_to_str(p.position))
                .unwrap_or_else(|| "bottom-right".to_string()),
            margin_pct: profile.as_ref().map(|p| p.margin_pct).unwrap_or(2.5),
            watermark_png_path,
            bundle_file_id: id,
            rotation: rotation_degrees_to_str(rot_deg).to_string(),
        };
        let params_json = serde_json::to_string(&params_struct).unwrap_or_else(|_| "{}".into());
        let job_id = crate::jobs::enqueue(
            &conn,
            "process_video",
            &params_json,
            Some(&uid),
            Some(&in_zip),
        )?;
        job_ids.push(job_id);
    }

    Ok(EnqueueVideoOpsResult {
        bundle_uid: uid,
        op_kind,
        enqueued_count: job_ids.len() as i64,
        skipped,
        job_ids,
        errors,
    })
}

/// Stable 8-hex key derived from the watermark profile content so
/// the rendered PNG can be cached at `.watermarks/<key>.png` and
/// reused across every video in a batch. Phase 5+ can extend this
/// to scope by bundle persona once watermarks become bundle-bound.
fn profile_cache_key(p: &WatermarkProfile) -> String {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(p.text.as_bytes());
    hasher.update([p.opacity_percent]);
    hasher.update(format!("{:?}", p.position).as_bytes());
    hasher.update(p.font_size_pct.to_le_bytes());
    hasher.update(p.margin_pct.to_le_bytes());
    let digest = hasher.finalize();
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut s = String::with_capacity(16);
    for b in digest.iter().take(8) {
        s.push(HEX[(b >> 4) as usize] as char);
        s.push(HEX[(b & 0x0f) as usize] as char);
    }
    s
}

pub fn watermark_position_to_str(p: WatermarkPosition) -> String {
    match p {
        WatermarkPosition::TopLeft      => "top-left",
        WatermarkPosition::TopCenter    => "top-center",
        WatermarkPosition::TopRight     => "top-right",
        WatermarkPosition::MiddleLeft   => "middle-left",
        WatermarkPosition::MiddleCenter => "middle-center",
        WatermarkPosition::MiddleRight  => "middle-right",
        WatermarkPosition::BottomLeft   => "bottom-left",
        WatermarkPosition::BottomCenter => "bottom-center",
        WatermarkPosition::BottomRight  => "bottom-right",
    }.to_string()
}

#[tauri::command]
pub fn list_jobs<R: Runtime>(
    handle: AppHandle<R>,
    status_filter: Option<String>,
) -> Result<Vec<crate::jobs::JobRow>, BundleError> {
    let conn = open_conn(&handle)?;
    Ok(crate::jobs::list(&conn, status_filter.as_deref())?)
}

#[tauri::command]
pub fn list_job_runs<R: Runtime>(
    handle: AppHandle<R>,
    job_id: i64,
) -> Result<Vec<crate::jobs::JobRunRow>, BundleError> {
    let conn = open_conn(&handle)?;
    Ok(crate::jobs::list_runs(&conn, job_id)?)
}

/// Status snapshot of the auto-assembled master MP4 for a bundle.
/// Frontend uses this to render the "Master cut" card on the Edit tab
/// — exists/missing flag, file size, last-modified timestamp so the
/// user knows whether the assemble step has actually produced output
/// (versus still queued or failed).
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MasterCutStatus {
    pub bundle_uid: String,
    pub master_path: String,
    pub exists: bool,
    pub size_bytes: i64,
    pub modified_at: Option<String>,
}

#[tauri::command]
pub fn get_master_cut_status<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<MasterCutStatus, BundleError> {
    let workspace = crate::extract::bundle_workspace_dir(&work_root(&handle)?, &uid);
    let master_path = workspace.join("auto").join("master.mp4");
    let (exists, size_bytes, modified_at) = match fs::metadata(&master_path) {
        Ok(m) => {
            let modified = m.modified().ok()
                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|d| {
                    let secs = d.as_secs() as i64;
                    chrono::DateTime::<chrono::Utc>::from_timestamp(secs, 0)
                        .map(|dt| dt.format("%Y-%m-%d %H:%M:%S UTC").to_string())
                        .unwrap_or_default()
                });
            (true, m.len() as i64, modified)
        }
        Err(_) => (false, 0, None),
    };
    Ok(MasterCutStatus {
        bundle_uid: uid,
        master_path: master_path.to_string_lossy().to_string(),
        exists, size_bytes, modified_at,
    })
}

#[tauri::command]
pub fn reveal_master_cut<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<(), BundleError> {
    let workspace = crate::extract::bundle_workspace_dir(&work_root(&handle)?, &uid);
    let master_path = workspace.join("auto").join("master.mp4");
    if !master_path.exists() {
        return Err(BundleError::NotFound(format!(
            "master.mp4 not yet at {}", master_path.display()
        )));
    }
    fsutil::reveal_in_file_browser(&master_path)?;
    Ok(())
}

#[tauri::command]
pub fn open_master_cut<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<(), BundleError> {
    let workspace = crate::extract::bundle_workspace_dir(&work_root(&handle)?, &uid);
    let master_path = workspace.join("auto").join("master.mp4");
    if !master_path.exists() {
        return Err(BundleError::NotFound(format!(
            "master.mp4 not yet at {}", master_path.display()
        )));
    }
    // Use the system default opener — QuickLook / VLC / preferred player.
    #[cfg(target_os = "macos")]
    {
        std::process::Command::new("open")
            .arg(&master_path)
            .spawn()
            .map_err(|e| BundleError::Io(std::io::Error::other(format!("open: {e}"))))?;
    }
    #[cfg(target_os = "windows")]
    {
        std::process::Command::new("cmd")
            .args(["/C", "start", "", master_path.to_str().unwrap_or("")])
            .spawn()
            .map_err(|e| BundleError::Io(std::io::Error::other(format!("start: {e}"))))?;
    }
    Ok(())
}

/// Reveal a processed file in Finder/Explorer. Scoped by
/// (bundle_uid, in_zip_path, op_kind) so the user can't ask us to
/// reveal an arbitrary path — we always validate against the
/// processed_files table.
#[tauri::command]
pub fn reveal_processed_file<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
    in_zip_path: String,
    op_kind: String,
) -> Result<(), BundleError> {
    let conn = open_conn(&handle)?;
    let output_path: Option<String> = conn.query_row(
        "SELECT pf.output_path
           FROM processed_files pf
           JOIN bundle_files bf ON bf.id = pf.bundle_file_id
          WHERE bf.bundle_uid = ?1 AND bf.in_zip_path = ?2 AND pf.op_kind = ?3",
        params![uid, in_zip_path, op_kind],
        |r| r.get(0),
    ).optional()?;
    let path = output_path
        .ok_or_else(|| BundleError::NotFound(format!("{uid}::{in_zip_path}::{op_kind}")))?;
    if !Path::new(&path).exists() {
        return Err(BundleError::NotFound(path));
    }
    fsutil::reveal_in_file_browser(Path::new(&path))?;
    Ok(())
}

/// Reveal the output produced by a completed job in Finder/Explorer.
/// Looks up the job's params_json and routes by `kind`. Scoping reveal
/// to a known job id keeps us from exposing a generic
/// `reveal_arbitrary_path` command from the frontend (any path on
/// disk would be a footgun).
#[tauri::command]
pub fn reveal_job_output<R: Runtime>(
    handle: AppHandle<R>,
    job_id: i64,
) -> Result<(), BundleError> {
    let conn = open_conn(&handle)?;
    let (kind, params_json): (String, String) = conn.query_row(
        "SELECT kind, params_json FROM jobs WHERE id = ?1",
        params![job_id],
        |row| Ok((row.get(0)?, row.get(1)?)),
    ).optional()?
        .ok_or_else(|| BundleError::NotFound(format!("job {job_id}")))?;

    let output_path: String = match kind.as_str() {
        "process_video" => {
            let p: crate::video::ProcessVideoParams = serde_json::from_str(&params_json)
                .map_err(|e| BundleError::Io(std::io::Error::other(format!("bad params: {e}"))))?;
            p.output_path
        }
        "render_title" => {
            let p: crate::auto_assemble::RenderTitleParams = serde_json::from_str(&params_json)
                .map_err(|e| BundleError::Io(std::io::Error::other(format!("bad params: {e}"))))?;
            p.output_path
        }
        "normalize_video" => {
            let p: crate::auto_assemble::NormalizeVideoParams = serde_json::from_str(&params_json)
                .map_err(|e| BundleError::Io(std::io::Error::other(format!("bad params: {e}"))))?;
            p.output_path
        }
        "assemble_master" => {
            let p: crate::auto_assemble::AssembleMasterParams = serde_json::from_str(&params_json)
                .map_err(|e| BundleError::Io(std::io::Error::other(format!("bad params: {e}"))))?;
            p.output_path
        }
        "transcribe_video" => {
            let p: crate::transcribe::TranscribeVideoParams = serde_json::from_str(&params_json)
                .map_err(|e| BundleError::Io(std::io::Error::other(format!("bad params: {e}"))))?;
            // Reveal the .txt sidecar (most likely target) rather than
            // the .json. If the .txt isn't there yet, fall back to JSON.
            let json = std::path::Path::new(&p.json_output_path);
            let txt = json.with_extension("txt");
            if txt.exists() { txt.to_string_lossy().to_string() }
            else { p.json_output_path }
        }
        other => return Err(BundleError::NotFound(format!("unknown job kind: {other}"))),
    };
    if !Path::new(&output_path).exists() {
        return Err(BundleError::NotFound(output_path));
    }
    fsutil::reveal_in_file_browser(Path::new(&output_path))?;
    Ok(())
}

#[tauri::command]
pub fn get_processed_previews<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<std::collections::HashMap<String, String>, BundleError> {
    use base64::{engine::general_purpose::STANDARD, Engine as _};
    let conn = open_conn(&handle)?;
    // For image outputs the processed file is a JPEG we can base64-embed.
    // For video outputs the processed file is an .mp4 — base64-ing it as
    // image/jpeg gives the browser garbage and the row renders the 🖼
    // placeholder (the bug Robert hit 2026-05-24). Fall back to the
    // source video's bundle_files.thumbnail_path (an ffmpeg-extracted
    // frame at t=1s, generated by thumbnails.rs).
    let mut stmt = conn.prepare(
        "SELECT bf.in_zip_path, bf.kind, pf.output_path, bf.thumbnail_path
           FROM processed_files pf
           JOIN bundle_files bf ON bf.id = pf.bundle_file_id
          WHERE bf.bundle_uid = ?1
          ORDER BY pf.created_at DESC",
    )?;
    let rows: Vec<(String, String, String, Option<String>)> = stmt
        .query_map(params![uid], |row| Ok((
            row.get(0)?, row.get(1)?, row.get(2)?, row.get::<_, Option<String>>(3)?,
        )))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    drop(stmt);

    let mut out: std::collections::HashMap<String, String> =
        std::collections::HashMap::with_capacity(rows.len());
    for (in_zip, kind, output_path, thumb_path) in rows {
        if out.contains_key(&in_zip) { continue; } // most-recent op wins
        // Pick the right source for the preview JPEG.
        let preview_src: Option<String> = match kind.as_str() {
            "image" => Some(output_path),
            "video" => thumb_path.filter(|p| !p.is_empty()),
            _ => None,
        };
        let Some(src) = preview_src else { continue };
        let Ok(bytes) = fs::read(&src) else { continue };
        out.insert(in_zip, format!("data:image/jpeg;base64,{}", STANDARD.encode(&bytes)));
    }
    Ok(out)
}

// ---------------------------------------------------------------------------
// Tests — exercise persist_validated against an in-memory DB so the
// commands' transactional behaviour is locked.
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bundle_io::{HashesDoc, HashesFile, HashesInnerZip};

    fn fresh_db() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch("PRAGMA foreign_keys = ON;").unwrap();
        conn.execute_batch(include_str!("../migrations/001_init.sql")).unwrap();
        conn.execute_batch(include_str!("../migrations/002_bundles.sql")).unwrap();
        conn.execute_batch(include_str!("../migrations/003_bundle_files.sql")).unwrap();
        conn.execute_batch(include_str!("../migrations/004_export_thumbs.sql")).unwrap();
        conn.execute_batch(include_str!("../migrations/005_image_ops.sql")).unwrap();
        conn.execute_batch(include_str!("../migrations/006_jobs.sql")).unwrap();
        conn.execute_batch(include_str!("../migrations/007_video_processed_files.sql")).unwrap();
        conn.execute_batch(include_str!("../migrations/008_watermark_per_media.sql")).unwrap();
        conn.execute_batch(include_str!("../migrations/009_bundle_file_rotation.sql")).unwrap();
        conn.execute_batch(include_str!("../migrations/010_jobs_kind_widen.sql")).unwrap();
        conn.execute_batch(include_str!("../migrations/011_auto_assembly_settings.sql")).unwrap();
        conn.execute_batch(include_str!("../migrations/012_processing_log.sql")).unwrap();
        conn.execute_batch(include_str!("../migrations/013_dropbox.sql")).unwrap();
        conn.execute_batch(include_str!("../migrations/014_dropbox_template_default.sql")).unwrap();
        conn.execute_batch(include_str!("../migrations/015_posting.sql")).unwrap();
        conn
    }

    fn fixture_validated(uid: &str, files: &[(&str, &str, u64)]) -> ValidatedBundle {
        let hashes_files = files
            .iter()
            .map(|(path, sha, _)| HashesFile {
                path: path.to_string(),
                sha256: sha.to_string(),
            })
            .collect();
        let file_sizes = files
            .iter()
            .map(|(path, _, size)| (path.to_string(), *size))
            .collect();
        ValidatedBundle {
            hashes: HashesDoc {
                bundle_uid: uid.to_string(),
                inner_zip: HashesInnerZip {
                    name: format!("{uid}-inner.zip"),
                    sha256: "i".repeat(64),
                    bytes: 0,
                },
                files: hashes_files,
            },
            source_zip_sha256: "s".repeat(64),
            info_md: "# Test\n".into(),
            molly_log: format!("Bundle UID: {uid}\nBundle type: fansite\n"),
            manifest_json: None,
            file_sizes,
            inner_zip_bytes: Vec::new(),
        }
    }

    fn fansite_manifest(uid: &str) -> BundleManifest {
        BundleManifest {
            uid: uid.to_string(),
            bundle_type: "fansite".to_string(),
            persona_code: Some("CoC".to_string()),
            title: "test".to_string(),
            fansite_year: Some(2026),
            fansite_month: Some(6),
            ..Default::default()
        }
    }

    #[test]
    fn persist_inserts_bundle_and_files() {
        let mut conn = fresh_db();
        let v = fixture_validated(
            "2026-01-01-0001",
            &[
                ("info.md", "a".repeat(64).as_str(), 10),
                ("Molly.log", "b".repeat(64).as_str(), 20),
                ("FanSite/01_01_pic.jpg", "c".repeat(64).as_str(), 30),
            ],
        );
        let m = fansite_manifest("2026-01-01-0001");
        let n = persist_validated(&mut conn, &v, &m, "molly_log", "/tmp/x.zip").unwrap();
        assert_eq!(n, 3, "all three inner-zip entries land in bundle_files");
        let count: i64 = conn
            .query_row("SELECT COUNT(*) FROM bundles", [], |r| r.get(0))
            .unwrap();
        assert_eq!(count, 1);
    }

    #[test]
    fn re_ingest_is_idempotent_and_preserves_uid_keyed_rows() {
        let mut conn = fresh_db();
        let v1 = fixture_validated("2026-01-01-0001", &[
            ("info.md", "a".repeat(64).as_str(), 1),
            ("FanSite/01_01_a.jpg", "b".repeat(64).as_str(), 2),
        ]);
        let m1 = fansite_manifest("2026-01-01-0001");
        persist_validated(&mut conn, &v1, &m1, "molly_log", "/tmp/v1.zip").unwrap();

        // Same UID, different files (simulating a re-publish).
        let v2 = fixture_validated("2026-01-01-0001", &[
            ("info.md", "z".repeat(64).as_str(), 5),
            ("Molly.log", "y".repeat(64).as_str(), 6),
            ("FanSite/02_01_b.jpg", "x".repeat(64).as_str(), 7),
        ]);
        let mut m2 = fansite_manifest("2026-01-01-0001");
        m2.title = "rev2".to_string();
        persist_validated(&mut conn, &v2, &m2, "molly_log", "/tmp/v2.zip").unwrap();

        let count: i64 = conn
            .query_row("SELECT COUNT(*) FROM bundles", [], |r| r.get(0))
            .unwrap();
        assert_eq!(count, 1, "still one bundle row — UID-keyed UPSERT");
        let title: String = conn
            .query_row("SELECT title FROM bundles WHERE uid = '2026-01-01-0001'", [], |r| r.get(0))
            .unwrap();
        assert_eq!(title, "rev2");
        let files: i64 = conn
            .query_row("SELECT COUNT(*) FROM bundle_files WHERE bundle_uid = '2026-01-01-0001'", [], |r| r.get(0))
            .unwrap();
        assert_eq!(files, 3, "old file rows replaced with new ones");
    }

    #[test]
    fn fansite_file_rows_capture_day_and_position() {
        let mut conn = fresh_db();
        let v = fixture_validated("2026-06-01-0001", &[
            ("FanSite/07_02_clip.mov", "1".repeat(64).as_str(), 100),
            ("FanSite/13_01_pic.jpg", "2".repeat(64).as_str(), 200),
        ]);
        let m = fansite_manifest("2026-06-01-0001");
        persist_validated(&mut conn, &v, &m, "molly_log", "/tmp/x.zip").unwrap();

        let mut stmt = conn.prepare(
            "SELECT in_zip_path, kind, position, fansite_day_of_month, original_name, size_bytes
             FROM bundle_files WHERE bundle_uid = ?1 ORDER BY fansite_day_of_month",
        ).unwrap();
        let rows: Vec<(String, String, i64, Option<i64>, String, i64)> = stmt
            .query_map(params!["2026-06-01-0001"], |r| {
                Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?))
            }).unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].1, "video");
        assert_eq!(rows[0].2, 2, "position from FanSite/07_02_...");
        assert_eq!(rows[0].3, Some(7));
        assert_eq!(rows[0].4, "clip.mov");
        assert_eq!(rows[0].5, 100);
        assert_eq!(rows[1].3, Some(13));
        assert_eq!(rows[1].1, "image");
    }

    #[test]
    fn delete_cascades_files() {
        let mut conn = fresh_db();
        let v = fixture_validated("x", &[
            ("info.md", "a".repeat(64).as_str(), 1),
            ("FanSite/01_01_a.jpg", "b".repeat(64).as_str(), 2),
        ]);
        let m = fansite_manifest("x");
        persist_validated(&mut conn, &v, &m, "molly_log", "/tmp/x.zip").unwrap();
        conn.execute("DELETE FROM bundles WHERE uid = 'x'", []).unwrap();
        let n: i64 = conn
            .query_row("SELECT COUNT(*) FROM bundle_files WHERE bundle_uid = 'x'", [], |r| r.get(0))
            .unwrap();
        assert_eq!(n, 0, "ON DELETE CASCADE wipes file rows");
    }

    #[test]
    fn check_constraint_rejects_invalid_bundle_type() {
        let conn = fresh_db();
        let now = iso_now();
        let r = conn.execute(
            "INSERT INTO bundles (uid, bundle_type, source_zip_path, ingested_at,
                                  verify_status, manifest_source, manifest_json,
                                  bundle_state, created_at, updated_at)
             VALUES ('x', 'nonsense', '/x.zip', ?1, 'verified', 'molly_log',
                     '{}', 'new', ?1, ?1)",
            params![now],
        );
        assert!(r.is_err(), "CHECK should reject bundle_type='nonsense'");
    }
}
