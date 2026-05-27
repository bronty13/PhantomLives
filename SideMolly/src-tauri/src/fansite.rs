// Phase 13 — FanSite posting workflow.
//
// FanSite bundles are posted before the start of each month, on a
// calendar cadence, to a *fixed roster of sites per persona*:
//
//   CoC → OnlyFans, ManyVids, Niteflirt
//   PoA → OnlyFans, Niteflirt, LoyalFans
//   Sa  → (no fan-sites; Sheer is excluded)
//
// None of these sites support API posting, so SideMolly's job is to
// put the right information + the right media in front of Robert and
// track what's been posted where. The flow is "all days for site A,
// then all days for site B, then site C" — so the data model keys
// per-day posting state on (bundle_uid, target_id, fansite_day) and we
// surface *every* fan-site target at once (the Phase-10 single-target
// `list_fansite_plan` was the precursor to this).
//
// Three pillars, all in this module:
//
//   1. get_fansite_plan        — the multi-site calendar + per-cell state
//   2. prepare_fansite_day     — the "infallible media" staging folder:
//                                rotate + strip-EXIF (NO watermark — the
//                                sites stamp their own, so we'd double it)
//                                copied into one folder per day so the
//                                upload dialog can only see that day's files
//   3. posting_log             — append-only audit trail of every
//                                posted / unposted / reset action,
//                                viewable in SideMolly + carried back to
//                                Molly in the post-bundle (posting-log.json)

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tauri::{AppHandle, Manager, Runtime};

use crate::bundles::{work_root, BundleError};
use crate::extract::bundle_workspace_dir;
use crate::images::{process_image, ImageOps};
use crate::posting::PostingTarget;
use crate::video::{process_video, ProcessVideoParams};

// ---------------------------------------------------------------------------
// Canonical per-persona fan-site roster
// ---------------------------------------------------------------------------

/// Persona prominent colors (mirror the `--persona-*` CSS vars). CoC =
/// pink (255 192 203), PoA = crimson (200 16 46). Used when seeding so
/// the per-site cards carry the persona's color.
const COC_COLOR: &str = "#FFC0CB";
const POA_COLOR: &str = "#C8102E";

/// (persona_code, site_name, icon, position). Names use Robert's
/// bracket notation so the `posting_targets.name` UNIQUE constraint
/// tolerates "OnlyFans" appearing under two personas.
const FANSITE_ROSTER: &[(&str, &str, &str, &str, i64)] = &[
    // CoC
    ("CoC", "OnlyFans [CoC]", "💙", COC_COLOR, 10),
    ("CoC", "ManyVids [CoC]", "🎬", COC_COLOR, 20),
    ("CoC", "Niteflirt [CoC]", "☎️", COC_COLOR, 30),
    // PoA
    ("PoA", "OnlyFans [PoA]", "💙", POA_COLOR, 10),
    ("PoA", "Niteflirt [PoA]", "☎️", POA_COLOR, 20),
    ("PoA", "LoyalFans [PoA]", "💜", POA_COLOR, 30),
];

// ---------------------------------------------------------------------------
// Boundary structs (camelCase contract — see lib.rs camel_case_contract)
// ---------------------------------------------------------------------------

/// One fan-site target's posting state for a single day.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FanSiteTargetDay {
    pub target_id: i64,
    pub state: String, // pending|scheduled|posted|skipped
    pub posted_at: Option<String>,
    pub posted_url: Option<String>,
    pub notes: Option<String>,
}

/// One calendar day from the manifest, plus its per-target state.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FanSiteDay {
    pub day_of_month: i64,
    pub message: String,
    pub file_count: i64,
    /// One entry per `FanSitePlan.targets` (same order); the frontend
    /// indexes by `target_id`.
    pub targets: Vec<FanSiteTargetDay>,
}

/// The full multi-site calendar plan for a FanSite bundle.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FanSitePlan {
    pub bundle_uid: String,
    pub persona_code: Option<String>,
    pub title: String,
    pub year: Option<i64>,
    pub month: Option<i64>,
    /// Every enabled fan-site target for this persona (the roster).
    pub targets: Vec<PostingTarget>,
    pub days: Vec<FanSiteDay>,
}

/// One file materialized into a day's staging folder.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PreparedDayFile {
    pub name: String,
    pub path: String,
    pub kind: String, // image|video|audio|other
    /// Original in-zip path so the frontend can look up the existing
    /// thumbnail from `get_bundle_thumbnails`.
    pub in_zip_path: String,
}

/// Result of preparing one day's media: a folder containing exactly
/// that day's processed files, ready to drag into an upload dialog.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PreparedDay {
    pub bundle_uid: String,
    pub day_of_month: i64,
    pub folder_path: String,
    pub files: Vec<PreparedDayFile>,
    pub processed_count: i64,
    pub skipped_count: i64,
    pub errors: Vec<String>,
}

/// One append-only audit row.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PostingLogRow {
    pub id: i64,
    pub bundle_uid: String,
    pub target_id: Option<i64>,
    pub target_name: String,
    pub persona_code: Option<String>,
    pub fansite_day: Option<i64>,
    pub title: Option<String>,
    pub action: String, // posted|unposted|reset
    pub posted_url: Option<String>,
    pub details: Option<String>,
    pub logged_at: String,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct SetFanSiteDayInput {
    pub bundle_uid: String,
    pub target_id: i64,
    pub fansite_day: i64,
    pub state: String,
    #[serde(default)]
    pub posted_url: Option<String>,
    #[serde(default)]
    pub notes: Option<String>,
}

// ---------------------------------------------------------------------------
// get_fansite_plan
// ---------------------------------------------------------------------------

#[tauri::command]
pub fn get_fansite_plan<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<FanSitePlan, BundleError> {
    let conn = open_conn(&handle)?;

    let (persona_code, title, manifest_json): (Option<String>, String, String) = conn
        .query_row(
            "SELECT persona_code, COALESCE(title, ''), manifest_json
               FROM bundles WHERE uid = ?1",
            params![uid],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )
        .optional()?
        .ok_or_else(|| BundleError::NotFound(format!("bundle {uid}")))?;
    let manifest: crate::manifest::BundleManifest =
        serde_json::from_str(&manifest_json).unwrap_or_default();

    let targets = fansite_targets_for(&conn, persona_code.as_deref())?;

    // Per-(day, target) state map.
    type Cell = (String, Option<String>, Option<String>, Option<String>);
    let mut by_cell: std::collections::HashMap<(i64, i64), Cell> =
        std::collections::HashMap::new();
    {
        let mut stmt = conn.prepare(
            "SELECT fansite_day, target_id, state, posted_at, posted_url, notes
               FROM bundle_postings
              WHERE bundle_uid = ?1 AND fansite_day IS NOT NULL",
        )?;
        let rows = stmt
            .query_map(params![uid], |r| {
                Ok((
                    r.get::<_, i64>(0)?,
                    r.get::<_, i64>(1)?,
                    r.get::<_, String>(2)?,
                    r.get::<_, Option<String>>(3)?,
                    r.get::<_, Option<String>>(4)?,
                    r.get::<_, Option<String>>(5)?,
                ))
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        for (day, tid, state, pa, pu, n) in rows {
            by_cell.insert((day, tid), (state, pa, pu, n));
        }
    }

    let mut days: Vec<FanSiteDay> = manifest
        .fan_days
        .iter()
        .map(|fd| {
            let targets = targets
                .iter()
                .map(|t| match by_cell.get(&(fd.day_of_month, t.id)) {
                    Some((state, pa, pu, n)) => FanSiteTargetDay {
                        target_id: t.id,
                        state: state.clone(),
                        posted_at: pa.clone(),
                        posted_url: pu.clone(),
                        notes: n.clone(),
                    },
                    None => FanSiteTargetDay {
                        target_id: t.id,
                        state: "pending".into(),
                        posted_at: None,
                        posted_url: None,
                        notes: None,
                    },
                })
                .collect();
            FanSiteDay {
                day_of_month: fd.day_of_month,
                message: fd.message.clone(),
                file_count: fd.file_count,
                targets,
            }
        })
        .collect();
    days.sort_by_key(|d| d.day_of_month);

    Ok(FanSitePlan {
        bundle_uid: uid,
        persona_code,
        title,
        year: manifest.fansite_year,
        month: manifest.fansite_month,
        targets,
        days,
    })
}

/// Enabled fan-site targets for a persona, ordered for display.
fn fansite_targets_for(
    conn: &Connection,
    persona: Option<&str>,
) -> Result<Vec<PostingTarget>, BundleError> {
    let mut stmt = conn.prepare(
        "SELECT id, name, url_template, persona_code, color, icon,
                position, kind, enabled
           FROM posting_targets
          WHERE enabled = 1
            AND kind = 'fansite'
            AND (persona_code IS NULL OR persona_code = ?1)
          ORDER BY position, name",
    )?;
    let rows = stmt
        .query_map(params![persona.unwrap_or_default()], |r| {
            Ok(PostingTarget {
                id: r.get(0)?,
                name: r.get(1)?,
                url_template: r.get(2)?,
                persona_code: r.get(3)?,
                color: r.get(4)?,
                icon: r.get(5)?,
                position: r.get(6)?,
                kind: r.get(7)?,
                enabled: r.get::<_, i64>(8)? != 0,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

// ---------------------------------------------------------------------------
// seed_fansite_targets
// ---------------------------------------------------------------------------

/// Create the canonical per-persona fan-site roster. Idempotent: a row
/// whose `name` already exists is left untouched (we never clobber the
/// user's color/url edits). Returns the full target list afterward.
#[tauri::command]
pub fn seed_fansite_targets<R: Runtime>(
    handle: AppHandle<R>,
) -> Result<Vec<PostingTarget>, BundleError> {
    let conn = open_conn(&handle)?;
    for (persona, name, icon, color, position) in FANSITE_ROSTER {
        let exists: bool = conn
            .query_row(
                "SELECT 1 FROM posting_targets WHERE name = ?1",
                params![name],
                |_| Ok(()),
            )
            .optional()?
            .is_some();
        if exists {
            continue;
        }
        conn.execute(
            "INSERT INTO posting_targets
                (name, url_template, persona_code, color, icon, position, kind, enabled)
             VALUES (?1, '', ?2, ?3, ?4, ?5, 'fansite', 1)",
            params![name, persona, color, icon, position],
        )?;
    }
    // Return the whole list (every persona/kind) so the Platforms UI
    // can refresh without a second round trip.
    let mut stmt = conn.prepare(
        "SELECT id, name, url_template, persona_code, color, icon,
                position, kind, enabled
           FROM posting_targets
          ORDER BY position, name",
    )?;
    let rows = stmt
        .query_map([], |r| {
            Ok(PostingTarget {
                id: r.get(0)?,
                name: r.get(1)?,
                url_template: r.get(2)?,
                persona_code: r.get(3)?,
                color: r.get(4)?,
                icon: r.get(5)?,
                position: r.get(6)?,
                kind: r.get(7)?,
                enabled: r.get::<_, i64>(8)? != 0,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

// ---------------------------------------------------------------------------
// prepare_fansite_day — the infallible media folder
// ---------------------------------------------------------------------------

/// Map the per-file rotation (degrees, clockwise) to ffmpeg's
/// transpose vocabulary used by `process_video`.
fn rotation_to_video(deg: i64) -> &'static str {
    match deg {
        90 => "cw",
        270 => "ccw",
        180 => "180",
        _ => "none",
    }
}

/// Folder for one day's staged media: `<workspace>/fansite-staging/Day NN/`.
fn day_folder(workspace: &std::path::Path, day: i64) -> PathBuf {
    workspace
        .join("fansite-staging")
        .join(format!("Day {day:02}"))
}

/// Stage one FanSite day's media into a dedicated folder, applying the
/// abbreviated fan-site processing — rotate + strip EXIF/metadata, NO
/// watermark (the sites watermark automatically; doubling it looks
/// bad). The folder is wiped + rebuilt each call so it contains
/// exactly the day's *current* media — the "infallible" guarantee.
#[tauri::command]
pub fn prepare_fansite_day<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
    day: i64,
) -> Result<PreparedDay, BundleError> {
    let workspace = bundle_workspace_dir(&work_root(&handle)?, &uid);
    let folder = day_folder(&workspace, day);

    // Wipe + recreate so stale files from a previous prepare can't
    // sneak into the upload.
    if folder.exists() {
        std::fs::remove_dir_all(&folder)?;
    }
    std::fs::create_dir_all(&folder)?;

    let conn = open_conn(&handle)?;
    let mut stmt = conn.prepare(
        "SELECT in_zip_path, original_name, kind, working_path, rotation_degrees
           FROM bundle_files
          WHERE bundle_uid = ?1 AND fansite_day_of_month = ?2
                AND working_path IS NOT NULL AND working_path != ''
          ORDER BY position, in_zip_path",
    )?;
    let candidates: Vec<(String, String, String, String, i64)> = stmt
        .query_map(params![uid, day], |r| {
            Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    drop(stmt);

    let mut files: Vec<PreparedDayFile> = Vec::new();
    let mut errors: Vec<String> = Vec::new();
    let mut skipped: i64 = 0;

    for (in_zip, original_name, kind, working, rot_deg) in candidates {
        let src = PathBuf::from(&working);
        if !src.exists() {
            skipped += 1;
            errors.push(format!("{in_zip}: working file missing"));
            continue;
        }
        let stem = std::path::Path::new(&original_name)
            .file_stem()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| original_name.clone());

        let result: Result<(PathBuf, String), String> = match kind.as_str() {
            "image" => {
                let dst = folder.join(format!("{stem}.jpg"));
                process_image(
                    &src,
                    &dst,
                    ImageOps { watermark: false, strip_exif: true, rename: false },
                    None,
                    &[],
                    rot_deg,
                )
                .map(|()| (dst, "image".to_string()))
                .map_err(|e| format!("{in_zip}: {e}"))
            }
            "video" => {
                let dst = folder.join(format!("{stem}.mp4"));
                let params = ProcessVideoParams {
                    working_path: working.clone(),
                    output_path: dst.to_string_lossy().to_string(),
                    op_kind: "video_strip".into(),
                    watermark: false,
                    strip_metadata: true,
                    rename: false,
                    position: "bottom-right".into(),
                    margin_pct: 0.0,
                    watermark_png_path: None,
                    bundle_file_id: 0,
                    rotation: rotation_to_video(rot_deg).into(),
                };
                process_video(&params)
                    .map(|()| (dst, "video".to_string()))
                    .map_err(|e| format!("{in_zip}: {e}"))
            }
            other => {
                // Audio / unknown — copy verbatim (no processing to apply).
                let dst = folder.join(&original_name);
                std::fs::copy(&src, &dst)
                    .map(|_| (dst, other.to_string()))
                    .map_err(|e| format!("{in_zip}: {e}"))
            }
        };

        match result {
            Ok((dst, kind)) => files.push(PreparedDayFile {
                name: dst
                    .file_name()
                    .map(|s| s.to_string_lossy().to_string())
                    .unwrap_or_default(),
                path: dst.to_string_lossy().to_string(),
                kind,
                in_zip_path: in_zip,
            }),
            Err(e) => {
                skipped += 1;
                errors.push(e);
            }
        }
    }

    Ok(PreparedDay {
        bundle_uid: uid,
        day_of_month: day,
        folder_path: folder.to_string_lossy().to_string(),
        processed_count: files.len() as i64,
        skipped_count: skipped,
        files,
        errors,
    })
}

/// Reveal a prepared day folder in Finder. Prepares it first if it
/// doesn't exist yet so "Reveal" always lands on a populated folder.
#[tauri::command]
pub fn reveal_fansite_day<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
    day: i64,
) -> Result<(), BundleError> {
    let workspace = bundle_workspace_dir(&work_root(&handle)?, &uid);
    let folder = day_folder(&workspace, day);
    if !folder.exists() {
        prepare_fansite_day(handle, uid, day)?;
    }
    crate::fsutil::reveal_in_file_browser(&folder)?;
    Ok(())
}

// ---------------------------------------------------------------------------
// set_fansite_day — upsert one cell + write the audit log
// ---------------------------------------------------------------------------

#[tauri::command]
pub fn set_fansite_day<R: Runtime>(
    handle: AppHandle<R>,
    input: SetFanSiteDayInput,
) -> Result<(), BundleError> {
    if !["pending", "scheduled", "posted", "skipped"].contains(&input.state.as_str()) {
        return Err(BundleError::Io(std::io::Error::other(format!(
            "invalid state '{}'",
            input.state
        ))));
    }
    let conn = open_conn(&handle)?;

    // Previous state for this cell (for log-action detection).
    let prev_state: Option<String> = conn
        .query_row(
            "SELECT state FROM bundle_postings
              WHERE bundle_uid = ?1 AND target_id = ?2 AND fansite_day = ?3",
            params![input.bundle_uid, input.target_id, input.fansite_day],
            |r| r.get(0),
        )
        .optional()?;

    let now_posted = input.state == "posted";

    // Upsert. posted_at: set to now when becoming posted; otherwise
    // keep whatever's there so the original post timestamp survives a
    // later state flip.
    if prev_state.is_some() {
        conn.execute(
            "UPDATE bundle_postings SET
                state = ?1,
                posted_url = COALESCE(?2, posted_url),
                notes = COALESCE(?3, notes),
                posted_at = CASE WHEN ?4 = 1
                                 THEN COALESCE(posted_at, datetime('now'))
                                 ELSE posted_at END,
                updated_at = datetime('now')
              WHERE bundle_uid = ?5 AND target_id = ?6 AND fansite_day = ?7",
            params![
                input.state,
                input.posted_url,
                input.notes,
                if now_posted { 1 } else { 0 },
                input.bundle_uid,
                input.target_id,
                input.fansite_day,
            ],
        )?;
    } else {
        conn.execute(
            "INSERT INTO bundle_postings
                (bundle_uid, target_id, state, posted_at, posted_url, notes,
                 fansite_day, updated_at)
             VALUES (?1, ?2, ?3, CASE WHEN ?4 = 1 THEN datetime('now') ELSE NULL END,
                     ?5, ?6, ?7, datetime('now'))",
            params![
                input.bundle_uid,
                input.target_id,
                input.state,
                if now_posted { 1 } else { 0 },
                input.posted_url,
                input.notes,
                input.fansite_day,
            ],
        )?;
    }

    // Audit: log a 'posted' when the cell flips TO posted, 'unposted'
    // when it flips AWAY from posted. Plain pending↔skipped churn isn't
    // logged (not a post event).
    let was_posted = prev_state.as_deref() == Some("posted");
    let action = if now_posted && !was_posted {
        Some("posted")
    } else if was_posted && !now_posted {
        Some("unposted")
    } else {
        None
    };
    if let Some(action) = action {
        let (target_name, persona, title) =
            cell_context(&conn, &input.bundle_uid, input.target_id)?;
        append_posting_log(
            &conn,
            &input.bundle_uid,
            Some(input.target_id),
            &target_name,
            persona.as_deref(),
            Some(input.fansite_day),
            title.as_deref(),
            action,
            input.posted_url.as_deref(),
            None,
        )?;
    }
    Ok(())
}

/// (target_name, persona_code, title) for a posting log row.
fn cell_context(
    conn: &Connection,
    bundle_uid: &str,
    target_id: i64,
) -> Result<(String, Option<String>, Option<String>), BundleError> {
    let target_name: String = conn
        .query_row(
            "SELECT name FROM posting_targets WHERE id = ?1",
            params![target_id],
            |r| r.get(0),
        )
        .optional()?
        .unwrap_or_default();
    let (persona, title): (Option<String>, Option<String>) = conn
        .query_row(
            "SELECT persona_code, title FROM bundles WHERE uid = ?1",
            params![bundle_uid],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .optional()?
        .unwrap_or((None, None));
    Ok((target_name, persona, title))
}

// ---------------------------------------------------------------------------
// reset_fansite_postings — unwind one site or the whole bundle
// ---------------------------------------------------------------------------

#[tauri::command]
pub fn reset_fansite_postings<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
    target_id: Option<i64>,
) -> Result<(), BundleError> {
    let conn = open_conn(&handle)?;
    let (persona, title): (Option<String>, Option<String>) = conn
        .query_row(
            "SELECT persona_code, title FROM bundles WHERE uid = ?1",
            params![uid],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .optional()?
        .unwrap_or((None, None));

    let (target_name, details) = match target_id {
        Some(tid) => {
            let name: String = conn
                .query_row(
                    "SELECT name FROM posting_targets WHERE id = ?1",
                    params![tid],
                    |r| r.get(0),
                )
                .optional()?
                .unwrap_or_default();
            conn.execute(
                "DELETE FROM bundle_postings
                  WHERE bundle_uid = ?1 AND target_id = ?2 AND fansite_day IS NOT NULL",
                params![uid, tid],
            )?;
            (name.clone(), format!("reset site {name}"))
        }
        None => {
            conn.execute(
                "DELETE FROM bundle_postings
                  WHERE bundle_uid = ?1 AND fansite_day IS NOT NULL",
                params![uid],
            )?;
            (String::new(), "reset all fan-sites".to_string())
        }
    };

    append_posting_log(
        &conn,
        &uid,
        target_id,
        &target_name,
        persona.as_deref(),
        None,
        title.as_deref(),
        "reset",
        None,
        Some(&details),
    )?;
    Ok(())
}

// ---------------------------------------------------------------------------
// posting_log queries
// ---------------------------------------------------------------------------

#[allow(clippy::too_many_arguments)]
fn append_posting_log(
    conn: &Connection,
    bundle_uid: &str,
    target_id: Option<i64>,
    target_name: &str,
    persona_code: Option<&str>,
    fansite_day: Option<i64>,
    title: Option<&str>,
    action: &str,
    posted_url: Option<&str>,
    details: Option<&str>,
) -> Result<(), BundleError> {
    conn.execute(
        "INSERT INTO posting_log
            (bundle_uid, target_id, target_name, persona_code, fansite_day,
             title, action, posted_url, details)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
        params![
            bundle_uid, target_id, target_name, persona_code, fansite_day,
            title, action, posted_url, details,
        ],
    )?;
    Ok(())
}

/// Read the posting log for a bundle. `newest_first` drives the
/// viewer (true) vs the deterministic export (false → oldest first).
pub fn read_posting_log(
    conn: &Connection,
    uid: &str,
    newest_first: bool,
) -> Result<Vec<PostingLogRow>, BundleError> {
    let order = if newest_first {
        "logged_at DESC, id DESC"
    } else {
        "logged_at ASC, id ASC"
    };
    let sql = format!(
        "SELECT id, bundle_uid, target_id, target_name, persona_code,
                fansite_day, title, action, posted_url, details, logged_at
           FROM posting_log
          WHERE bundle_uid = ?1
          ORDER BY {order}"
    );
    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt
        .query_map(params![uid], |r| {
            Ok(PostingLogRow {
                id: r.get(0)?,
                bundle_uid: r.get(1)?,
                target_id: r.get(2)?,
                target_name: r.get(3)?,
                persona_code: r.get(4)?,
                fansite_day: r.get(5)?,
                title: r.get(6)?,
                action: r.get(7)?,
                posted_url: r.get(8)?,
                details: r.get(9)?,
                logged_at: r.get(10)?,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

#[tauri::command]
pub fn list_posting_log<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<Vec<PostingLogRow>, BundleError> {
    let conn = open_conn(&handle)?;
    read_posting_log(&conn, &uid, true)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn open_conn<R: Runtime>(handle: &AppHandle<R>) -> Result<Connection, BundleError> {
    let dir = handle
        .path()
        .resolve("", tauri::path::BaseDirectory::AppLocalData)
        .map_err(|e| BundleError::Io(std::io::Error::other(format!("appdata path: {e}"))))?;
    Ok(Connection::open(dir.join("sidemolly.db"))?)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rotation_maps_to_ffmpeg_transpose() {
        assert_eq!(rotation_to_video(0), "none");
        assert_eq!(rotation_to_video(90), "cw");
        assert_eq!(rotation_to_video(180), "180");
        assert_eq!(rotation_to_video(270), "ccw");
        assert_eq!(rotation_to_video(45), "none");
    }

    #[test]
    fn day_folder_is_zero_padded() {
        let p = day_folder(std::path::Path::new("/work/uid"), 7);
        assert!(p.ends_with("fansite-staging/Day 07"));
        let p = day_folder(std::path::Path::new("/work/uid"), 13);
        assert!(p.ends_with("fansite-staging/Day 13"));
    }

    #[test]
    fn roster_covers_coc_and_poa_only() {
        let coc = FANSITE_ROSTER.iter().filter(|r| r.0 == "CoC").count();
        let poa = FANSITE_ROSTER.iter().filter(|r| r.0 == "PoA").count();
        let sa = FANSITE_ROSTER.iter().filter(|r| r.0 == "Sa").count();
        assert_eq!(coc, 3, "CoC posts to 3 fan-sites");
        assert_eq!(poa, 3, "PoA posts to 3 fan-sites");
        assert_eq!(sa, 0, "Sheer has no fan-sites");
    }

    #[test]
    fn posting_log_appends_and_reads_in_order() {
        // posting_log carries FK references; FK enforcement is off by
        // default for in-memory connections, so we can exercise the
        // table standalone.
        let conn = Connection::open_in_memory().unwrap();
        // Minimal parent tables for the FK references in 017.
        conn.execute_batch(
            "CREATE TABLE bundles (uid TEXT PRIMARY KEY);
             CREATE TABLE posting_targets (id INTEGER PRIMARY KEY);",
        ).unwrap();
        conn.execute_batch(include_str!("../migrations/017_posting_log.sql"))
            .unwrap();
        conn.execute_batch(
            "INSERT INTO bundles (uid) VALUES ('uid1'), ('uid2');
             INSERT INTO posting_targets (id) VALUES (1);",
        ).unwrap();

        append_posting_log(
            &conn, "uid1", Some(1), "OnlyFans [CoC]", Some("CoC"),
            Some(3), Some("June drop"), "posted",
            Some("https://onlyfans.com/p/1"), None,
        ).unwrap();
        append_posting_log(
            &conn, "uid1", Some(1), "OnlyFans [CoC]", Some("CoC"),
            Some(3), Some("June drop"), "unposted", None, None,
        ).unwrap();
        // A different bundle's row must not leak in.
        append_posting_log(
            &conn, "uid2", None, "", Some("PoA"),
            None, None, "reset", None, Some("reset all fan-sites"),
        ).unwrap();

        let newest = read_posting_log(&conn, "uid1", true).unwrap();
        assert_eq!(newest.len(), 2, "only uid1 rows");
        assert_eq!(newest[0].action, "unposted", "newest-first");
        assert_eq!(newest[0].target_name, "OnlyFans [CoC]");
        assert_eq!(newest[1].action, "posted");
        assert_eq!(newest[1].posted_url.as_deref(), Some("https://onlyfans.com/p/1"));

        let oldest = read_posting_log(&conn, "uid1", false).unwrap();
        assert_eq!(oldest[0].action, "posted", "oldest-first for export");

        let other = read_posting_log(&conn, "uid2", true).unwrap();
        assert_eq!(other.len(), 1);
        assert_eq!(other[0].action, "reset");
        assert_eq!(other[0].fansite_day, None);
    }

    #[test]
    fn roster_names_are_unique() {
        // posting_targets.name has a UNIQUE constraint — the bracket
        // notation must keep cross-persona names distinct.
        let mut names: Vec<&str> = FANSITE_ROSTER.iter().map(|r| r.1).collect();
        names.sort();
        let before = names.len();
        names.dedup();
        assert_eq!(before, names.len(), "roster names must be unique");
    }
}
