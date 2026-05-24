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

use std::path::{Path, PathBuf};

use chrono::Local;
use rusqlite::{params, Connection};
use serde::Serialize;
use tauri::{AppHandle, Manager, Runtime};

use crate::bundle_io::{
    classify_kind, parse_content_prefix, parse_fansite_prefix, verify_outer_zip,
    BundleIoError, ValidatedBundle,
};
use crate::manifest::{
    parse_manifest_json, parse_molly_log, BundleManifest, ManifestError,
};

#[derive(Debug, thiserror::Error)]
pub enum BundleError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("verify: {0}")]
    Verify(#[from] BundleIoError),
    #[error("manifest: {0}")]
    Manifest(#[from] ManifestError),
    #[error("db: {0}")]
    Db(#[from] rusqlite::Error),
    #[error("app data dir: {0}")]
    AppData(String),
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

#[tauri::command]
pub fn ingest_bundle<R: Runtime>(
    handle: AppHandle<R>,
    path: String,
) -> Result<IngestResult, BundleError> {
    let validated = verify_outer_zip(Path::new(&path))?;

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

    let mut conn = open_conn(&handle)?;
    let file_count = persist_validated(
        &mut conn,
        &validated,
        &manifest,
        &manifest_source,
        &path,
    )?;

    Ok(IngestResult {
        uid: manifest.uid,
        bundle_type: manifest.bundle_type,
        persona_code: manifest.persona_code,
        title: manifest.title,
        verify_status: "verified".to_string(),
        file_count,
        manifest_source,
    })
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
                fansite_day_of_month, sha256, size_bytes
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
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;

    Ok(BundleDetail { summary, manifest, files })
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
