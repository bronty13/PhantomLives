// v1.20.0 — Import SideMolly's "return file" back into Molly.
//
// SideMolly composes a deterministic post-bundle ZIP at
// `~/Downloads/Molly post-bundles/<UID>-post.zip` after Robert posts
// the bundle's content to its targets. This module is the Molly side:
// scan + parse + import + idempotency.
//
// Outer ZIP layout (mirrors SideMolly's post_bundle.rs):
//
//   <UID>-post.zip
//   └── <UID>-post/
//       ├── hashes.json
//       └── <UID>-post-inner.zip
//           └── <UID>-post-inner/
//               ├── report.json          ← what we parse
//               ├── notes.md
//               ├── posting-log.json
//               ├── processing.log (optional)
//               └── artifacts/...
//
// Hash check: hashes.json names the inner zip's sha256; we recompute the
// inner zip bytes and reject mismatches. Per-file hashes inside hashes.json
// aren't checked here — `report.json` round-trips literally.
//
// Bundle ↔ clip linkage: bundles and clips are decoupled in Molly's data
// model, so the writeback resolves clip_id by matching the filename stem of
// each `bundle_files.original_name` against `clips.id` / `clips.external_clip_id`
// / `clips.title` (case-insensitive). Misses are recorded with clip_id=NULL
// and surfaced in the result so Sallie can see what didn't link.

use std::fs;
use std::io::{Cursor, Read};
use std::path::{Path, PathBuf};
use std::time::Duration;

use chrono::Utc;
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tauri::{AppHandle, Manager, Runtime};

use crate::bundles::BundleError;
use crate::fsutil;

const POST_BUNDLE_FOLDER: &str = "Molly post-bundles";
const DELETE_AFTER_DAYS: i64 = 3;

// ---------------------------------------------------------------------------
// Boundary types — camelCase across the IPC seam.
// ---------------------------------------------------------------------------

/// One target row in the SideMolly report. Field names mirror
/// `SideMolly/src-tauri/src/post_bundle.rs::ReportTarget` exactly so a small
/// schema bump there is a one-line update here.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReportTarget {
    pub target_id: String,
    pub target_name: String,
    pub state: String,
    pub posted_at: Option<String>,
    pub posted_url: Option<String>,
    pub body_override: Option<String>,
    pub files_used: Vec<String>,
    pub notes: Option<String>,
    pub fansite_day: Option<i64>,
}

/// SideMolly's report.json schema (mirror of its `Report` struct).
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Report {
    pub report_version: i64,
    pub bundle_uid: String,
    pub bundle_type: String,
    pub persona_code: Option<String>,
    pub report_composed_at: String,
    pub bundle_state: String,
    pub targets: Vec<ReportTarget>,
    #[serde(default)]
    pub bundle_level_notes: Option<String>,
}

/// Row in the candidate list shown in the import wizard's first stage.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReturnFileCandidate {
    pub path: String,
    pub filename: String,
    pub bundle_uid: String,
    pub bundle_type: String,
    pub bundle_known: bool,
    pub already_imported: bool,
    pub composed_at: String,
    pub size_bytes: i64,
}

/// One file's writeback outcome — surfaced in the result modal.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PostingFileOutcome {
    pub relpath: String,
    pub original_name: Option<String>,
    pub clip_id: Option<String>,
    pub clip_title: Option<String>,
}

/// One posting's outcome — used by the result modal AND by
/// `get_bundle_postings` for surfacing on the bundle detail.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BundlePostingDto {
    pub id: i64,
    pub bundle_uid: String,
    pub target_id: String,
    pub target_name: String,
    pub state: String,
    pub posted_at: Option<String>,
    pub posted_url: Option<String>,
    pub body_override: Option<String>,
    pub notes: Option<String>,
    pub fansite_day: Option<i64>,
    pub imported_at: String,
    pub files: Vec<PostingFileOutcome>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReturnFileImportResult {
    pub bundle_uid: String,
    pub bundle_type: String,
    pub completed_at: String,
    pub delete_after: Option<String>,
    pub bundle_already_purged: bool,
    pub postings: Vec<BundlePostingDto>,
    pub matched_file_count: i64,
    pub total_file_count: i64,
    pub was_duplicate: bool,
    /// Non-null when SideMolly's report.bundleType disagrees with Molly's
    /// stored type — holds SideMolly's claimed type so the UI can show
    /// "stored=X · reported=Y". `bundle_type` is always Molly's stored
    /// (canonical) value.
    pub reported_bundle_type: Option<String>,
}

// ---------------------------------------------------------------------------
// Default drop dir (mirrors SideMolly's default_drop_dir).
// ---------------------------------------------------------------------------

pub fn default_drop_dir() -> PathBuf {
    fsutil::downloads_subdir(POST_BUNDLE_FOLDER)
}

// ---------------------------------------------------------------------------
// Connection plumbing (same shape as bundles.rs::open_conn).
// ---------------------------------------------------------------------------

fn app_data_dir<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, BundleError> {
    handle
        .path()
        .app_data_dir()
        .map_err(|e| BundleError::Settings(e.to_string()))
}

fn open_conn(app_data_dir: &Path) -> Result<Connection, BundleError> {
    let db_path = app_data_dir.join("molly.db");
    let conn = Connection::open(&db_path)
        .map_err(|e| BundleError::Db(format!("open {}: {e}", db_path.display())))?;
    conn.busy_timeout(Duration::from_secs(5))?;
    conn.execute_batch("PRAGMA foreign_keys = ON;")?;
    Ok(conn)
}

// ---------------------------------------------------------------------------
// ZIP plumbing — open outer, locate inner, locate report.json.
// ---------------------------------------------------------------------------

fn sha256_hex(bytes: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(bytes);
    format!("{:x}", h.finalize())
}

/// Read inner zip bytes + parsed report from a `<UID>-post.zip` file.
/// Returns the report, the raw report.json bytes, and the file's sha256.
fn read_return_file(path: &Path) -> Result<ParsedReturnFile, BundleError> {
    let file_bytes = fs::read(path)
        .map_err(|e| BundleError::Io(std::io::Error::other(format!("read {}: {e}", path.display()))))?;
    let source_sha = sha256_hex(&file_bytes);

    let mut outer = zip::ZipArchive::new(Cursor::new(&file_bytes))
        .map_err(|e| BundleError::Zip(format!("open outer zip: {e}")))?;

    // Find <root>/<UID>-post-inner.zip — root is whatever single top-level
    // directory the outer ZIP wraps everything in (SideMolly uses
    // `<UID>-post/`). Older SideMolly versions wrote without the wrapper, so
    // accept either shape: ".../-post-inner.zip" anywhere in the entry tree.
    let inner_buf = read_inner_zip_bytes(&mut outer)?;
    let inner_sha = sha256_hex(&inner_buf);

    // Verify against hashes.json if present.
    if let Some(hashes_json) = read_first_entry_ending_with(&mut outer, "/hashes.json")? {
        let parsed: serde_json::Value = serde_json::from_slice(&hashes_json)
            .map_err(|e| BundleError::Invalid(format!("parse hashes.json: {e}")))?;
        if let Some(claimed) = parsed
            .get("innerZip")
            .and_then(|i| i.get("sha256"))
            .and_then(|s| s.as_str())
        {
            if !claimed.eq_ignore_ascii_case(&inner_sha) {
                return Err(BundleError::Invalid(format!(
                    "inner zip hash mismatch (hashes.json={claimed}, computed={inner_sha})"
                )));
            }
        }
    }

    // Parse report.json out of the inner zip.
    let mut inner = zip::ZipArchive::new(Cursor::new(&inner_buf))
        .map_err(|e| BundleError::Zip(format!("open inner zip: {e}")))?;
    let report_bytes = read_first_entry_ending_with(&mut inner, "/report.json")?
        .ok_or_else(|| BundleError::Invalid("report.json missing from inner zip".into()))?;
    let report: Report = serde_json::from_slice(&report_bytes)
        .map_err(|e| BundleError::Invalid(format!("parse report.json: {e}")))?;

    Ok(ParsedReturnFile {
        source_sha,
        report,
    })
}

struct ParsedReturnFile {
    source_sha: String,
    report: Report,
}

fn read_inner_zip_bytes(
    outer: &mut zip::ZipArchive<Cursor<&Vec<u8>>>,
) -> Result<Vec<u8>, BundleError> {
    // Pick the first entry whose name ends with `-post-inner.zip`.
    let mut target: Option<String> = None;
    for i in 0..outer.len() {
        let entry = outer
            .by_index(i)
            .map_err(|e| BundleError::Zip(format!("scan outer: {e}")))?;
        let name = entry.name().to_string();
        if name.ends_with("-post-inner.zip") {
            target = Some(name);
            break;
        }
    }
    let name = target.ok_or_else(|| BundleError::Invalid("no *-post-inner.zip in outer".into()))?;
    let mut entry = outer
        .by_name(&name)
        .map_err(|e| BundleError::Zip(format!("read inner entry {name}: {e}")))?;
    let mut buf = Vec::with_capacity(entry.size() as usize);
    entry
        .read_to_end(&mut buf)
        .map_err(|e| BundleError::Io(std::io::Error::other(format!("read inner: {e}"))))?;
    Ok(buf)
}

fn read_first_entry_ending_with(
    archive: &mut zip::ZipArchive<Cursor<&Vec<u8>>>,
    suffix: &str,
) -> Result<Option<Vec<u8>>, BundleError> {
    let mut target: Option<String> = None;
    for i in 0..archive.len() {
        let entry = archive
            .by_index(i)
            .map_err(|e| BundleError::Zip(format!("scan: {e}")))?;
        let name = entry.name().to_string();
        // Accept both `<root>/report.json` AND a bare `report.json` (legacy /
        // unwrapped ZIPs). Suffix is `/report.json`; bare match is allowed
        // via the explicit equality check.
        if name.ends_with(suffix) || name == suffix.trim_start_matches('/') {
            target = Some(name);
            break;
        }
    }
    let Some(name) = target else { return Ok(None) };
    let mut entry = archive
        .by_name(&name)
        .map_err(|e| BundleError::Zip(format!("read {name}: {e}")))?;
    let mut buf = Vec::with_capacity(entry.size() as usize);
    entry
        .read_to_end(&mut buf)
        .map_err(|e| BundleError::Io(std::io::Error::other(format!("read {name}: {e}"))))?;
    Ok(Some(buf))
}

// ---------------------------------------------------------------------------
// Filename → clip resolution.
// ---------------------------------------------------------------------------

/// Strip a `00001_` style positional prefix (bundle compose uses `NNNNN_`
/// for content/custom and `DD_NN_` for FanSite) and the file extension,
/// returning a lowercase stem suitable for matching against clip identifiers.
fn filename_stem_for_match(original_name: &str) -> String {
    let without_dir = original_name.rsplit('/').next().unwrap_or(original_name);
    let without_ext = match without_dir.rfind('.') {
        Some(i) => &without_dir[..i],
        None => without_dir,
    };
    let without_prefix = strip_leading_position_prefix(without_ext);
    without_prefix.trim().to_lowercase()
}

fn strip_leading_position_prefix(s: &str) -> &str {
    // `00001_rest` → `rest`. `12_03_rest` (FanSite day prefix) → `rest`.
    let mut rest = s;
    loop {
        let Some(idx) = rest.find('_') else { return rest };
        let head = &rest[..idx];
        if !head.is_empty() && head.chars().all(|c| c.is_ascii_digit()) {
            rest = &rest[idx + 1..];
        } else {
            return rest;
        }
    }
}

/// Find the clip whose id / external_clip_id / title (case-insensitive)
/// matches `stem`. Returns (clip_id, clip_title) on a hit.
fn resolve_clip_for_stem(
    conn: &Connection,
    stem: &str,
) -> rusqlite::Result<Option<(String, String)>> {
    if stem.is_empty() {
        return Ok(None);
    }
    // ID and external_clip_id are precise; title is fuzzy. Prefer the
    // precise hits — query in priority order, short-circuit on first match.
    let by_id: Option<(String, String)> = conn
        .query_row(
            "SELECT id, title FROM clips WHERE LOWER(id) = ?1 LIMIT 1",
            params![stem],
            |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)),
        )
        .optional()?;
    if by_id.is_some() {
        return Ok(by_id);
    }
    let by_external: Option<(String, String)> = conn
        .query_row(
            "SELECT id, title FROM clips WHERE LOWER(external_clip_id) = ?1 LIMIT 1",
            params![stem],
            |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)),
        )
        .optional()?;
    if by_external.is_some() {
        return Ok(by_external);
    }
    let by_title: Option<(String, String)> = conn
        .query_row(
            "SELECT id, title FROM clips WHERE LOWER(title) = ?1 LIMIT 1",
            params![stem],
            |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)),
        )
        .optional()?;
    Ok(by_title)
}

// ---------------------------------------------------------------------------
// Core import — pure(ish): takes a &mut Connection and the parsed report.
// ---------------------------------------------------------------------------

pub fn pure_import_return_file(
    conn: &mut Connection,
    source_path: &str,
    source_sha: &str,
    report: &Report,
) -> Result<ReturnFileImportResult, BundleError> {
    // Idempotency — same source bytes? Surface the prior result without
    // touching the DB.
    let prior: Option<String> = conn
        .query_row(
            "SELECT bundle_uid FROM return_file_imports WHERE source_sha256 = ?1",
            params![source_sha],
            |r| r.get::<_, String>(0),
        )
        .optional()?;
    if let Some(_uid) = prior {
        return build_result_for(conn, &report.bundle_uid, true);
    }

    // Bundle row must exist (look up by UID from the report).
    let bundle_row: Option<(String, Option<String>, Option<String>)> = conn
        .query_row(
            "SELECT bundle_type, state, bundle_path FROM bundles WHERE uid = ?1",
            params![&report.bundle_uid],
            |r| Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?, r.get::<_, Option<String>>(2)?)),
        )
        .optional()?;
    let (stored_bundle_type, bundle_state, bundle_path) = bundle_row
        .ok_or_else(|| BundleError::NotFound(format!("bundle {}", report.bundle_uid)))?;

    // Soft check on type: if SideMolly's report disagrees with Molly's
    // stored type, we still import — the report drives writeback semantics
    // (fansite-vs-content controls whether we touch clips) — but the
    // divergence gets surfaced in the result for Sallie to investigate.
    let type_mismatch = if stored_bundle_type != report.bundle_type {
        Some(report.bundle_type.clone())
    } else {
        None
    };

    let already_purged = bundle_state.as_deref() == Some("purged") || bundle_path.is_none();

    let now = Utc::now().to_rfc3339();
    let delete_after = if already_purged {
        None
    } else {
        Some((Utc::now() + chrono::Duration::days(DELETE_AFTER_DAYS)).to_rfc3339())
    };

    let tx = conn.transaction()?;

    // Per-target writes. UPSERT on (bundle_uid, target_id, fansite_day) so
    // future re-imports (different file, same bundle) merge rather than
    // duplicate. NULL fansite_day folds into the unique key as itself.
    let is_fansite = report.bundle_type == "fansite";
    for target in &report.targets {
        if !["pending", "scheduled", "posted", "skipped"].contains(&target.state.as_str()) {
            return Err(BundleError::Invalid(format!(
                "target {} has unknown state {}", target.target_id, target.state,
            )));
        }
        // Delete any prior row for the same key so we can re-insert clean.
        // (UPSERT on a 3-col unique index would work too, but we need to
        // re-write the bundle_posting_files child rows anyway, and the cascade
        // FK cleanly removes them when the parent row is deleted.)
        tx.execute(
            "DELETE FROM bundle_postings
               WHERE bundle_uid = ?1
                 AND target_id = ?2
                 AND IFNULL(fansite_day, -1) = IFNULL(?3, -1)",
            params![&report.bundle_uid, &target.target_id, target.fansite_day],
        )?;
        tx.execute(
            "INSERT INTO bundle_postings
                (bundle_uid, target_id, target_name, state, posted_at, posted_url,
                 body_override, notes, fansite_day, imported_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
            params![
                &report.bundle_uid,
                &target.target_id,
                &target.target_name,
                &target.state,
                &target.posted_at,
                &target.posted_url,
                &target.body_override,
                &target.notes,
                target.fansite_day,
                &now,
            ],
        )?;
        let posting_id = tx.last_insert_rowid();

        // Per-file rows. For content/custom we attempt clip matching by
        // filename stem; for fansite we record the file but never match
        // (fansite days don't belong to clips in Molly's model).
        for relpath in &target.files_used {
            let clip_id: Option<String> = if is_fansite {
                None
            } else {
                let original_name: Option<String> = tx
                    .query_row(
                        "SELECT original_name FROM bundle_files
                           WHERE bundle_uid = ?1 AND relpath = ?2 LIMIT 1",
                        params![&report.bundle_uid, relpath],
                        |r| r.get(0),
                    )
                    .optional()?;
                match original_name.as_deref() {
                    Some(n) => {
                        let stem = filename_stem_for_match(n);
                        resolve_clip_for_stem(&tx, &stem)?.map(|(id, _)| id)
                    }
                    None => None,
                }
            };
            tx.execute(
                "INSERT INTO bundle_posting_files (posting_id, relpath, clip_id)
                 VALUES (?1, ?2, ?3)",
                params![posting_id, relpath, &clip_id],
            )?;
            // Mirror posted_at/posted_url onto a matched clip's social_promos
            // row — append-only audit trail. Skip if no clip matched OR
            // target wasn't actually posted.
            if let Some(cid) = &clip_id {
                if target.state == "posted" {
                    insert_social_promo(&tx, cid, target)?;
                }
            }
        }
    }

    // Stamp the bundle row: completed_at + delete_after.
    tx.execute(
        "UPDATE bundles
            SET completed_at = ?1,
                delete_after = ?2,
                updated_at   = datetime('now')
          WHERE uid = ?3",
        params![&now, &delete_after, &report.bundle_uid],
    )?;

    // Record the import for idempotency.
    tx.execute(
        "INSERT INTO return_file_imports (bundle_uid, source_path, source_sha256, imported_at)
         VALUES (?1, ?2, ?3, ?4)",
        params![&report.bundle_uid, source_path, source_sha, &now],
    )?;

    // Journal entry — a single mollys_log line so the import is visible in
    // the Molly's Log view without any new UI.
    let (matched, total) = count_match_outcomes_in_tx(&tx, &report.bundle_uid)?;
    let body = format_log_body(&report.bundle_uid, &report.targets, matched, total, &delete_after);
    tx.execute(
        "INSERT INTO mollys_log (body, attachment_filename, attachment_mime, attachment_size, attachment_data)
         VALUES (?1, '', '', 0, NULL)",
        params![body],
    )?;

    tx.commit()?;

    let mut result = build_result_for(conn, &report.bundle_uid, false)?;
    result.reported_bundle_type = type_mismatch;
    Ok(result)
}

fn insert_social_promo(
    conn: &Connection,
    clip_id: &str,
    target: &ReportTarget,
) -> Result<(), BundleError> {
    // The social_promos table has been around since migration 009; reuse it
    // for the "where did this clip get posted" audit trail. social_platforms
    // is a small lookup we don't necessarily have rows in — write the
    // free-form platform name onto the promo row directly when a
    // canonical platform is missing.
    let posted_at = target.posted_at.clone().unwrap_or_else(|| Utc::now().to_rfc3339());
    let url = target.posted_url.clone().unwrap_or_default();
    // Look up or fallback to a `name` column directly.
    let platform_id: Option<i64> = conn
        .query_row(
            "SELECT id FROM social_platforms WHERE LOWER(name) = LOWER(?1) LIMIT 1",
            params![&target.target_name],
            |r| r.get(0),
        )
        .optional()
        .unwrap_or(None);
    // social_promos requires platform_id (FK to social_platforms). Skip the
    // mirror if we don't have a matching platform row — Sallie can wire the
    // platform later and we still have the canonical bundle_postings row.
    let Some(pid) = platform_id else { return Ok(()) };
    conn.execute(
        "INSERT INTO social_promos (clip_id, platform_id, posted_at, url, notes)
         VALUES (?1, ?2, ?3, ?4, ?5)",
        params![clip_id, pid, &posted_at, &url, &target.notes],
    )?;
    Ok(())
}

fn count_match_outcomes_in_tx(
    tx: &rusqlite::Transaction,
    bundle_uid: &str,
) -> Result<(i64, i64), BundleError> {
    let matched: i64 = tx.query_row(
        "SELECT COUNT(*) FROM bundle_posting_files bpf
           JOIN bundle_postings bp ON bp.id = bpf.posting_id
          WHERE bp.bundle_uid = ?1 AND bpf.clip_id IS NOT NULL",
        params![bundle_uid],
        |r| r.get(0),
    )?;
    let total: i64 = tx.query_row(
        "SELECT COUNT(*) FROM bundle_posting_files bpf
           JOIN bundle_postings bp ON bp.id = bpf.posting_id
          WHERE bp.bundle_uid = ?1",
        params![bundle_uid],
        |r| r.get(0),
    )?;
    Ok((matched, total))
}

fn format_log_body(
    bundle_uid: &str,
    targets: &[ReportTarget],
    matched: i64,
    total: i64,
    delete_after: &Option<String>,
) -> String {
    let posted = targets.iter().filter(|t| t.state == "posted").count();
    let cleanup = match delete_after {
        Some(s) => format!("cleanup {}", s.chars().take(10).collect::<String>()),
        None => "bundle already cleaned up".to_string(),
    };
    format!(
        "Imported return file for bundle {} · {}/{} targets posted · {}/{} files linked to clips · {}",
        bundle_uid, posted, targets.len(), matched, total, cleanup,
    )
}

fn build_result_for(
    conn: &Connection,
    bundle_uid: &str,
    was_duplicate: bool,
) -> Result<ReturnFileImportResult, BundleError> {
    let row: (String, Option<String>, Option<String>, Option<String>) = conn
        .query_row(
            "SELECT bundle_type, completed_at, delete_after, bundle_path
               FROM bundles WHERE uid = ?1",
            params![bundle_uid],
            |r| Ok((
                r.get::<_, String>(0)?,
                r.get::<_, Option<String>>(1)?,
                r.get::<_, Option<String>>(2)?,
                r.get::<_, Option<String>>(3)?,
            )),
        )?;
    let (bundle_type, completed_at, delete_after, bundle_path) = row;
    let already_purged = bundle_path.is_none();

    let postings = list_postings_for_bundle(conn, bundle_uid)?;
    let total_file_count: i64 = postings.iter().map(|p| p.files.len() as i64).sum();
    let matched_file_count: i64 = postings
        .iter()
        .flat_map(|p| p.files.iter())
        .filter(|f| f.clip_id.is_some())
        .count() as i64;

    Ok(ReturnFileImportResult {
        bundle_uid: bundle_uid.to_string(),
        bundle_type,
        completed_at: completed_at.unwrap_or_default(),
        delete_after,
        bundle_already_purged: already_purged,
        postings,
        matched_file_count,
        total_file_count,
        was_duplicate,
        reported_bundle_type: None,
    })
}

pub fn list_postings_for_bundle(
    conn: &Connection,
    bundle_uid: &str,
) -> Result<Vec<BundlePostingDto>, BundleError> {
    let mut stmt = conn.prepare(
        "SELECT id, bundle_uid, target_id, target_name, state, posted_at, posted_url,
                body_override, notes, fansite_day, imported_at
           FROM bundle_postings
          WHERE bundle_uid = ?1
          ORDER BY fansite_day, target_name COLLATE NOCASE",
    )?;
    let mut postings: Vec<BundlePostingDto> = stmt
        .query_map(params![bundle_uid], |r| {
            Ok(BundlePostingDto {
                id: r.get(0)?,
                bundle_uid: r.get(1)?,
                target_id: r.get(2)?,
                target_name: r.get(3)?,
                state: r.get(4)?,
                posted_at: r.get(5)?,
                posted_url: r.get(6)?,
                body_override: r.get(7)?,
                notes: r.get(8)?,
                fansite_day: r.get(9)?,
                imported_at: r.get(10)?,
                files: Vec::new(),
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    drop(stmt);

    for p in postings.iter_mut() {
        let mut file_stmt = conn.prepare(
            "SELECT bpf.relpath, bf.original_name, bpf.clip_id, c.title
               FROM bundle_posting_files bpf
               LEFT JOIN bundle_files bf
                      ON bf.bundle_uid = (SELECT bundle_uid FROM bundle_postings WHERE id = bpf.posting_id)
                     AND bf.relpath = bpf.relpath
               LEFT JOIN clips c ON c.id = bpf.clip_id
              WHERE bpf.posting_id = ?1
              ORDER BY bpf.id",
        )?;
        let files: Vec<PostingFileOutcome> = file_stmt
            .query_map(params![p.id], |r| {
                Ok(PostingFileOutcome {
                    relpath: r.get(0)?,
                    original_name: r.get(1)?,
                    clip_id: r.get(2)?,
                    clip_title: r.get(3)?,
                })
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        p.files = files;
    }
    Ok(postings)
}

// ---------------------------------------------------------------------------
// Tauri commands
// ---------------------------------------------------------------------------

#[tauri::command]
pub fn list_return_file_candidates<R: Runtime>(
    handle: AppHandle<R>,
) -> Result<Vec<ReturnFileCandidate>, BundleError> {
    let dir = default_drop_dir();
    let app_data = app_data_dir(&handle)?;
    let conn = open_conn(&app_data)?;

    let mut out: Vec<ReturnFileCandidate> = Vec::new();
    let entries = match fs::read_dir(&dir) {
        Ok(e) => e,
        Err(_) => return Ok(out), // no folder yet → no candidates
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let filename = match path.file_name().and_then(|n| n.to_str()) {
            Some(s) => s.to_string(),
            None => continue,
        };
        if !filename.ends_with("-post.zip") {
            continue;
        }
        let metadata = match entry.metadata() {
            Ok(m) => m,
            Err(_) => continue,
        };
        let size_bytes = metadata.len() as i64;

        // Pull bundleUid from the report; if the file is corrupt, skip it
        // rather than letting one bad file break the whole listing.
        let parsed = match read_return_file(&path) {
            Ok(p) => p,
            Err(_) => continue,
        };

        let bundle_known: bool = conn
            .query_row(
                "SELECT 1 FROM bundles WHERE uid = ?1",
                params![&parsed.report.bundle_uid],
                |_| Ok(()),
            )
            .optional()?
            .is_some();
        let already_imported: bool = conn
            .query_row(
                "SELECT 1 FROM return_file_imports WHERE source_sha256 = ?1",
                params![&parsed.source_sha],
                |_| Ok(()),
            )
            .optional()?
            .is_some();

        out.push(ReturnFileCandidate {
            path: path.to_string_lossy().to_string(),
            filename,
            bundle_uid: parsed.report.bundle_uid.clone(),
            bundle_type: parsed.report.bundle_type.clone(),
            bundle_known,
            already_imported,
            composed_at: parsed.report.report_composed_at.clone(),
            size_bytes,
        });
    }
    // Newest composed first.
    out.sort_by(|a, b| b.composed_at.cmp(&a.composed_at));
    Ok(out)
}

#[tauri::command]
pub fn import_return_file<R: Runtime>(
    handle: AppHandle<R>,
    path: String,
) -> Result<ReturnFileImportResult, BundleError> {
    let app_data = app_data_dir(&handle)?;
    let mut conn = open_conn(&app_data)?;
    let parsed = read_return_file(Path::new(&path))?;
    pure_import_return_file(&mut conn, &path, &parsed.source_sha, &parsed.report)
}

#[tauri::command]
pub fn get_bundle_postings<R: Runtime>(
    handle: AppHandle<R>,
    bundle_uid: String,
) -> Result<Vec<BundlePostingDto>, BundleError> {
    let app_data = app_data_dir(&handle)?;
    let conn = open_conn(&app_data)?;
    list_postings_for_bundle(&conn, &bundle_uid)
}

#[tauri::command]
pub fn reveal_post_bundles_dir() -> Result<(), BundleError> {
    let dir = default_drop_dir();
    if !dir.exists() {
        fs::create_dir_all(&dir)?;
    }
    fsutil::reveal_in_file_browser(&dir)
        .map_err(|e| BundleError::Io(std::io::Error::other(format!("reveal: {e}"))))
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
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
            include_str!("../migrations/021_keystore_stay_unlocked.sql"),
            include_str!("../migrations/022_job_run_log_path.sql"),
            include_str!("../migrations/023_notes.sql"),
            include_str!("../migrations/024_note_font_size.sql"),
            include_str!("../migrations/025_holidays.sql"),
            include_str!("../migrations/026_content_tags.sql"),
            include_str!("../migrations/027_fanday_tags.sql"),
            include_str!("../migrations/028_clip_tags.sql"),
            include_str!("../migrations/029_subreddits.sql"),
            include_str!("../migrations/030_hours.sql"),
            include_str!("../migrations/031_daily_tasks.sql"),
            include_str!("../migrations/032_drop_content_release_defaults.sql"),
            include_str!("../migrations/033_ui_theme.sql"),
            include_str!("../migrations/034_return_file_import.sql"),
        ] {
            conn.execute_batch(sql).unwrap();
        }
        conn
    }

    fn seed_published_bundle(conn: &Connection, uid: &str, bundle_type: &str) {
        conn.execute(
            "INSERT INTO bundles
                (uid, bundle_type, state, title, content_date, go_live_date,
                 published_at, bundle_path)
             VALUES (?1, ?2, 'published', 'Test Bundle', '2026-05-20', '2026-05-25',
                     '2026-05-21T00:00:00Z', '/tmp/dummy.zip')",
            params![uid, bundle_type],
        ).unwrap();
        conn.execute(
            "INSERT INTO bundle_files
                (bundle_uid, fansite_day_id, position, relpath, original_name, kind,
                 size_bytes, sha256)
             VALUES (?1, NULL, 1, 'Video/00001_my-clip.mp4', 'my-clip.mp4', 'video', 1024, 'abc')",
            params![uid],
        ).unwrap();
    }

    fn seed_clip(conn: &Connection, id: &str, title: &str) {
        conn.execute(
            "INSERT INTO clips (id, external_clip_id, persona_code, title, status,
                                content_date, length, price, categories,
                                keywords, performers, notes, molly_notes_html, imported_at)
             VALUES (?1, ?2, NULL, ?3, 'Bundled', '2026-05-20', '00:05:00',
                     '$5.00', '', '', '', '', '', datetime('now'))",
            params![id, id, title],
        ).unwrap();
    }

    fn fixture_report(uid: &str, bundle_type: &str) -> Report {
        Report {
            report_version: 1,
            bundle_uid: uid.into(),
            bundle_type: bundle_type.into(),
            persona_code: None,
            report_composed_at: "2026-05-25T18:42:00Z".into(),
            bundle_state: "shipped".into(),
            targets: vec![ReportTarget {
                target_id: "c4s".into(),
                target_name: "Clips4Sale".into(),
                state: "posted".into(),
                posted_at: Some("2026-05-25T17:00:00Z".into()),
                posted_url: Some("https://c4s.example/abc".into()),
                body_override: None,
                files_used: vec!["Video/00001_my-clip.mp4".into()],
                notes: None,
                fansite_day: None,
            }],
            bundle_level_notes: None,
        }
    }

    #[test]
    fn filename_stem_strips_extension_and_position_prefix() {
        assert_eq!(filename_stem_for_match("Video/00001_my-clip.mp4"), "my-clip");
        assert_eq!(filename_stem_for_match("Photos/00012_lookbook.jpg"), "lookbook");
        assert_eq!(filename_stem_for_match("FanSite/12_03_dayfile.mp4"), "dayfile");
        assert_eq!(filename_stem_for_match("clip-only.mp4"), "clip-only");
        assert_eq!(filename_stem_for_match("no_ext"), "no_ext"); // no digit-prefix → not stripped
        assert_eq!(filename_stem_for_match("00001_MIXEDcase.MP4"), "mixedcase");
    }

    #[test]
    fn resolve_clip_matches_id_then_external_id_then_title() {
        let conn = fresh_db();
        seed_clip(&conn, "MJP1234", "My Hot Clip");

        assert_eq!(
            resolve_clip_for_stem(&conn, "mjp1234").unwrap().map(|(id, _)| id),
            Some("MJP1234".into()),
        );
        // Title match (case-insensitive) — note we look up the lowercase stem.
        assert_eq!(
            resolve_clip_for_stem(&conn, "my hot clip").unwrap().map(|(id, _)| id),
            Some("MJP1234".into()),
        );
        assert!(resolve_clip_for_stem(&conn, "no-such-clip").unwrap().is_none());
        assert!(resolve_clip_for_stem(&conn, "").unwrap().is_none());
    }

    #[test]
    fn import_records_posting_and_links_matched_clip() {
        let mut conn = fresh_db();
        seed_published_bundle(&conn, "2026-05-20-0001", "content");
        seed_clip(&conn, "my-clip", "My Clip Title");

        let report = fixture_report("2026-05-20-0001", "content");
        let result = pure_import_return_file(&mut conn, "/tmp/u-post.zip", "deadbeef", &report).unwrap();

        assert_eq!(result.bundle_uid, "2026-05-20-0001");
        assert_eq!(result.bundle_type, "content");
        assert!(!result.was_duplicate);
        assert_eq!(result.postings.len(), 1);
        assert_eq!(result.postings[0].state, "posted");
        assert_eq!(result.postings[0].files.len(), 1);
        assert_eq!(result.postings[0].files[0].clip_id.as_deref(), Some("my-clip"));
        assert_eq!(result.matched_file_count, 1);
        assert_eq!(result.total_file_count, 1);
        assert!(!result.bundle_already_purged);
        assert!(result.delete_after.is_some());

        // The bundle row was stamped.
        let (completed_at, delete_after): (Option<String>, Option<String>) = conn
            .query_row(
                "SELECT completed_at, delete_after FROM bundles WHERE uid = ?1",
                params!["2026-05-20-0001"],
                |r| Ok((r.get(0)?, r.get(1)?)),
            ).unwrap();
        assert!(completed_at.is_some());
        assert!(delete_after.is_some());

        // Mollys_log entry was added.
        let log_rows: i64 = conn
            .query_row("SELECT COUNT(*) FROM mollys_log", [], |r| r.get(0))
            .unwrap();
        assert_eq!(log_rows, 1);
    }

    #[test]
    fn import_unmatched_file_records_null_clip_id() {
        let mut conn = fresh_db();
        seed_published_bundle(&conn, "2026-05-20-0002", "content");
        // No matching clip seeded.

        let report = fixture_report("2026-05-20-0002", "content");
        let result = pure_import_return_file(&mut conn, "/tmp/u-post.zip", "cafe1234", &report).unwrap();

        assert_eq!(result.matched_file_count, 0);
        assert_eq!(result.total_file_count, 1);
        assert!(result.postings[0].files[0].clip_id.is_none());
    }

    #[test]
    fn import_is_idempotent_by_source_sha() {
        let mut conn = fresh_db();
        seed_published_bundle(&conn, "2026-05-20-0003", "content");
        seed_clip(&conn, "my-clip", "My Clip Title");

        let report = fixture_report("2026-05-20-0003", "content");
        let _first = pure_import_return_file(&mut conn, "/tmp/u-post.zip", "sha-abc", &report).unwrap();
        let second = pure_import_return_file(&mut conn, "/tmp/u-post.zip", "sha-abc", &report).unwrap();

        assert!(second.was_duplicate);
        // No duplicate bundle_postings.
        let row_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM bundle_postings WHERE bundle_uid = ?1",
                params!["2026-05-20-0003"],
                |r| r.get(0),
            ).unwrap();
        assert_eq!(row_count, 1);
        // Only one journal entry.
        let log_count: i64 = conn
            .query_row("SELECT COUNT(*) FROM mollys_log", [], |r| r.get(0))
            .unwrap();
        assert_eq!(log_count, 1);
    }

    #[test]
    fn import_fansite_does_not_write_to_clips() {
        let mut conn = fresh_db();
        // Seed a fansite bundle with a per-day file (file id 1).
        conn.execute(
            "INSERT INTO bundles
                (uid, bundle_type, state, title, content_date,
                 fansite_year, fansite_month,
                 published_at, bundle_path)
             VALUES ('2026-05-01-0001', 'fansite', 'published', 'May 2026', '2026-05-01',
                     2026, 5,
                     '2026-05-01T00:00:00Z', '/tmp/dummy.zip')",
            [],
        ).unwrap();
        conn.execute(
            "INSERT INTO bundle_fan_days (bundle_uid, day_of_month, message)
             VALUES ('2026-05-01-0001', 12, 'a message')",
            [],
        ).unwrap();
        let day_id: i64 = conn
            .query_row("SELECT last_insert_rowid()", [], |r| r.get(0))
            .unwrap();
        conn.execute(
            "INSERT INTO bundle_files (bundle_uid, fansite_day_id, position, relpath, original_name, kind, size_bytes, sha256)
             VALUES ('2026-05-01-0001', ?1, 1, 'FanSite/12_01_daypic.jpg', 'daypic.jpg', 'image', 100, 'abc')",
            params![day_id],
        ).unwrap();
        seed_clip(&conn, "daypic", "Should Not Link");

        let mut report = fixture_report("2026-05-01-0001", "fansite");
        report.targets[0].files_used = vec!["FanSite/12_01_daypic.jpg".into()];
        report.targets[0].fansite_day = Some(12);

        let result = pure_import_return_file(&mut conn, "/tmp/u-post.zip", "sha-fan", &report).unwrap();
        assert_eq!(result.bundle_type, "fansite");
        assert_eq!(result.postings.len(), 1);
        assert_eq!(result.postings[0].fansite_day, Some(12));
        // FanSite never writes clip_id.
        assert!(result.postings[0].files[0].clip_id.is_none());
        assert_eq!(result.matched_file_count, 0);
    }

    #[test]
    fn import_rejects_unknown_bundle_uid() {
        let mut conn = fresh_db();
        let report = fixture_report("2099-12-31-9999", "content");
        let err = pure_import_return_file(&mut conn, "/tmp/u-post.zip", "missing", &report).unwrap_err();
        match err {
            BundleError::NotFound(_) => {}
            other => panic!("expected NotFound, got {other:?}"),
        }
    }

    #[test]
    fn import_surfaces_type_mismatch_without_blocking() {
        let mut conn = fresh_db();
        seed_published_bundle(&conn, "2026-05-20-0004", "content");
        // Return file claims fansite even though Molly stored it as content.
        // Import should proceed (the report describes what got posted) and
        // surface the divergence in the result.
        let report = fixture_report("2026-05-20-0004", "fansite");
        let result = pure_import_return_file(&mut conn, "/tmp/u-post.zip", "mismatch", &report).unwrap();
        assert_eq!(result.reported_bundle_type.as_deref(), Some("fansite"));
        assert_eq!(result.bundle_type, "content"); // stored is the canonical answer
        assert_eq!(result.postings.len(), 1);
    }

    #[test]
    fn import_on_purged_bundle_skips_delete_after() {
        let mut conn = fresh_db();
        conn.execute(
            "INSERT INTO bundles
                (uid, bundle_type, state, title, content_date, go_live_date,
                 published_at, bundle_path, completed_at, delete_after)
             VALUES ('2026-05-20-0005', 'content', 'purged', 'Old', '2026-05-20',
                     '2026-05-25', '2026-05-21T00:00:00Z', NULL, NULL, NULL)",
            [],
        ).unwrap();
        // Add a fake bundle_files row so files_used can resolve.
        conn.execute(
            "INSERT INTO bundle_files (bundle_uid, position, relpath, original_name, kind, size_bytes, sha256)
             VALUES ('2026-05-20-0005', 1, 'Video/00001_x.mp4', 'x.mp4', 'video', 0, '')",
            [],
        ).unwrap();
        let mut report = fixture_report("2026-05-20-0005", "content");
        report.targets[0].files_used = vec!["Video/00001_x.mp4".into()];

        let result = pure_import_return_file(&mut conn, "/tmp/u.zip", "purged", &report).unwrap();
        assert!(result.bundle_already_purged);
        assert!(result.delete_after.is_none());
    }
}
