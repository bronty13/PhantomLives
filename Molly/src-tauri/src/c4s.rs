use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::time::Duration;
use tauri::{AppHandle, Manager, Runtime};

// Phase 8: Clips4Sale snapshot. Same rationale as history.rs for opening
// a parallel rusqlite handle to molly.db — we want a single ATOMIC
// transaction (DELETE+INSERT*N+audit) for overlay-replace semantics, and
// tauri-plugin-sql doesn't expose transactions cleanly through the JS
// bridge. Two handles to one SQLite file cooperate via WAL + busy_timeout.

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct C4SClipDto {
    pub clip_id: String,
    pub clip_status: String,
    pub clip_tracking_tag: String,
    pub clip_title: String,
    pub clip_description: String,
    pub categories: String,
    pub keywords: String,
    pub clip_filename: String,
    pub clip_thumbnail: String,
    pub clip_preview: String,
    pub performers: String,
    pub price_cents: Option<i64>,
    pub sales_count: Option<i64>,
    pub income_6mo_cents: Option<i64>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReplaceResult {
    pub persona_code: String,
    pub deleted_count: u64,
    pub inserted_count: u64,
    pub expected_count: u64,
    pub matches: bool,
    pub imported_at: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeleteAllResult {
    pub deleted_clips: u64,
    pub deleted_imports: u64,
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
    conn.busy_timeout(Duration::from_secs(5))
        .map_err(|e| format!("busy_timeout: {e}"))?;
    Ok(conn)
}

fn validate_persona(code: &str) -> Result<(), String> {
    match code {
        "CoC" | "PoA" => Ok(()),
        other => Err(format!("unknown persona code {other:?} (expected CoC or PoA)")),
    }
}

// ---------- Pure SQL helpers (testable; the Tauri commands wrap these) ----

/// Atomically replace every row for `persona_code` with `rows`, write an
/// audit row, and verify the post-commit count matches `rows.len()`.
/// `imported_at` is the ISO timestamp written on every clip + audit row.
pub fn replace_persona_atomic(
    conn: &mut Connection,
    persona_code: &str,
    source_file: &str,
    rows: &[C4SClipDto],
    imported_at: &str,
) -> rusqlite::Result<(u64, u64, u64)> {
    let tx = conn.transaction()?;
    let deleted = tx.execute(
        "DELETE FROM c4s_clips WHERE persona_code = ?1",
        params![persona_code],
    )? as u64;

    {
        let mut stmt = tx.prepare(
            "INSERT INTO c4s_clips (
                clip_id, persona_code, clip_status, clip_tracking_tag,
                clip_title, clip_description, categories, keywords,
                clip_filename, clip_thumbnail, clip_preview, performers,
                price_cents, sales_count, income_6mo_cents, imported_at
            ) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16)",
        )?;
        for r in rows {
            stmt.execute(params![
                r.clip_id,
                persona_code,
                r.clip_status,
                r.clip_tracking_tag,
                r.clip_title,
                r.clip_description,
                r.categories,
                r.keywords,
                r.clip_filename,
                r.clip_thumbnail,
                r.clip_preview,
                r.performers,
                r.price_cents,
                r.sales_count,
                r.income_6mo_cents,
                imported_at,
            ])?;
        }
    }

    tx.execute(
        "INSERT INTO c4s_imports (persona_code, source_file, row_count, imported_at)
         VALUES (?1, ?2, ?3, ?4)",
        params![persona_code, source_file, rows.len() as i64, imported_at],
    )?;

    tx.commit()?;

    let actual: i64 = conn.query_row(
        "SELECT COUNT(*) FROM c4s_clips WHERE persona_code = ?1",
        params![persona_code],
        |row| row.get(0),
    )?;
    Ok((deleted, rows.len() as u64, actual as u64))
}

pub fn delete_all(conn: &mut Connection) -> rusqlite::Result<(u64, u64)> {
    let tx = conn.transaction()?;
    let clips = tx.execute("DELETE FROM c4s_clips", [])? as u64;
    let audit = tx.execute("DELETE FROM c4s_imports", [])? as u64;
    tx.commit()?;
    Ok((clips, audit))
}

// ---------- Tauri commands -------------------------------------------------

#[tauri::command]
pub fn replace_c4s_clips<R: Runtime>(
    handle: AppHandle<R>,
    persona_code: String,
    source_file: String,
    rows: Vec<C4SClipDto>,
) -> Result<ReplaceResult, String> {
    validate_persona(&persona_code)?;
    let mut conn = open_conn(&handle)?;
    let imported_at = chrono_now_iso();
    let (deleted, inserted, actual) =
        replace_persona_atomic(&mut conn, &persona_code, &source_file, &rows, &imported_at)
            .map_err(|e| format!("replace failed: {e}"))?;
    Ok(ReplaceResult {
        persona_code,
        deleted_count: deleted,
        inserted_count: actual,
        expected_count: inserted,
        matches: actual == inserted,
        imported_at,
    })
}

#[tauri::command]
pub fn delete_all_c4s_data<R: Runtime>(handle: AppHandle<R>) -> Result<DeleteAllResult, String> {
    let mut conn = open_conn(&handle)?;
    let (clips, imports) = delete_all(&mut conn).map_err(|e| format!("delete all: {e}"))?;
    Ok(DeleteAllResult {
        deleted_clips: clips,
        deleted_imports: imports,
    })
}

fn chrono_now_iso() -> String {
    // No chrono dep — match the SQLite datetime('now') format used elsewhere
    // for consistency in audit rows. UTC, second precision is plenty for a
    // human-visible "X days old" banner.
    use std::time::{SystemTime, UNIX_EPOCH};
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    let (y, m, d, hh, mm, ss) = epoch_to_ymdhms(secs);
    format!("{y:04}-{m:02}-{d:02} {hh:02}:{mm:02}:{ss:02}")
}

// Lightweight epoch→Y-M-D-H-M-S (UTC). Good enough for ISO timestamps in
// audit rows; the JS side uses Date.now() for display math.
fn epoch_to_ymdhms(epoch: i64) -> (i32, u32, u32, u32, u32, u32) {
    let days = epoch.div_euclid(86_400);
    let secs_of_day = epoch.rem_euclid(86_400) as u32;
    let hh = secs_of_day / 3600;
    let mm = (secs_of_day / 60) % 60;
    let ss = secs_of_day % 60;
    // Days since 1970-01-01 → date via the algorithm from Howard Hinnant's
    // date library (public domain). Handles Gregorian leap rules correctly.
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u32;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe as i32 + era as i32 * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = y + if m <= 2 { 1 } else { 0 };
    (y, m, d, hh, mm, ss)
}

#[cfg(test)]
mod tests {
    use super::*;

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
        ] {
            conn.execute_batch(sql).unwrap();
        }
        conn
    }

    fn dto(id: &str, title: &str) -> C4SClipDto {
        C4SClipDto {
            clip_id: id.into(),
            clip_status: "active".into(),
            clip_tracking_tag: "".into(),
            clip_title: title.into(),
            clip_description: "desc".into(),
            categories: "BBW, HUMILIATION".into(),
            keywords: "kw".into(),
            clip_filename: "f.mp4".into(),
            clip_thumbnail: "f.gif".into(),
            clip_preview: "".into(),
            performers: "CoC".into(),
            price_cents: Some(999),
            sales_count: None,
            income_6mo_cents: None,
        }
    }

    #[test]
    fn replace_inserts_then_counts_match() {
        let mut conn = fresh_db();
        let rows = vec![dto("1", "a"), dto("2", "b"), dto("3", "c")];
        let (deleted, expected, actual) =
            replace_persona_atomic(&mut conn, "CoC", "src.csv", &rows, "2026-05-21 00:00:00").unwrap();
        assert_eq!(deleted, 0);
        assert_eq!(expected, 3);
        assert_eq!(actual, 3);
        let audit: i64 = conn
            .query_row("SELECT COUNT(*) FROM c4s_imports", [], |r| r.get(0))
            .unwrap();
        assert_eq!(audit, 1);
    }

    #[test]
    fn replace_overwrites_only_its_own_persona() {
        let mut conn = fresh_db();
        let coc = vec![dto("1", "coc-a"), dto("2", "coc-b")];
        let poa = vec![dto("100", "poa-a"), dto("101", "poa-b"), dto("102", "poa-c")];
        replace_persona_atomic(&mut conn, "CoC", "coc.csv", &coc, "2026-05-21 00:00:00").unwrap();
        replace_persona_atomic(&mut conn, "PoA", "poa.csv", &poa, "2026-05-21 00:00:00").unwrap();

        // Re-import CoC with a single row — PoA must be untouched.
        let coc_v2 = vec![dto("9", "coc-fresh")];
        let (deleted, expected, actual) =
            replace_persona_atomic(&mut conn, "CoC", "coc.csv", &coc_v2, "2026-05-22 00:00:00").unwrap();
        assert_eq!(deleted, 2);
        assert_eq!(expected, 1);
        assert_eq!(actual, 1);

        let poa_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM c4s_clips WHERE persona_code = 'PoA'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(poa_count, 3, "PoA rows must survive a CoC re-import");
    }

    #[test]
    fn replace_with_empty_rows_clears_persona() {
        let mut conn = fresh_db();
        let rows = vec![dto("1", "a"), dto("2", "b")];
        replace_persona_atomic(&mut conn, "CoC", "src.csv", &rows, "2026-05-21 00:00:00").unwrap();

        let (deleted, expected, actual) =
            replace_persona_atomic(&mut conn, "CoC", "empty.csv", &[], "2026-05-22 00:00:00").unwrap();
        assert_eq!(deleted, 2);
        assert_eq!(expected, 0);
        assert_eq!(actual, 0);
    }

    #[test]
    fn delete_all_wipes_both_stores_and_audit() {
        let mut conn = fresh_db();
        replace_persona_atomic(&mut conn, "CoC", "a.csv", &vec![dto("1", "x")], "2026-05-21 00:00:00").unwrap();
        replace_persona_atomic(&mut conn, "PoA", "b.csv", &vec![dto("2", "y")], "2026-05-21 00:00:00").unwrap();
        let (clips, audit) = delete_all(&mut conn).unwrap();
        assert_eq!(clips, 2);
        assert_eq!(audit, 2);
    }

    #[test]
    fn invalid_persona_check_constraint_rejects() {
        let mut conn = fresh_db();
        let rows = vec![dto("1", "a")];
        let result = replace_persona_atomic(&mut conn, "ZZ", "z.csv", &rows, "2026-05-21 00:00:00");
        assert!(result.is_err(), "expected CHECK constraint violation");
    }

    // A round-trip date conversion check. The whole point of epoch_to_ymdhms
    // is "datetime('now')"-shaped audit strings, so the format must align
    // perfectly.
    #[test]
    fn iso_timestamp_format_is_yyyymmdd_hhmmss() {
        let s = chrono_now_iso();
        assert_eq!(s.len(), 19, "expected YYYY-MM-DD HH:MM:SS shape, got {s:?}");
        assert_eq!(&s[4..5], "-");
        assert_eq!(&s[7..8], "-");
        assert_eq!(&s[10..11], " ");
        assert_eq!(&s[13..14], ":");
        assert_eq!(&s[16..17], ":");
    }
}
