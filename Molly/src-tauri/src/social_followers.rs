// v1.25.0 — Per-platform daily FOLLOWER COUNT tracking.
//
// SNAPSHOT semantics, deliberately the OPPOSITE of social_drops.rs:
//   * social_post_drops is an append-only INCREMENT log (COUNT(*) rows).
//   * social_follower_counts is an absolute SNAPSHOT — one row per
//     (persona, platform, day), written by UPSERT (latest write wins).
//
// Read that twice before "optimising": there is no COUNT(*) here. A
// missing day is a GAP (unknown), not zero. The ALL/`None`-persona view
// is a read-time COMBINE across personas (each persona's latest snapshot
// summed), NOT "ALL sees nothing" like drops. Forecast/trend math lives
// in the TS lib `src/lib/followerForecast.ts`; this module is a thin
// store: validate, upsert, read.

use chrono::NaiveDate;
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use tauri::{AppHandle, Manager, Runtime};

const MAX_FOLLOWERS: i64 = 1_000_000_000; // 1e9 — fat-finger guard
const MAX_GOAL: i64 = 100_000_000; // 1e8

#[derive(Debug, thiserror::Error)]
pub enum FollowerError {
    #[error("sqlite: {0}")]
    Sql(#[from] rusqlite::Error),
    #[error("settings: {0}")]
    Settings(String),
    #[error("invalid: {0}")]
    Invalid(String),
    #[error("not found: {0}")]
    NotFound(i64),
}

impl serde::Serialize for FollowerError {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.to_string())
    }
}

// ---- Boundary structs ------------------------------------------------------

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PlatformFollowerToday {
    pub platform_id: i64,
    pub name: String,
    pub short_code: String,
    pub icon: String,
    pub color: String,
    pub sort_order: i64,
    pub follower_goal: i64, // 0 = no goal
    pub latest_count: Option<i64>, // most recent snapshot on/before `date`
    pub latest_date: Option<String>,
    pub today_count: Option<i64>, // snapshot for `date` exactly; None drives the nudge
    pub prev_count: Option<i64>, // snapshot strictly before latest_date
    pub delta: Option<i64>, // latest - prev when both present
    pub goal_hit: bool, // latest >= goal (goal > 0)
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct FollowerHistoryEntry {
    pub date: String,
    pub count: Option<i64>, // None = no snapshot that day (a GAP — not zero!)
    pub is_logged: bool,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LoggedPoint {
    pub date: String,
    pub count: i64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct FollowerUpsertResult {
    pub persona_code: String,
    pub platform_id: i64,
    pub count_date: String,
    pub follower_count: i64,
    pub prev_count: Option<i64>, // most-recent value BEFORE this date (for the Δ delight)
    pub delta: Option<i64>,
    pub follower_goal: i64,
    pub goal_hit: bool,
    pub just_hit_goal: bool, // crossed the goal with THIS save
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PersonaFollowerSlice {
    pub persona_code: String,
    pub persona_name: String,
    pub latest_count: Option<i64>,
    pub latest_date: Option<String>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CombinedFollowerToday {
    pub platform_id: i64,
    pub name: String,
    pub short_code: String,
    pub icon: String,
    pub color: String,
    pub sort_order: i64,
    pub follower_goal: i64,
    pub combined_latest: Option<i64>, // SUM of each persona's latest snapshot
    pub contributing_personas: i64,
    pub breakdown: Vec<PersonaFollowerSlice>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FollowerInput {
    pub persona_code: Option<String>, // REQUIRED on write; None → Invalid
    pub platform_id: i64,
    pub count_date: String,
    pub follower_count: i64,
}

// ---- Internals -------------------------------------------------------------

fn app_data_dir<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, FollowerError> {
    handle
        .path()
        .app_data_dir()
        .map_err(|e| FollowerError::Settings(e.to_string()))
}

fn open_conn(app_data_dir: &Path) -> Result<Connection, FollowerError> {
    Ok(Connection::open(app_data_dir.join("molly.db"))?)
}

fn valid_iso_date(s: &str) -> bool {
    NaiveDate::parse_from_str(s, "%Y-%m-%d").is_ok()
}

fn platform_goal(conn: &Connection, platform_id: i64) -> Result<i64, FollowerError> {
    conn.query_row(
        "SELECT follower_goal FROM social_platforms WHERE id = ?1",
        params![platform_id],
        |r| r.get(0),
    )
    .optional()?
    .ok_or(FollowerError::NotFound(platform_id))
}

/// The most recent snapshot for (persona, platform) strictly before `date`.
fn latest_before(
    conn: &Connection,
    persona_code: &str,
    platform_id: i64,
    date: &str,
) -> Result<Option<i64>, FollowerError> {
    Ok(conn
        .query_row(
            "SELECT follower_count FROM social_follower_counts
             WHERE persona_code = ?1 AND platform_id = ?2 AND count_date < ?3
             ORDER BY count_date DESC LIMIT 1",
            params![persona_code, platform_id, date],
            |r| r.get(0),
        )
        .optional()?)
}

/// The most recent snapshot on/before `date` → (count, date).
fn latest_on_or_before(
    conn: &Connection,
    persona_code: &str,
    platform_id: i64,
    date: &str,
) -> Result<Option<(i64, String)>, FollowerError> {
    Ok(conn
        .query_row(
            "SELECT follower_count, count_date FROM social_follower_counts
             WHERE persona_code = ?1 AND platform_id = ?2 AND count_date <= ?3
             ORDER BY count_date DESC LIMIT 1",
            params![persona_code, platform_id, date],
            |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)),
        )
        .optional()?)
}

// ---- Pure functions (testable without Tauri) -------------------------------

pub(crate) fn pure_upsert_follower(
    conn: &Connection,
    input: &FollowerInput,
) -> Result<FollowerUpsertResult, FollowerError> {
    let persona = input
        .persona_code
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| FollowerError::Invalid("pick a persona to log followers".into()))?;
    if !valid_iso_date(&input.count_date) {
        return Err(FollowerError::Invalid(format!(
            "bad date: {}",
            input.count_date
        )));
    }
    if input.follower_count < 0 || input.follower_count > MAX_FOLLOWERS {
        return Err(FollowerError::Invalid(format!(
            "follower count out of range: {}",
            input.follower_count
        )));
    }
    let goal = platform_goal(conn, input.platform_id)?;
    // Baseline for the Δ delight: the most-recent value on a PRIOR day,
    // so re-editing today celebrates vs yesterday, not vs the just-typed
    // value being overwritten.
    let prev = latest_before(conn, persona, input.platform_id, &input.count_date)?;

    conn.execute(
        "INSERT INTO social_follower_counts
             (persona_code, platform_id, count_date, follower_count, source, recorded_at)
         VALUES (?1, ?2, ?3, ?4, 'manual', datetime('now'))
         ON CONFLICT(persona_code, platform_id, count_date)
         DO UPDATE SET follower_count = excluded.follower_count,
                       recorded_at = datetime('now')",
        params![
            persona,
            input.platform_id,
            input.count_date,
            input.follower_count
        ],
    )?;

    let new = input.follower_count;
    let delta = prev.map(|p| new - p);
    let goal_hit = goal > 0 && new >= goal;
    // First-ever log that's already ≥ goal counts as a cross (prev = None).
    let just_hit_goal = goal > 0 && prev.map_or(true, |p| p < goal) && new >= goal;

    Ok(FollowerUpsertResult {
        persona_code: persona.to_string(),
        platform_id: input.platform_id,
        count_date: input.count_date.clone(),
        follower_count: new,
        prev_count: prev,
        delta,
        follower_goal: goal,
        goal_hit,
        just_hit_goal,
    })
}

pub(crate) fn pure_list_followers_today(
    conn: &Connection,
    persona_code: Option<&str>,
    date: &str,
) -> Result<Vec<PlatformFollowerToday>, FollowerError> {
    if !valid_iso_date(date) {
        return Err(FollowerError::Invalid(format!("bad date: {date}")));
    }
    // ALL persona has nothing to log against — return empty; the UI uses
    // the combined endpoint for ALL.
    let Some(persona) = persona_code else {
        return Ok(Vec::new());
    };

    let mut stmt = conn.prepare(
        "SELECT id, name, short_code, icon, color, sort_order, follower_goal
         FROM social_platforms
         WHERE archived = 0
         ORDER BY sort_order, name",
    )?;
    let rows = stmt
        .query_map([], |r| {
            Ok((
                r.get::<_, i64>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, String>(3)?,
                r.get::<_, String>(4)?,
                r.get::<_, i64>(5)?,
                r.get::<_, i64>(6)?,
            ))
        })?
        .collect::<Result<Vec<_>, _>>()?;

    let mut out = Vec::with_capacity(rows.len());
    for (platform_id, name, short_code, icon, color, sort_order, follower_goal) in rows {
        let latest = latest_on_or_before(conn, persona, platform_id, date)?;
        let today_count: Option<i64> = conn
            .query_row(
                "SELECT follower_count FROM social_follower_counts
                 WHERE persona_code = ?1 AND platform_id = ?2 AND count_date = ?3",
                params![persona, platform_id, date],
                |r| r.get(0),
            )
            .optional()?;
        let (latest_count, latest_date) = match &latest {
            Some((c, d)) => (Some(*c), Some(d.clone())),
            None => (None, None),
        };
        let prev_count = match &latest_date {
            Some(ld) => latest_before(conn, persona, platform_id, ld)?,
            None => None,
        };
        let delta = match (latest_count, prev_count) {
            (Some(l), Some(p)) => Some(l - p),
            _ => None,
        };
        let goal_hit = follower_goal > 0 && latest_count.map_or(false, |c| c >= follower_goal);
        out.push(PlatformFollowerToday {
            platform_id,
            name,
            short_code,
            icon,
            color,
            sort_order,
            follower_goal,
            latest_count,
            latest_date,
            today_count,
            prev_count,
            delta,
            goal_hit,
        });
    }
    Ok(out)
}

pub(crate) fn pure_list_follower_history(
    conn: &Connection,
    persona_code: Option<&str>,
    platform_id: i64,
    end_date: &str,
    days: i64,
) -> Result<Vec<FollowerHistoryEntry>, FollowerError> {
    if !valid_iso_date(end_date) {
        return Err(FollowerError::Invalid(format!("bad date: {end_date}")));
    }
    if days <= 0 || days > 365 {
        return Err(FollowerError::Invalid(format!("days out of range: {days}")));
    }
    // Confirm the platform exists for a clean error on a bad id.
    platform_goal(conn, platform_id)?;
    let Some(persona) = persona_code else {
        return Ok(Vec::new());
    };
    let end = NaiveDate::parse_from_str(end_date, "%Y-%m-%d")
        .map_err(|e| FollowerError::Invalid(format!("bad date: {e}")))?;
    let mut out = Vec::with_capacity(days as usize);
    for offset in (0..days).rev() {
        let d = end - chrono::Duration::days(offset);
        let ds = d.format("%Y-%m-%d").to_string();
        let count: Option<i64> = conn
            .query_row(
                "SELECT follower_count FROM social_follower_counts
                 WHERE persona_code = ?1 AND platform_id = ?2 AND count_date = ?3",
                params![persona, platform_id, ds],
                |r| r.get(0),
            )
            .optional()?;
        out.push(FollowerHistoryEntry {
            date: ds,
            is_logged: count.is_some(),
            count,
        });
    }
    Ok(out)
}

/// Sparse — only the logged days (oldest-first). Feeds the forecast lib,
/// which wants real points, not a dense gappy array.
pub(crate) fn pure_list_logged_follower_history(
    conn: &Connection,
    persona_code: Option<&str>,
    platform_id: i64,
    end_date: &str,
) -> Result<Vec<LoggedPoint>, FollowerError> {
    if !valid_iso_date(end_date) {
        return Err(FollowerError::Invalid(format!("bad date: {end_date}")));
    }
    let Some(persona) = persona_code else {
        return Ok(Vec::new());
    };
    let mut stmt = conn.prepare(
        "SELECT count_date, follower_count FROM social_follower_counts
         WHERE persona_code = ?1 AND platform_id = ?2 AND count_date <= ?3
         ORDER BY count_date ASC",
    )?;
    let rows = stmt
        .query_map(params![persona, platform_id, end_date], |r| {
            Ok(LoggedPoint {
                date: r.get::<_, String>(0)?,
                count: r.get::<_, i64>(1)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(rows)
}

/// ALL view: per platform, sum each persona's latest-on-or-before snapshot.
/// Personas log on different days, so we carry-forward each persona's most
/// recent known value rather than requiring a same-day entry. A persona
/// with no history contributes nothing and is excluded from the count.
pub(crate) fn pure_list_combined_followers_today(
    conn: &Connection,
    date: &str,
) -> Result<Vec<CombinedFollowerToday>, FollowerError> {
    if !valid_iso_date(date) {
        return Err(FollowerError::Invalid(format!("bad date: {date}")));
    }
    let personas: Vec<(String, String)> = conn
        .prepare("SELECT code, name FROM personas ORDER BY name")?
        .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?
        .collect::<Result<Vec<_>, _>>()?;

    let platforms: Vec<(i64, String, String, String, String, i64, i64)> = conn
        .prepare(
            "SELECT id, name, short_code, icon, color, sort_order, follower_goal
             FROM social_platforms WHERE archived = 0 ORDER BY sort_order, name",
        )?
        .query_map([], |r| {
            Ok((
                r.get::<_, i64>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, String>(3)?,
                r.get::<_, String>(4)?,
                r.get::<_, i64>(5)?,
                r.get::<_, i64>(6)?,
            ))
        })?
        .collect::<Result<Vec<_>, _>>()?;

    let mut out = Vec::with_capacity(platforms.len());
    for (platform_id, name, short_code, icon, color, sort_order, follower_goal) in platforms {
        let mut breakdown = Vec::new();
        let mut sum = 0i64;
        let mut contributing = 0i64;
        for (code, pname) in &personas {
            let latest = latest_on_or_before(conn, code, platform_id, date)?;
            let (latest_count, latest_date) = match &latest {
                Some((c, d)) => {
                    sum += *c;
                    contributing += 1;
                    (Some(*c), Some(d.clone()))
                }
                None => (None, None),
            };
            // Only surface personas that have ever logged this platform.
            if latest_count.is_some() {
                breakdown.push(PersonaFollowerSlice {
                    persona_code: code.clone(),
                    persona_name: pname.clone(),
                    latest_count,
                    latest_date,
                });
            }
        }
        out.push(CombinedFollowerToday {
            platform_id,
            name,
            short_code,
            icon,
            color,
            sort_order,
            follower_goal,
            combined_latest: if contributing > 0 { Some(sum) } else { None },
            contributing_personas: contributing,
            breakdown,
        });
    }
    Ok(out)
}

pub(crate) fn pure_set_follower_goal(
    conn: &Connection,
    platform_id: i64,
    follower_goal: i64,
) -> Result<(), FollowerError> {
    if follower_goal < 0 || follower_goal > MAX_GOAL {
        return Err(FollowerError::Invalid(format!(
            "goal out of range: {follower_goal}"
        )));
    }
    let n = conn.execute(
        "UPDATE social_platforms SET follower_goal = ?1, updated_at = datetime('now')
         WHERE id = ?2",
        params![follower_goal, platform_id],
    )?;
    if n == 0 {
        return Err(FollowerError::NotFound(platform_id));
    }
    Ok(())
}

pub(crate) fn pure_delete_follower(
    conn: &Connection,
    persona_code: Option<&str>,
    platform_id: i64,
    count_date: &str,
) -> Result<bool, FollowerError> {
    if !valid_iso_date(count_date) {
        return Err(FollowerError::Invalid(format!("bad date: {count_date}")));
    }
    let persona = persona_code
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| FollowerError::Invalid("pick a persona".into()))?;
    let n = conn.execute(
        "DELETE FROM social_follower_counts
         WHERE persona_code = ?1 AND platform_id = ?2 AND count_date = ?3",
        params![persona, platform_id, count_date],
    )?;
    Ok(n > 0)
}

// ---- Tauri commands --------------------------------------------------------

#[tauri::command]
pub fn upsert_follower_count<R: Runtime>(
    handle: AppHandle<R>,
    input: FollowerInput,
) -> Result<FollowerUpsertResult, FollowerError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_upsert_follower(&conn, &input)
}

#[tauri::command]
pub fn list_followers_today<R: Runtime>(
    handle: AppHandle<R>,
    persona_code: Option<String>,
    date: String,
) -> Result<Vec<PlatformFollowerToday>, FollowerError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_list_followers_today(&conn, persona_code.as_deref(), &date)
}

#[tauri::command]
pub fn list_follower_history<R: Runtime>(
    handle: AppHandle<R>,
    persona_code: Option<String>,
    platform_id: i64,
    end_date: String,
    days: i64,
) -> Result<Vec<FollowerHistoryEntry>, FollowerError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_list_follower_history(&conn, persona_code.as_deref(), platform_id, &end_date, days)
}

#[tauri::command]
pub fn list_logged_follower_history<R: Runtime>(
    handle: AppHandle<R>,
    persona_code: Option<String>,
    platform_id: i64,
    end_date: String,
) -> Result<Vec<LoggedPoint>, FollowerError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_list_logged_follower_history(&conn, persona_code.as_deref(), platform_id, &end_date)
}

#[tauri::command]
pub fn list_combined_followers_today<R: Runtime>(
    handle: AppHandle<R>,
    date: String,
) -> Result<Vec<CombinedFollowerToday>, FollowerError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_list_combined_followers_today(&conn, &date)
}

#[tauri::command]
pub fn set_social_platform_follower_goal<R: Runtime>(
    handle: AppHandle<R>,
    platform_id: i64,
    follower_goal: i64,
) -> Result<(), FollowerError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_set_follower_goal(&conn, platform_id, follower_goal)
}

#[tauri::command]
pub fn delete_follower_count<R: Runtime>(
    handle: AppHandle<R>,
    persona_code: Option<String>,
    platform_id: i64,
    count_date: String,
) -> Result<bool, FollowerError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    pure_delete_follower(&conn, persona_code.as_deref(), platform_id, &count_date)
}

// ---- Tests -----------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn mk_db() -> Connection {
        let c = Connection::open_in_memory().unwrap();
        c.execute_batch(
            r#"
            CREATE TABLE personas (
                code TEXT PRIMARY KEY,
                name TEXT NOT NULL
            );
            INSERT INTO personas (code, name) VALUES
                ('CoC', 'Curves'),
                ('Princess', 'Princess');

            CREATE TABLE social_platforms (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                short_code TEXT NOT NULL,
                icon TEXT NOT NULL DEFAULT '',
                color TEXT NOT NULL DEFAULT '#000',
                sort_order INTEGER NOT NULL DEFAULT 0,
                archived INTEGER NOT NULL DEFAULT 0,
                follower_goal INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
            INSERT INTO social_platforms (id, name, short_code, icon, color, sort_order)
            VALUES
                (1, 'Reddit',    'rdt', '🐶', '#FF4500', 10),
                (2, 'X',         'x',   '✖️', '#000000', 20),
                (3, 'Instagram', 'ig',  '📸', '#E1306C', 30),
                (4, 'TikTok',    'tt',  '🎵', '#69C9D0', 40);

            CREATE TABLE social_follower_counts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                persona_code TEXT,
                platform_id INTEGER NOT NULL,
                count_date TEXT NOT NULL,
                follower_count INTEGER NOT NULL,
                source TEXT NOT NULL DEFAULT 'manual',
                recorded_at TEXT NOT NULL DEFAULT (datetime('now')),
                UNIQUE(persona_code, platform_id, count_date)
            );
            "#,
        )
        .unwrap();
        c
    }

    fn up(c: &Connection, persona: Option<&str>, platform: i64, date: &str, count: i64) -> FollowerUpsertResult {
        pure_upsert_follower(
            c,
            &FollowerInput {
                persona_code: persona.map(String::from),
                platform_id: platform,
                count_date: date.into(),
                follower_count: count,
            },
        )
        .unwrap()
    }

    #[test]
    fn upsert_inserts_then_overwrites_same_date() {
        let c = mk_db();
        let r1 = up(&c, Some("CoC"), 4, "2026-06-01", 1000);
        assert_eq!(r1.follower_count, 1000);
        assert_eq!(r1.prev_count, None);
        assert_eq!(r1.delta, None);
        // Re-save the same day → overwrites, one row only.
        let r2 = up(&c, Some("CoC"), 4, "2026-06-01", 1050);
        assert_eq!(r2.follower_count, 1050);
        let n: i64 = c
            .query_row(
                "SELECT COUNT(*) FROM social_follower_counts WHERE persona_code='CoC' AND platform_id=4",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(n, 1, "same-date upsert must not create a second row");
    }

    #[test]
    fn prev_count_excludes_the_current_date() {
        let c = mk_db();
        up(&c, Some("CoC"), 4, "2026-06-01", 1000);
        // Editing 06-02 twice: prev should stay 1000 (06-01), not the
        // value just typed on 06-02.
        let a = up(&c, Some("CoC"), 4, "2026-06-02", 1200);
        assert_eq!(a.prev_count, Some(1000));
        assert_eq!(a.delta, Some(200));
        let b = up(&c, Some("CoC"), 4, "2026-06-02", 1250);
        assert_eq!(b.prev_count, Some(1000), "Δ baseline is yesterday, not the overwritten value");
        assert_eq!(b.delta, Some(250));
    }

    #[test]
    fn persona_isolation() {
        let c = mk_db();
        up(&c, Some("CoC"), 4, "2026-06-01", 1000);
        up(&c, Some("Princess"), 4, "2026-06-01", 500);
        let coc = pure_list_followers_today(&c, Some("CoC"), "2026-06-01").unwrap();
        let pr = pure_list_followers_today(&c, Some("Princess"), "2026-06-01").unwrap();
        assert_eq!(coc.iter().find(|r| r.platform_id == 4).unwrap().latest_count, Some(1000));
        assert_eq!(pr.iter().find(|r| r.platform_id == 4).unwrap().latest_count, Some(500));
    }

    #[test]
    fn null_persona_write_is_rejected() {
        let c = mk_db();
        let err = pure_upsert_follower(
            &c,
            &FollowerInput { persona_code: None, platform_id: 4, count_date: "2026-06-01".into(), follower_count: 10 },
        );
        assert!(err.is_err());
        let err2 = pure_upsert_follower(
            &c,
            &FollowerInput { persona_code: Some("  ".into()), platform_id: 4, count_date: "2026-06-01".into(), follower_count: 10 },
        );
        assert!(err2.is_err(), "blank persona is also rejected");
    }

    #[test]
    fn list_today_none_persona_is_empty() {
        let c = mk_db();
        up(&c, Some("CoC"), 4, "2026-06-01", 1000);
        let all = pure_list_followers_today(&c, None, "2026-06-01").unwrap();
        assert!(all.is_empty(), "ALL uses the combined endpoint, not this one");
    }

    #[test]
    fn today_count_drives_the_nudge() {
        let c = mk_db();
        up(&c, Some("CoC"), 4, "2026-05-30", 900);
        // On 06-01, latest carries forward (900) but today_count is None.
        let rows = pure_list_followers_today(&c, Some("CoC"), "2026-06-01").unwrap();
        let tt = rows.iter().find(|r| r.platform_id == 4).unwrap();
        assert_eq!(tt.latest_count, Some(900));
        assert_eq!(tt.today_count, None, "unlogged today → nudge");
        // Log today → today_count present.
        up(&c, Some("CoC"), 4, "2026-06-01", 950);
        let rows2 = pure_list_followers_today(&c, Some("CoC"), "2026-06-01").unwrap();
        let tt2 = rows2.iter().find(|r| r.platform_id == 4).unwrap();
        assert_eq!(tt2.today_count, Some(950));
        assert_eq!(tt2.delta, Some(50));
    }

    #[test]
    fn history_returns_gaps_as_none() {
        let c = mk_db();
        up(&c, Some("CoC"), 4, "2026-05-30", 900);
        up(&c, Some("CoC"), 4, "2026-06-01", 950); // skipped 05-31
        let hist = pure_list_follower_history(&c, Some("CoC"), 4, "2026-06-01", 3).unwrap();
        assert_eq!(hist.len(), 3);
        assert_eq!(hist[0].date, "2026-05-30");
        assert_eq!(hist[0].count, Some(900));
        assert_eq!(hist[1].date, "2026-05-31");
        assert_eq!(hist[1].count, None, "skipped day is a gap, not zero");
        assert!(!hist[1].is_logged);
        assert_eq!(hist[2].count, Some(950));
    }

    #[test]
    fn logged_history_is_sparse_oldest_first() {
        let c = mk_db();
        up(&c, Some("CoC"), 4, "2026-06-01", 950);
        up(&c, Some("CoC"), 4, "2026-05-30", 900);
        let pts = pure_list_logged_follower_history(&c, Some("CoC"), 4, "2026-06-01").unwrap();
        assert_eq!(pts.len(), 2);
        assert_eq!(pts[0].date, "2026-05-30");
        assert_eq!(pts[1].date, "2026-06-01");
        // end_date clips the future.
        up(&c, Some("CoC"), 4, "2026-06-05", 1000);
        let clipped = pure_list_logged_follower_history(&c, Some("CoC"), 4, "2026-06-01").unwrap();
        assert_eq!(clipped.len(), 2);
    }

    #[test]
    fn combined_sums_each_personas_latest() {
        let c = mk_db();
        // Curves last logged TikTok 3 days ago; Princess logged today.
        up(&c, Some("CoC"), 4, "2026-05-29", 9800);
        up(&c, Some("Princess"), 4, "2026-06-01", 4200);
        let rows = pure_list_combined_followers_today(&c, "2026-06-01").unwrap();
        let tt = rows.iter().find(|r| r.platform_id == 4).unwrap();
        assert_eq!(tt.combined_latest, Some(14000), "carry-forward each persona's latest");
        assert_eq!(tt.contributing_personas, 2);
        assert_eq!(tt.breakdown.len(), 2);
        // A platform nobody logged → None, zero contributors.
        let x = rows.iter().find(|r| r.platform_id == 2).unwrap();
        assert_eq!(x.combined_latest, None);
        assert_eq!(x.contributing_personas, 0);
        assert!(x.breakdown.is_empty());
    }

    #[test]
    fn goal_just_hit_crosses_once() {
        let c = mk_db();
        pure_set_follower_goal(&c, 4, 1000).unwrap();
        let r1 = up(&c, Some("CoC"), 4, "2026-06-01", 950);
        assert!(!r1.goal_hit);
        assert!(!r1.just_hit_goal);
        let r2 = up(&c, Some("CoC"), 4, "2026-06-02", 1010);
        assert!(r2.goal_hit);
        assert!(r2.just_hit_goal, "crossed the goal");
        let r3 = up(&c, Some("CoC"), 4, "2026-06-03", 1050);
        assert!(r3.goal_hit);
        assert!(!r3.just_hit_goal, "already past — don't re-fire");
    }

    #[test]
    fn first_log_already_past_goal_counts_as_hit() {
        let c = mk_db();
        pure_set_follower_goal(&c, 4, 1000).unwrap();
        let r = up(&c, Some("CoC"), 4, "2026-06-01", 5000);
        assert!(r.just_hit_goal, "first-ever log ≥ goal celebrates once");
    }

    #[test]
    fn set_goal_validates_and_updates() {
        let c = mk_db();
        pure_set_follower_goal(&c, 4, 10000).unwrap();
        let g = platform_goal(&c, 4).unwrap();
        assert_eq!(g, 10000);
        assert!(pure_set_follower_goal(&c, 4, -1).is_err());
        assert!(pure_set_follower_goal(&c, 4, MAX_GOAL + 1).is_err());
        assert!(pure_set_follower_goal(&c, 999, 100).is_err());
    }

    #[test]
    fn delete_removes_a_day() {
        let c = mk_db();
        up(&c, Some("CoC"), 4, "2026-06-01", 1000);
        let removed = pure_delete_follower(&c, Some("CoC"), 4, "2026-06-01").unwrap();
        assert!(removed);
        let again = pure_delete_follower(&c, Some("CoC"), 4, "2026-06-01").unwrap();
        assert!(!again);
    }

    #[test]
    fn rejects_bad_input() {
        let c = mk_db();
        assert!(pure_upsert_follower(&c, &FollowerInput {
            persona_code: Some("CoC".into()), platform_id: 4, count_date: "nope".into(), follower_count: 10,
        }).is_err());
        assert!(pure_upsert_follower(&c, &FollowerInput {
            persona_code: Some("CoC".into()), platform_id: 4, count_date: "2026-06-01".into(), follower_count: -5,
        }).is_err());
        assert!(pure_upsert_follower(&c, &FollowerInput {
            persona_code: Some("CoC".into()), platform_id: 4, count_date: "2026-06-01".into(), follower_count: MAX_FOLLOWERS + 1,
        }).is_err());
        assert!(pure_list_follower_history(&c, Some("CoC"), 4, "2026-06-01", 0).is_err());
        assert!(pure_list_follower_history(&c, Some("CoC"), 4, "2026-06-01", 999).is_err());
    }
}
