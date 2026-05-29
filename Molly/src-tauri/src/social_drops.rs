// v1.21.0 — Social-hub piggy-bank tracker.
//
// One "+1 Post" tap from Sallie = one row in `social_post_drops`.
// All counts are aggregated; nothing carries content (URL, body, etc.) —
// that's what `social_promos` is for. This module is intentionally
// minimal: it's a coin counter with a streak attached.
//
// Reddit is special-cased only in count reads: its daily count merges
// generic drops with rows in `subreddit_posts` (which Sallie's existing
// "mark as posted" button writes when she logs a specific subreddit).
// Writes from the Piggy Bank's "+1 Reddit" button still go to
// `social_post_drops` — Sallie can use whichever tool fits the moment.

use chrono::NaiveDate;
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use tauri::{AppHandle, Manager, Runtime};

const REDDIT_PLATFORM_ID: i64 = 1;

#[derive(Debug, thiserror::Error)]
pub enum SocialDropError {
    #[error("sqlite: {0}")]
    Sql(#[from] rusqlite::Error),
    #[error("settings: {0}")]
    Settings(String),
    #[error("invalid: {0}")]
    Invalid(String),
    #[error("not found: {0}")]
    NotFound(i64),
}

impl serde::Serialize for SocialDropError {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.to_string())
    }
}

// ---- Boundary structs ------------------------------------------------------

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PlatformToday {
    pub platform_id: i64,
    pub name: String,
    pub short_code: String,
    pub icon: String,
    pub color: String,
    pub sort_order: i64,
    pub daily_goal: i64,
    pub count: i64,
    pub hit: bool,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct DayHistoryEntry {
    pub date: String,
    pub count: i64,
    pub goal: i64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct DropResult {
    pub id: i64,
    pub new_count: i64,
    pub goal: i64,
    pub hit: bool,
    pub just_hit: bool,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DropInput {
    pub persona_code: Option<String>,
    pub platform_id: i64,
    pub posted_date: String,
}

// ---- Internals -------------------------------------------------------------

fn app_data_dir<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, SocialDropError> {
    handle
        .path()
        .app_data_dir()
        .map_err(|e| SocialDropError::Settings(e.to_string()))
}

fn open_conn(app_data_dir: &Path) -> Result<Connection, SocialDropError> {
    Ok(Connection::open(app_data_dir.join("molly.db"))?)
}

fn valid_iso_date(s: &str) -> bool {
    NaiveDate::parse_from_str(s, "%Y-%m-%d").is_ok()
}

/// Reddit count = generic drops + subreddit_posts for that (persona, date).
/// Subreddit_posts may exist before this module's migration if the user
/// upgraded mid-cycle; coalesce the COUNT so we tolerate either table
/// being empty.
fn count_for(
    conn: &Connection,
    persona_code: Option<&str>,
    platform_id: i64,
    date: &str,
) -> Result<i64, SocialDropError> {
    let drops: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM social_post_drops
             WHERE platform_id = ?1 AND posted_date = ?2
               AND ((persona_code IS NULL AND ?3 IS NULL) OR persona_code = ?3)",
            params![platform_id, date, persona_code],
            |r| r.get(0),
        )
        .unwrap_or(0);

    if platform_id != REDDIT_PLATFORM_ID {
        return Ok(drops);
    }

    let subreddit_rows: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM subreddit_posts
             WHERE posted_date = ?1
               AND ((persona_code IS NULL AND ?2 IS NULL) OR persona_code = ?2)",
            params![date, persona_code],
            |r| r.get(0),
        )
        .unwrap_or(0);

    Ok(drops + subreddit_rows)
}

// ---- Pure functions (testable without Tauri) -------------------------------

pub(crate) fn pure_list_today(
    conn: &Connection,
    persona_code: Option<&str>,
    date: &str,
) -> Result<Vec<PlatformToday>, SocialDropError> {
    if !valid_iso_date(date) {
        return Err(SocialDropError::Invalid(format!("bad date: {date}")));
    }
    let mut stmt = conn.prepare(
        "SELECT id, name, short_code, icon, color, sort_order, daily_goal
         FROM social_platforms
         WHERE archived = 0
         ORDER BY sort_order, name",
    )?;
    let rows = stmt.query_map([], |r| {
        Ok((
            r.get::<_, i64>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, String>(2)?,
            r.get::<_, String>(3)?,
            r.get::<_, String>(4)?,
            r.get::<_, i64>(5)?,
            r.get::<_, i64>(6)?,
        ))
    })?;
    let mut out = Vec::new();
    for r in rows {
        let (platform_id, name, short_code, icon, color, sort_order, daily_goal) = r?;
        let count = count_for(conn, persona_code, platform_id, date)?;
        out.push(PlatformToday {
            platform_id,
            name,
            short_code,
            icon,
            color,
            sort_order,
            daily_goal,
            count,
            hit: count >= daily_goal,
        });
    }
    Ok(out)
}

pub(crate) fn pure_add_drop(
    conn: &Connection,
    input: &DropInput,
) -> Result<DropResult, SocialDropError> {
    if !valid_iso_date(&input.posted_date) {
        return Err(SocialDropError::Invalid(format!(
            "bad date: {}",
            input.posted_date
        )));
    }
    let goal: i64 = conn
        .query_row(
            "SELECT daily_goal FROM social_platforms WHERE id = ?1",
            params![input.platform_id],
            |r| r.get(0),
        )
        .optional()?
        .ok_or(SocialDropError::NotFound(input.platform_id))?;

    let before = count_for(
        conn,
        input.persona_code.as_deref(),
        input.platform_id,
        &input.posted_date,
    )?;

    conn.execute(
        "INSERT INTO social_post_drops (persona_code, platform_id, posted_date, posted_at)
         VALUES (?1, ?2, ?3, datetime('now'))",
        params![input.persona_code, input.platform_id, input.posted_date],
    )?;
    let id = conn.last_insert_rowid();

    let after = before + 1;
    Ok(DropResult {
        id,
        new_count: after,
        goal,
        hit: after >= goal,
        just_hit: before < goal && after >= goal,
    })
}

/// Removes the *most recent* generic drop for (persona, platform, date).
/// Subreddit_posts are never touched — they're "real" posts with their
/// own table; undoing them happens in the Reddit Post-log section.
/// Returns true if a row was removed.
pub(crate) fn pure_undo_last_drop(
    conn: &Connection,
    persona_code: Option<&str>,
    platform_id: i64,
    date: &str,
) -> Result<bool, SocialDropError> {
    if !valid_iso_date(date) {
        return Err(SocialDropError::Invalid(format!("bad date: {date}")));
    }
    let id: Option<i64> = conn
        .query_row(
            "SELECT id FROM social_post_drops
             WHERE platform_id = ?1 AND posted_date = ?2
               AND ((persona_code IS NULL AND ?3 IS NULL) OR persona_code = ?3)
             ORDER BY id DESC LIMIT 1",
            params![platform_id, date, persona_code],
            |r| r.get(0),
        )
        .optional()?;
    let Some(id) = id else { return Ok(false) };
    conn.execute("DELETE FROM social_post_drops WHERE id = ?1", params![id])?;
    Ok(true)
}

pub(crate) fn pure_list_platform_history(
    conn: &Connection,
    persona_code: Option<&str>,
    platform_id: i64,
    end_date: &str,
    days: i64,
) -> Result<Vec<DayHistoryEntry>, SocialDropError> {
    if !valid_iso_date(end_date) {
        return Err(SocialDropError::Invalid(format!("bad date: {end_date}")));
    }
    if days <= 0 || days > 365 {
        return Err(SocialDropError::Invalid(format!("days out of range: {days}")));
    }
    let goal: i64 = conn
        .query_row(
            "SELECT daily_goal FROM social_platforms WHERE id = ?1",
            params![platform_id],
            |r| r.get(0),
        )
        .optional()?
        .ok_or(SocialDropError::NotFound(platform_id))?;

    let end = NaiveDate::parse_from_str(end_date, "%Y-%m-%d")
        .map_err(|e| SocialDropError::Invalid(format!("bad date: {e}")))?;
    let mut out = Vec::with_capacity(days as usize);
    for offset in (0..days).rev() {
        let d = end - chrono::Duration::days(offset);
        let ds = d.format("%Y-%m-%d").to_string();
        let count = count_for(conn, persona_code, platform_id, &ds)?;
        out.push(DayHistoryEntry { date: ds, count, goal });
    }
    Ok(out)
}

/// Overall streak: consecutive days (walking back from `end_date`) on
/// which *every* non-archived platform's persona-count met its goal.
/// `end_date` itself only counts if every platform is hit today. The
/// chain stops at the first day with any miss.
pub(crate) fn pure_overall_streak(
    conn: &Connection,
    persona_code: Option<&str>,
    end_date: &str,
) -> Result<i64, SocialDropError> {
    if !valid_iso_date(end_date) {
        return Err(SocialDropError::Invalid(format!("bad date: {end_date}")));
    }
    let mut platforms: Vec<(i64, i64)> = conn
        .prepare(
            "SELECT id, daily_goal FROM social_platforms WHERE archived = 0 ORDER BY id",
        )?
        .query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, i64>(1)?)))?
        .collect::<Result<Vec<_>, _>>()?;
    platforms.retain(|(_, goal)| *goal > 0);
    if platforms.is_empty() {
        return Ok(0);
    }
    let end = NaiveDate::parse_from_str(end_date, "%Y-%m-%d")
        .map_err(|e| SocialDropError::Invalid(format!("bad date: {e}")))?;
    let mut streak = 0i64;
    let mut cursor = end;
    loop {
        let ds = cursor.format("%Y-%m-%d").to_string();
        let mut all_hit = true;
        for (pid, goal) in &platforms {
            let c = count_for(conn, persona_code, *pid, &ds)?;
            if c < *goal {
                all_hit = false;
                break;
            }
        }
        if !all_hit {
            break;
        }
        streak += 1;
        cursor = match cursor.pred_opt() {
            Some(d) => d,
            None => break,
        };
        // safety: never walk back further than a year — anything past
        // that is "lifetime achievement" territory and the count_for
        // queries get expensive for no UX gain.
        if streak >= 365 {
            break;
        }
    }
    Ok(streak)
}

/// Per-platform streak. Same idea but only checks one platform.
pub(crate) fn pure_platform_streak(
    conn: &Connection,
    persona_code: Option<&str>,
    platform_id: i64,
    end_date: &str,
) -> Result<i64, SocialDropError> {
    if !valid_iso_date(end_date) {
        return Err(SocialDropError::Invalid(format!("bad date: {end_date}")));
    }
    let goal: i64 = conn
        .query_row(
            "SELECT daily_goal FROM social_platforms WHERE id = ?1",
            params![platform_id],
            |r| r.get(0),
        )
        .optional()?
        .ok_or(SocialDropError::NotFound(platform_id))?;
    if goal <= 0 {
        return Ok(0);
    }
    let end = NaiveDate::parse_from_str(end_date, "%Y-%m-%d")
        .map_err(|e| SocialDropError::Invalid(format!("bad date: {e}")))?;
    let mut streak = 0i64;
    let mut cursor = end;
    loop {
        let ds = cursor.format("%Y-%m-%d").to_string();
        let c = count_for(conn, persona_code, platform_id, &ds)?;
        if c < goal {
            break;
        }
        streak += 1;
        cursor = match cursor.pred_opt() {
            Some(d) => d,
            None => break,
        };
        if streak >= 365 {
            break;
        }
    }
    Ok(streak)
}

pub(crate) fn pure_set_platform_daily_goal(
    conn: &Connection,
    platform_id: i64,
    daily_goal: i64,
) -> Result<(), SocialDropError> {
    if daily_goal < 0 || daily_goal > 1000 {
        return Err(SocialDropError::Invalid(format!(
            "goal out of range: {daily_goal}"
        )));
    }
    let n = conn.execute(
        "UPDATE social_platforms SET daily_goal = ?1, updated_at = datetime('now')
         WHERE id = ?2",
        params![daily_goal, platform_id],
    )?;
    if n == 0 {
        return Err(SocialDropError::NotFound(platform_id));
    }
    Ok(())
}

// ---- Tauri commands --------------------------------------------------------

#[tauri::command]
pub fn list_social_today<R: Runtime>(
    handle: AppHandle<R>,
    persona_code: Option<String>,
    posted_date: String,
) -> Result<Vec<PlatformToday>, SocialDropError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_list_today(&conn, persona_code.as_deref(), &posted_date)
}

#[tauri::command]
pub fn add_social_drop<R: Runtime>(
    handle: AppHandle<R>,
    input: DropInput,
) -> Result<DropResult, SocialDropError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_add_drop(&conn, &input)
}

#[tauri::command]
pub fn undo_last_social_drop<R: Runtime>(
    handle: AppHandle<R>,
    persona_code: Option<String>,
    platform_id: i64,
    posted_date: String,
) -> Result<bool, SocialDropError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_undo_last_drop(&conn, persona_code.as_deref(), platform_id, &posted_date)
}

#[tauri::command]
pub fn list_social_platform_history<R: Runtime>(
    handle: AppHandle<R>,
    persona_code: Option<String>,
    platform_id: i64,
    end_date: String,
    days: i64,
) -> Result<Vec<DayHistoryEntry>, SocialDropError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_list_platform_history(
        &conn,
        persona_code.as_deref(),
        platform_id,
        &end_date,
        days,
    )
}

#[tauri::command]
pub fn compute_social_overall_streak<R: Runtime>(
    handle: AppHandle<R>,
    persona_code: Option<String>,
    end_date: String,
) -> Result<i64, SocialDropError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_overall_streak(&conn, persona_code.as_deref(), &end_date)
}

#[tauri::command]
pub fn compute_social_platform_streak<R: Runtime>(
    handle: AppHandle<R>,
    persona_code: Option<String>,
    platform_id: i64,
    end_date: String,
) -> Result<i64, SocialDropError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_platform_streak(&conn, persona_code.as_deref(), platform_id, &end_date)
}

#[tauri::command]
pub fn set_social_platform_goal<R: Runtime>(
    handle: AppHandle<R>,
    platform_id: i64,
    daily_goal: i64,
) -> Result<(), SocialDropError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_set_platform_daily_goal(&conn, platform_id, daily_goal)
}

// ---- Tests -----------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;

    fn mk_db() -> Connection {
        let c = Connection::open_in_memory().unwrap();
        // Minimal schema for the bits we touch. Real migrations are not
        // run here — they pull in dozens of tables we don't need.
        c.execute_batch(
            r#"
            CREATE TABLE social_platforms (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                short_code TEXT NOT NULL,
                icon TEXT NOT NULL DEFAULT '',
                color TEXT NOT NULL DEFAULT '#000',
                sort_order INTEGER NOT NULL DEFAULT 0,
                archived INTEGER NOT NULL DEFAULT 0,
                daily_goal INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
            INSERT INTO social_platforms (id, name, short_code, icon, color, sort_order, daily_goal)
            VALUES
                (1, 'Reddit',    'rdt', '🐶', '#FF4500', 10, 10),
                (2, 'X',         'x',   '✖️', '#000000', 20, 3),
                (3, 'Instagram', 'ig',  '📸', '#E1306C', 30, 2),
                (4, 'TikTok',    'tt',  '🎵', '#69C9D0', 40, 2);

            CREATE TABLE social_post_drops (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                persona_code TEXT,
                platform_id INTEGER NOT NULL,
                posted_date TEXT NOT NULL,
                posted_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
            CREATE TABLE subreddit_posts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                persona_code TEXT,
                subreddit_id INTEGER,
                subreddit_name TEXT NOT NULL,
                tag_id INTEGER,
                posted_date TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
            "#,
        )
        .unwrap();
        c
    }

    fn drop(c: &Connection, persona: Option<&str>, platform: i64, date: &str) -> DropResult {
        pure_add_drop(
            c,
            &DropInput {
                persona_code: persona.map(String::from),
                platform_id: platform,
                posted_date: date.into(),
            },
        )
        .unwrap()
    }

    #[test]
    fn list_today_returns_all_platforms_with_zero_counts_initially() {
        let c = mk_db();
        let rows = pure_list_today(&c, Some("CoC"), "2026-05-29").unwrap();
        assert_eq!(rows.len(), 4);
        assert!(rows.iter().all(|r| r.count == 0));
        assert!(rows.iter().all(|r| !r.hit));
        assert_eq!(rows[0].name, "Reddit");
        assert_eq!(rows[0].daily_goal, 10);
        assert_eq!(rows[1].daily_goal, 3); // X
    }

    #[test]
    fn add_drop_increments_count_and_sets_just_hit_when_goal_reached() {
        let c = mk_db();
        // X has goal=3.
        let r1 = drop(&c, Some("CoC"), 2, "2026-05-29");
        assert_eq!(r1.new_count, 1);
        assert!(!r1.hit);
        assert!(!r1.just_hit);
        let r2 = drop(&c, Some("CoC"), 2, "2026-05-29");
        assert_eq!(r2.new_count, 2);
        assert!(!r2.hit);
        let r3 = drop(&c, Some("CoC"), 2, "2026-05-29");
        assert_eq!(r3.new_count, 3);
        assert!(r3.hit);
        assert!(r3.just_hit);
        let r4 = drop(&c, Some("CoC"), 2, "2026-05-29");
        assert_eq!(r4.new_count, 4);
        assert!(r4.hit);
        assert!(!r4.just_hit, "just_hit only fires on the threshold cross");
    }

    #[test]
    fn persona_isolation_for_counts() {
        let c = mk_db();
        drop(&c, Some("CoC"),      2, "2026-05-29");
        drop(&c, Some("Princess"), 2, "2026-05-29");
        let coc = pure_list_today(&c, Some("CoC"), "2026-05-29").unwrap();
        let pr  = pure_list_today(&c, Some("Princess"), "2026-05-29").unwrap();
        assert_eq!(coc.iter().find(|r| r.platform_id == 2).unwrap().count, 1);
        assert_eq!(pr .iter().find(|r| r.platform_id == 2).unwrap().count, 1);
        // NULL persona (ALL) sees neither because they're persona-scoped.
        let all = pure_list_today(&c, None, "2026-05-29").unwrap();
        assert_eq!(all.iter().find(|r| r.platform_id == 2).unwrap().count, 0);
    }

    #[test]
    fn reddit_count_merges_subreddit_posts() {
        let c = mk_db();
        // Two generic Reddit drops.
        drop(&c, Some("CoC"), 1, "2026-05-29");
        drop(&c, Some("CoC"), 1, "2026-05-29");
        // Three subreddit-specific marks for the same persona+date.
        for sr in ["r/gonewild", "r/tits", "r/curvy"] {
            c.execute(
                "INSERT INTO subreddit_posts (persona_code, subreddit_id, subreddit_name, tag_id, posted_date)
                 VALUES (?1, NULL, ?2, NULL, ?3)",
                params!["CoC", sr, "2026-05-29"],
            )
            .unwrap();
        }
        let n = count_for(&c, Some("CoC"), 1, "2026-05-29").unwrap();
        assert_eq!(n, 5);
        // Non-Reddit count must NOT pick up subreddit_posts.
        let x = count_for(&c, Some("CoC"), 2, "2026-05-29").unwrap();
        assert_eq!(x, 0);
    }

    #[test]
    fn undo_removes_only_generic_drops_not_subreddit_posts() {
        let c = mk_db();
        drop(&c, Some("CoC"), 1, "2026-05-29");
        c.execute(
            "INSERT INTO subreddit_posts (persona_code, subreddit_id, subreddit_name, tag_id, posted_date)
             VALUES ('CoC', NULL, 'r/foo', NULL, '2026-05-29')",
            [],
        )
        .unwrap();
        let before = count_for(&c, Some("CoC"), 1, "2026-05-29").unwrap();
        assert_eq!(before, 2);
        let removed = pure_undo_last_drop(&c, Some("CoC"), 1, "2026-05-29").unwrap();
        assert!(removed);
        let after = count_for(&c, Some("CoC"), 1, "2026-05-29").unwrap();
        assert_eq!(after, 1, "subreddit_posts row must survive");
        // Another undo finds no generic drop → returns false, count unchanged.
        let removed_again = pure_undo_last_drop(&c, Some("CoC"), 1, "2026-05-29").unwrap();
        assert!(!removed_again);
    }

    #[test]
    fn overall_streak_breaks_on_first_miss() {
        let c = mk_db();
        // Day -2 (2026-05-27): all four hit.
        // Day -1 (2026-05-28): all four hit.
        // Day  0 (2026-05-29): Reddit short by 1.
        let days_hit = ["2026-05-27", "2026-05-28"];
        for d in days_hit {
            for _ in 0..10 { drop(&c, Some("CoC"), 1, d); }   // Reddit 10
            for _ in 0..3  { drop(&c, Some("CoC"), 2, d); }   // X 3
            for _ in 0..2  { drop(&c, Some("CoC"), 3, d); }   // IG 2
            for _ in 0..2  { drop(&c, Some("CoC"), 4, d); }   // TT 2
        }
        // 2026-05-29: only 9 Reddit.
        for _ in 0..9 { drop(&c, Some("CoC"), 1, "2026-05-29"); }
        for _ in 0..3 { drop(&c, Some("CoC"), 2, "2026-05-29"); }
        for _ in 0..2 { drop(&c, Some("CoC"), 3, "2026-05-29"); }
        for _ in 0..2 { drop(&c, Some("CoC"), 4, "2026-05-29"); }

        let streak = pure_overall_streak(&c, Some("CoC"), "2026-05-29").unwrap();
        assert_eq!(streak, 0, "today doesn't count, streak hasn't started");

        // Top up Reddit to 10 and the streak should become 3.
        drop(&c, Some("CoC"), 1, "2026-05-29");
        let streak = pure_overall_streak(&c, Some("CoC"), "2026-05-29").unwrap();
        assert_eq!(streak, 3);
    }

    #[test]
    fn platform_streak_independent_per_platform() {
        let c = mk_db();
        // X goal 3 — hit 3 consecutive days. TikTok 0 days.
        for d in ["2026-05-27", "2026-05-28", "2026-05-29"] {
            for _ in 0..3 { drop(&c, Some("CoC"), 2, d); }
        }
        let x = pure_platform_streak(&c, Some("CoC"), 2, "2026-05-29").unwrap();
        assert_eq!(x, 3);
        let tt = pure_platform_streak(&c, Some("CoC"), 4, "2026-05-29").unwrap();
        assert_eq!(tt, 0);
    }

    #[test]
    fn list_history_returns_oldest_first_with_per_day_count() {
        let c = mk_db();
        drop(&c, Some("CoC"), 2, "2026-05-28");
        drop(&c, Some("CoC"), 2, "2026-05-28");
        drop(&c, Some("CoC"), 2, "2026-05-29");
        let hist = pure_list_platform_history(&c, Some("CoC"), 2, "2026-05-29", 3).unwrap();
        assert_eq!(hist.len(), 3);
        assert_eq!(hist[0].date, "2026-05-27");
        assert_eq!(hist[0].count, 0);
        assert_eq!(hist[1].date, "2026-05-28");
        assert_eq!(hist[1].count, 2);
        assert_eq!(hist[2].date, "2026-05-29");
        assert_eq!(hist[2].count, 1);
        assert!(hist.iter().all(|h| h.goal == 3));
    }

    #[test]
    fn set_goal_updates_and_rejects_bad_input() {
        let c = mk_db();
        pure_set_platform_daily_goal(&c, 2, 5).unwrap();
        let rows = pure_list_today(&c, None, "2026-05-29").unwrap();
        assert_eq!(rows.iter().find(|r| r.platform_id == 2).unwrap().daily_goal, 5);
        assert!(pure_set_platform_daily_goal(&c, 2, -1).is_err());
        assert!(pure_set_platform_daily_goal(&c, 2, 2000).is_err());
        assert!(pure_set_platform_daily_goal(&c, 999, 5).is_err());
    }

    #[test]
    fn reject_bad_dates() {
        let c = mk_db();
        assert!(pure_list_today(&c, None, "2026-13-01").is_err());
        assert!(pure_list_today(&c, None, "not-a-date").is_err());
        assert!(pure_overall_streak(&c, None, "junk").is_err());
    }
}
