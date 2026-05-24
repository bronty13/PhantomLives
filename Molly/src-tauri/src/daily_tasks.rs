// Phase 15 PR3: Daily to-do list.
//
// Tasks belong to a date (for_date YYYY-MM-DD). The frontend always
// queries for "today" via the current local-date string; old rows stay
// around as silent history.

use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use tauri::{AppHandle, Manager, Runtime};

#[derive(Debug, thiserror::Error)]
pub enum DailyError {
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
}

impl serde::Serialize for DailyError {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.to_string())
    }
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct DailyTask {
    pub id: i64,
    pub persona_code: Option<String>,
    pub for_date: String,
    pub text: String,
    pub category: String,
    pub done_at: Option<String>,
    pub sort_order: i64,
    pub created_at: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DailyTaskInput {
    pub persona_code: Option<String>,
    pub for_date: String,
    pub text: String,
    pub category: String,
}

fn app_data_dir<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, DailyError> {
    handle
        .path()
        .app_data_dir()
        .map_err(|e| DailyError::Settings(e.to_string()))
}

fn open_conn(app_data_dir: &Path) -> Result<Connection, DailyError> {
    Ok(Connection::open(app_data_dir.join("molly.db"))?)
}

fn valid_category(s: &str) -> bool {
    matches!(s, "reddit" | "youtube" | "content" | "admin" | "other")
}

fn valid_iso_date(s: &str) -> bool {
    if s.len() != 10 {
        return false;
    }
    let b = s.as_bytes();
    b[4] == b'-'
        && b[7] == b'-'
        && b[0..4].iter().all(|c| c.is_ascii_digit())
        && b[5..7].iter().all(|c| c.is_ascii_digit())
        && b[8..10].iter().all(|c| c.is_ascii_digit())
}

fn row_to_task(r: &rusqlite::Row) -> rusqlite::Result<DailyTask> {
    Ok(DailyTask {
        id: r.get(0)?,
        persona_code: r.get(1)?,
        for_date: r.get(2)?,
        text: r.get(3)?,
        category: r.get(4)?,
        done_at: r.get(5)?,
        sort_order: r.get(6)?,
        created_at: r.get(7)?,
    })
}

pub(crate) fn pure_list_tasks_for_date(
    conn: &Connection,
    for_date: &str,
    persona_code: Option<&str>,
) -> Result<Vec<DailyTask>, DailyError> {
    if !valid_iso_date(for_date) {
        return Err(DailyError::Invalid(format!(
            "for_date must be YYYY-MM-DD (got {for_date})"
        )));
    }
    if let Some(p) = persona_code {
        let mut stmt = conn.prepare(
            "SELECT id, persona_code, for_date, text, category, done_at, sort_order, created_at
             FROM daily_tasks
             WHERE for_date = ?1 AND persona_code = ?2
             ORDER BY done_at IS NOT NULL, sort_order, id",
        )?;
        let rows = stmt
            .query_map(params![for_date, p], row_to_task)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(rows)
    } else {
        let mut stmt = conn.prepare(
            "SELECT id, persona_code, for_date, text, category, done_at, sort_order, created_at
             FROM daily_tasks
             WHERE for_date = ?1
             ORDER BY done_at IS NOT NULL, sort_order, id",
        )?;
        let rows = stmt
            .query_map(params![for_date], row_to_task)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(rows)
    }
}

pub(crate) fn pure_create_task(
    conn: &Connection,
    input: &DailyTaskInput,
) -> Result<i64, DailyError> {
    let text = input.text.trim();
    if text.is_empty() {
        return Err(DailyError::Invalid("task text required".into()));
    }
    if !valid_iso_date(&input.for_date) {
        return Err(DailyError::Invalid(format!(
            "for_date must be YYYY-MM-DD (got {})",
            input.for_date
        )));
    }
    if !valid_category(&input.category) {
        return Err(DailyError::Invalid(format!(
            "category must be reddit|youtube|content|admin|other (got {})",
            input.category
        )));
    }
    let next_order: i64 = conn
        .query_row(
            "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM daily_tasks
             WHERE for_date = ?1 AND (persona_code IS ?2 OR (persona_code IS NULL AND ?2 IS NULL))",
            params![input.for_date, input.persona_code],
            |r| r.get(0),
        )
        .unwrap_or(1);
    conn.execute(
        "INSERT INTO daily_tasks (persona_code, for_date, text, category, sort_order)
         VALUES (?1, ?2, ?3, ?4, ?5)",
        params![
            input.persona_code,
            input.for_date,
            text,
            input.category,
            next_order
        ],
    )?;
    Ok(conn.last_insert_rowid())
}

/// Persist a new sort_order for the given tasks. The list must contain
/// every still-open task in its desired order — done tasks keep their
/// existing sort_order (they're not visible to drag). Renumbered 1..N
/// so the column never collides with new INSERTs (which compute
/// `MAX(sort_order)+1`).
pub(crate) fn pure_reorder_tasks(
    conn: &Connection,
    ordered_ids: &[i64],
) -> Result<(), DailyError> {
    let tx_started = !conn.is_autocommit();
    if !tx_started {
        conn.execute_batch("BEGIN")?;
    }
    let result: Result<(), DailyError> = (|| {
        for (i, id) in ordered_ids.iter().enumerate() {
            let new_order = (i as i64) + 1;
            let n = conn.execute(
                "UPDATE daily_tasks SET sort_order = ?1 WHERE id = ?2",
                params![new_order, id],
            )?;
            if n == 0 {
                return Err(DailyError::NotFound(*id));
            }
        }
        Ok(())
    })();
    if !tx_started {
        if result.is_ok() {
            conn.execute_batch("COMMIT")?;
        } else {
            let _ = conn.execute_batch("ROLLBACK");
        }
    }
    result
}

pub(crate) fn pure_complete_task(conn: &Connection, id: i64) -> Result<(), DailyError> {
    let n = conn.execute(
        "UPDATE daily_tasks SET done_at = datetime('now') WHERE id = ?1 AND done_at IS NULL",
        params![id],
    )?;
    if n == 0 {
        // Either no such row, or already complete. Treat both as not-found
        // for the caller's purposes; checking with a separate SELECT would
        // race anyway.
        return Err(DailyError::NotFound(id));
    }
    Ok(())
}

pub(crate) fn pure_undo_task(conn: &Connection, id: i64) -> Result<(), DailyError> {
    let n = conn.execute(
        "UPDATE daily_tasks SET done_at = NULL WHERE id = ?1 AND done_at IS NOT NULL",
        params![id],
    )?;
    if n == 0 {
        return Err(DailyError::NotFound(id));
    }
    Ok(())
}

pub(crate) fn pure_delete_task(conn: &Connection, id: i64) -> Result<(), DailyError> {
    let n = conn.execute("DELETE FROM daily_tasks WHERE id = ?1", params![id])?;
    if n == 0 {
        return Err(DailyError::NotFound(id));
    }
    Ok(())
}

// ---- Tauri commands --------------------------------------------------------

#[tauri::command]
pub fn list_daily_tasks<R: Runtime>(
    handle: AppHandle<R>,
    for_date: String,
    persona_code: Option<String>,
) -> Result<Vec<DailyTask>, DailyError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_list_tasks_for_date(&conn, &for_date, persona_code.as_deref())
}

#[tauri::command]
pub fn create_daily_task<R: Runtime>(
    handle: AppHandle<R>,
    input: DailyTaskInput,
) -> Result<i64, DailyError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_create_task(&conn, &input)
}

#[tauri::command]
pub fn complete_daily_task<R: Runtime>(
    handle: AppHandle<R>,
    id: i64,
) -> Result<(), DailyError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_complete_task(&conn, id)
}

#[tauri::command]
pub fn undo_daily_task<R: Runtime>(handle: AppHandle<R>, id: i64) -> Result<(), DailyError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_undo_task(&conn, id)
}

#[tauri::command]
pub fn delete_daily_task<R: Runtime>(handle: AppHandle<R>, id: i64) -> Result<(), DailyError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_delete_task(&conn, id)
}

#[tauri::command]
pub fn reorder_daily_tasks<R: Runtime>(
    handle: AppHandle<R>,
    ordered_ids: Vec<i64>,
) -> Result<(), DailyError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_reorder_tasks(&conn, &ordered_ids)
}

// ---- Tests -----------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_db() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        for sql in [
            include_str!("../migrations/001_init.sql"),
            include_str!("../migrations/031_daily_tasks.sql"),
        ] {
            conn.execute_batch(sql).unwrap();
        }
        conn.execute_batch("PRAGMA foreign_keys = ON;").unwrap();
        conn
    }

    fn mk_input(date: &str, text: &str, cat: &str, persona: Option<&str>) -> DailyTaskInput {
        DailyTaskInput {
            persona_code: persona.map(String::from),
            for_date: date.into(),
            text: text.into(),
            category: cat.into(),
        }
    }

    #[test]
    fn create_list_round_trip() {
        let conn = fresh_db();
        let id = pure_create_task(&conn, &mk_input("2026-06-15", "Reddit posts", "reddit", Some("CoC"))).unwrap();
        let rows = pure_list_tasks_for_date(&conn, "2026-06-15", Some("CoC")).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, id);
        assert_eq!(rows[0].text, "Reddit posts");
        assert_eq!(rows[0].category, "reddit");
        assert!(rows[0].done_at.is_none());
    }

    #[test]
    fn previous_day_tasks_dont_appear_in_today() {
        let conn = fresh_db();
        pure_create_task(&conn, &mk_input("2026-06-14", "yesterday", "other", Some("CoC"))).unwrap();
        pure_create_task(&conn, &mk_input("2026-06-15", "today", "other", Some("CoC"))).unwrap();
        let today = pure_list_tasks_for_date(&conn, "2026-06-15", Some("CoC")).unwrap();
        assert_eq!(today.len(), 1);
        assert_eq!(today[0].text, "today");
    }

    #[test]
    fn complete_undo_delete_cycle() {
        let conn = fresh_db();
        let id = pure_create_task(&conn, &mk_input("2026-06-15", "x", "other", None)).unwrap();
        pure_complete_task(&conn, id).unwrap();
        let row = pure_list_tasks_for_date(&conn, "2026-06-15", None).unwrap();
        assert!(row[0].done_at.is_some());
        // Completing again is a no-op error (already done).
        assert!(matches!(
            pure_complete_task(&conn, id),
            Err(DailyError::NotFound(_))
        ));
        pure_undo_task(&conn, id).unwrap();
        let row = pure_list_tasks_for_date(&conn, "2026-06-15", None).unwrap();
        assert!(row[0].done_at.is_none());
        // Undo of a not-done task is a no-op error too.
        assert!(matches!(
            pure_undo_task(&conn, id),
            Err(DailyError::NotFound(_))
        ));
        pure_delete_task(&conn, id).unwrap();
        assert!(pure_list_tasks_for_date(&conn, "2026-06-15", None).unwrap().is_empty());
    }

    #[test]
    fn create_validates_inputs() {
        let conn = fresh_db();
        // empty text
        assert!(pure_create_task(&conn, &mk_input("2026-06-15", "  ", "other", None)).is_err());
        // bad date
        assert!(pure_create_task(&conn, &mk_input("Jun 15", "x", "other", None)).is_err());
        // bad category
        assert!(pure_create_task(&conn, &mk_input("2026-06-15", "x", "tiktok", None)).is_err());
    }

    #[test]
    fn reorder_renumbers_and_persists() {
        let conn = fresh_db();
        let a = pure_create_task(&conn, &mk_input("2026-05-24", "alpha", "other", None)).unwrap();
        let b = pure_create_task(&conn, &mk_input("2026-05-24", "bravo", "other", None)).unwrap();
        let c = pure_create_task(&conn, &mk_input("2026-05-24", "charlie", "other", None)).unwrap();
        // Drag charlie → top, bravo → middle, alpha → bottom.
        pure_reorder_tasks(&conn, &[c, b, a]).unwrap();
        let rows = pure_list_tasks_for_date(&conn, "2026-05-24", None).unwrap();
        assert_eq!(rows[0].id, c);
        assert_eq!(rows[1].id, b);
        assert_eq!(rows[2].id, a);
        // sort_order is dense 1..N so new INSERTs land at the end.
        assert_eq!(rows[0].sort_order, 1);
        assert_eq!(rows[1].sort_order, 2);
        assert_eq!(rows[2].sort_order, 3);
        let d = pure_create_task(&conn, &mk_input("2026-05-24", "delta", "other", None)).unwrap();
        let rows = pure_list_tasks_for_date(&conn, "2026-05-24", None).unwrap();
        let added = rows.iter().find(|t| t.id == d).unwrap();
        assert_eq!(added.sort_order, 4);
    }

    #[test]
    fn reorder_rejects_unknown_id_and_rolls_back() {
        let conn = fresh_db();
        let a = pure_create_task(&conn, &mk_input("2026-05-24", "alpha", "other", None)).unwrap();
        // Mix a real id with a fake one — should error AND leave sort_order untouched.
        let original = pure_list_tasks_for_date(&conn, "2026-05-24", None).unwrap()[0].sort_order;
        let err = pure_reorder_tasks(&conn, &[a, 99_999]);
        assert!(matches!(err, Err(DailyError::NotFound(_))));
        let after = pure_list_tasks_for_date(&conn, "2026-05-24", None).unwrap()[0].sort_order;
        assert_eq!(after, original, "rolled-back transaction must leave sort_order untouched");
    }

    #[test]
    fn list_orders_unfinished_first_then_done() {
        let conn = fresh_db();
        let a = pure_create_task(&conn, &mk_input("2026-06-15", "first", "other", None)).unwrap();
        let b = pure_create_task(&conn, &mk_input("2026-06-15", "second", "other", None)).unwrap();
        let c = pure_create_task(&conn, &mk_input("2026-06-15", "third", "other", None)).unwrap();
        // Complete the first → it should drop to the bottom.
        pure_complete_task(&conn, a).unwrap();
        let rows = pure_list_tasks_for_date(&conn, "2026-06-15", None).unwrap();
        assert_eq!(rows.len(), 3);
        // Unfinished first (b, c), then a (completed).
        assert_eq!(rows[0].id, b);
        assert_eq!(rows[1].id, c);
        assert_eq!(rows[2].id, a);
    }
}
