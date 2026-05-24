// Phase 11 — compose a deterministic post-bundle ZIP back to Molly.
//
// Layout (mirrors Molly's outbound bundle pattern):
//
//   <UID>-post.zip                      (outer)
//   ├── <UID>-post-inner.zip            (inner — MS-DOS epoch, sorted entries)
//   │   ├── report.json                 (structured posting outcomes per §9.2)
//   │   ├── notes.md                    (Robert's freeform notes; empty allowed)
//   │   ├── processing.log              (optional — auto-included when present)
//   │   └── artifacts/
//   │       ├── transcripts/<stem>.txt + .srt   (if generated in Phase 5)
//   │       └── thumbnails/<stem>.jpg            (per-file thumbnails)
//   └── hashes.json                     (inner-zip hash + per-entry hashes)
//
// Determinism: every zip entry's mtime is set to the MS-DOS epoch
// (1980-01-01 00:00:00) and entries are written in sorted-name order
// so re-runs against the same source data produce byte-identical
// outputs. Matches Molly's bundle_zip.rs exactly so the round-trip
// is bit-stable and signable.
//
// Drop location: ~/Downloads/Molly post-bundles/ (sibling to the
// inbound ~/Downloads/Molly bundles/). User can override via Settings;
// the default convention is documented in CLAUDE.md.
//
// Trigger surfaces:
//   - Manual: 📤 Send to Molly button in the bundle workspace header
//     (always available, even on partial-state postings).
//   - Auto-on-shipped (deferred): once every target is posted/skipped
//     AND bundle_state flips to 'shipped', compose runs inside a job
//     with a 5-second undo banner. Land this in v0.16.x once the
//     plain manual path is happy.

use std::collections::BTreeMap;
use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tauri::{AppHandle, Manager, Runtime};
use zip::write::SimpleFileOptions;

use crate::bundles::{work_root, BundleError};
use crate::extract::bundle_workspace_dir;

// MS-DOS zip epoch — 1980-01-01 00:00:00 — earliest representable in
// the legacy zip header timestamp field. Used on every entry for
// byte-identical re-runs.
fn dos_epoch() -> zip::DateTime {
    zip::DateTime::from_date_and_time(1980, 1, 1, 0, 0, 0)
        .expect("MS-DOS epoch is a valid zip DateTime")
}

// ---------------------------------------------------------------------------
// report.json schema (per PLAN.md §9.2)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReportTarget {
    pub target_id: String,        // posting_targets.name (stable across Molly imports)
    pub target_name: String,
    pub state: String,            // pending|scheduled|posted|skipped
    pub posted_at: Option<String>,
    pub posted_url: Option<String>,
    pub body_override: Option<String>,
    pub files_used: Vec<String>,  // bundle-relative paths the user attached
    pub notes: Option<String>,
    pub fansite_day: Option<i64>, // only set for FanSite per-day rows
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Report {
    pub report_version: i64,
    pub bundle_uid: String,
    pub bundle_type: String,
    pub persona_code: Option<String>,
    pub report_composed_at: String,   // RFC3339 UTC
    pub bundle_state: String,
    pub targets: Vec<ReportTarget>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bundle_level_notes: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ComposeResult {
    pub bundle_uid: String,
    pub output_path: String,
    pub inner_zip_sha256: String,
    pub outer_zip_sha256: String,
    pub target_count: i64,
    pub artifact_count: i64,
    pub bytes_written: i64,
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

/// Default drop directory: sibling to the inbound ~/Downloads/Molly
/// bundles/ folder Molly drops her bundles into. Created on demand;
/// Robert can override via Settings → Watched folder (Phase 11 reuses
/// that path-picker UI rather than adding yet another settings tab).
pub fn default_drop_dir() -> PathBuf {
    if let Some(home) = dirs::home_dir() {
        home.join("Downloads").join("Molly post-bundles")
    } else {
        PathBuf::from("./Molly post-bundles")
    }
}

// ---------------------------------------------------------------------------
// Compose command
// ---------------------------------------------------------------------------

#[tauri::command]
pub fn compose_post_bundle<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<ComposeResult, BundleError> {
    let conn = open_conn(&handle)?;

    // Build the report in-memory from current DB state.
    let report = build_report(&conn, &uid)?;
    let report_json = serde_json::to_string_pretty(&report)
        .map_err(|e| BundleError::Io(std::io::Error::other(format!("report serialize: {e}"))))?;
    let notes_md = "".to_string();  // Phase 11 ships empty; UI can populate later.

    // Collect artifacts: transcripts + per-file thumbnails. Keyed by
    // their in-zip path so the BTreeMap ordering drives deterministic
    // entry order.
    let mut artifacts: BTreeMap<String, Vec<u8>> = BTreeMap::new();
    collect_artifacts(&handle, &conn, &uid, &mut artifacts)?;

    // Optional: include the per-bundle processing log if the user
    // exported it (Phase 5 follow-up). Detect by file presence.
    let workspace = bundle_workspace_dir(&work_root(&handle)?, &uid);
    let log_path = workspace.join("processing.log");
    let log_bytes = if log_path.exists() {
        fs::read(&log_path).ok()
    } else {
        None
    };

    // ── Inner ZIP (deterministic) ────────────────────────────────────
    let mut inner_buf: Vec<u8> = Vec::new();
    {
        let cursor = std::io::Cursor::new(&mut inner_buf);
        let mut zip = zip::ZipWriter::new(cursor);
        let opts = SimpleFileOptions::default()
            .compression_method(zip::CompressionMethod::Deflated)
            .unix_permissions(0o644)
            .last_modified_time(dos_epoch());

        // Sorted-by-name iteration via BTreeMap. report.json first
        // (per the §9.1 layout convention), then notes.md, then
        // processing.log if present, then artifacts/* alphabetically.
        zip.start_file("report.json", opts)?;
        zip.write_all(report_json.as_bytes())?;

        zip.start_file("notes.md", opts)?;
        zip.write_all(notes_md.as_bytes())?;

        if let Some(log) = &log_bytes {
            zip.start_file("processing.log", opts)?;
            zip.write_all(log)?;
        }

        // artifacts/ directory entry first (zip convention; some tools
        // refuse to extract a tree without explicit directory markers).
        if !artifacts.is_empty() {
            zip.add_directory("artifacts/", opts)?;
            // Group by subdirectory for explicit dir entries.
            let mut emitted_dirs: std::collections::HashSet<String> =
                std::collections::HashSet::new();
            for (path, _) in &artifacts {
                if let Some((dir, _)) = path.rsplit_once('/') {
                    if emitted_dirs.insert(dir.to_string()) {
                        zip.add_directory(format!("{dir}/"), opts)?;
                    }
                }
            }
            for (path, bytes) in &artifacts {
                zip.start_file(path, opts)?;
                zip.write_all(bytes)?;
            }
        }
        zip.finish()?;
    }

    let inner_zip_name = format!("{uid}-post-inner.zip");
    let inner_sha = sha256_hex(&inner_buf);

    // ── hashes.json — same shape as inbound bundles (see bundle_io.rs).
    // Per-entry hashes mirror the inner zip's file list.
    let mut files_for_hashes: Vec<HashesFile> = Vec::new();
    files_for_hashes.push(HashesFile {
        path: "report.json".into(),
        sha256: sha256_hex(report_json.as_bytes()),
    });
    files_for_hashes.push(HashesFile {
        path: "notes.md".into(),
        sha256: sha256_hex(notes_md.as_bytes()),
    });
    if let Some(log) = &log_bytes {
        files_for_hashes.push(HashesFile {
            path: "processing.log".into(),
            sha256: sha256_hex(log),
        });
    }
    for (path, bytes) in &artifacts {
        files_for_hashes.push(HashesFile {
            path: path.clone(),
            sha256: sha256_hex(bytes),
        });
    }
    files_for_hashes.sort_by(|a, b| a.path.cmp(&b.path));
    let hashes = HashesDoc {
        bundle_uid: uid.clone(),
        inner_zip: HashesInnerZip {
            name: inner_zip_name.clone(),
            sha256: inner_sha.clone(),
            bytes: inner_buf.len() as u64,
        },
        files: files_for_hashes,
    };
    let hashes_json = serde_json::to_string_pretty(&hashes)
        .map_err(|e| BundleError::Io(std::io::Error::other(format!("hashes serialize: {e}"))))?;

    // ── Outer ZIP ─────────────────────────────────────────────────────
    let drop_dir = default_drop_dir();
    fs::create_dir_all(&drop_dir)?;
    let out_path = drop_dir.join(format!("{uid}-post.zip"));
    let tmp_path = out_path.with_extension("zip.tmp");

    {
        let file = fs::File::create(&tmp_path)?;
        let mut zip = zip::ZipWriter::new(file);
        let opts = SimpleFileOptions::default()
            .compression_method(zip::CompressionMethod::Stored)  // inner is already deflated
            .unix_permissions(0o644)
            .last_modified_time(dos_epoch());

        // hashes.json + inner.zip — sorted by name so re-runs are
        // bit-stable. Inner zip comes after hashes alphabetically:
        //   <UID>-post-inner.zip
        //   hashes.json
        // ...so they actually sort the OTHER way (capital `2` < `h`).
        // Just write both in the canonical hashes-then-inner order
        // the spec uses; verifiers don't care about zip entry order.
        zip.start_file("hashes.json", opts)?;
        zip.write_all(hashes_json.as_bytes())?;

        zip.start_file(&inner_zip_name, opts)?;
        zip.write_all(&inner_buf)?;

        zip.finish()?;
    }

    let outer_bytes = fs::read(&tmp_path)?;
    let outer_sha = sha256_hex(&outer_bytes);

    // Atomic replace.
    if out_path.exists() { let _ = fs::remove_file(&out_path); }
    fs::rename(&tmp_path, &out_path)?;

    // Log to processing_log.
    crate::processing_log::write(
        &conn, Some(&uid), None, Some("post_bundle"),
        crate::processing_log::Level::Info,
        &format!("composed post-bundle ({} targets, {} artifacts, {} bytes)",
                 report.targets.len(), artifacts.len(), outer_bytes.len()),
        Some(&out_path.to_string_lossy()),
        None,
    );

    Ok(ComposeResult {
        bundle_uid: uid,
        output_path: out_path.to_string_lossy().to_string(),
        inner_zip_sha256: inner_sha,
        outer_zip_sha256: outer_sha,
        target_count: report.targets.len() as i64,
        artifact_count: artifacts.len() as i64,
        bytes_written: outer_bytes.len() as i64,
    })
}

#[tauri::command]
pub fn reveal_post_bundle<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<(), BundleError> {
    let _ = handle;
    let out_path = default_drop_dir().join(format!("{uid}-post.zip"));
    if !out_path.exists() {
        return Err(BundleError::NotFound(format!(
            "{} — compose the post-bundle first", out_path.display(),
        )));
    }
    crate::fsutil::reveal_in_file_browser(&out_path)?;
    Ok(())
}

/// Status of a bundle's post-bundle output — used by the UI to flip
/// the header button between "📤 Send to Molly" and "✓ Sent (123KB)".
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PostBundleStatus {
    pub bundle_uid: String,
    pub output_path: String,
    pub exists: bool,
    pub size_bytes: i64,
    pub modified_at: Option<String>,
}

#[tauri::command]
pub fn get_post_bundle_status<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<PostBundleStatus, BundleError> {
    let _ = handle;
    let out_path = default_drop_dir().join(format!("{uid}-post.zip"));
    let (exists, size_bytes, modified_at) = match fs::metadata(&out_path) {
        Ok(m) => {
            let modified = m.modified().ok()
                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                .and_then(|d| chrono::DateTime::<chrono::Utc>::from_timestamp(d.as_secs() as i64, 0))
                .map(|dt| dt.format("%Y-%m-%d %H:%M:%S UTC").to_string());
            (true, m.len() as i64, modified)
        }
        Err(_) => (false, 0, None),
    };
    Ok(PostBundleStatus {
        bundle_uid: uid,
        output_path: out_path.to_string_lossy().to_string(),
        exists, size_bytes, modified_at,
    })
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HashesInnerZip {
    name: String,
    sha256: String,
    bytes: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HashesFile {
    path: String,
    sha256: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HashesDoc {
    bundle_uid: String,
    inner_zip: HashesInnerZip,
    files: Vec<HashesFile>,
}

fn sha256_hex(bytes: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(bytes);
    format!("{:x}", h.finalize())
}

fn open_conn<R: Runtime>(handle: &AppHandle<R>) -> Result<Connection, BundleError> {
    let dir = handle.path()
        .resolve("", tauri::path::BaseDirectory::AppLocalData)
        .map_err(|e| BundleError::Io(std::io::Error::other(format!("appdata path: {e}"))))?;
    Ok(Connection::open(dir.join("sidemolly.db"))?)
}

fn build_report(conn: &Connection, uid: &str) -> Result<Report, BundleError> {
    let row: Option<(String, Option<String>, String)> = conn.query_row(
        "SELECT bundle_type, persona_code, bundle_state
           FROM bundles WHERE uid = ?1",
        params![uid],
        |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
    ).optional()?;
    let (bundle_type, persona_code, bundle_state) = row
        .ok_or_else(|| BundleError::NotFound(format!("bundle {uid}")))?;

    let mut stmt = conn.prepare(
        "SELECT pt.name, pt.name, bp.state, bp.posted_at, bp.posted_url,
                bp.body_override, bp.selected_assets_json, bp.notes, bp.fansite_day
           FROM bundle_postings bp
           JOIN posting_targets pt ON pt.id = bp.target_id
          WHERE bp.bundle_uid = ?1
          ORDER BY pt.position, pt.name, bp.fansite_day",
    )?;
    let rows: Vec<(String, String, String, Option<String>, Option<String>, Option<String>, String, Option<String>, Option<i64>)> =
        stmt.query_map(params![uid], |r| Ok((
            r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?,
            r.get(5)?, r.get(6)?, r.get(7)?, r.get(8)?,
        )))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    drop(stmt);

    let mut targets: Vec<ReportTarget> = Vec::with_capacity(rows.len());
    for (target_id, target_name, state, posted_at, posted_url, body_override,
         selected_assets_json, notes, fansite_day) in rows {
        // Parse the assets-used JSON into a list of bundle-relative
        // paths. Robust against the legacy `[]` default.
        let files_used: Vec<String> = serde_json::from_str::<Vec<serde_json::Value>>(&selected_assets_json)
            .ok()
            .map(|arr| arr.into_iter()
                .filter_map(|v| v.get("path").and_then(|p| p.as_str()).map(String::from))
                .collect())
            .unwrap_or_default();
        targets.push(ReportTarget {
            target_id, target_name, state,
            posted_at, posted_url, body_override, files_used, notes,
            fansite_day,
        });
    }

    Ok(Report {
        report_version: 1,
        bundle_uid: uid.to_string(),
        bundle_type,
        persona_code,
        report_composed_at: chrono::Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        bundle_state,
        targets,
        bundle_level_notes: None,
    })
}

fn collect_artifacts<R: Runtime>(
    handle: &AppHandle<R>,
    _conn: &Connection,
    uid: &str,
    out: &mut BTreeMap<String, Vec<u8>>,
) -> Result<(), BundleError> {
    let workspace = bundle_workspace_dir(&work_root(handle)?, uid);

    // Transcripts (Phase 5 sidecars). Skip .json — too detailed for
    // Molly's "Posted to" view + already covered by the report's
    // `filesUsed` field when relevant.
    let tx_dir = workspace.join("transcripts");
    if tx_dir.is_dir() {
        if let Ok(entries) = fs::read_dir(&tx_dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if !path.is_file() { continue; }
                let Some(ext) = path.extension().and_then(|s| s.to_str()) else { continue };
                if ext != "txt" && ext != "srt" { continue; }
                let name = path.file_name().and_then(|s| s.to_str()).unwrap_or("");
                if let Ok(bytes) = fs::read(&path) {
                    out.insert(format!("artifacts/transcripts/{name}"), bytes);
                }
            }
        }
    }

    // Per-file thumbnails (Phase 1c). Locked-in payload per §9.1.
    // Files live in `<workspace>/thumbs/<stem>.jpg`.
    let thumb_dir = workspace.join("thumbs");
    if thumb_dir.is_dir() {
        if let Ok(entries) = fs::read_dir(&thumb_dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if !path.is_file() { continue; }
                let Some(ext) = path.extension().and_then(|s| s.to_str()) else { continue };
                if ext != "jpg" && ext != "jpeg" { continue; }
                let name = path.file_name().and_then(|s| s.to_str()).unwrap_or("");
                if let Ok(bytes) = fs::read(&path) {
                    out.insert(format!("artifacts/thumbnails/{name}"), bytes);
                }
            }
        }
    }

    Ok(())
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn report_serializes_to_camel_case() {
        let r = Report {
            report_version: 1,
            bundle_uid: "u".into(),
            bundle_type: "content".into(),
            persona_code: Some("CoC".into()),
            report_composed_at: "2026-05-25T18:42:00Z".into(),
            bundle_state: "shipped".into(),
            targets: vec![ReportTarget {
                target_id: "c4s".into(),
                target_name: "Clips4Sale".into(),
                state: "posted".into(),
                posted_at: Some("2026-05-23T14:22:00Z".into()),
                posted_url: Some("https://example.com/x".into()),
                body_override: None,
                files_used: vec!["a.mp4".into()],
                notes: None,
                fansite_day: None,
            }],
            bundle_level_notes: None,
        };
        let json = serde_json::to_string(&r).unwrap();
        assert!(json.contains("\"reportVersion\":1"), "{json}");
        assert!(json.contains("\"bundleUid\""), "{json}");
        assert!(json.contains("\"reportComposedAt\""), "{json}");
        assert!(json.contains("\"filesUsed\""), "{json}");
        assert!(json.contains("\"fansiteDay\""), "{json}");
    }

    #[test]
    fn dos_epoch_is_jan_1_1980() {
        let e = dos_epoch();
        assert_eq!(e.year(), 1980);
        assert_eq!(e.month(), 1);
        assert_eq!(e.day(), 1);
        assert_eq!(e.hour(), 0);
    }

    #[test]
    fn sha256_hex_is_lowercase_64_chars() {
        let s = sha256_hex(b"hello");
        assert_eq!(s.len(), 64);
        assert!(s.chars().all(|c| c.is_ascii_hexdigit() && (!c.is_alphabetic() || c.is_lowercase())));
    }
}
