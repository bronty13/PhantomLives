// Central activity log for SideMolly processing.
//
// One row per significant event during job execution — job lifecycle
// transitions (claimed / done / failed), watermark cache misses,
// DeepFilterNet skip-due-to-missing-binary, etc. Written by every
// dispatcher (job-level events from jobs.rs; op-specific events from
// the per-kind modules when something noteworthy happens).
//
// Surfaces:
//   - Edit tab Step 6 "📜 Activity log" — per-bundle, newest-first.
//   - `export_bundle_log` Tauri command — writes a text file to the
//     bundle workspace, ready to fold into the Phase 11 return-bundle
//     ZIP back to Molly.

use std::fs;
use std::path::PathBuf;

use rusqlite::{params, Connection, OptionalExtension};
use serde::Serialize;
use tauri::{AppHandle, Manager, Runtime};

use crate::bundles::{work_root, BundleError};
use crate::extract::bundle_workspace_dir;

/// Log levels match the standard info/warn/error trio.
#[derive(Debug, Clone, Copy)]
pub enum Level { Info, Warn, Error }

impl Level {
    fn as_str(self) -> &'static str {
        match self { Level::Info => "info", Level::Warn => "warn", Level::Error => "error" }
    }
}

/// Append one row to processing_log. Failures are swallowed and
/// `eprintln!`'d — logging must never break the job that's logging.
pub fn write(
    conn: &Connection,
    bundle_uid: Option<&str>,
    job_id: Option<i64>,
    kind: Option<&str>,
    level: Level,
    message: &str,
    subject: Option<&str>,
    details: Option<&str>,
) {
    let result = conn.execute(
        "INSERT INTO processing_log
            (bundle_uid, job_id, kind, level, message, subject, details)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        params![bundle_uid, job_id, kind, level.as_str(), message, subject, details],
    );
    if let Err(e) = result {
        eprintln!("[sidemolly:log] insert failed: {e}");
    }
}

// ---------------------------------------------------------------------------
// Tauri-boundary types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LogRow {
    pub id: i64,
    pub timestamp: String,
    pub bundle_uid: Option<String>,
    pub job_id: Option<i64>,
    pub kind: Option<String>,
    pub level: String,
    pub message: String,
    pub subject: Option<String>,
    pub details: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ExportLogResult {
    pub bundle_uid: String,
    pub output_path: String,
    pub row_count: i64,
}

// ---------------------------------------------------------------------------
// Tauri commands
// ---------------------------------------------------------------------------

/// Fetch log rows for the UI. When `bundle_uid` is provided, scopes
/// to that bundle. Newest first. `limit` caps the result size so a
/// 10k-row history doesn't fly across the IPC boundary every refresh.
#[tauri::command]
pub fn list_log_entries<R: Runtime>(
    handle: AppHandle<R>,
    bundle_uid: Option<String>,
    limit: Option<i64>,
) -> Result<Vec<LogRow>, BundleError> {
    let conn = open_conn(&handle)?;
    let limit = limit.unwrap_or(500).clamp(1, 5000);
    let (sql, args): (&str, Vec<&dyn rusqlite::ToSql>) = match &bundle_uid {
        Some(uid) => (
            "SELECT id, timestamp, bundle_uid, job_id, kind, level, message, subject, details
               FROM processing_log
              WHERE bundle_uid = ?1
              ORDER BY id DESC
              LIMIT ?2",
            vec![uid, &limit],
        ),
        None => (
            "SELECT id, timestamp, bundle_uid, job_id, kind, level, message, subject, details
               FROM processing_log
              ORDER BY id DESC
              LIMIT ?1",
            vec![&limit],
        ),
    };
    let mut stmt = conn.prepare(sql)?;
    let rows = stmt
        .query_map(rusqlite::params_from_iter(args.iter()), |row| {
            Ok(LogRow {
                id: row.get(0)?,
                timestamp: row.get(1)?,
                bundle_uid: row.get(2)?,
                job_id: row.get(3)?,
                kind: row.get(4)?,
                level: row.get(5)?,
                message: row.get(6)?,
                subject: row.get(7)?,
                details: row.get(8)?,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

/// Dump the bundle's full log to a text file inside the bundle
/// workspace. Path:
///   ~/Library/.../work/<uid>/processing.log
/// Format is one event per line, tab-separated columns. Returned to
/// the caller so the frontend can reveal it in Finder.
#[tauri::command]
pub fn export_bundle_log<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<ExportLogResult, BundleError> {
    let workspace = bundle_workspace_dir(&work_root(&handle)?, &uid);
    fs::create_dir_all(&workspace)?;
    let dst: PathBuf = workspace.join("processing.log");

    let conn = open_conn(&handle)?;
    let mut stmt = conn.prepare(
        "SELECT timestamp, level, kind, subject, message, details
           FROM processing_log
          WHERE bundle_uid = ?1
          ORDER BY id ASC",
    )?;
    let rows: Vec<(String, String, Option<String>, Option<String>, String, Option<String>)> = stmt
        .query_map(params![uid], |row| Ok((
            row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?, row.get(4)?, row.get(5)?,
        )))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    drop(stmt);

    let mut out = String::with_capacity(rows.len() * 80);
    out.push_str(&format!(
        "# SideMolly processing log · bundle {uid} · {} entries\n",
        rows.len(),
    ));
    out.push_str("# columns: timestamp \\t level \\t kind \\t subject \\t message\n\n");
    for (ts, level, kind, subject, message, details) in &rows {
        out.push_str(&format!(
            "{ts}\t{lvl}\t{kind}\t{subj}\t{msg}\n",
            lvl = level,
            kind = kind.as_deref().unwrap_or("-"),
            subj = subject.as_deref().unwrap_or("-"),
            msg = message.replace('\n', " "),
        ));
        if let Some(d) = details {
            for line in d.lines() {
                out.push_str(&format!("\t\t\t\t    | {line}\n"));
            }
        }
    }

    fs::write(&dst, out)?;

    Ok(ExportLogResult {
        bundle_uid: uid,
        output_path: dst.to_string_lossy().to_string(),
        row_count: rows.len() as i64,
    })
}

#[tauri::command]
pub fn clear_bundle_log<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<i64, BundleError> {
    let conn = open_conn(&handle)?;
    let n = conn.execute(
        "DELETE FROM processing_log WHERE bundle_uid = ?1",
        params![uid],
    )?;
    Ok(n as i64)
}

#[tauri::command]
pub fn reveal_bundle_log<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<(), BundleError> {
    let workspace = bundle_workspace_dir(&work_root(&handle)?, &uid);
    let dst = workspace.join("processing.log");
    if !dst.exists() {
        return Err(BundleError::NotFound(format!(
            "{} — call export_bundle_log first", dst.display(),
        )));
    }
    crate::fsutil::reveal_in_file_browser(&dst)?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn open_conn<R: Runtime>(handle: &AppHandle<R>) -> Result<Connection, BundleError> {
    let dir = handle.path()
        .resolve("", tauri::path::BaseDirectory::AppLocalData)
        .map_err(|e| BundleError::Io(std::io::Error::other(format!("appdata path: {e}"))))?;
    let db_path = dir.join("sidemolly.db");
    let conn = Connection::open(db_path)?;
    Ok(conn)
}

// Lookup the bundle_uid for a job. Convenience for callers that
// only have a job_id in hand (e.g. the worker dispatcher logging
// inside jobs.rs).
pub fn bundle_uid_for_job(conn: &Connection, job_id: i64) -> Option<String> {
    conn.query_row(
        "SELECT bundle_uid FROM jobs WHERE id = ?1",
        params![job_id],
        |r| r.get::<_, Option<String>>(0),
    ).optional().ok().flatten().flatten()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_db() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(include_str!("../migrations/001_init.sql")).unwrap();
        conn.execute_batch(include_str!("../migrations/002_bundles.sql")).unwrap();
        conn.execute_batch(include_str!("../migrations/003_bundle_files.sql")).unwrap();
        conn.execute_batch(include_str!("../migrations/006_jobs.sql")).unwrap();
        conn.execute_batch(include_str!("../migrations/012_processing_log.sql")).unwrap();
        conn
    }

    #[test]
    fn write_inserts_a_row() {
        let conn = fresh_db();
        // Seed a bundle so the FK on processing_log.bundle_uid resolves.
        conn.execute(
            "INSERT INTO bundles (uid, bundle_type, source_zip_path, manifest_json)
             VALUES ('u', 'content', '/x', '{}')",
            [],
        ).unwrap();
        write(&conn, Some("u"), None, Some("kind"), Level::Info, "hello", Some("file"), None);
        let count: i64 = conn.query_row(
            "SELECT COUNT(*) FROM processing_log WHERE bundle_uid='u'",
            [], |r| r.get(0),
        ).unwrap();
        assert_eq!(count, 1);
    }

    #[test]
    fn null_bundle_uid_skips_foreign_key() {
        let conn = fresh_db();
        write(&conn, None, None, Some("lifecycle"), Level::Info, "app started", None, None);
        let count: i64 = conn.query_row(
            "SELECT COUNT(*) FROM processing_log WHERE bundle_uid IS NULL",
            [], |r| r.get(0),
        ).unwrap();
        assert_eq!(count, 1);
    }

    #[test]
    fn level_check_rejects_unknown() {
        let conn = fresh_db();
        let r = conn.execute(
            "INSERT INTO processing_log (level, message) VALUES ('nonsense', 'x')",
            [],
        );
        assert!(r.is_err(), "CHECK should reject unknown levels");
    }
}
