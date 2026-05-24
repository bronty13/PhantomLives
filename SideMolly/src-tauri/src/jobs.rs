// Phase 4 — generic background job queue.
//
// One sequential worker (spawned from lib.rs::setup) polls the `jobs`
// table every 2s, claims the oldest pending row, dispatches by kind,
// and writes back 'done' or 'failed' + last_error.
//
// Sequential by design: ffmpeg + future transcribers are CPU/GPU-bound
// and parallelism would just thrash. If a kind comes along that's
// I/O-bound (Dropbox upload?), we can add a per-kind concurrency knob
// in a later phase.
//
// Persistence semantics: status moves pending → running → done|failed
// inside the worker thread. The UPDATE that claims a job is atomic
// (UPDATE ... WHERE status='pending') so even if two workers ever ran
// they wouldn't double-claim. job_runs is append-only — one row per
// attempt, populated with started_at + finished_at + exit_code.

use std::path::PathBuf;
use std::time::Duration;

use rusqlite::{params, Connection, OptionalExtension};
use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, Runtime};

use crate::bundles::BundleError;

const POLL_INTERVAL: Duration = Duration::from_secs(2);

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JobRow {
    pub id: i64,
    pub kind: String,
    pub params_json: String,
    pub bundle_uid: Option<String>,
    pub source_in_zip_path: Option<String>,
    pub status: String,
    pub attempts: i64,
    pub last_error: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JobRunRow {
    pub id: i64,
    pub job_id: i64,
    pub started_at: String,
    pub finished_at: Option<String>,
    pub exit_code: Option<i64>,
    pub log_path: Option<String>,
}

fn app_data_dir<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, BundleError> {
    handle
        .path()
        .app_data_dir()
        .map_err(|e| BundleError::AppData(e.to_string()))
}

fn open_conn<R: Runtime>(handle: &AppHandle<R>) -> Result<Connection, BundleError> {
    let path = app_data_dir(handle)?.join("sidemolly.db");
    let conn = Connection::open(path)?;
    conn.execute_batch("PRAGMA foreign_keys = ON;")?;
    Ok(conn)
}

/// Insert a new pending job. Returns the new row id.
pub fn enqueue(
    conn: &Connection,
    kind: &str,
    params_json: &str,
    bundle_uid: Option<&str>,
    source_in_zip_path: Option<&str>,
) -> rusqlite::Result<i64> {
    conn.execute(
        "INSERT INTO jobs (kind, params_json, bundle_uid, source_in_zip_path, status)
         VALUES (?1, ?2, ?3, ?4, 'pending')",
        params![kind, params_json, bundle_uid, source_in_zip_path],
    )?;
    Ok(conn.last_insert_rowid())
}

/// Claim the oldest pending job, transitioning it to 'running' atomically.
/// Returns None if the queue is empty. Increments `attempts` on the
/// claimed row so callers can track retries.
pub fn claim_next_pending(conn: &Connection) -> rusqlite::Result<Option<JobRow>> {
    // Pick the next id; UPDATE to mark running; SELECT it back.
    let next_id: Option<i64> = conn
        .query_row(
            "SELECT id FROM jobs WHERE status = 'pending' ORDER BY created_at ASC LIMIT 1",
            [],
            |r| r.get(0),
        )
        .optional()?;
    let Some(id) = next_id else { return Ok(None); };
    let updated = conn.execute(
        "UPDATE jobs SET status = 'running', attempts = attempts + 1,
                         updated_at = datetime('now')
         WHERE id = ?1 AND status = 'pending'",
        params![id],
    )?;
    if updated == 0 {
        // Lost a race (or the row vanished). Treat as empty.
        return Ok(None);
    }
    Ok(Some(load_one(conn, id)?))
}

pub fn mark_done(conn: &Connection, job_id: i64) -> rusqlite::Result<()> {
    conn.execute(
        "UPDATE jobs SET status = 'done', last_error = NULL,
                         updated_at = datetime('now')
         WHERE id = ?1",
        params![job_id],
    )?;
    Ok(())
}

pub fn mark_failed(conn: &Connection, job_id: i64, err: &str) -> rusqlite::Result<()> {
    conn.execute(
        "UPDATE jobs SET status = 'failed', last_error = ?2,
                         updated_at = datetime('now')
         WHERE id = ?1",
        params![job_id, err],
    )?;
    Ok(())
}

pub fn record_run(
    conn: &Connection,
    job_id: i64,
    exit_code: Option<i64>,
    log_path: Option<&str>,
) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO job_runs (job_id, started_at, finished_at, exit_code, log_path)
         VALUES (?1, datetime('now'), datetime('now'), ?2, ?3)",
        params![job_id, exit_code, log_path],
    )?;
    Ok(())
}

fn load_one(conn: &Connection, id: i64) -> rusqlite::Result<JobRow> {
    conn.query_row(
        "SELECT id, kind, params_json, bundle_uid, source_in_zip_path,
                status, attempts, last_error, created_at, updated_at
         FROM jobs WHERE id = ?1",
        params![id],
        |row| Ok(JobRow {
            id: row.get(0)?,
            kind: row.get(1)?,
            params_json: row.get(2)?,
            bundle_uid: row.get(3)?,
            source_in_zip_path: row.get(4)?,
            status: row.get(5)?,
            attempts: row.get(6)?,
            last_error: row.get(7)?,
            created_at: row.get(8)?,
            updated_at: row.get(9)?,
        }),
    )
}

pub fn list(conn: &Connection, status_filter: Option<&str>) -> rusqlite::Result<Vec<JobRow>> {
    let (sql, args): (&str, Vec<rusqlite::types::Value>) = match status_filter {
        Some(s) if !s.is_empty() && s != "all" => (
            "SELECT id, kind, params_json, bundle_uid, source_in_zip_path,
                    status, attempts, last_error, created_at, updated_at
             FROM jobs WHERE status = ?1
             ORDER BY datetime(updated_at) DESC LIMIT 200",
            vec![s.to_string().into()],
        ),
        _ => (
            "SELECT id, kind, params_json, bundle_uid, source_in_zip_path,
                    status, attempts, last_error, created_at, updated_at
             FROM jobs
             ORDER BY datetime(updated_at) DESC LIMIT 200",
            vec![],
        ),
    };
    let mut stmt = conn.prepare(sql)?;
    let rows = stmt
        .query_map(rusqlite::params_from_iter(args.iter()), |row| Ok(JobRow {
            id: row.get(0)?,
            kind: row.get(1)?,
            params_json: row.get(2)?,
            bundle_uid: row.get(3)?,
            source_in_zip_path: row.get(4)?,
            status: row.get(5)?,
            attempts: row.get(6)?,
            last_error: row.get(7)?,
            created_at: row.get(8)?,
            updated_at: row.get(9)?,
        }))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

pub fn list_runs(conn: &Connection, job_id: i64) -> rusqlite::Result<Vec<JobRunRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, job_id, started_at, finished_at, exit_code, log_path
           FROM job_runs WHERE job_id = ?1 ORDER BY id ASC",
    )?;
    let rows = stmt
        .query_map(params![job_id], |row| Ok(JobRunRow {
            id: row.get(0)?,
            job_id: row.get(1)?,
            started_at: row.get(2)?,
            finished_at: row.get(3)?,
            exit_code: row.get(4)?,
            log_path: row.get(5)?,
        }))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

// ---------------------------------------------------------------------------
// Background worker — spawned from lib.rs::setup. Polls every 2s,
// claims one pending job at a time, dispatches by kind.
// ---------------------------------------------------------------------------

pub fn spawn_worker<R: Runtime>(handle: AppHandle<R>) {
    std::thread::spawn(move || run_worker(handle));
}

fn run_worker<R: Runtime>(handle: AppHandle<R>) {
    eprintln!("[sidemolly:jobs] worker started");
    loop {
        std::thread::sleep(POLL_INTERVAL);
        let conn = match open_conn(&handle) {
            Ok(c) => c,
            Err(e) => {
                eprintln!("[sidemolly:jobs] open conn failed: {e}");
                continue;
            }
        };

        // Phase 12 — honor the user-controlled pause toggle. Worker
        // keeps polling but doesn't claim anything until the user
        // hits Resume. Cheap (one indexed SELECT against
        // app_settings) so the poll loop's wall-clock cost is
        // basically unchanged.
        let paused: Option<String> = conn
            .query_row(
                "SELECT value FROM app_settings WHERE key='jobs_paused'",
                [], |r| r.get(0),
            ).optional().ok().flatten();
        if paused.as_deref() == Some("1") { continue; }

        let job = match claim_next_pending(&conn) {
            Ok(Some(j)) => j,
            Ok(None) => continue,
            Err(e) => {
                eprintln!("[sidemolly:jobs] claim failed: {e}");
                continue;
            }
        };
        // Emit running event before doing work.
        let _ = handle.emit("job-updated", &job);
        crate::processing_log::write(
            &conn, job.bundle_uid.as_deref(), Some(job.id), Some(&job.kind),
            crate::processing_log::Level::Info,
            "started",
            job.source_in_zip_path.as_deref(),
            None,
        );

        // Dispatch.
        let started = std::time::Instant::now();
        let outcome = dispatch(&handle, &conn, &job);
        let elapsed_ms = started.elapsed().as_millis() as i64;

        match outcome {
            Ok(()) => {
                let _ = mark_done(&conn, job.id);
                let _ = record_run(&conn, job.id, Some(0), None);
                crate::processing_log::write(
                    &conn, job.bundle_uid.as_deref(), Some(job.id), Some(&job.kind),
                    crate::processing_log::Level::Info,
                    &format!("done in {:.1}s", elapsed_ms as f64 / 1000.0),
                    job.source_in_zip_path.as_deref(),
                    None,
                );
            }
            Err(e) => {
                let msg = e.to_string();
                eprintln!("[sidemolly:jobs] job {} {} failed: {msg}", job.id, job.kind);
                let _ = mark_failed(&conn, job.id, &msg);
                let _ = record_run(&conn, job.id, Some(-1), None);
                crate::processing_log::write(
                    &conn, job.bundle_uid.as_deref(), Some(job.id), Some(&job.kind),
                    crate::processing_log::Level::Error,
                    "failed",
                    job.source_in_zip_path.as_deref(),
                    Some(&msg),
                );
            }
        }
        // Emit terminal event so frontend can refresh.
        if let Ok(latest) = load_one(&conn, job.id) {
            let _ = handle.emit("job-updated", &latest);
        }
    }
}

/// Dispatch a single claimed job. Errors bubble up so the worker
/// marks the row failed with the message. Kept thin — heavy logic
/// lives in the op-specific modules (video.rs, transcribe.rs in Phase 5).
fn dispatch<R: Runtime>(
    handle: &AppHandle<R>,
    conn: &Connection,
    job: &JobRow,
) -> Result<(), BundleError> {
    match job.kind.as_str() {
        "process_video" => crate::video::dispatch_process_video(handle, conn, job),
        "render_title" => {
            let p: crate::auto_assemble::RenderTitleParams =
                serde_json::from_str(&job.params_json)
                    .map_err(|e| BundleError::Io(std::io::Error::other(
                        format!("render_title bad params: {e}"),
                    )))?;
            crate::auto_assemble::dispatch_render_title(handle, p)
        }
        "normalize_video" => {
            let p: crate::auto_assemble::NormalizeVideoParams =
                serde_json::from_str(&job.params_json)
                    .map_err(|e| BundleError::Io(std::io::Error::other(
                        format!("normalize_video bad params: {e}"),
                    )))?;
            crate::auto_assemble::dispatch_normalize_video(handle, p)
        }
        "assemble_master" => {
            let p: crate::auto_assemble::AssembleMasterParams =
                serde_json::from_str(&job.params_json)
                    .map_err(|e| BundleError::Io(std::io::Error::other(
                        format!("assemble_master bad params: {e}"),
                    )))?;
            crate::auto_assemble::dispatch_assemble_master(handle, p)
        }
        "transcribe_video" => {
            let p: crate::transcribe::TranscribeVideoParams =
                serde_json::from_str(&job.params_json)
                    .map_err(|e| BundleError::Io(std::io::Error::other(
                        format!("transcribe_video bad params: {e}"),
                    )))?;
            crate::transcribe::dispatch_transcribe_video(handle, p)
        }
        other => Err(BundleError::NotFound(format!("unknown job kind: {other}"))),
    }
}

// ---------------------------------------------------------------------------
// Phase 12 — operational commands. Surface in the 🛠 Jobs view.
// ---------------------------------------------------------------------------

/// Reset a failed job back to pending so the worker can take another
/// swing at it. `attempts` counter survives so the row's history is
/// preserved; only `status` and `last_error` flip.
#[tauri::command]
pub fn retry_job<R: Runtime>(
    handle: AppHandle<R>,
    id: i64,
) -> Result<(), BundleError> {
    let conn = open_conn(&handle)?;
    let n = conn.execute(
        "UPDATE jobs
            SET status = 'pending',
                last_error = NULL,
                updated_at = datetime('now')
          WHERE id = ?1 AND status = 'failed'",
        params![id],
    )?;
    if n == 0 {
        return Err(BundleError::NotFound(format!(
            "no failed job {id} to retry (already pending/running/done?)"
        )));
    }
    let _ = handle.emit("job-updated", serde_json::json!({ "id": id }));
    Ok(())
}

/// Drop a pending job before the worker claims it. Running jobs are
/// out of scope — they'd need a signal mechanism inside the
/// dispatchers (ffmpeg etc. don't have a graceful interruption API
/// today). User can mark it failed manually if a hard-kill is needed.
#[tauri::command]
pub fn cancel_pending_job<R: Runtime>(
    handle: AppHandle<R>,
    id: i64,
) -> Result<(), BundleError> {
    let conn = open_conn(&handle)?;
    let n = conn.execute(
        "DELETE FROM jobs WHERE id = ?1 AND status = 'pending'",
        params![id],
    )?;
    if n == 0 {
        return Err(BundleError::NotFound(format!(
            "no pending job {id} to cancel"
        )));
    }
    let _ = handle.emit("job-updated", serde_json::json!({ "deleted": id }));
    Ok(())
}

/// Bulk-delete jobs by status. Returns the number of rows removed.
/// UI uses this for "Clear done" / "Clear failed" — keeps the queue
/// view scannable after a long batch.
#[tauri::command]
pub fn clear_jobs_by_status<R: Runtime>(
    handle: AppHandle<R>,
    statuses: Vec<String>,
) -> Result<i64, BundleError> {
    if statuses.is_empty() {
        return Ok(0);
    }
    for s in &statuses {
        if !["pending", "running", "done", "failed"].contains(&s.as_str()) {
            return Err(BundleError::NotFound(format!("invalid status: {s}")));
        }
    }
    let conn = open_conn(&handle)?;
    let placeholders = statuses.iter().map(|_| "?").collect::<Vec<_>>().join(",");
    let sql = format!("DELETE FROM jobs WHERE status IN ({placeholders})");
    let params_vec: Vec<&dyn rusqlite::ToSql> = statuses.iter()
        .map(|s| s as &dyn rusqlite::ToSql).collect();
    let n = conn.execute(&sql, params_vec.as_slice())?;
    let _ = handle.emit("job-updated", serde_json::json!({ "cleared": n }));
    Ok(n as i64)
}

/// Read the current worker-paused flag from app_settings. Missing key
/// = unpaused.
#[tauri::command]
pub fn get_worker_paused<R: Runtime>(
    handle: AppHandle<R>,
) -> Result<bool, BundleError> {
    let conn = open_conn(&handle)?;
    let v: Option<String> = conn.query_row(
        "SELECT value FROM app_settings WHERE key='jobs_paused'",
        [], |r| r.get(0),
    ).optional()?;
    Ok(v.as_deref() == Some("1"))
}

#[tauri::command]
pub fn set_worker_paused<R: Runtime>(
    handle: AppHandle<R>,
    paused: bool,
) -> Result<(), BundleError> {
    let conn = open_conn(&handle)?;
    conn.execute(
        "INSERT INTO app_settings (key, value) VALUES ('jobs_paused', ?1)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![if paused { "1" } else { "0" }],
    )?;
    let _ = handle.emit("job-updated", serde_json::json!({ "paused": paused }));
    Ok(())
}

// ---------------------------------------------------------------------------
// Tests — pure DB round-trips against an in-memory fresh schema.
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_db() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch("PRAGMA foreign_keys = ON;").unwrap();
        for sql in &[
            include_str!("../migrations/001_init.sql"),
            include_str!("../migrations/002_bundles.sql"),
            include_str!("../migrations/003_bundle_files.sql"),
            include_str!("../migrations/004_export_thumbs.sql"),
            include_str!("../migrations/005_image_ops.sql"),
            include_str!("../migrations/006_jobs.sql"),
        ] {
            conn.execute_batch(sql).unwrap();
        }
        conn
    }

    #[test]
    fn enqueue_then_claim_marks_running_and_increments_attempts() {
        let conn = fresh_db();
        let id = enqueue(&conn, "process_video", "{}", None, None).unwrap();
        assert!(id > 0);
        let claimed = claim_next_pending(&conn).unwrap().unwrap();
        assert_eq!(claimed.id, id);
        assert_eq!(claimed.status, "running");
        assert_eq!(claimed.attempts, 1);
    }

    #[test]
    fn claim_returns_none_when_empty() {
        let conn = fresh_db();
        assert!(claim_next_pending(&conn).unwrap().is_none());
    }

    #[test]
    fn claim_only_returns_pending_jobs() {
        let conn = fresh_db();
        let id = enqueue(&conn, "process_video", "{}", None, None).unwrap();
        // First claim transitions to running.
        let _ = claim_next_pending(&conn).unwrap().unwrap();
        // Second claim of the same row must return None (already running).
        assert!(claim_next_pending(&conn).unwrap().is_none());
        // After marking done, still no pending jobs to claim.
        mark_done(&conn, id).unwrap();
        assert!(claim_next_pending(&conn).unwrap().is_none());
    }

    #[test]
    fn mark_done_clears_error() {
        let conn = fresh_db();
        let id = enqueue(&conn, "process_video", "{}", None, None).unwrap();
        let _ = claim_next_pending(&conn).unwrap();
        mark_failed(&conn, id, "boom").unwrap();
        let row = load_one(&conn, id).unwrap();
        assert_eq!(row.status, "failed");
        assert_eq!(row.last_error.as_deref(), Some("boom"));
        mark_done(&conn, id).unwrap();
        let row = load_one(&conn, id).unwrap();
        assert_eq!(row.status, "done");
        assert!(row.last_error.is_none());
    }

    #[test]
    fn claim_orders_by_created_at_ascending() {
        let conn = fresh_db();
        let a = enqueue(&conn, "process_video", "{\"i\":1}", None, None).unwrap();
        // Force a different created_at by sleeping briefly (sqlite
        // datetime('now') is second-resolution; tweak by re-setting it).
        conn.execute(
            "UPDATE jobs SET created_at = '2026-01-01 00:00:01' WHERE id = ?1",
            params![a],
        ).unwrap();
        let b = enqueue(&conn, "process_video", "{\"i\":2}", None, None).unwrap();
        conn.execute(
            "UPDATE jobs SET created_at = '2026-01-01 00:00:00' WHERE id = ?1",
            params![b],
        ).unwrap();
        // b has the earlier created_at, so claim_next must pick b first.
        let next = claim_next_pending(&conn).unwrap().unwrap();
        assert_eq!(next.id, b, "oldest-pending must be claimed first");
    }

    #[test]
    fn list_filters_by_status() {
        let conn = fresh_db();
        let p = enqueue(&conn, "process_video", "{}", None, None).unwrap();
        let r = enqueue(&conn, "process_video", "{}", None, None).unwrap();
        // Promote r to running.
        conn.execute(
            "UPDATE jobs SET status='running' WHERE id = ?1",
            params![r],
        ).unwrap();

        let all = list(&conn, None).unwrap();
        assert_eq!(all.len(), 2);
        let pending = list(&conn, Some("pending")).unwrap();
        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0].id, p);
        let running = list(&conn, Some("running")).unwrap();
        assert_eq!(running.len(), 1);
        assert_eq!(running[0].id, r);
    }

    #[test]
    fn record_run_persists_per_attempt() {
        let conn = fresh_db();
        let id = enqueue(&conn, "process_video", "{}", None, None).unwrap();
        let _ = claim_next_pending(&conn).unwrap();
        record_run(&conn, id, Some(0), Some("/tmp/x.log")).unwrap();
        let _ = claim_next_pending(&conn).unwrap(); // no-op (already running)
        record_run(&conn, id, Some(1), None).unwrap();
        let runs = list_runs(&conn, id).unwrap();
        assert_eq!(runs.len(), 2);
        assert_eq!(runs[0].exit_code, Some(0));
        assert_eq!(runs[0].log_path.as_deref(), Some("/tmp/x.log"));
        assert_eq!(runs[1].exit_code, Some(1));
    }
}
