// Phase 14 PR1: Holidays on the Calendar.
//
// Storage of recurring holidays (either fixed Month/Day or "Nth weekday of
// Month"). The frontend resolves them to concrete ISO dates per visible
// month (lib/holidayResolver.ts); this Rust side just owns CRUD + the
// US-default reset path.
//
// We never auto-purge user-edited rows: "Reset to US defaults" is an
// explicit destructive action that deletes only rows where source =
// 'us_default' and re-runs the seed insert. Custom rows survive.

use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use tauri::{AppHandle, Manager, Runtime};

#[derive(Debug, thiserror::Error)]
pub enum HolidayError {
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

impl serde::Serialize for HolidayError {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.to_string())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Holiday {
    pub id: i64,
    pub name: String,
    pub kind: String, // "fixed" | "nth_weekday"
    pub month: i64,
    pub day: Option<i64>,
    pub weekday: Option<i64>,
    pub nth: Option<i64>,
    pub color_primary: String,
    pub color_secondary: Option<String>,
    pub color_text: String,
    pub emoji: Option<String>,
    pub enabled: bool,
    pub source: String, // "us_default" | "custom"
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HolidayInput {
    pub name: String,
    pub kind: String,
    pub month: i64,
    pub day: Option<i64>,
    pub weekday: Option<i64>,
    pub nth: Option<i64>,
    pub color_primary: String,
    pub color_secondary: Option<String>,
    pub color_text: String,
    pub emoji: Option<String>,
    pub enabled: bool,
}

fn app_data_dir<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, HolidayError> {
    handle
        .path()
        .app_data_dir()
        .map_err(|e| HolidayError::Settings(e.to_string()))
}

fn open_conn(app_data_dir: &Path) -> Result<Connection, HolidayError> {
    let db_path = app_data_dir.join("molly.db");
    Ok(Connection::open(db_path)?)
}

fn validate(input: &HolidayInput) -> Result<(), HolidayError> {
    if input.name.trim().is_empty() {
        return Err(HolidayError::Invalid("name is required".into()));
    }
    if !(1..=12).contains(&input.month) {
        return Err(HolidayError::Invalid(format!(
            "month must be 1..12 (got {})",
            input.month
        )));
    }
    match input.kind.as_str() {
        "fixed" => {
            let Some(d) = input.day else {
                return Err(HolidayError::Invalid("fixed holidays need a day".into()));
            };
            if !(1..=31).contains(&d) {
                return Err(HolidayError::Invalid(format!("day must be 1..31 (got {d})")));
            }
        }
        "nth_weekday" => {
            let Some(w) = input.weekday else {
                return Err(HolidayError::Invalid(
                    "nth_weekday holidays need a weekday".into(),
                ));
            };
            if !(0..=6).contains(&w) {
                return Err(HolidayError::Invalid(format!(
                    "weekday must be 0..6 (got {w})"
                )));
            }
            let Some(n) = input.nth else {
                return Err(HolidayError::Invalid("nth_weekday holidays need an nth".into()));
            };
            if !(n == -1 || (1..=4).contains(&n)) {
                return Err(HolidayError::Invalid(format!(
                    "nth must be 1..4 or -1 (got {n})"
                )));
            }
        }
        other => return Err(HolidayError::Invalid(format!("unknown kind {other}"))),
    }
    if !is_hex_color(&input.color_primary) {
        return Err(HolidayError::Invalid("colorPrimary must be #RRGGBB".into()));
    }
    if !is_hex_color(&input.color_text) {
        return Err(HolidayError::Invalid("colorText must be #RRGGBB".into()));
    }
    if let Some(s) = input.color_secondary.as_deref() {
        if !s.is_empty() && !is_hex_color(s) {
            return Err(HolidayError::Invalid("colorSecondary must be #RRGGBB".into()));
        }
    }
    Ok(())
}

fn is_hex_color(s: &str) -> bool {
    let bytes = s.as_bytes();
    bytes.len() == 7 && bytes[0] == b'#' && bytes[1..].iter().all(|b| b.is_ascii_hexdigit())
}

pub(crate) fn pure_list(conn: &Connection) -> Result<Vec<Holiday>, HolidayError> {
    let mut stmt = conn.prepare(
        "SELECT id, name, kind, month, day, weekday, nth,
                color_primary, color_secondary, color_text, emoji,
                enabled, source, created_at, updated_at
         FROM holidays
         ORDER BY month, COALESCE(day, 99), name",
    )?;
    let rows = stmt
        .query_map([], |r| {
            Ok(Holiday {
                id: r.get(0)?,
                name: r.get(1)?,
                kind: r.get(2)?,
                month: r.get(3)?,
                day: r.get(4)?,
                weekday: r.get(5)?,
                nth: r.get(6)?,
                color_primary: r.get(7)?,
                color_secondary: r.get(8)?,
                color_text: r.get(9)?,
                emoji: r.get(10)?,
                enabled: r.get::<_, i64>(11)? != 0,
                source: r.get(12)?,
                created_at: r.get(13)?,
                updated_at: r.get(14)?,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

pub(crate) fn pure_create(conn: &Connection, input: &HolidayInput) -> Result<i64, HolidayError> {
    validate(input)?;
    conn.execute(
        "INSERT INTO holidays (name, kind, month, day, weekday, nth,
                               color_primary, color_secondary, color_text, emoji,
                               enabled, source)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, 'custom')",
        params![
            input.name.trim(),
            input.kind,
            input.month,
            input.day,
            input.weekday,
            input.nth,
            input.color_primary,
            input.color_secondary,
            input.color_text,
            input.emoji,
            if input.enabled { 1_i64 } else { 0 },
        ],
    )?;
    Ok(conn.last_insert_rowid())
}

pub(crate) fn pure_update(
    conn: &Connection,
    id: i64,
    input: &HolidayInput,
) -> Result<(), HolidayError> {
    validate(input)?;
    let n = conn.execute(
        "UPDATE holidays
         SET name = ?1, kind = ?2, month = ?3, day = ?4, weekday = ?5, nth = ?6,
             color_primary = ?7, color_secondary = ?8, color_text = ?9, emoji = ?10,
             enabled = ?11, updated_at = datetime('now')
         WHERE id = ?12",
        params![
            input.name.trim(),
            input.kind,
            input.month,
            input.day,
            input.weekday,
            input.nth,
            input.color_primary,
            input.color_secondary,
            input.color_text,
            input.emoji,
            if input.enabled { 1_i64 } else { 0 },
            id,
        ],
    )?;
    if n == 0 {
        return Err(HolidayError::NotFound(id));
    }
    Ok(())
}

pub(crate) fn pure_set_enabled(
    conn: &Connection,
    id: i64,
    enabled: bool,
) -> Result<(), HolidayError> {
    let n = conn.execute(
        "UPDATE holidays SET enabled = ?1, updated_at = datetime('now') WHERE id = ?2",
        params![if enabled { 1_i64 } else { 0 }, id],
    )?;
    if n == 0 {
        return Err(HolidayError::NotFound(id));
    }
    Ok(())
}

pub(crate) fn pure_delete(conn: &Connection, id: i64) -> Result<(), HolidayError> {
    let n = conn.execute("DELETE FROM holidays WHERE id = ?1", params![id])?;
    if n == 0 {
        return Err(HolidayError::NotFound(id));
    }
    Ok(())
}

/// Deletes ONLY the seeded defaults and re-inserts the canonical set.
/// User-added (source='custom') rows are kept. Edits to seeded rows are
/// reverted — that's the contract of "Reset to US defaults."
pub(crate) fn pure_reset_us_defaults(conn: &Connection) -> Result<u32, HolidayError> {
    conn.execute("DELETE FROM holidays WHERE source = 'us_default'", [])?;
    // Re-apply the seed insert from migration 025 verbatim. Strip ALL
    // `--` comment lines first so any `;` that happens to live in a
    // comment doesn't fool the statement splitter below.
    let seed = include_str!("../migrations/025_holidays.sql");
    let stripped: String = seed
        .lines()
        .filter(|l| !l.trim_start().starts_with("--"))
        .collect::<Vec<_>>()
        .join("\n");
    let mut count = 0u32;
    for raw in stripped.split(';') {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            continue;
        }
        let lower = trimmed.to_ascii_lowercase();
        if !lower.starts_with("insert into holidays") {
            continue;
        }
        conn.execute(trimmed, [])?;
        count += conn.changes() as u32;
    }
    Ok(count)
}

// ---- Tauri commands ---------------------------------------------------------

#[tauri::command]
pub fn list_holidays<R: Runtime>(handle: AppHandle<R>) -> Result<Vec<Holiday>, HolidayError> {
    let dir = app_data_dir(&handle)?;
    let conn = open_conn(&dir)?;
    pure_list(&conn)
}

#[tauri::command]
pub fn create_holiday<R: Runtime>(
    handle: AppHandle<R>,
    input: HolidayInput,
) -> Result<i64, HolidayError> {
    let dir = app_data_dir(&handle)?;
    let conn = open_conn(&dir)?;
    pure_create(&conn, &input)
}

#[tauri::command]
pub fn update_holiday<R: Runtime>(
    handle: AppHandle<R>,
    id: i64,
    input: HolidayInput,
) -> Result<(), HolidayError> {
    let dir = app_data_dir(&handle)?;
    let conn = open_conn(&dir)?;
    pure_update(&conn, id, &input)
}

#[tauri::command]
pub fn set_holiday_enabled<R: Runtime>(
    handle: AppHandle<R>,
    id: i64,
    enabled: bool,
) -> Result<(), HolidayError> {
    let dir = app_data_dir(&handle)?;
    let conn = open_conn(&dir)?;
    pure_set_enabled(&conn, id, enabled)
}

#[tauri::command]
pub fn delete_holiday<R: Runtime>(handle: AppHandle<R>, id: i64) -> Result<(), HolidayError> {
    let dir = app_data_dir(&handle)?;
    let conn = open_conn(&dir)?;
    pure_delete(&conn, id)
}

#[tauri::command]
pub fn reset_holidays_to_us_defaults<R: Runtime>(
    handle: AppHandle<R>,
) -> Result<u32, HolidayError> {
    let dir = app_data_dir(&handle)?;
    let conn = open_conn(&dir)?;
    pure_reset_us_defaults(&conn)
}

// ---- Tests ------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_db() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        // Migrations 001 (app_settings) + 025 are the only ones the holidays
        // module touches. Apply both inline.
        conn.execute_batch(include_str!("../migrations/001_init.sql"))
            .unwrap();
        conn.execute_batch(include_str!("../migrations/025_holidays.sql"))
            .unwrap();
        conn
    }

    fn good_input() -> HolidayInput {
        HolidayInput {
            name: "Pi Day".into(),
            kind: "fixed".into(),
            month: 3,
            day: Some(14),
            weekday: None,
            nth: None,
            color_primary: "#1A1A1A".into(),
            color_secondary: None,
            color_text: "#FFFFFF".into(),
            emoji: Some("π".into()),
            enabled: true,
        }
    }

    #[test]
    fn seed_loads_us_defaults() {
        let conn = fresh_db();
        let all = pure_list(&conn).unwrap();
        assert!(all.len() >= 17, "expected >=17 US default holidays, got {}", all.len());
        assert!(all.iter().any(|h| h.name == "Independence Day" && h.month == 7));
        assert!(all.iter().any(|h| h.name == "Christmas Day" && h.color_secondary.as_deref() == Some("#15803D")));
        assert!(all.iter().all(|h| h.source == "us_default"));
    }

    #[test]
    fn create_round_trip() {
        let conn = fresh_db();
        let id = pure_create(&conn, &good_input()).unwrap();
        let all = pure_list(&conn).unwrap();
        let added = all.iter().find(|h| h.id == id).unwrap();
        assert_eq!(added.name, "Pi Day");
        assert_eq!(added.source, "custom");
        assert!(added.enabled);
    }

    #[test]
    fn validate_rejects_bad_inputs() {
        let conn = fresh_db();

        let mut bad = good_input();
        bad.name = "  ".into();
        assert!(pure_create(&conn, &bad).is_err());

        let mut bad = good_input();
        bad.month = 13;
        assert!(pure_create(&conn, &bad).is_err());

        let mut bad = good_input();
        bad.color_primary = "not-a-hex".into();
        assert!(pure_create(&conn, &bad).is_err());

        let mut bad = good_input();
        bad.kind = "nth_weekday".into();
        bad.weekday = None;
        bad.nth = Some(3);
        assert!(pure_create(&conn, &bad).is_err());

        let mut bad = good_input();
        bad.kind = "nth_weekday".into();
        bad.weekday = Some(1);
        bad.nth = Some(7);
        assert!(pure_create(&conn, &bad).is_err());
    }

    #[test]
    fn update_preserves_source_and_changes_fields() {
        let conn = fresh_db();
        let id = pure_create(&conn, &good_input()).unwrap();
        let mut next = good_input();
        next.name = "Tau Day".into();
        next.day = Some(28);
        next.month = 6;
        pure_update(&conn, id, &next).unwrap();
        let row = pure_list(&conn)
            .unwrap()
            .into_iter()
            .find(|h| h.id == id)
            .unwrap();
        assert_eq!(row.name, "Tau Day");
        assert_eq!(row.month, 6);
        assert_eq!(row.day, Some(28));
        assert_eq!(row.source, "custom");
    }

    #[test]
    fn set_enabled_flips_flag() {
        let conn = fresh_db();
        let id = pure_create(&conn, &good_input()).unwrap();
        pure_set_enabled(&conn, id, false).unwrap();
        let row = pure_list(&conn).unwrap().into_iter().find(|h| h.id == id).unwrap();
        assert!(!row.enabled);
    }

    #[test]
    fn delete_removes_row() {
        let conn = fresh_db();
        let id = pure_create(&conn, &good_input()).unwrap();
        pure_delete(&conn, id).unwrap();
        assert!(pure_list(&conn).unwrap().iter().all(|h| h.id != id));
        assert!(matches!(pure_delete(&conn, id), Err(HolidayError::NotFound(_))));
    }

    #[test]
    fn reset_preserves_custom_rows_and_reverts_edits() {
        let conn = fresh_db();
        // Add a custom row + edit a default one.
        let custom_id = pure_create(&conn, &good_input()).unwrap();
        let xmas = pure_list(&conn)
            .unwrap()
            .into_iter()
            .find(|h| h.name == "Christmas Day")
            .unwrap();
        let mut edited = HolidayInput {
            name: "X-Mas (renamed!)".into(),
            kind: xmas.kind.clone(),
            month: xmas.month,
            day: xmas.day,
            weekday: xmas.weekday,
            nth: xmas.nth,
            color_primary: "#000000".into(),
            color_secondary: None,
            color_text: "#FFFFFF".into(),
            emoji: None,
            enabled: false,
        };
        edited.name = "X-Mas (renamed!)".into();
        pure_update(&conn, xmas.id, &edited).unwrap();

        let inserted = pure_reset_us_defaults(&conn).unwrap();
        assert!(inserted >= 17);
        let after = pure_list(&conn).unwrap();
        // Custom row survives.
        assert!(after.iter().any(|h| h.id == custom_id && h.name == "Pi Day"));
        // Christmas back to canonical name + color.
        assert!(after.iter().any(|h| h.name == "Christmas Day" && h.color_secondary.as_deref() == Some("#15803D")));
        // Renamed row is gone.
        assert!(after.iter().all(|h| h.name != "X-Mas (renamed!)"));
    }
}
