// Phase 15 PR1: Reddit ops — subreddits, post log, captions.
//
// All three concepts persona-scoped (rows carry a nullable persona_code
// referencing personas). The frontend filters on the active persona; the
// commands accept an Option<String> so the caller can request "all
// personas" (ALL switcher) by passing None.

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use tauri::{AppHandle, Manager, Runtime};

#[derive(Debug, thiserror::Error)]
pub enum RedditError {
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

impl serde::Serialize for RedditError {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.to_string())
    }
}

// ---- Boundary structs ------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Subreddit {
    pub id: i64,
    pub persona_code: Option<String>,
    pub name: String,
    pub tag_id: Option<i64>,
    pub verified: bool,
    pub karma_req: String,
    pub rotation: String, // "fresh" | "soon" | "wait"
    pub last_posted_at: Option<String>,
    pub notes: String,
    pub starred: bool,
    pub sort_order: i64,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SubredditInput {
    pub persona_code: Option<String>,
    pub name: String,
    pub tag_id: Option<i64>,
    pub verified: bool,
    pub karma_req: String,
    pub rotation: String,
    pub notes: String,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SubredditPost {
    pub id: i64,
    pub persona_code: Option<String>,
    pub subreddit_id: Option<i64>,
    pub subreddit_name: String,
    pub tag_id: Option<i64>,
    pub posted_date: String,
    pub notes: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SubredditPostInput {
    pub persona_code: Option<String>,
    pub subreddit_id: Option<i64>,
    pub subreddit_name: String,
    pub tag_id: Option<i64>,
    pub posted_date: String,
    pub notes: String,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Caption {
    pub id: i64,
    pub persona_code: Option<String>,
    pub text: String,
    pub tag_id: Option<i64>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CaptionInput {
    pub persona_code: Option<String>,
    pub text: String,
    pub tag_id: Option<i64>,
}

// ---- Internals -------------------------------------------------------------

fn app_data_dir<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, RedditError> {
    handle
        .path()
        .app_data_dir()
        .map_err(|e| RedditError::Settings(e.to_string()))
}

fn open_conn(app_data_dir: &Path) -> Result<Connection, RedditError> {
    Ok(Connection::open(app_data_dir.join("molly.db"))?)
}

fn valid_rotation(s: &str) -> bool {
    matches!(s, "fresh" | "soon" | "wait")
}

fn valid_iso_date(s: &str) -> bool {
    // YYYY-MM-DD shape check — relies on strftime-style padding from the
    // caller. Frontend always sends the right shape; this guards a typo.
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

// ---- Subreddits ------------------------------------------------------------

fn row_to_subreddit(r: &rusqlite::Row) -> rusqlite::Result<Subreddit> {
    Ok(Subreddit {
        id: r.get(0)?,
        persona_code: r.get(1)?,
        name: r.get(2)?,
        tag_id: r.get(3)?,
        verified: r.get::<_, i64>(4)? != 0,
        karma_req: r.get(5)?,
        rotation: r.get(6)?,
        last_posted_at: r.get(7)?,
        notes: r.get(8)?,
        starred: r.get::<_, i64>(9)? != 0,
        sort_order: r.get(10)?,
        created_at: r.get(11)?,
        updated_at: r.get(12)?,
    })
}

pub(crate) fn pure_list_subreddits(
    conn: &Connection,
    persona_code: Option<&str>,
) -> Result<Vec<Subreddit>, RedditError> {
    if let Some(p) = persona_code {
        let mut stmt = conn.prepare(
            "SELECT id, persona_code, name, tag_id, verified, karma_req, rotation,
                    last_posted_at, notes, starred, sort_order, created_at, updated_at
             FROM subreddits
             WHERE persona_code = ?1
             ORDER BY starred DESC, name COLLATE NOCASE",
        )?;
        let rows = stmt
            .query_map(params![p], row_to_subreddit)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(rows)
    } else {
        let mut stmt = conn.prepare(
            "SELECT id, persona_code, name, tag_id, verified, karma_req, rotation,
                    last_posted_at, notes, starred, sort_order, created_at, updated_at
             FROM subreddits
             ORDER BY starred DESC, name COLLATE NOCASE",
        )?;
        let rows = stmt
            .query_map([], row_to_subreddit)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(rows)
    }
}

pub(crate) fn pure_create_subreddit(
    conn: &Connection,
    input: &SubredditInput,
) -> Result<i64, RedditError> {
    let name = input.name.trim().trim_start_matches("r/").trim_start_matches("R/");
    if name.is_empty() {
        return Err(RedditError::Invalid("subreddit name required".into()));
    }
    if !valid_rotation(&input.rotation) {
        return Err(RedditError::Invalid(format!(
            "rotation must be fresh|soon|wait (got {})",
            input.rotation
        )));
    }
    conn.execute(
        "INSERT INTO subreddits (persona_code, name, tag_id, verified, karma_req,
                                 rotation, notes)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        params![
            input.persona_code,
            name,
            input.tag_id,
            if input.verified { 1_i64 } else { 0 },
            input.karma_req,
            input.rotation,
            input.notes,
        ],
    )?;
    Ok(conn.last_insert_rowid())
}

pub(crate) fn pure_update_subreddit(
    conn: &Connection,
    id: i64,
    input: &SubredditInput,
) -> Result<(), RedditError> {
    let name = input.name.trim().trim_start_matches("r/").trim_start_matches("R/");
    if name.is_empty() {
        return Err(RedditError::Invalid("subreddit name required".into()));
    }
    if !valid_rotation(&input.rotation) {
        return Err(RedditError::Invalid(format!(
            "rotation must be fresh|soon|wait (got {})",
            input.rotation
        )));
    }
    let n = conn.execute(
        "UPDATE subreddits
         SET persona_code = ?1, name = ?2, tag_id = ?3, verified = ?4,
             karma_req = ?5, rotation = ?6, notes = ?7,
             updated_at = datetime('now')
         WHERE id = ?8",
        params![
            input.persona_code,
            name,
            input.tag_id,
            if input.verified { 1_i64 } else { 0 },
            input.karma_req,
            input.rotation,
            input.notes,
            id,
        ],
    )?;
    if n == 0 {
        return Err(RedditError::NotFound(id));
    }
    Ok(())
}

pub(crate) fn pure_set_subreddit_starred(
    conn: &Connection,
    id: i64,
    starred: bool,
) -> Result<(), RedditError> {
    let n = conn.execute(
        "UPDATE subreddits SET starred = ?1, updated_at = datetime('now') WHERE id = ?2",
        params![if starred { 1_i64 } else { 0 }, id],
    )?;
    if n == 0 {
        return Err(RedditError::NotFound(id));
    }
    Ok(())
}

pub(crate) fn pure_set_subreddit_verified(
    conn: &Connection,
    id: i64,
    verified: bool,
) -> Result<(), RedditError> {
    let n = conn.execute(
        "UPDATE subreddits SET verified = ?1, updated_at = datetime('now') WHERE id = ?2",
        params![if verified { 1_i64 } else { 0 }, id],
    )?;
    if n == 0 {
        return Err(RedditError::NotFound(id));
    }
    Ok(())
}

pub(crate) fn pure_delete_subreddit(conn: &Connection, id: i64) -> Result<(), RedditError> {
    let n = conn.execute("DELETE FROM subreddits WHERE id = ?1", params![id])?;
    if n == 0 {
        return Err(RedditError::NotFound(id));
    }
    Ok(())
}

/// Flip a subreddit's rotation to 'wait' and stamp its last_posted_at to
/// `posted_date`. Logs the action by inserting a row into subreddit_posts
/// with the same date so the post log stays in sync. Returns the new
/// post id so the UI can navigate to it.
pub(crate) fn pure_mark_subreddit_posted(
    conn: &Connection,
    subreddit_id: i64,
    posted_date: &str,
) -> Result<i64, RedditError> {
    if !valid_iso_date(posted_date) {
        return Err(RedditError::Invalid(format!(
            "posted_date must be YYYY-MM-DD (got {posted_date})"
        )));
    }
    let row: Option<(Option<String>, String, Option<i64>)> = conn
        .query_row(
            "SELECT persona_code, name, tag_id FROM subreddits WHERE id = ?1",
            params![subreddit_id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )
        .optional()?;
    let Some((persona, name, tag)) = row else {
        return Err(RedditError::NotFound(subreddit_id));
    };
    conn.execute(
        "UPDATE subreddits
         SET last_posted_at = ?1, rotation = 'wait', updated_at = datetime('now')
         WHERE id = ?2",
        params![posted_date, subreddit_id],
    )?;
    conn.execute(
        "INSERT INTO subreddit_posts (persona_code, subreddit_id, subreddit_name,
                                      tag_id, posted_date, notes)
         VALUES (?1, ?2, ?3, ?4, ?5, '')",
        params![persona, subreddit_id, name, tag, posted_date],
    )?;
    Ok(conn.last_insert_rowid())
}

// ---- Posts -----------------------------------------------------------------

fn row_to_post(r: &rusqlite::Row) -> rusqlite::Result<SubredditPost> {
    Ok(SubredditPost {
        id: r.get(0)?,
        persona_code: r.get(1)?,
        subreddit_id: r.get(2)?,
        subreddit_name: r.get(3)?,
        tag_id: r.get(4)?,
        posted_date: r.get(5)?,
        notes: r.get(6)?,
        created_at: r.get(7)?,
    })
}

pub(crate) fn pure_list_posts_in_range(
    conn: &Connection,
    from: &str,
    to: &str,
    persona_code: Option<&str>,
) -> Result<Vec<SubredditPost>, RedditError> {
    if !valid_iso_date(from) || !valid_iso_date(to) {
        return Err(RedditError::Invalid(
            "from/to must be ISO YYYY-MM-DD".into(),
        ));
    }
    if let Some(p) = persona_code {
        let mut stmt = conn.prepare(
            "SELECT id, persona_code, subreddit_id, subreddit_name, tag_id,
                    posted_date, notes, created_at
             FROM subreddit_posts
             WHERE posted_date BETWEEN ?1 AND ?2 AND persona_code = ?3
             ORDER BY posted_date DESC, created_at DESC",
        )?;
        let rows = stmt
            .query_map(params![from, to, p], row_to_post)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(rows)
    } else {
        let mut stmt = conn.prepare(
            "SELECT id, persona_code, subreddit_id, subreddit_name, tag_id,
                    posted_date, notes, created_at
             FROM subreddit_posts
             WHERE posted_date BETWEEN ?1 AND ?2
             ORDER BY posted_date DESC, created_at DESC",
        )?;
        let rows = stmt
            .query_map(params![from, to], row_to_post)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(rows)
    }
}

pub(crate) fn pure_create_post(
    conn: &Connection,
    input: &SubredditPostInput,
) -> Result<i64, RedditError> {
    let name = input
        .subreddit_name
        .trim()
        .trim_start_matches("r/")
        .trim_start_matches("R/");
    if name.is_empty() {
        return Err(RedditError::Invalid("subreddit_name required".into()));
    }
    if !valid_iso_date(&input.posted_date) {
        return Err(RedditError::Invalid(format!(
            "posted_date must be YYYY-MM-DD (got {})",
            input.posted_date
        )));
    }
    conn.execute(
        "INSERT INTO subreddit_posts (persona_code, subreddit_id, subreddit_name,
                                      tag_id, posted_date, notes)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![
            input.persona_code,
            input.subreddit_id,
            name,
            input.tag_id,
            input.posted_date,
            input.notes,
        ],
    )?;
    Ok(conn.last_insert_rowid())
}

pub(crate) fn pure_delete_post(conn: &Connection, id: i64) -> Result<(), RedditError> {
    let n = conn.execute("DELETE FROM subreddit_posts WHERE id = ?1", params![id])?;
    if n == 0 {
        return Err(RedditError::NotFound(id));
    }
    Ok(())
}

// ---- Captions --------------------------------------------------------------

fn row_to_caption(r: &rusqlite::Row) -> rusqlite::Result<Caption> {
    Ok(Caption {
        id: r.get(0)?,
        persona_code: r.get(1)?,
        text: r.get(2)?,
        tag_id: r.get(3)?,
        created_at: r.get(4)?,
        updated_at: r.get(5)?,
    })
}

pub(crate) fn pure_list_captions(
    conn: &Connection,
    persona_code: Option<&str>,
) -> Result<Vec<Caption>, RedditError> {
    if let Some(p) = persona_code {
        let mut stmt = conn.prepare(
            "SELECT id, persona_code, text, tag_id, created_at, updated_at
             FROM captions
             WHERE persona_code = ?1
             ORDER BY updated_at DESC",
        )?;
        let rows = stmt
            .query_map(params![p], row_to_caption)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(rows)
    } else {
        let mut stmt = conn.prepare(
            "SELECT id, persona_code, text, tag_id, created_at, updated_at
             FROM captions
             ORDER BY updated_at DESC",
        )?;
        let rows = stmt
            .query_map([], row_to_caption)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(rows)
    }
}

pub(crate) fn pure_create_caption(
    conn: &Connection,
    input: &CaptionInput,
) -> Result<i64, RedditError> {
    let text = input.text.trim();
    if text.is_empty() {
        return Err(RedditError::Invalid("caption text required".into()));
    }
    conn.execute(
        "INSERT INTO captions (persona_code, text, tag_id) VALUES (?1, ?2, ?3)",
        params![input.persona_code, text, input.tag_id],
    )?;
    Ok(conn.last_insert_rowid())
}

pub(crate) fn pure_update_caption(
    conn: &Connection,
    id: i64,
    input: &CaptionInput,
) -> Result<(), RedditError> {
    let text = input.text.trim();
    if text.is_empty() {
        return Err(RedditError::Invalid("caption text required".into()));
    }
    let n = conn.execute(
        "UPDATE captions
         SET persona_code = ?1, text = ?2, tag_id = ?3, updated_at = datetime('now')
         WHERE id = ?4",
        params![input.persona_code, text, input.tag_id, id],
    )?;
    if n == 0 {
        return Err(RedditError::NotFound(id));
    }
    Ok(())
}

pub(crate) fn pure_delete_caption(conn: &Connection, id: i64) -> Result<(), RedditError> {
    let n = conn.execute("DELETE FROM captions WHERE id = ?1", params![id])?;
    if n == 0 {
        return Err(RedditError::NotFound(id));
    }
    Ok(())
}

// ---- Tauri commands --------------------------------------------------------

#[tauri::command]
pub fn list_subreddits<R: Runtime>(
    handle: AppHandle<R>,
    persona_code: Option<String>,
) -> Result<Vec<Subreddit>, RedditError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_list_subreddits(&conn, persona_code.as_deref())
}

#[tauri::command]
pub fn create_subreddit<R: Runtime>(
    handle: AppHandle<R>,
    input: SubredditInput,
) -> Result<i64, RedditError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_create_subreddit(&conn, &input)
}

#[tauri::command]
pub fn update_subreddit<R: Runtime>(
    handle: AppHandle<R>,
    id: i64,
    input: SubredditInput,
) -> Result<(), RedditError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_update_subreddit(&conn, id, &input)
}

#[tauri::command]
pub fn set_subreddit_starred<R: Runtime>(
    handle: AppHandle<R>,
    id: i64,
    starred: bool,
) -> Result<(), RedditError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_set_subreddit_starred(&conn, id, starred)
}

#[tauri::command]
pub fn set_subreddit_verified<R: Runtime>(
    handle: AppHandle<R>,
    id: i64,
    verified: bool,
) -> Result<(), RedditError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_set_subreddit_verified(&conn, id, verified)
}

#[tauri::command]
pub fn delete_subreddit<R: Runtime>(
    handle: AppHandle<R>,
    id: i64,
) -> Result<(), RedditError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_delete_subreddit(&conn, id)
}

#[tauri::command]
pub fn mark_subreddit_posted<R: Runtime>(
    handle: AppHandle<R>,
    subreddit_id: i64,
    posted_date: String,
) -> Result<i64, RedditError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_mark_subreddit_posted(&conn, subreddit_id, &posted_date)
}

#[tauri::command]
pub fn list_subreddit_posts_in_range<R: Runtime>(
    handle: AppHandle<R>,
    from: String,
    to: String,
    persona_code: Option<String>,
) -> Result<Vec<SubredditPost>, RedditError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_list_posts_in_range(&conn, &from, &to, persona_code.as_deref())
}

#[tauri::command]
pub fn create_subreddit_post<R: Runtime>(
    handle: AppHandle<R>,
    input: SubredditPostInput,
) -> Result<i64, RedditError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_create_post(&conn, &input)
}

#[tauri::command]
pub fn delete_subreddit_post<R: Runtime>(
    handle: AppHandle<R>,
    id: i64,
) -> Result<(), RedditError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_delete_post(&conn, id)
}

#[tauri::command]
pub fn list_captions<R: Runtime>(
    handle: AppHandle<R>,
    persona_code: Option<String>,
) -> Result<Vec<Caption>, RedditError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_list_captions(&conn, persona_code.as_deref())
}

#[tauri::command]
pub fn create_caption<R: Runtime>(
    handle: AppHandle<R>,
    input: CaptionInput,
) -> Result<i64, RedditError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_create_caption(&conn, &input)
}

#[tauri::command]
pub fn update_caption<R: Runtime>(
    handle: AppHandle<R>,
    id: i64,
    input: CaptionInput,
) -> Result<(), RedditError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_update_caption(&conn, id, &input)
}

#[tauri::command]
pub fn delete_caption<R: Runtime>(
    handle: AppHandle<R>,
    id: i64,
) -> Result<(), RedditError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_delete_caption(&conn, id)
}

// ---- Tests -----------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_db() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
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
            include_str!("../migrations/029_subreddits.sql"),
        ] {
            conn.execute_batch(sql).unwrap();
        }
        // Personas seeded by 001_init.sql — CoC/PoA/Sa already present.
        conn.execute_batch("PRAGMA foreign_keys = ON;").unwrap();
        conn
    }

    fn mk_sub_input(persona: Option<&str>, name: &str) -> SubredditInput {
        SubredditInput {
            persona_code: persona.map(String::from),
            name: name.into(),
            tag_id: None,
            verified: false,
            karma_req: "50+".into(),
            rotation: "fresh".into(),
            notes: String::new(),
        }
    }

    #[test]
    fn seed_loads_thirty_three_coc_subs() {
        let conn = fresh_db();
        let coc = pure_list_subreddits(&conn, Some("CoC")).unwrap();
        assert_eq!(coc.len(), 33);
        // 'bbw' must be starred per the seed and rotation 'fresh'.
        let bbw = coc.iter().find(|s| s.name == "bbw").expect("bbw seeded");
        assert!(bbw.starred);
        assert_eq!(bbw.rotation, "fresh");
        // Tag resolution worked (no NULL tag_ids for seeded rows).
        assert!(coc.iter().all(|s| s.tag_id.is_some()), "every seeded sub got a tag");
    }

    #[test]
    fn list_filters_by_persona() {
        let conn = fresh_db();
        let id = pure_create_subreddit(&conn, &mk_sub_input(Some("PoA"), "princess_sub")).unwrap();
        let poa = pure_list_subreddits(&conn, Some("PoA")).unwrap();
        assert!(poa.iter().any(|s| s.id == id));
        let coc = pure_list_subreddits(&conn, Some("CoC")).unwrap();
        assert!(coc.iter().all(|s| s.id != id), "PoA sub must not show under CoC");
    }

    #[test]
    fn create_strips_leading_r_slash() {
        let conn = fresh_db();
        let id =
            pure_create_subreddit(&conn, &mk_sub_input(Some("PoA"), "r/leading_r_slash")).unwrap();
        let row = pure_list_subreddits(&conn, Some("PoA"))
            .unwrap()
            .into_iter()
            .find(|s| s.id == id)
            .unwrap();
        assert_eq!(row.name, "leading_r_slash");
    }

    #[test]
    fn create_rejects_blank_name_and_bad_rotation() {
        let conn = fresh_db();
        assert!(pure_create_subreddit(&conn, &mk_sub_input(Some("PoA"), "   ")).is_err());
        let mut bad = mk_sub_input(Some("PoA"), "ok_name");
        bad.rotation = "later".into();
        assert!(pure_create_subreddit(&conn, &bad).is_err());
    }

    #[test]
    fn unique_name_per_persona_but_same_name_across_personas() {
        let conn = fresh_db();
        pure_create_subreddit(&conn, &mk_sub_input(Some("PoA"), "dup")).unwrap();
        // Same persona + same name (case-insensitive) → fail.
        assert!(pure_create_subreddit(&conn, &mk_sub_input(Some("PoA"), "DUP")).is_err());
        // Different persona → fine.
        pure_create_subreddit(&conn, &mk_sub_input(Some("CoC"), "dup")).unwrap();
    }

    #[test]
    fn star_verify_round_trip() {
        let conn = fresh_db();
        let id = pure_create_subreddit(&conn, &mk_sub_input(Some("PoA"), "starme")).unwrap();
        pure_set_subreddit_starred(&conn, id, true).unwrap();
        pure_set_subreddit_verified(&conn, id, true).unwrap();
        let row = pure_list_subreddits(&conn, Some("PoA"))
            .unwrap()
            .into_iter()
            .find(|s| s.id == id)
            .unwrap();
        assert!(row.starred && row.verified);
    }

    #[test]
    fn mark_posted_flips_rotation_and_creates_post_row() {
        let conn = fresh_db();
        let id = pure_create_subreddit(&conn, &mk_sub_input(Some("PoA"), "marky")).unwrap();
        let post_id = pure_mark_subreddit_posted(&conn, id, "2026-06-04").unwrap();
        let row = pure_list_subreddits(&conn, Some("PoA"))
            .unwrap()
            .into_iter()
            .find(|s| s.id == id)
            .unwrap();
        assert_eq!(row.rotation, "wait");
        assert_eq!(row.last_posted_at.as_deref(), Some("2026-06-04"));
        let posts =
            pure_list_posts_in_range(&conn, "2026-06-01", "2026-06-30", Some("PoA")).unwrap();
        assert!(posts.iter().any(|p| p.id == post_id && p.subreddit_id == Some(id)));
    }

    #[test]
    fn mark_posted_rejects_bad_date_and_missing_sub() {
        let conn = fresh_db();
        let id = pure_create_subreddit(&conn, &mk_sub_input(Some("PoA"), "x")).unwrap();
        assert!(pure_mark_subreddit_posted(&conn, id, "tomorrow").is_err());
        assert!(matches!(
            pure_mark_subreddit_posted(&conn, 99_999, "2026-06-04"),
            Err(RedditError::NotFound(_))
        ));
    }

    #[test]
    fn post_log_supports_future_and_past_dates() {
        let conn = fresh_db();
        let id = pure_create_subreddit(&conn, &mk_sub_input(Some("PoA"), "futurex")).unwrap();
        // Future
        pure_create_post(
            &conn,
            &SubredditPostInput {
                persona_code: Some("PoA".into()),
                subreddit_id: Some(id),
                subreddit_name: "futurex".into(),
                tag_id: None,
                posted_date: "2099-01-01".into(),
                notes: "scheduled".into(),
            },
        )
        .unwrap();
        // Past
        pure_create_post(
            &conn,
            &SubredditPostInput {
                persona_code: Some("PoA".into()),
                subreddit_id: Some(id),
                subreddit_name: "futurex".into(),
                tag_id: None,
                posted_date: "2024-01-01".into(),
                notes: "back-log".into(),
            },
        )
        .unwrap();
        let rows =
            pure_list_posts_in_range(&conn, "2024-01-01", "2099-12-31", Some("PoA")).unwrap();
        assert_eq!(rows.len(), 2);
    }

    #[test]
    fn deleting_subreddit_keeps_post_history_via_set_null() {
        let conn = fresh_db();
        let id = pure_create_subreddit(&conn, &mk_sub_input(Some("PoA"), "stillhere")).unwrap();
        let post_id = pure_mark_subreddit_posted(&conn, id, "2026-06-10").unwrap();
        pure_delete_subreddit(&conn, id).unwrap();
        let posts =
            pure_list_posts_in_range(&conn, "2026-06-01", "2026-06-30", Some("PoA")).unwrap();
        let p = posts.iter().find(|p| p.id == post_id).unwrap();
        assert!(p.subreddit_id.is_none(), "FK set null on parent delete");
        // Name snapshot survives so the log still displays it.
        assert_eq!(p.subreddit_name, "stillhere");
    }

    #[test]
    fn caption_crud_round_trip() {
        let conn = fresh_db();
        let id = pure_create_caption(
            &conn,
            &CaptionInput {
                persona_code: Some("CoC".into()),
                text: "  Soft and warm  ".into(),
                tag_id: None,
            },
        )
        .unwrap();
        let row = pure_list_captions(&conn, Some("CoC"))
            .unwrap()
            .into_iter()
            .find(|c| c.id == id)
            .unwrap();
        assert_eq!(row.text, "Soft and warm");
        // Update
        pure_update_caption(
            &conn,
            id,
            &CaptionInput {
                persona_code: Some("CoC".into()),
                text: "updated".into(),
                tag_id: None,
            },
        )
        .unwrap();
        let row = pure_list_captions(&conn, Some("CoC"))
            .unwrap()
            .into_iter()
            .find(|c| c.id == id)
            .unwrap();
        assert_eq!(row.text, "updated");
        // Empty text rejected.
        assert!(pure_create_caption(
            &conn,
            &CaptionInput { persona_code: None, text: "  ".into(), tag_id: None }
        )
        .is_err());
        // Delete
        pure_delete_caption(&conn, id).unwrap();
        assert!(matches!(
            pure_delete_caption(&conn, id),
            Err(RedditError::NotFound(_))
        ));
    }
}
