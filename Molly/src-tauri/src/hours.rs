// Phase 15 PR2: Hours tracker + reward milestones.
//
// One-at-a-time clock semantics: starting a session while another is
// open auto-stops the open one first (defensive — UI should never get
// into that state, but if it does, don't accumulate orphans).

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};
use tauri::{AppHandle, Manager, Runtime};

#[derive(Debug, thiserror::Error)]
pub enum HoursError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("sqlite: {0}")]
    Sql(#[from] rusqlite::Error),
    #[error("settings: {0}")]
    Settings(String),
    #[error("invalid: {0}")]
    Invalid(String),
    #[error("not found: {0}")]
    NotFound(i64),
    #[error("no open session")]
    NoOpenSession,
}

impl serde::Serialize for HoursError {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.to_string())
    }
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ClockSession {
    pub id: i64,
    pub persona_code: Option<String>,
    pub start_ms: i64,
    /// `None` while the session is still running.
    pub duration_ms: Option<i64>,
    pub notes: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct HoursTotals {
    pub today_ms: i64,
    pub week_ms: i64,
    pub month_ms: i64,
    pub all_time_ms: i64,
    /// `start_ms` of the currently-open session, if any. The UI uses
    /// this to drive a live HH:MM:SS counter without polling.
    pub open_session_start_ms: Option<i64>,
    pub open_session_id: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RewardMilestone {
    pub id: i64,
    pub hours_goal: f64,
    pub label: String,
    pub sort_order: i64,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RewardMilestoneInput {
    pub hours_goal: f64,
    pub label: String,
}

fn app_data_dir<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, HoursError> {
    handle
        .path()
        .app_data_dir()
        .map_err(|e| HoursError::Settings(e.to_string()))
}

fn open_conn(app_data_dir: &Path) -> Result<Connection, HoursError> {
    Ok(Connection::open(app_data_dir.join("molly.db"))?)
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

// ---- Sessions --------------------------------------------------------------

/// Start a new session. If a session is already open, auto-close it first
/// (defensive: avoids accumulating orphan rows if state drifts). Returns
/// the id of the new session.
pub(crate) fn pure_start_session(
    conn: &Connection,
    persona_code: Option<&str>,
    now: i64,
) -> Result<i64, HoursError> {
    // Auto-close any open session.
    if let Some((open_id, open_start)) = pure_find_open_raw(conn)? {
        let dur = (now - open_start).max(0);
        conn.execute(
            "UPDATE clock_sessions SET duration_ms = ?1 WHERE id = ?2",
            params![dur, open_id],
        )?;
    }
    conn.execute(
        "INSERT INTO clock_sessions (persona_code, start_ms) VALUES (?1, ?2)",
        params![persona_code, now],
    )?;
    Ok(conn.last_insert_rowid())
}

/// Stop the currently-open session. Errors with NoOpenSession if none.
/// Returns the closed session's duration_ms.
pub(crate) fn pure_stop_session(conn: &Connection, now: i64) -> Result<i64, HoursError> {
    let open = pure_find_open_raw(conn)?;
    let Some((id, start)) = open else {
        return Err(HoursError::NoOpenSession);
    };
    let dur = (now - start).max(0);
    conn.execute(
        "UPDATE clock_sessions SET duration_ms = ?1 WHERE id = ?2",
        params![dur, id],
    )?;
    Ok(dur)
}

pub(crate) fn pure_list_sessions(
    conn: &Connection,
    limit: i64,
) -> Result<Vec<ClockSession>, HoursError> {
    let mut stmt = conn.prepare(
        "SELECT id, persona_code, start_ms, duration_ms, notes, created_at
         FROM clock_sessions
         ORDER BY start_ms DESC
         LIMIT ?1",
    )?;
    let rows = stmt
        .query_map(params![limit], |r| {
            Ok(ClockSession {
                id: r.get(0)?,
                persona_code: r.get(1)?,
                start_ms: r.get(2)?,
                duration_ms: r.get(3)?,
                notes: r.get(4)?,
                created_at: r.get(5)?,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

pub(crate) fn pure_delete_session(conn: &Connection, id: i64) -> Result<(), HoursError> {
    let n = conn.execute("DELETE FROM clock_sessions WHERE id = ?1", params![id])?;
    if n == 0 {
        return Err(HoursError::NotFound(id));
    }
    Ok(())
}

fn pure_find_open_raw(conn: &Connection) -> Result<Option<(i64, i64)>, HoursError> {
    Ok(conn
        .query_row(
            "SELECT id, start_ms FROM clock_sessions WHERE duration_ms IS NULL LIMIT 1",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .optional()?)
}

/// Sum of completed sessions whose start_ms is in [from_ms, now] PLUS
/// the portion of any open session whose start_ms is in the same range.
fn pure_sum_range(conn: &Connection, from_ms: i64, now: i64) -> Result<i64, HoursError> {
    let completed: i64 = conn
        .query_row(
            "SELECT COALESCE(SUM(duration_ms), 0)
             FROM clock_sessions
             WHERE duration_ms IS NOT NULL AND start_ms >= ?1",
            params![from_ms],
            |r| r.get(0),
        )
        .unwrap_or(0);
    let open: i64 = if let Some((_, start)) = pure_find_open_raw(conn)? {
        if start >= from_ms {
            (now - start).max(0)
        } else {
            0
        }
    } else {
        0
    };
    Ok(completed + open)
}

/// Compute today / week / month / all-time rollups + the open-session
/// state for the live UI counter. `now` is the current epoch ms; `tz_offset_min`
/// is the client's timezone offset in minutes (e.g. -420 for UTC-7) — the
/// "today" / "week" / "month" windows are anchored to that local clock.
pub(crate) fn pure_totals(
    conn: &Connection,
    now: i64,
    tz_offset_min: i32,
) -> Result<HoursTotals, HoursError> {
    let tz_ms = (tz_offset_min as i64) * 60 * 1000;
    // Convert "now" to local epoch ms by adding the tz offset, then floor
    // to local midnight / Monday / first-of-month, then convert back to
    // UTC ms by subtracting the offset.
    let local_now_ms = now + tz_ms;
    let day_ms = 24 * 60 * 60 * 1000;
    let local_today_start = (local_now_ms / day_ms) * day_ms;
    let today_start = local_today_start - tz_ms;

    // Week (Monday start). Local day-of-week: 1970-01-01 was a Thursday (4).
    // (local_today_start / day_ms) gives days since 1970-01-01.
    let days_since_epoch = local_today_start / day_ms;
    // Monday = (days_since_epoch + 3) % 7  (because epoch was Thursday=3 if Mon=0)
    let dow_from_mon = ((days_since_epoch + 3) % 7) as i64;
    let local_week_start = local_today_start - dow_from_mon * day_ms;
    let week_start = local_week_start - tz_ms;

    // Month (first day, local). Use chrono for safety.
    let local_now_dt = chrono::DateTime::<chrono::Utc>::from_timestamp_millis(local_now_ms)
        .ok_or_else(|| HoursError::Invalid("bad now timestamp".into()))?;
    let local_first =
        chrono::NaiveDate::from_ymd_opt(local_now_dt.year(), local_now_dt.month(), 1)
            .and_then(|d| d.and_hms_opt(0, 0, 0))
            .ok_or_else(|| HoursError::Invalid("bad date".into()))?;
    let local_month_start_ms = local_first.and_utc().timestamp_millis();
    let month_start = local_month_start_ms - tz_ms;

    let today_ms = pure_sum_range(conn, today_start, now)?;
    let week_ms = pure_sum_range(conn, week_start, now)?;
    let month_ms = pure_sum_range(conn, month_start, now)?;
    let all_time_ms = pure_sum_range(conn, i64::MIN / 2, now)?;
    let open = pure_find_open_raw(conn)?;

    Ok(HoursTotals {
        today_ms,
        week_ms,
        month_ms,
        all_time_ms,
        open_session_start_ms: open.map(|(_, s)| s),
        open_session_id: open.map(|(id, _)| id),
    })
}

// Re-export so the chrono trait imports inside pure_totals don't pollute the
// outer scope.
use chrono::Datelike;

// ---- Reward milestones -----------------------------------------------------

pub(crate) fn pure_list_milestones(
    conn: &Connection,
) -> Result<Vec<RewardMilestone>, HoursError> {
    let mut stmt = conn.prepare(
        "SELECT id, hours_goal, label, sort_order, created_at, updated_at
         FROM reward_milestones
         ORDER BY hours_goal ASC, sort_order ASC",
    )?;
    let rows = stmt
        .query_map([], |r| {
            Ok(RewardMilestone {
                id: r.get(0)?,
                hours_goal: r.get(1)?,
                label: r.get(2)?,
                sort_order: r.get(3)?,
                created_at: r.get(4)?,
                updated_at: r.get(5)?,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

pub(crate) fn pure_create_milestone(
    conn: &Connection,
    input: &RewardMilestoneInput,
) -> Result<i64, HoursError> {
    let label = input.label.trim();
    if label.is_empty() {
        return Err(HoursError::Invalid("milestone label required".into()));
    }
    if !(input.hours_goal > 0.0) {
        return Err(HoursError::Invalid("hours_goal must be > 0".into()));
    }
    let next_order: i64 = conn
        .query_row(
            "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM reward_milestones",
            [],
            |r| r.get(0),
        )
        .unwrap_or(1);
    conn.execute(
        "INSERT INTO reward_milestones (hours_goal, label, sort_order)
         VALUES (?1, ?2, ?3)",
        params![input.hours_goal, label, next_order],
    )?;
    Ok(conn.last_insert_rowid())
}

pub(crate) fn pure_update_milestone(
    conn: &Connection,
    id: i64,
    input: &RewardMilestoneInput,
) -> Result<(), HoursError> {
    let label = input.label.trim();
    if label.is_empty() {
        return Err(HoursError::Invalid("milestone label required".into()));
    }
    if !(input.hours_goal > 0.0) {
        return Err(HoursError::Invalid("hours_goal must be > 0".into()));
    }
    let n = conn.execute(
        "UPDATE reward_milestones
         SET hours_goal = ?1, label = ?2, updated_at = datetime('now')
         WHERE id = ?3",
        params![input.hours_goal, label, id],
    )?;
    if n == 0 {
        return Err(HoursError::NotFound(id));
    }
    Ok(())
}

pub(crate) fn pure_delete_milestone(conn: &Connection, id: i64) -> Result<(), HoursError> {
    let n = conn.execute(
        "DELETE FROM reward_milestones WHERE id = ?1",
        params![id],
    )?;
    if n == 0 {
        return Err(HoursError::NotFound(id));
    }
    Ok(())
}

// ---- Tauri commands --------------------------------------------------------

#[tauri::command]
pub fn hours_start_session<R: Runtime>(
    handle: AppHandle<R>,
    persona_code: Option<String>,
) -> Result<i64, HoursError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_start_session(&conn, persona_code.as_deref(), now_ms())
}

#[tauri::command]
pub fn hours_stop_session<R: Runtime>(handle: AppHandle<R>) -> Result<i64, HoursError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_stop_session(&conn, now_ms())
}

#[tauri::command]
pub fn hours_list_sessions<R: Runtime>(
    handle: AppHandle<R>,
    limit: Option<i64>,
) -> Result<Vec<ClockSession>, HoursError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_list_sessions(&conn, limit.unwrap_or(200))
}

#[tauri::command]
pub fn hours_delete_session<R: Runtime>(
    handle: AppHandle<R>,
    id: i64,
) -> Result<(), HoursError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_delete_session(&conn, id)
}

#[tauri::command]
pub fn hours_totals<R: Runtime>(
    handle: AppHandle<R>,
    tz_offset_min: i32,
) -> Result<HoursTotals, HoursError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_totals(&conn, now_ms(), tz_offset_min)
}

#[tauri::command]
pub fn list_reward_milestones<R: Runtime>(
    handle: AppHandle<R>,
) -> Result<Vec<RewardMilestone>, HoursError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_list_milestones(&conn)
}

#[tauri::command]
pub fn create_reward_milestone<R: Runtime>(
    handle: AppHandle<R>,
    input: RewardMilestoneInput,
) -> Result<i64, HoursError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_create_milestone(&conn, &input)
}

#[tauri::command]
pub fn update_reward_milestone<R: Runtime>(
    handle: AppHandle<R>,
    id: i64,
    input: RewardMilestoneInput,
) -> Result<(), HoursError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_update_milestone(&conn, id, &input)
}

#[tauri::command]
pub fn delete_reward_milestone<R: Runtime>(
    handle: AppHandle<R>,
    id: i64,
) -> Result<(), HoursError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_delete_milestone(&conn, id)
}

// ---- Tests -----------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_db() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        for sql in [
            include_str!("../migrations/001_init.sql"),
            include_str!("../migrations/030_hours.sql"),
        ] {
            conn.execute_batch(sql).unwrap();
        }
        conn.execute_batch("PRAGMA foreign_keys = ON;").unwrap();
        conn
    }

    #[test]
    fn start_stop_round_trip() {
        let conn = fresh_db();
        let id = pure_start_session(&conn, Some("CoC"), 1_000_000).unwrap();
        let dur = pure_stop_session(&conn, 1_005_000).unwrap();
        assert_eq!(dur, 5_000);
        let sessions = pure_list_sessions(&conn, 10).unwrap();
        let row = sessions.iter().find(|s| s.id == id).unwrap();
        assert_eq!(row.duration_ms, Some(5_000));
        assert!(row.start_ms == 1_000_000);
    }

    #[test]
    fn stop_without_open_errors() {
        let conn = fresh_db();
        assert!(matches!(
            pure_stop_session(&conn, 1_000),
            Err(HoursError::NoOpenSession)
        ));
    }

    #[test]
    fn starting_when_open_auto_closes_previous() {
        let conn = fresh_db();
        let a = pure_start_session(&conn, None, 1_000).unwrap();
        let b = pure_start_session(&conn, None, 2_000).unwrap();
        assert_ne!(a, b);
        let sessions = pure_list_sessions(&conn, 10).unwrap();
        let first = sessions.iter().find(|s| s.id == a).unwrap();
        let second = sessions.iter().find(|s| s.id == b).unwrap();
        assert_eq!(first.duration_ms, Some(1_000), "previous session must auto-close");
        assert!(second.duration_ms.is_none(), "new session is the open one");
    }

    #[test]
    fn delete_session() {
        let conn = fresh_db();
        let id = pure_start_session(&conn, None, 1_000).unwrap();
        pure_stop_session(&conn, 2_000).unwrap();
        pure_delete_session(&conn, id).unwrap();
        assert!(pure_list_sessions(&conn, 10).unwrap().iter().all(|s| s.id != id));
    }

    #[test]
    fn totals_sum_completed_sessions_in_their_window() {
        let conn = fresh_db();
        // Pick "now" = 2026-06-15 12:00 UTC. That's a Monday — convenient
        // because it makes week_start == today_start. June starts on a
        // Monday too, so day-20 falls in May and lands outside `month`.
        let now = chrono::NaiveDate::from_ymd_opt(2026, 6, 15)
            .unwrap()
            .and_hms_opt(12, 0, 0)
            .unwrap()
            .and_utc()
            .timestamp_millis();
        let day = 24 * 60 * 60 * 1000_i64;
        let hour = 60 * 60 * 1000_i64;
        let m30 = 30 * 60 * 1000_i64;
        let m10 = 10 * 60 * 1000_i64;
        //  - today (06-15): 30 min ago, lasted 10 min     → today + week + month
        //  - 5 days ago (06-10): lasted 1h                → month only
        //  - 20 days ago (05-26 in MAY): lasted 2h        → all-time only
        //  - 40 days ago (05-06 in MAY): lasted 5h        → all-time only
        for (start, dur) in [
            (now - m30, m10),
            (now - 5 * day, hour),
            (now - 20 * day, 2 * hour),
            (now - 40 * day, 5 * hour),
        ] {
            conn.execute(
                "INSERT INTO clock_sessions (start_ms, duration_ms) VALUES (?1, ?2)",
                params![start, dur],
            )
            .unwrap();
        }
        let totals = pure_totals(&conn, now, 0).unwrap();
        assert_eq!(totals.today_ms, m10);
        assert_eq!(totals.week_ms, m10, "06-15 is Monday → week_start == today_start");
        assert_eq!(totals.month_ms, m10 + hour, "20-day-old session is in May");
        assert_eq!(totals.all_time_ms, m10 + hour + 2 * hour + 5 * hour);
    }

    #[test]
    fn totals_include_open_session_running_portion() {
        let conn = fresh_db();
        let now = 100 * 60 * 1000_i64; // 100 minutes since epoch
        pure_start_session(&conn, None, now - 25 * 60 * 1000).unwrap(); // 25 min ago
        let totals = pure_totals(&conn, now, 0).unwrap();
        assert_eq!(totals.today_ms, 25 * 60 * 1000);
        assert_eq!(totals.all_time_ms, 25 * 60 * 1000);
        assert!(totals.open_session_start_ms.is_some());
        assert!(totals.open_session_id.is_some());
    }

    #[test]
    fn milestone_crud_and_validation() {
        let conn = fresh_db();
        let id = pure_create_milestone(
            &conn,
            &RewardMilestoneInput { hours_goal: 100.0, label: "  spa day  ".into() },
        )
        .unwrap();
        let row = pure_list_milestones(&conn)
            .into_iter()
            .flatten()
            .find(|m| m.id == id)
            .unwrap();
        assert_eq!(row.label, "spa day");
        // hours_goal must be > 0.
        assert!(pure_create_milestone(
            &conn,
            &RewardMilestoneInput { hours_goal: 0.0, label: "x".into() }
        )
        .is_err());
        // Label required.
        assert!(pure_create_milestone(
            &conn,
            &RewardMilestoneInput { hours_goal: 10.0, label: "  ".into() }
        )
        .is_err());
        pure_update_milestone(
            &conn,
            id,
            &RewardMilestoneInput { hours_goal: 150.0, label: "spa weekend".into() },
        )
        .unwrap();
        let row = pure_list_milestones(&conn)
            .into_iter()
            .flatten()
            .find(|m| m.id == id)
            .unwrap();
        assert_eq!(row.hours_goal, 150.0);
        pure_delete_milestone(&conn, id).unwrap();
        assert!(matches!(
            pure_delete_milestone(&conn, id),
            Err(HoursError::NotFound(_))
        ));
    }

    #[test]
    fn list_orders_milestones_by_goal_ascending() {
        let conn = fresh_db();
        pure_create_milestone(&conn, &RewardMilestoneInput { hours_goal: 250.0, label: "big".into() }).unwrap();
        pure_create_milestone(&conn, &RewardMilestoneInput { hours_goal: 100.0, label: "small".into() }).unwrap();
        pure_create_milestone(&conn, &RewardMilestoneInput { hours_goal: 150.0, label: "mid".into() }).unwrap();
        let rows = pure_list_milestones(&conn).unwrap();
        let goals: Vec<f64> = rows.iter().map(|m| m.hours_goal).collect();
        assert_eq!(goals, vec![100.0, 150.0, 250.0]);
    }
}
