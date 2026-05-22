// Phase 12: generic background-jobs runner.
//
// Architecture intentionally minimal:
//   - `background_jobs` rows describe recurring tasks (kind + cadence).
//   - `background_job_runs` rows are an append-only history.
//   - `tick(...)` is the runner heartbeat — pure SQL, no async deps.
//     Called every 60s from a spawned task in lib.rs::setup.
//   - Dispatch is a `match kind { ... }` — for v1 only 'atw_repost'
//     exists; future kinds (other site automations, summary digests,
//     etc.) slot in by adding a match arm + a runner module.
//
// We do NOT overload the existing schedules/occurrences system —
// that's UI-facing (materialize "what reminders show today?"), this
// is execution-facing (fire a Tauri command at cadence X).

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use chrono::{DateTime, Utc};
use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, Runtime, State};

use crate::atw;
use crate::crypto::keystore::KeystoreState;
use crate::crypto::CryptoError;

/// How often the runner ticks; jobs fire when `next_run_at <= now`.
/// Coarser than the user's cadence (so a 4h job that's 3 min late
/// fires within 60s of becoming due rather than 0s).
const TICK_INTERVAL_SECONDS: u64 = 60;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BackgroundJob {
    pub id: i64,
    pub kind: String,
    pub name: String,
    pub enabled: bool,
    pub cadence_seconds: i64,
    pub params_json: String,
    pub last_run_at: Option<String>,
    pub next_run_at: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BackgroundJobRun {
    pub id: i64,
    pub job_id: i64,
    pub started_at: String,
    pub finished_at: Option<String>,
    pub status: String,
    pub summary: String,
    pub log_excerpt: String,
}

fn app_data_dir<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, CryptoError> {
    handle
        .path()
        .app_data_dir()
        .map_err(|e| CryptoError::Internal(format!("app_data_dir: {e}")))
}

fn open_conn(app_data: &Path) -> Result<Connection, CryptoError> {
    let db_path = app_data.join("molly.db");
    let conn = Connection::open(&db_path)
        .map_err(|e| CryptoError::Db(format!("open {}: {e}", db_path.display())))?;
    conn.busy_timeout(Duration::from_secs(5))?;
    conn.execute_batch("PRAGMA foreign_keys = ON;")?;
    Ok(conn)
}

// ----- Pure CRUD helpers ------------------------------------------------------

pub(crate) fn pure_list_jobs(conn: &Connection) -> Result<Vec<BackgroundJob>, CryptoError> {
    let mut stmt = conn.prepare(
        "SELECT id, kind, name, enabled, cadence_seconds, params_json,
                last_run_at, next_run_at, created_at, updated_at
         FROM background_jobs
         ORDER BY id ASC",
    )?;
    let rows = stmt
        .query_map([], |r| {
            Ok(BackgroundJob {
                id: r.get(0)?,
                kind: r.get(1)?,
                name: r.get(2)?,
                enabled: r.get::<_, i64>(3)? != 0,
                cadence_seconds: r.get(4)?,
                params_json: r.get(5)?,
                last_run_at: r.get(6)?,
                next_run_at: r.get(7)?,
                created_at: r.get(8)?,
                updated_at: r.get(9)?,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

pub(crate) fn pure_list_runs(
    conn: &Connection,
    job_id: i64,
    limit: i64,
) -> Result<Vec<BackgroundJobRun>, CryptoError> {
    let mut stmt = conn.prepare(
        "SELECT id, job_id, started_at, finished_at, status, summary, log_excerpt
         FROM background_job_runs
         WHERE job_id = ?1
         ORDER BY started_at DESC, id DESC
         LIMIT ?2",
    )?;
    let rows = stmt
        .query_map(params![job_id, limit], |r| {
            Ok(BackgroundJobRun {
                id: r.get(0)?,
                job_id: r.get(1)?,
                started_at: r.get(2)?,
                finished_at: r.get(3)?,
                status: r.get(4)?,
                summary: r.get(5)?,
                log_excerpt: r.get(6)?,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

pub(crate) fn pure_upsert_job(
    conn: &Connection,
    kind: &str,
    name: &str,
    cadence_seconds: i64,
) -> Result<i64, CryptoError> {
    // Idempotent — if a row of this kind exists, update cadence + name.
    let existing: Option<i64> = conn
        .query_row(
            "SELECT id FROM background_jobs WHERE kind = ?1 LIMIT 1",
            params![kind],
            |r| r.get(0),
        )
        .ok();
    if let Some(id) = existing {
        conn.execute(
            "UPDATE background_jobs
             SET name = ?1, cadence_seconds = ?2, updated_at = datetime('now')
             WHERE id = ?3",
            params![name, cadence_seconds, id],
        )?;
        return Ok(id);
    }
    let next_run = (Utc::now() + chrono::Duration::seconds(cadence_seconds)).to_rfc3339();
    conn.execute(
        "INSERT INTO background_jobs (kind, name, cadence_seconds, next_run_at)
         VALUES (?1, ?2, ?3, ?4)",
        params![kind, name, cadence_seconds, next_run],
    )?;
    Ok(conn.last_insert_rowid())
}

pub(crate) fn pure_set_enabled(
    conn: &Connection,
    job_id: i64,
    enabled: bool,
) -> Result<(), CryptoError> {
    conn.execute(
        "UPDATE background_jobs SET enabled = ?1, updated_at = datetime('now') WHERE id = ?2",
        params![if enabled { 1 } else { 0 }, job_id],
    )?;
    Ok(())
}

pub(crate) fn pure_set_cadence(
    conn: &Connection,
    job_id: i64,
    cadence_seconds: i64,
) -> Result<(), CryptoError> {
    let next_run = (Utc::now() + chrono::Duration::seconds(cadence_seconds)).to_rfc3339();
    conn.execute(
        "UPDATE background_jobs
         SET cadence_seconds = ?1, next_run_at = ?2, updated_at = datetime('now')
         WHERE id = ?3",
        params![cadence_seconds, next_run, job_id],
    )?;
    Ok(())
}

/// Insert a 'running' run row; returns the new id. Caller updates with
/// final status + summary + log_excerpt when the dispatch completes.
pub(crate) fn pure_begin_run(
    conn: &Connection,
    job_id: i64,
) -> Result<i64, CryptoError> {
    conn.execute(
        "INSERT INTO background_job_runs (job_id, status) VALUES (?1, 'running')",
        params![job_id],
    )?;
    Ok(conn.last_insert_rowid())
}

pub(crate) fn pure_finish_run(
    conn: &Connection,
    run_id: i64,
    status: &str,
    summary: &str,
    log_excerpt: &str,
) -> Result<(), CryptoError> {
    conn.execute(
        "UPDATE background_job_runs
         SET finished_at = datetime('now'),
             status = ?1, summary = ?2, log_excerpt = ?3
         WHERE id = ?4",
        params![status, summary, log_excerpt, run_id],
    )?;
    Ok(())
}

/// After a successful or failed run, advance the job's next_run_at.
pub(crate) fn pure_mark_job_ran(
    conn: &Connection,
    job_id: i64,
) -> Result<(), CryptoError> {
    let cadence: i64 = conn.query_row(
        "SELECT cadence_seconds FROM background_jobs WHERE id = ?1",
        params![job_id],
        |r| r.get(0),
    )?;
    let next_run = (Utc::now() + chrono::Duration::seconds(cadence)).to_rfc3339();
    conn.execute(
        "UPDATE background_jobs
         SET last_run_at = datetime('now'), next_run_at = ?1, updated_at = datetime('now')
         WHERE id = ?2",
        params![next_run, job_id],
    )?;
    Ok(())
}

/// Find jobs whose next_run_at has passed. Pure SQL — `now` is passed
/// in to keep the function testable.
pub(crate) fn pure_due_jobs(
    conn: &Connection,
    now: DateTime<Utc>,
) -> Result<Vec<BackgroundJob>, CryptoError> {
    let now_str = now.to_rfc3339();
    let mut stmt = conn.prepare(
        "SELECT id, kind, name, enabled, cadence_seconds, params_json,
                last_run_at, next_run_at, created_at, updated_at
         FROM background_jobs
         WHERE enabled = 1
           AND (next_run_at IS NULL OR next_run_at <= ?1)
         ORDER BY id ASC",
    )?;
    let rows = stmt
        .query_map(params![now_str], |r| {
            Ok(BackgroundJob {
                id: r.get(0)?,
                kind: r.get(1)?,
                name: r.get(2)?,
                enabled: r.get::<_, i64>(3)? != 0,
                cadence_seconds: r.get(4)?,
                params_json: r.get(5)?,
                last_run_at: r.get(6)?,
                next_run_at: r.get(7)?,
                created_at: r.get(8)?,
                updated_at: r.get(9)?,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

// ----- Runner heartbeat ------------------------------------------------------

/// Single tick of the runner. Selects due jobs, dispatches each, writes
/// a run row, advances next_run_at. Errors from individual jobs are
/// recorded as `failed` rows — the tick itself never fails the loop.
///
/// Note: this is intentionally async because the dispatched jobs
/// (currently only ATW) are async themselves.
pub async fn tick<R: Runtime>(
    handle: &AppHandle<R>,
    state: &State<'_, Arc<KeystoreState>>,
) -> Result<(), CryptoError> {
    let app_data = app_data_dir(handle)?;
    let conn = open_conn(&app_data)?;
    let due = pure_due_jobs(&conn, Utc::now())?;
    drop(conn);

    for job in due {
        // Begin run row.
        let conn = open_conn(&app_data)?;
        let run_id = pure_begin_run(&conn, job.id)?;
        drop(conn);

        // Dispatch (catches errors; "panicked dispatch" can't propagate
        // because catch_unwind on async is gnarly — keep the dispatchers
        // returning Result and we treat any Err as failed).
        let outcome = match job.kind.as_str() {
            "atw_repost" => atw::run_once(handle, state).await,
            other => Err(CryptoError::Internal(format!(
                "unknown background job kind: {other}"
            ))),
        };

        let conn = open_conn(&app_data)?;
        match outcome {
            Ok(o) => {
                pure_finish_run(&conn, run_id, &o.status, &o.summary, &o.log_excerpt)?;
            }
            Err(e) => {
                pure_finish_run(&conn, run_id, "failed", &format!("{}", e), "")?;
            }
        }
        pure_mark_job_ran(&conn, job.id)?;
    }
    Ok(())
}

/// Background runner loop spawned from lib.rs::setup. Polls every 60s.
pub async fn run_loop<R: Runtime>(handle: AppHandle<R>) {
    let mut interval = tokio::time::interval(Duration::from_secs(TICK_INTERVAL_SECONDS));
    interval.tick().await; // skip immediate tick
    loop {
        interval.tick().await;
        let state: State<Arc<KeystoreState>> = match handle.try_state() {
            Some(s) => s,
            None => continue,
        };
        if let Err(err) = tick(&handle, &state).await {
            eprintln!("[molly] background job tick failed: {err}");
        }
    }
}

// ----- Tauri commands --------------------------------------------------------

#[tauri::command]
pub fn list_background_jobs<R: Runtime>(
    handle: AppHandle<R>,
) -> Result<Vec<BackgroundJob>, CryptoError> {
    let app_data = app_data_dir(&handle)?;
    let conn = open_conn(&app_data)?;
    pure_list_jobs(&conn)
}

#[tauri::command]
pub fn list_job_runs<R: Runtime>(
    handle: AppHandle<R>,
    job_id: i64,
    limit: Option<i64>,
) -> Result<Vec<BackgroundJobRun>, CryptoError> {
    let app_data = app_data_dir(&handle)?;
    let conn = open_conn(&app_data)?;
    pure_list_runs(&conn, job_id, limit.unwrap_or(50))
}

#[tauri::command]
pub fn upsert_atw_job<R: Runtime>(
    handle: AppHandle<R>,
    cadence_seconds: i64,
) -> Result<i64, CryptoError> {
    let app_data = app_data_dir(&handle)?;
    let conn = open_conn(&app_data)?;
    pure_upsert_job(&conn, "atw_repost", "ATW Repost", cadence_seconds)
}

#[tauri::command]
pub fn set_job_enabled<R: Runtime>(
    handle: AppHandle<R>,
    job_id: i64,
    enabled: bool,
) -> Result<(), CryptoError> {
    let app_data = app_data_dir(&handle)?;
    let conn = open_conn(&app_data)?;
    pure_set_enabled(&conn, job_id, enabled)
}

#[tauri::command]
pub fn set_job_cadence<R: Runtime>(
    handle: AppHandle<R>,
    job_id: i64,
    cadence_seconds: i64,
) -> Result<(), CryptoError> {
    let app_data = app_data_dir(&handle)?;
    let conn = open_conn(&app_data)?;
    pure_set_cadence(&conn, job_id, cadence_seconds)
}

/// On-demand run from the React UI. Writes the run row + invokes the
/// dispatcher just like the tick loop would.
#[tauri::command]
pub async fn run_job_now<R: Runtime>(
    handle: AppHandle<R>,
    state: State<'_, Arc<KeystoreState>>,
    job_id: i64,
) -> Result<i64, CryptoError> {
    let app_data = app_data_dir(&handle)?;
    let conn = open_conn(&app_data)?;
    let kind: String = conn.query_row(
        "SELECT kind FROM background_jobs WHERE id = ?1",
        params![job_id],
        |r| r.get(0),
    )?;
    let run_id = pure_begin_run(&conn, job_id)?;
    drop(conn);

    let outcome = match kind.as_str() {
        "atw_repost" => atw::run_once(&handle, &state).await,
        other => Err(CryptoError::Internal(format!("unknown kind {other}"))),
    };

    let conn = open_conn(&app_data)?;
    match outcome {
        Ok(o) => {
            pure_finish_run(&conn, run_id, &o.status, &o.summary, &o.log_excerpt)?;
        }
        Err(e) => {
            pure_finish_run(&conn, run_id, "failed", &format!("{}", e), "")?;
        }
    }
    pure_mark_job_ran(&conn, job_id)?;
    Ok(run_id)
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Duration as CDur;
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
            include_str!("../migrations/016_c4s_clips.sql"),
            include_str!("../migrations/017_bundles.sql"),
            include_str!("../migrations/018_crypto_keystore.sql"),
            include_str!("../migrations/019_site_credentials.sql"),
            include_str!("../migrations/020_background_jobs.sql"),
        ] {
            conn.execute_batch(sql).unwrap();
        }
        conn
    }

    #[test]
    fn upsert_creates_then_updates() {
        let conn = fresh_db();
        let id1 = pure_upsert_job(&conn, "atw_repost", "ATW Repost", 14400).unwrap();
        let id2 = pure_upsert_job(&conn, "atw_repost", "ATW Repost (renamed)", 7200).unwrap();
        assert_eq!(id1, id2, "second upsert should reuse the existing row");
        let jobs = pure_list_jobs(&conn).unwrap();
        assert_eq!(jobs.len(), 1);
        assert_eq!(jobs[0].name, "ATW Repost (renamed)");
        assert_eq!(jobs[0].cadence_seconds, 7200);
    }

    #[test]
    fn due_jobs_filters_correctly() {
        let conn = fresh_db();
        let _due = pure_upsert_job(&conn, "kind_a", "A", 60).unwrap();
        // Force its next_run_at into the past.
        conn.execute(
            "UPDATE background_jobs SET next_run_at = ?1 WHERE kind = 'kind_a'",
            params![(Utc::now() - CDur::hours(1)).to_rfc3339()],
        )
        .unwrap();
        let not_due = pure_upsert_job(&conn, "kind_b", "B", 60).unwrap();
        conn.execute(
            "UPDATE background_jobs SET next_run_at = ?1 WHERE id = ?2",
            params![(Utc::now() + CDur::hours(1)).to_rfc3339(), not_due],
        )
        .unwrap();
        let due = pure_due_jobs(&conn, Utc::now()).unwrap();
        assert_eq!(due.len(), 1);
        assert_eq!(due[0].kind, "kind_a");
    }

    #[test]
    fn disabled_jobs_never_due() {
        let conn = fresh_db();
        let id = pure_upsert_job(&conn, "kind_a", "A", 60).unwrap();
        conn.execute(
            "UPDATE background_jobs SET next_run_at = ?1 WHERE id = ?2",
            params![(Utc::now() - CDur::hours(1)).to_rfc3339(), id],
        )
        .unwrap();
        pure_set_enabled(&conn, id, false).unwrap();
        let due = pure_due_jobs(&conn, Utc::now()).unwrap();
        assert!(due.is_empty());
    }

    #[test]
    fn begin_then_finish_run() {
        let conn = fresh_db();
        let job_id = pure_upsert_job(&conn, "kind_a", "A", 60).unwrap();
        let run_id = pure_begin_run(&conn, job_id).unwrap();
        let runs = pure_list_runs(&conn, job_id, 10).unwrap();
        assert_eq!(runs.len(), 1);
        assert_eq!(runs[0].status, "running");
        assert!(runs[0].finished_at.is_none());

        pure_finish_run(&conn, run_id, "success", "did the thing", "log line\nline 2").unwrap();
        let runs = pure_list_runs(&conn, job_id, 10).unwrap();
        assert_eq!(runs[0].status, "success");
        assert_eq!(runs[0].summary, "did the thing");
        assert!(runs[0].finished_at.is_some());
    }

    #[test]
    fn mark_job_ran_advances_next_run_at() {
        let conn = fresh_db();
        let id = pure_upsert_job(&conn, "kind_a", "A", 60).unwrap();
        let before: Option<String> = conn
            .query_row(
                "SELECT next_run_at FROM background_jobs WHERE id = ?1",
                params![id],
                |r| r.get(0),
            )
            .unwrap();
        std::thread::sleep(std::time::Duration::from_millis(50));
        pure_mark_job_ran(&conn, id).unwrap();
        let after: Option<String> = conn
            .query_row(
                "SELECT next_run_at FROM background_jobs WHERE id = ?1",
                params![id],
                |r| r.get(0),
            )
            .unwrap();
        assert_ne!(before, after, "next_run_at should advance after mark_job_ran");
        let last: Option<String> = conn
            .query_row(
                "SELECT last_run_at FROM background_jobs WHERE id = ?1",
                params![id],
                |r| r.get(0),
            )
            .unwrap();
        assert!(last.is_some());
    }

    #[test]
    fn deleting_job_cascades_runs() {
        let conn = fresh_db();
        let id = pure_upsert_job(&conn, "kind_a", "A", 60).unwrap();
        pure_begin_run(&conn, id).unwrap();
        pure_begin_run(&conn, id).unwrap();
        assert_eq!(pure_list_runs(&conn, id, 10).unwrap().len(), 2);
        conn.execute("DELETE FROM background_jobs WHERE id = ?1", params![id]).unwrap();
        // FK cascade should have wiped the runs.
        let leftover: i64 = conn
            .query_row("SELECT COUNT(*) FROM background_job_runs WHERE job_id = ?1", params![id], |r| r.get(0))
            .unwrap();
        assert_eq!(leftover, 0);
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
#[allow(dead_code)] // reserved for future "create custom job" UI
pub struct CreateJobPayload {
    pub kind: String,
    pub name: String,
    pub cadence_seconds: i64,
}
