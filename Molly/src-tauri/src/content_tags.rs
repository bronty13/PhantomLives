// Phase 14 PR2: Global content tags + per-bundle tagging.
//
// Mirrors the Notes tag CRUD shape: tag definitions live in
// `content_tags_def` (renameable + recolourable, deleting a built-in is
// rejected), and `bundle_tag_links` joins bundles to tags. The link
// table cascades on bundle delete + tag delete, so set_bundle_tags is
// a simple "replace" — no orphan cleanup needed.

use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use tauri::{AppHandle, Manager, Runtime};

#[derive(Debug, thiserror::Error)]
pub enum TagError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("sqlite: {0}")]
    Sql(#[from] rusqlite::Error),
    #[error("settings: {0}")]
    Settings(String),
    #[error("invalid: {0}")]
    Invalid(String),
    #[error("built-in tag {0} cannot be deleted (you can rename and recolour it instead)")]
    BuiltinUndeletable(String),
}

impl serde::Serialize for TagError {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.to_string())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ContentTag {
    pub id: i64,
    pub name: String,
    pub color: String,
    pub sort_order: i64,
    pub is_builtin: bool,
}

fn app_data_dir<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, TagError> {
    handle
        .path()
        .app_data_dir()
        .map_err(|e| TagError::Settings(e.to_string()))
}

fn open_conn(app_data_dir: &Path) -> Result<Connection, TagError> {
    let db_path = app_data_dir.join("molly.db");
    Ok(Connection::open(db_path)?)
}

fn is_hex_color(s: &str) -> bool {
    let bytes = s.as_bytes();
    bytes.len() == 7 && bytes[0] == b'#' && bytes[1..].iter().all(|b| b.is_ascii_hexdigit())
}

pub(crate) fn pure_list_tags(conn: &Connection) -> Result<Vec<ContentTag>, TagError> {
    let mut stmt = conn.prepare(
        "SELECT id, name, color, sort_order, is_builtin
         FROM content_tags_def
         ORDER BY sort_order, name COLLATE NOCASE",
    )?;
    let rows = stmt
        .query_map([], |r| {
            Ok(ContentTag {
                id: r.get(0)?,
                name: r.get(1)?,
                color: r.get(2)?,
                sort_order: r.get(3)?,
                is_builtin: r.get::<_, i64>(4)? != 0,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

pub(crate) fn pure_create_tag(
    conn: &Connection,
    name: &str,
    color: &str,
) -> Result<i64, TagError> {
    let name = name.trim();
    if name.is_empty() {
        return Err(TagError::Invalid("tag name required".into()));
    }
    if !is_hex_color(color) {
        return Err(TagError::Invalid("color must be #RRGGBB".into()));
    }
    let next_order: i64 = conn
        .query_row(
            "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM content_tags_def",
            [],
            |r| r.get(0),
        )
        .unwrap_or(1);
    conn.execute(
        "INSERT INTO content_tags_def (name, color, sort_order, is_builtin)
         VALUES (?1, ?2, ?3, 0)",
        params![name, color, next_order],
    )?;
    Ok(conn.last_insert_rowid())
}

pub(crate) fn pure_update_tag(
    conn: &Connection,
    tag_id: i64,
    name: &str,
    color: &str,
) -> Result<(), TagError> {
    let name = name.trim();
    if name.is_empty() {
        return Err(TagError::Invalid("tag name required".into()));
    }
    if !is_hex_color(color) {
        return Err(TagError::Invalid("color must be #RRGGBB".into()));
    }
    conn.execute(
        "UPDATE content_tags_def SET name = ?1, color = ?2, updated_at = datetime('now')
         WHERE id = ?3",
        params![name, color, tag_id],
    )?;
    Ok(())
}

pub(crate) fn pure_delete_tag(conn: &Connection, tag_id: i64) -> Result<(), TagError> {
    let (is_builtin, name): (i64, String) = conn
        .query_row(
            "SELECT is_builtin, name FROM content_tags_def WHERE id = ?1",
            params![tag_id],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap_or((0, String::new()));
    if is_builtin != 0 {
        return Err(TagError::BuiltinUndeletable(name));
    }
    conn.execute(
        "DELETE FROM content_tags_def WHERE id = ?1",
        params![tag_id],
    )?;
    Ok(())
}

pub(crate) fn pure_bundle_tag_ids(
    conn: &Connection,
    bundle_uid: &str,
) -> Result<Vec<i64>, TagError> {
    // Bundle-level tags only (fan_day_id IS NULL). FanSite per-day tags
    // are read via pure_fan_day_tag_ids.
    let mut stmt = conn.prepare(
        "SELECT tag_id FROM bundle_tag_links
         WHERE bundle_uid = ?1 AND fan_day_id IS NULL
         ORDER BY tag_id",
    )?;
    let rows = stmt
        .query_map(params![bundle_uid], |r| r.get::<_, i64>(0))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

pub(crate) fn pure_set_bundle_tags(
    conn: &Connection,
    bundle_uid: &str,
    tag_ids: &[i64],
) -> Result<(), TagError> {
    // Only delete bundle-level links — leave any FanSite per-day links
    // alone. Otherwise saving the bundle-level picker would wipe out
    // every day's tags.
    conn.execute(
        "DELETE FROM bundle_tag_links WHERE bundle_uid = ?1 AND fan_day_id IS NULL",
        params![bundle_uid],
    )?;
    for tid in tag_ids {
        conn.execute(
            "INSERT OR IGNORE INTO bundle_tag_links (bundle_uid, tag_id, fan_day_id)
             VALUES (?1, ?2, NULL)",
            params![bundle_uid, tid],
        )?;
    }
    conn.execute(
        "UPDATE bundles SET updated_at = datetime('now') WHERE uid = ?1",
        params![bundle_uid],
    )?;
    Ok(())
}

pub(crate) fn pure_fan_day_tag_ids(
    conn: &Connection,
    fan_day_id: i64,
) -> Result<Vec<i64>, TagError> {
    let mut stmt = conn.prepare(
        "SELECT tag_id FROM bundle_tag_links
         WHERE fan_day_id = ?1
         ORDER BY tag_id",
    )?;
    let rows = stmt
        .query_map(params![fan_day_id], |r| r.get::<_, i64>(0))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

pub(crate) fn pure_set_fan_day_tags(
    conn: &Connection,
    fan_day_id: i64,
    tag_ids: &[i64],
) -> Result<(), TagError> {
    // Resolve the parent bundle so we can stamp updated_at + pass it to
    // the link insert (we want the FK on bundle_uid for cascade-on-bundle-
    // delete to keep working).
    let bundle_uid: String = conn
        .query_row(
            "SELECT bundle_uid FROM bundle_fan_days WHERE id = ?1",
            params![fan_day_id],
            |r| r.get(0),
        )
        .map_err(|_| TagError::Invalid(format!("fan_day_id {fan_day_id} not found")))?;

    conn.execute(
        "DELETE FROM bundle_tag_links WHERE fan_day_id = ?1",
        params![fan_day_id],
    )?;
    for tid in tag_ids {
        conn.execute(
            "INSERT OR IGNORE INTO bundle_tag_links (bundle_uid, tag_id, fan_day_id)
             VALUES (?1, ?2, ?3)",
            params![bundle_uid, tid, fan_day_id],
        )?;
    }
    conn.execute(
        "UPDATE bundles SET updated_at = datetime('now') WHERE uid = ?1",
        params![bundle_uid],
    )?;
    Ok(())
}

pub(crate) fn pure_clip_tag_ids(
    conn: &Connection,
    clip_id: &str,
) -> Result<Vec<i64>, TagError> {
    let mut stmt = conn.prepare(
        "SELECT tag_id FROM clip_tag_links WHERE clip_id = ?1 ORDER BY tag_id",
    )?;
    let rows = stmt
        .query_map(params![clip_id], |r| r.get::<_, i64>(0))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

pub(crate) fn pure_set_clip_tags(
    conn: &Connection,
    clip_id: &str,
    tag_ids: &[i64],
) -> Result<(), TagError> {
    conn.execute(
        "DELETE FROM clip_tag_links WHERE clip_id = ?1",
        params![clip_id],
    )?;
    for tid in tag_ids {
        conn.execute(
            "INSERT OR IGNORE INTO clip_tag_links (clip_id, tag_id) VALUES (?1, ?2)",
            params![clip_id, tid],
        )?;
    }
    Ok(())
}

/// Mirror clip_tag_links from a bundle's bundle-level tags. Called by
/// the bundle publish path so that publishing a Content bundle stamps
/// the same tag set onto the resulting clip row. Idempotent — re-publish
/// re-syncs.
pub(crate) fn pure_mirror_bundle_tags_to_clip(
    conn: &Connection,
    bundle_uid: &str,
    clip_id: &str,
) -> Result<(), TagError> {
    let mut stmt = conn.prepare(
        "SELECT tag_id FROM bundle_tag_links
         WHERE bundle_uid = ?1 AND fan_day_id IS NULL
         ORDER BY tag_id",
    )?;
    let tag_ids: Vec<i64> = stmt
        .query_map(params![bundle_uid], |r| r.get::<_, i64>(0))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    drop(stmt);
    pure_set_clip_tags(conn, clip_id, &tag_ids)
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ClipTagInDate {
    /// go_live_date of the clip, sliced to YYYY-MM-DD.
    pub date: String,
    pub clip_id: String,
    pub persona_code: Option<String>,
    pub tag_id: i64,
    pub tag_name: String,
    pub tag_color: String,
}

/// All clip tags whose parent clip's go_live_date falls in [from, to].
/// Optionally filter by persona. Used by the Calendar overlay.
pub(crate) fn pure_clip_tags_in_range(
    conn: &Connection,
    from: &str,
    to: &str,
    persona_code: Option<&str>,
) -> Result<Vec<ClipTagInDate>, TagError> {
    let mut sql = String::from(
        "SELECT substr(c.go_live_date, 1, 10) AS date,
                c.id, c.persona_code, t.id, t.name, t.color
         FROM clip_tag_links l
         JOIN clips c ON c.id = l.clip_id
         JOIN content_tags_def t ON t.id = l.tag_id
         WHERE c.go_live_date IS NOT NULL
           AND substr(c.go_live_date, 1, 10) BETWEEN ?1 AND ?2",
    );
    if persona_code.is_some() {
        sql.push_str(" AND c.persona_code = ?3");
    }
    sql.push_str(" ORDER BY date, t.sort_order, t.name");
    let mut stmt = conn.prepare(&sql)?;
    let mapper = |r: &rusqlite::Row| {
        Ok(ClipTagInDate {
            date: r.get(0)?,
            clip_id: r.get(1)?,
            persona_code: r.get(2)?,
            tag_id: r.get(3)?,
            tag_name: r.get(4)?,
            tag_color: r.get(5)?,
        })
    };
    let rows: rusqlite::Result<Vec<_>> = match persona_code {
        Some(code) => stmt.query_map(params![from, to, code], mapper)?.collect(),
        None => stmt.query_map(params![from, to], mapper)?.collect(),
    };
    Ok(rows?)
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct FanSiteDayTag {
    /// ISO date the FanSite day resolves to: YYYY-MM-DD.
    pub date: String,
    pub bundle_uid: String,
    pub persona_code: Option<String>,
    pub fan_day_id: i64,
    pub tag_id: i64,
    pub tag_name: String,
    pub tag_color: String,
}

/// All FanSite per-day tags whose resolved date falls in [from, to]
/// (inclusive ISO date strings, YYYY-MM-DD). Optionally filter by
/// persona. Used by the Calendar overlay; cheap because the row count
/// is bounded by visible days × tags per day.
pub(crate) fn pure_fansite_tags_in_range(
    conn: &Connection,
    from: &str,
    to: &str,
    persona_code: Option<&str>,
) -> Result<Vec<FanSiteDayTag>, TagError> {
    let mut sql = String::from(
        "SELECT printf('%04d-%02d-%02d', b.fansite_year, b.fansite_month, d.day_of_month) AS date,
                b.uid, b.persona_code, d.id, t.id, t.name, t.color
         FROM bundle_tag_links l
         JOIN bundle_fan_days d ON d.id = l.fan_day_id
         JOIN bundles b ON b.uid = l.bundle_uid
         JOIN content_tags_def t ON t.id = l.tag_id
         WHERE l.fan_day_id IS NOT NULL
           AND b.bundle_type = 'fansite'
           AND b.fansite_year IS NOT NULL
           AND b.fansite_month IS NOT NULL
           AND printf('%04d-%02d-%02d', b.fansite_year, b.fansite_month, d.day_of_month)
               BETWEEN ?1 AND ?2",
    );
    if persona_code.is_some() {
        sql.push_str(" AND b.persona_code = ?3");
    }
    sql.push_str(" ORDER BY date, t.sort_order, t.name");

    let mut stmt = conn.prepare(&sql)?;
    let mapper = |r: &rusqlite::Row| {
        Ok(FanSiteDayTag {
            date: r.get(0)?,
            bundle_uid: r.get(1)?,
            persona_code: r.get(2)?,
            fan_day_id: r.get(3)?,
            tag_id: r.get(4)?,
            tag_name: r.get(5)?,
            tag_color: r.get(6)?,
        })
    };
    let rows: rusqlite::Result<Vec<_>> = match persona_code {
        Some(code) => stmt
            .query_map(params![from, to, code], mapper)?
            .collect(),
        None => stmt.query_map(params![from, to], mapper)?.collect(),
    };
    Ok(rows?)
}

// ---- Tauri commands ---------------------------------------------------------

#[tauri::command]
pub fn list_content_tags<R: Runtime>(handle: AppHandle<R>) -> Result<Vec<ContentTag>, TagError> {
    let dir = app_data_dir(&handle)?;
    let conn = open_conn(&dir)?;
    pure_list_tags(&conn)
}

#[tauri::command]
pub fn create_content_tag<R: Runtime>(
    handle: AppHandle<R>,
    name: String,
    color: String,
) -> Result<i64, TagError> {
    let dir = app_data_dir(&handle)?;
    let conn = open_conn(&dir)?;
    pure_create_tag(&conn, &name, &color)
}

#[tauri::command]
pub fn update_content_tag<R: Runtime>(
    handle: AppHandle<R>,
    tag_id: i64,
    name: String,
    color: String,
) -> Result<(), TagError> {
    let dir = app_data_dir(&handle)?;
    let conn = open_conn(&dir)?;
    pure_update_tag(&conn, tag_id, &name, &color)
}

#[tauri::command]
pub fn delete_content_tag<R: Runtime>(handle: AppHandle<R>, tag_id: i64) -> Result<(), TagError> {
    let dir = app_data_dir(&handle)?;
    let conn = open_conn(&dir)?;
    pure_delete_tag(&conn, tag_id)
}

#[tauri::command]
pub fn list_bundle_tags<R: Runtime>(
    handle: AppHandle<R>,
    bundle_uid: String,
) -> Result<Vec<i64>, TagError> {
    let dir = app_data_dir(&handle)?;
    let conn = open_conn(&dir)?;
    pure_bundle_tag_ids(&conn, &bundle_uid)
}

#[tauri::command]
pub fn set_bundle_tags<R: Runtime>(
    handle: AppHandle<R>,
    bundle_uid: String,
    tag_ids: Vec<i64>,
) -> Result<(), TagError> {
    let dir = app_data_dir(&handle)?;
    let conn = open_conn(&dir)?;
    pure_set_bundle_tags(&conn, &bundle_uid, &tag_ids)
}

#[tauri::command]
pub fn list_fan_day_tags<R: Runtime>(
    handle: AppHandle<R>,
    fan_day_id: i64,
) -> Result<Vec<i64>, TagError> {
    let dir = app_data_dir(&handle)?;
    let conn = open_conn(&dir)?;
    pure_fan_day_tag_ids(&conn, fan_day_id)
}

#[tauri::command]
pub fn set_fan_day_tags<R: Runtime>(
    handle: AppHandle<R>,
    fan_day_id: i64,
    tag_ids: Vec<i64>,
) -> Result<(), TagError> {
    let dir = app_data_dir(&handle)?;
    let conn = open_conn(&dir)?;
    pure_set_fan_day_tags(&conn, fan_day_id, &tag_ids)
}

#[tauri::command]
pub fn list_fansite_day_tags_in_range<R: Runtime>(
    handle: AppHandle<R>,
    from: String,
    to: String,
    persona_code: Option<String>,
) -> Result<Vec<FanSiteDayTag>, TagError> {
    let dir = app_data_dir(&handle)?;
    let conn = open_conn(&dir)?;
    pure_fansite_tags_in_range(&conn, &from, &to, persona_code.as_deref())
}

#[tauri::command]
pub fn list_clip_tags<R: Runtime>(
    handle: AppHandle<R>,
    clip_id: String,
) -> Result<Vec<i64>, TagError> {
    let dir = app_data_dir(&handle)?;
    let conn = open_conn(&dir)?;
    pure_clip_tag_ids(&conn, &clip_id)
}

#[tauri::command]
pub fn set_clip_tags<R: Runtime>(
    handle: AppHandle<R>,
    clip_id: String,
    tag_ids: Vec<i64>,
) -> Result<(), TagError> {
    let dir = app_data_dir(&handle)?;
    let conn = open_conn(&dir)?;
    pure_set_clip_tags(&conn, &clip_id, &tag_ids)
}

#[tauri::command]
pub fn list_clip_tags_in_range<R: Runtime>(
    handle: AppHandle<R>,
    from: String,
    to: String,
    persona_code: Option<String>,
) -> Result<Vec<ClipTagInDate>, TagError> {
    let dir = app_data_dir(&handle)?;
    let conn = open_conn(&dir)?;
    pure_clip_tags_in_range(&conn, &from, &to, persona_code.as_deref())
}

// ---- Tests ------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_db() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        // Bundles depends on sites + clips, so apply the full chain up to
        // 017 plus 026. Mirrors the pattern in bundles::tests::fresh_db.
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
            include_str!("../migrations/026_content_tags.sql"),
            include_str!("../migrations/027_fanday_tags.sql"),
            include_str!("../migrations/028_clip_tags.sql"),
        ] {
            conn.execute_batch(sql).unwrap();
        }
        conn.execute_batch("PRAGMA foreign_keys = ON;").unwrap();
        conn
    }

    fn seed_bundle(conn: &Connection, uid: &str) {
        conn.execute(
            "INSERT INTO bundles (uid, bundle_type, content_date)
             VALUES (?1, 'content', '2026-05-22')",
            params![uid],
        )
        .unwrap();
    }

    #[test]
    fn eight_builtins_seeded() {
        let conn = fresh_db();
        let all = pure_list_tags(&conn).unwrap();
        assert_eq!(all.len(), 8);
        let names: Vec<&str> = all.iter().map(|t| t.name.as_str()).collect();
        assert_eq!(
            names,
            vec!["tits", "pantyhose", "panties", "face", "ass", "feet", "flats", "heels"]
        );
        assert!(all.iter().all(|t| t.is_builtin));
    }

    #[test]
    fn create_validates_inputs() {
        let conn = fresh_db();
        assert!(pure_create_tag(&conn, "  ", "#FFFFFF").is_err());
        assert!(pure_create_tag(&conn, "x", "not-a-hex").is_err());
        let id = pure_create_tag(&conn, "stockings", "#F472B6").unwrap();
        let row = pure_list_tags(&conn)
            .unwrap()
            .into_iter()
            .find(|t| t.id == id)
            .unwrap();
        assert!(!row.is_builtin);
        assert_eq!(row.name, "stockings");
    }

    #[test]
    fn builtin_cannot_be_deleted_but_can_be_renamed() {
        let conn = fresh_db();
        let tits = pure_list_tags(&conn)
            .unwrap()
            .into_iter()
            .find(|t| t.name == "tits")
            .unwrap();
        assert!(matches!(
            pure_delete_tag(&conn, tits.id),
            Err(TagError::BuiltinUndeletable(_))
        ));
        pure_update_tag(&conn, tits.id, "TITS!", "#000000").unwrap();
        let after = pure_list_tags(&conn)
            .unwrap()
            .into_iter()
            .find(|t| t.id == tits.id)
            .unwrap();
        assert_eq!(after.name, "TITS!");
        assert_eq!(after.color, "#000000");
    }

    #[test]
    fn set_bundle_tags_round_trips() {
        let conn = fresh_db();
        seed_bundle(&conn, "B1");
        let ids: Vec<i64> = pure_list_tags(&conn).unwrap().iter().take(3).map(|t| t.id).collect();
        pure_set_bundle_tags(&conn, "B1", &ids).unwrap();
        let got = pure_bundle_tag_ids(&conn, "B1").unwrap();
        let mut got_sorted = got.clone();
        got_sorted.sort();
        let mut want_sorted = ids.clone();
        want_sorted.sort();
        assert_eq!(got_sorted, want_sorted);
        // Replace with a subset.
        pure_set_bundle_tags(&conn, "B1", &[ids[0]]).unwrap();
        let got = pure_bundle_tag_ids(&conn, "B1").unwrap();
        assert_eq!(got, vec![ids[0]]);
    }

    #[test]
    fn deleting_bundle_cascades_links() {
        let conn = fresh_db();
        seed_bundle(&conn, "B1");
        let id = pure_list_tags(&conn).unwrap()[0].id;
        pure_set_bundle_tags(&conn, "B1", &[id]).unwrap();
        conn.execute("DELETE FROM bundles WHERE uid = 'B1'", [])
            .unwrap();
        let n: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM bundle_tag_links WHERE bundle_uid = 'B1'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(n, 0);
    }

    #[test]
    fn deleting_user_tag_cascades_links() {
        let conn = fresh_db();
        seed_bundle(&conn, "B1");
        let tid = pure_create_tag(&conn, "stockings", "#F472B6").unwrap();
        pure_set_bundle_tags(&conn, "B1", &[tid]).unwrap();
        pure_delete_tag(&conn, tid).unwrap();
        let got = pure_bundle_tag_ids(&conn, "B1").unwrap();
        assert!(got.is_empty());
    }

    // ---- PR3: per-day FanSite tags --------------------------------------

    fn seed_fansite_bundle(conn: &Connection, uid: &str, year: i64, month: i64, persona: Option<&str>) {
        conn.execute(
            "INSERT INTO bundles (uid, bundle_type, content_date, persona_code,
                                  fansite_year, fansite_month)
             VALUES (?1, 'fansite', '2026-05-01', ?2, ?3, ?4)",
            params![uid, persona, year, month],
        )
        .unwrap();
    }

    fn seed_fan_day(conn: &Connection, bundle_uid: &str, day: i64) -> i64 {
        conn.execute(
            "INSERT INTO bundle_fan_days (bundle_uid, day_of_month) VALUES (?1, ?2)",
            params![bundle_uid, day],
        )
        .unwrap();
        conn.last_insert_rowid()
    }

    #[test]
    fn bundle_level_set_does_not_touch_day_level() {
        let conn = fresh_db();
        seed_fansite_bundle(&conn, "F1", 2026, 6, Some("CoC"));
        let day = seed_fan_day(&conn, "F1", 4);
        let all = pure_list_tags(&conn).unwrap();
        let (t1, t2) = (all[0].id, all[1].id);
        pure_set_fan_day_tags(&conn, day, &[t1, t2]).unwrap();
        // A bundle-level set should leave the day-level row intact.
        pure_set_bundle_tags(&conn, "F1", &[t1]).unwrap();
        let day_tags = pure_fan_day_tag_ids(&conn, day).unwrap();
        let mut got = day_tags.clone();
        got.sort();
        let mut want = vec![t1, t2];
        want.sort();
        assert_eq!(got, want);
        // Bundle-level view returns just the bundle-level row.
        assert_eq!(pure_bundle_tag_ids(&conn, "F1").unwrap(), vec![t1]);
    }

    #[test]
    fn day_level_set_replaces_only_that_day() {
        let conn = fresh_db();
        seed_fansite_bundle(&conn, "F1", 2026, 6, None);
        let d4 = seed_fan_day(&conn, "F1", 4);
        let d11 = seed_fan_day(&conn, "F1", 11);
        let all = pure_list_tags(&conn).unwrap();
        let (t1, t2, t3) = (all[0].id, all[1].id, all[2].id);
        pure_set_fan_day_tags(&conn, d4, &[t1, t2]).unwrap();
        pure_set_fan_day_tags(&conn, d11, &[t3]).unwrap();
        // Replace day 4 — day 11 must survive.
        pure_set_fan_day_tags(&conn, d4, &[t3]).unwrap();
        assert_eq!(pure_fan_day_tag_ids(&conn, d4).unwrap(), vec![t3]);
        assert_eq!(pure_fan_day_tag_ids(&conn, d11).unwrap(), vec![t3]);
    }

    #[test]
    fn deleting_fan_day_cascades_day_tags() {
        let conn = fresh_db();
        seed_fansite_bundle(&conn, "F1", 2026, 6, None);
        let day = seed_fan_day(&conn, "F1", 4);
        let t1 = pure_list_tags(&conn).unwrap()[0].id;
        pure_set_fan_day_tags(&conn, day, &[t1]).unwrap();
        conn.execute("DELETE FROM bundle_fan_days WHERE id = ?1", params![day])
            .unwrap();
        let n: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM bundle_tag_links WHERE fan_day_id = ?1",
                params![day],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(n, 0);
    }

    fn seed_clip(conn: &Connection, id: &str, persona: Option<&str>, go_live: Option<&str>) {
        conn.execute(
            "INSERT INTO clips (id, persona_code, go_live_date) VALUES (?1, ?2, ?3)",
            params![id, persona, go_live],
        )
        .unwrap();
    }

    #[test]
    fn set_clip_tags_round_trips() {
        let conn = fresh_db();
        seed_clip(&conn, "C1", Some("CoC"), Some("2026-06-10"));
        let all = pure_list_tags(&conn).unwrap();
        let (t1, t2) = (all[0].id, all[1].id);
        pure_set_clip_tags(&conn, "C1", &[t1, t2]).unwrap();
        let mut got = pure_clip_tag_ids(&conn, "C1").unwrap();
        got.sort();
        let mut want = vec![t1, t2];
        want.sort();
        assert_eq!(got, want);
        // Replace with subset.
        pure_set_clip_tags(&conn, "C1", &[t1]).unwrap();
        assert_eq!(pure_clip_tag_ids(&conn, "C1").unwrap(), vec![t1]);
    }

    #[test]
    fn deleting_clip_cascades_clip_tags() {
        let conn = fresh_db();
        seed_clip(&conn, "C1", None, None);
        let t1 = pure_list_tags(&conn).unwrap()[0].id;
        pure_set_clip_tags(&conn, "C1", &[t1]).unwrap();
        conn.execute("DELETE FROM clips WHERE id = ?1", params!["C1"])
            .unwrap();
        let n: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM clip_tag_links WHERE clip_id = ?1",
                params!["C1"],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(n, 0);
    }

    #[test]
    fn mirror_bundle_tags_to_clip_copies_only_bundle_level() {
        let conn = fresh_db();
        seed_bundle(&conn, "B1");
        seed_clip(&conn, "B1", Some("CoC"), Some("2026-06-10"));
        // Also seed a fan-day for the same bundle with its own tag — must
        // NOT show up on the clip.
        let day = conn
            .query_row(
                "INSERT INTO bundle_fan_days (bundle_uid, day_of_month)
                 VALUES (?1, 4) RETURNING id",
                params!["B1"],
                |r| r.get::<_, i64>(0),
            )
            .unwrap();
        let all = pure_list_tags(&conn).unwrap();
        let (t1, t2, t3) = (all[0].id, all[1].id, all[2].id);
        pure_set_bundle_tags(&conn, "B1", &[t1, t2]).unwrap();
        pure_set_fan_day_tags(&conn, day, &[t3]).unwrap();

        pure_mirror_bundle_tags_to_clip(&conn, "B1", "B1").unwrap();
        let mut got = pure_clip_tag_ids(&conn, "B1").unwrap();
        got.sort();
        let mut want = vec![t1, t2];
        want.sort();
        assert_eq!(got, want);
    }

    #[test]
    fn clip_range_query_resolves_dates_and_filters_by_persona() {
        let conn = fresh_db();
        seed_clip(&conn, "C1", Some("CoC"), Some("2026-06-10"));
        seed_clip(&conn, "C2", Some("PoA"), Some("2026-06-15 14:30"));
        seed_clip(&conn, "C3", Some("CoC"), Some("2026-07-01"));
        let all = pure_list_tags(&conn).unwrap();
        let (t1, t2) = (all[0].id, all[1].id);
        pure_set_clip_tags(&conn, "C1", &[t1]).unwrap();
        pure_set_clip_tags(&conn, "C2", &[t2]).unwrap();
        pure_set_clip_tags(&conn, "C3", &[t1]).unwrap();

        let all_rows = pure_clip_tags_in_range(&conn, "2026-06-01", "2026-06-30", None).unwrap();
        assert_eq!(all_rows.len(), 2);
        assert!(all_rows.iter().any(|r| r.clip_id == "C1" && r.date == "2026-06-10"));
        // Timestamp-form go_live_date is sliced to YYYY-MM-DD.
        assert!(all_rows.iter().any(|r| r.clip_id == "C2" && r.date == "2026-06-15"));

        let coc =
            pure_clip_tags_in_range(&conn, "2026-06-01", "2026-06-30", Some("CoC")).unwrap();
        assert_eq!(coc.len(), 1);
        assert_eq!(coc[0].clip_id, "C1");

        let next_month =
            pure_clip_tags_in_range(&conn, "2026-07-01", "2026-07-31", None).unwrap();
        assert_eq!(next_month.len(), 1);
        assert_eq!(next_month[0].clip_id, "C3");
    }

    #[test]
    fn range_query_resolves_dates_and_filters_by_persona() {
        let conn = fresh_db();
        seed_fansite_bundle(&conn, "F1", 2026, 6, Some("CoC"));
        seed_fansite_bundle(&conn, "F2", 2026, 6, Some("PoA"));
        let d4_coc = seed_fan_day(&conn, "F1", 4);
        let d18_poa = seed_fan_day(&conn, "F2", 18);
        let d4_poa = seed_fan_day(&conn, "F2", 4);
        let all = pure_list_tags(&conn).unwrap();
        let (t1, t2) = (all[0].id, all[1].id);
        pure_set_fan_day_tags(&conn, d4_coc, &[t1]).unwrap();
        pure_set_fan_day_tags(&conn, d18_poa, &[t2]).unwrap();
        pure_set_fan_day_tags(&conn, d4_poa, &[t1, t2]).unwrap();

        // Full month, all personas.
        let all_rows =
            pure_fansite_tags_in_range(&conn, "2026-06-01", "2026-06-30", None).unwrap();
        assert_eq!(all_rows.len(), 4);
        assert!(all_rows.iter().any(|r| r.date == "2026-06-04" && r.persona_code.as_deref() == Some("CoC")));
        assert!(all_rows.iter().any(|r| r.date == "2026-06-18" && r.persona_code.as_deref() == Some("PoA")));

        // Persona-filtered.
        let coc =
            pure_fansite_tags_in_range(&conn, "2026-06-01", "2026-06-30", Some("CoC")).unwrap();
        assert_eq!(coc.len(), 1);
        assert_eq!(coc[0].date, "2026-06-04");
        assert_eq!(coc[0].persona_code.as_deref(), Some("CoC"));

        // Out-of-range — no rows.
        let none =
            pure_fansite_tags_in_range(&conn, "2026-07-01", "2026-07-31", None).unwrap();
        assert!(none.is_empty());
    }
}
