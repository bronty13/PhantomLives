// Phase 6 — local Dropbox-folder copy.
//
// "Dropbox" here is just the local sync folder (~/Dropbox by default).
// We never touch the HTTP API — files land on disk, the Dropbox app
// syncs them up. Locked-in decision #11 (PLAN.md §12).
//
// Per Robert's direction 2026-05-24, the destination layout is FLAT
// per bundle:
//
//   <root>/YYYY-MM-DD <Title>/
//       01_01_xxx__watermark_strip.jpg
//       02_01_xxx__watermark_strip.jpg
//       …
//       30_01_xxx__video_watermark_strip.mp4
//       master.mp4
//       30_01_xxx.txt
//       30_01_xxx.srt
//
// Everything sits at the bundle-folder root, no per-kind subfolders.
//
// Idempotency: each (bundle_uid, source_path, dropbox_path) tuple gets
// one row in dropbox_copies, recording the source's sha256 at copy
// time. Re-running the copy command re-hashes the source and skips
// when the recorded sha matches — so a 50-file bundle that's only had
// 3 files touched only re-copies those 3.
//
// Verify-on-write: after copying, we re-hash the destination and
// compare against the source hash. Mismatches surface as a failed
// verify in the result row.

use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tauri::{AppHandle, Manager, Runtime};

use crate::bundles::{work_root, BundleError};
use crate::extract::bundle_workspace_dir;

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DropboxSettings {
    pub root_path: String,
    pub template: String,
}

impl DropboxSettings {
    pub fn load(conn: &Connection) -> Result<Self, BundleError> {
        let row = conn.query_row(
            "SELECT root_path, template FROM dropbox_settings WHERE id = 1",
            [],
            |r| Ok(Self {
                root_path: r.get(0)?,
                template: r.get(1)?,
            }),
        )?;
        Ok(row)
    }
}

/// Best-effort default Dropbox root path. macOS users typically have
/// `~/Dropbox/`; we suggest it on first load so the user just clicks
/// Save without having to file-pick. They can override via Settings.
pub fn default_dropbox_root() -> Option<String> {
    let home = dirs::home_dir()?;
    let candidate = home.join("Dropbox");
    if candidate.is_dir() {
        return Some(candidate.to_string_lossy().to_string());
    }
    // Some macOS Dropbox installs use ~/Library/CloudStorage/Dropbox.
    let cs = home.join("Library/CloudStorage").join("Dropbox");
    if cs.is_dir() {
        return Some(cs.to_string_lossy().to_string());
    }
    None
}

#[tauri::command]
pub fn get_dropbox_settings<R: Runtime>(
    handle: AppHandle<R>,
) -> Result<DropboxSettings, BundleError> {
    let conn = open_conn(&handle)?;
    let mut s = DropboxSettings::load(&conn)?;
    // First-load convenience: when the user hasn't set anything yet,
    // populate root_path with the auto-detected default if available.
    if s.root_path.is_empty() {
        if let Some(d) = default_dropbox_root() {
            s.root_path = d;
        }
    }
    Ok(s)
}

#[tauri::command]
pub fn set_dropbox_settings<R: Runtime>(
    handle: AppHandle<R>,
    settings: DropboxSettings,
) -> Result<(), BundleError> {
    let conn = open_conn(&handle)?;
    conn.execute(
        "UPDATE dropbox_settings
            SET root_path = ?1, template = ?2, updated_at = datetime('now')
            WHERE id = 1",
        params![settings.root_path, settings.template],
    )?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Template resolution
// ---------------------------------------------------------------------------

/// Resolve the bundle's destination folder name from the template.
/// Template variables:
///
///   {date}     — bundle's ingested_at date, YYYY-MM-DD
///   {title}    — bundle.title, sanitized for filesystem (replaces
///                slashes, colons, etc. with `-`)
///   {uid}      — bundle.uid (e.g. "2026-05-22-0002")
///   {persona}  — bundle.persona_code (or "nopersona" when null)
///
/// Robert's default is `{date} {title}` — a date-prefixed flat
/// layout (e.g. `2025-12-31 Mary Poppins`) that sorts naturally in
/// Finder.
fn resolve_folder_name(template: &str, b: &BundleResolution) -> String {
    let date_str = extract_date(&b.ingested_at);
    let title = sanitize_filename(&b.title);
    let persona = b.persona_code.as_deref().unwrap_or("nopersona");
    let mut out = template.to_string();
    out = out.replace("{date}", &date_str);
    out = out.replace("{title}", &title);
    out = out.replace("{uid}", &b.uid);
    out = out.replace("{persona}", persona);
    // Filename-safety on the final result too — template could
    // include literal slashes the user didn't intend as path separators.
    sanitize_filename(&out)
}

/// Take `2026-05-22 18:34:21` → `2026-05-22`. Falls back to whatever
/// prefix we can find (`bundles.ingested_at` is always present and
/// always starts with the date when stored via `datetime('now')`).
fn extract_date(timestamp: &str) -> String {
    timestamp.split(' ').next().unwrap_or(timestamp).to_string()
}

/// Replace filesystem-hostile chars with `-`. We're permissive on
/// purpose — Robert's bundle titles like "and before too soon it was
/// JUNE" should pass through nearly unchanged.
fn sanitize_filename(s: &str) -> String {
    s.chars().map(|c| match c {
        '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' | '\0' => '-',
        // Keep printable ASCII + common punctuation + spaces + unicode.
        c if c.is_control() => '-',
        c => c,
    }).collect::<String>().trim().to_string()
}

// ---------------------------------------------------------------------------
// Dry-run + copy
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DryRunRow {
    pub source_path: String,
    pub source_sha256: String,
    pub source_size_bytes: i64,
    pub dropbox_path: String,
    pub destination_name: String,
    /// Category for the UI grouping. "image" / "video" / "master" /
    /// "transcript-txt" / "transcript-srt" / "transcript-json".
    pub kind: String,
    /// "new" — never copied. "skip" — already at dropbox_path with
    /// matching sha. "changed" — present but sha differs (will
    /// overwrite). "missing" — listed in DB but file not on disk.
    pub status: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DryRunSummary {
    pub bundle_uid: String,
    pub root_configured: bool,
    pub dropbox_root: String,
    pub destination_dir: String,
    pub items: Vec<DryRunRow>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CopyResultRow {
    pub source_path: String,
    pub dropbox_path: String,
    pub status: String,        // "copied" | "skipped" | "failed"
    pub verified: bool,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CopyResultSummary {
    pub bundle_uid: String,
    pub destination_dir: String,
    pub copied: i64,
    pub skipped: i64,
    pub failed: i64,
    pub items: Vec<CopyResultRow>,
}

struct BundleResolution {
    uid: String,
    title: String,
    persona_code: Option<String>,
    ingested_at: String,
}

fn resolve_bundle(conn: &Connection, uid: &str) -> Result<BundleResolution, BundleError> {
    conn.query_row(
        "SELECT uid, COALESCE(title, ''), persona_code, ingested_at
           FROM bundles WHERE uid = ?1",
        params![uid],
        |r| Ok(BundleResolution {
            uid: r.get(0)?,
            title: r.get(1)?,
            persona_code: r.get(2)?,
            ingested_at: r.get(3)?,
        }),
    ).optional()?
        .ok_or_else(|| BundleError::NotFound(format!("bundle {uid}")))
}

/// Collect the artifact(s) we ship to Dropbox for this bundle.
///
/// **Only the assembled master cut.** Per Robert's 2026-06-01 request,
/// Distribute → Copy to Dropbox ships *only* the final assembled video —
/// not the redundant per-clip processed videos (already folded into the
/// master), the processed images, or the transcript sidecars. Those still
/// live in the bundle workspace; they're just not pushed to Dropbox.
///
/// Returns (source_path, destination_filename, kind) tuples — at most one
/// entry (the master), or empty when no master cut has been assembled yet.
fn enumerate_artifacts<R: Runtime>(
    handle: &AppHandle<R>,
    conn: &Connection,
    uid: &str,
) -> Result<Vec<(PathBuf, String, String)>, BundleError> {
    let mut out: Vec<(PathBuf, String, String)> = Vec::new();

    // Master cut — the assembled file, and the only thing we copy.
    let workspace = bundle_workspace_dir(&work_root(handle)?, uid);
    let title = crate::bundles::fetch_bundle_title(conn, uid)?;
    let master = crate::bundles::resolve_master_cut_path(&workspace, &title);
    if master.exists() {
        let name = master.file_name()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| "master.mp4".into());
        out.push((master, name, "master".into()));
    }

    Ok(out)
}

fn sha256_file(path: &Path) -> std::io::Result<String> {
    let mut file = fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 65536];
    loop {
        let n = file.read(&mut buf)?;
        if n == 0 { break; }
        hasher.update(&buf[..n]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

#[tauri::command]
pub fn dry_run_dropbox<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<DryRunSummary, BundleError> {
    let conn = open_conn(&handle)?;
    let settings = DropboxSettings::load(&conn)?;
    let bundle = resolve_bundle(&conn, &uid)?;
    let folder = resolve_folder_name(&settings.template, &bundle);

    let root_configured = !settings.root_path.is_empty();
    let dest_dir = if root_configured {
        PathBuf::from(&settings.root_path).join(&folder)
    } else {
        PathBuf::from("(unconfigured)").join(&folder)
    };

    let artifacts = enumerate_artifacts(&handle, &conn, &uid)?;
    let mut items: Vec<DryRunRow> = Vec::with_capacity(artifacts.len());
    for (src, name, kind) in artifacts {
        let size = fs::metadata(&src).ok().map(|m| m.len() as i64).unwrap_or(0);
        let exists = src.exists();
        let dest = dest_dir.join(&name);
        let sha = if exists { sha256_file(&src).unwrap_or_default() } else { String::new() };

        let status = if !exists {
            "missing".to_string()
        } else {
            // Check if we've copied this exact (source_path, dropbox_path)
            // before AND the recorded sha matches the source's current sha.
            let existing_sha: Option<String> = conn.query_row(
                "SELECT sha256 FROM dropbox_copies
                  WHERE bundle_uid = ?1 AND source_path = ?2 AND dropbox_path = ?3",
                params![uid, src.to_string_lossy(), dest.to_string_lossy()],
                |r| r.get(0),
            ).optional()?;
            match existing_sha {
                Some(s) if s == sha && dest.exists() => "skip".to_string(),
                Some(_) => "changed".to_string(),
                None => "new".to_string(),
            }
        };

        items.push(DryRunRow {
            source_path: src.to_string_lossy().to_string(),
            source_sha256: sha,
            source_size_bytes: size,
            dropbox_path: dest.to_string_lossy().to_string(),
            destination_name: name,
            kind,
            status,
        });
    }

    Ok(DryRunSummary {
        bundle_uid: uid,
        root_configured,
        dropbox_root: settings.root_path,
        destination_dir: dest_dir.to_string_lossy().to_string(),
        items,
    })
}

#[tauri::command]
pub fn copy_to_dropbox<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<CopyResultSummary, BundleError> {
    let conn = open_conn(&handle)?;
    let settings = DropboxSettings::load(&conn)?;
    if settings.root_path.is_empty() {
        return Err(BundleError::NotFound(
            "Dropbox root not configured. Set it in Settings → Dropbox.".into(),
        ));
    }
    let bundle = resolve_bundle(&conn, &uid)?;
    let folder = resolve_folder_name(&settings.template, &bundle);
    let dest_dir = PathBuf::from(&settings.root_path).join(&folder);
    fs::create_dir_all(&dest_dir)?;

    let artifacts = enumerate_artifacts(&handle, &conn, &uid)?;
    let mut copied = 0i64;
    let mut skipped = 0i64;
    let mut failed = 0i64;
    let mut item_results: Vec<CopyResultRow> = Vec::with_capacity(artifacts.len());

    for (src, name, _kind) in artifacts {
        let dest = dest_dir.join(&name);
        let src_str = src.to_string_lossy().to_string();
        let dest_str = dest.to_string_lossy().to_string();

        if !src.exists() {
            failed += 1;
            item_results.push(CopyResultRow {
                source_path: src_str,
                dropbox_path: dest_str,
                status: "failed".into(),
                verified: false,
                error: Some("source missing".into()),
            });
            continue;
        }

        // Compute source sha once. Reused for the skip check + the
        // post-copy verify.
        let src_sha = match sha256_file(&src) {
            Ok(s) => s,
            Err(e) => {
                failed += 1;
                item_results.push(CopyResultRow {
                    source_path: src_str,
                    dropbox_path: dest_str,
                    status: "failed".into(),
                    verified: false,
                    error: Some(format!("sha source: {e}")),
                });
                continue;
            }
        };

        // Skip if we've already copied this exact source+dest with the
        // same sha AND the destination file still exists. Cheaper than
        // re-hashing the destination — the post-copy verify already
        // catches drift on the destination side at write time.
        let existing_sha: Option<String> = conn.query_row(
            "SELECT sha256 FROM dropbox_copies
              WHERE bundle_uid = ?1 AND source_path = ?2 AND dropbox_path = ?3",
            params![uid, src_str, dest_str],
            |r| r.get(0),
        ).optional()?;
        if let Some(prev) = &existing_sha {
            if prev == &src_sha && dest.exists() {
                skipped += 1;
                item_results.push(CopyResultRow {
                    source_path: src_str,
                    dropbox_path: dest_str,
                    status: "skipped".into(),
                    verified: true,
                    error: None,
                });
                continue;
            }
        }

        // Copy. Atomic via tmp file + rename so a partial write never
        // leaves a half-copied destination visible to Dropbox sync.
        let tmp = dest.with_extension("sm-dropbox-tmp");
        let copy_result = fs::copy(&src, &tmp).map(|_| ())
            .and_then(|()| {
                if dest.exists() { fs::remove_file(&dest)?; }
                fs::rename(&tmp, &dest)
            });
        if let Err(e) = copy_result {
            let _ = fs::remove_file(&tmp);
            failed += 1;
            crate::processing_log::write(
                &conn, Some(&uid), None, Some("dropbox_copy"),
                crate::processing_log::Level::Error,
                "copy failed", Some(&dest_str), Some(&e.to_string()),
            );
            item_results.push(CopyResultRow {
                source_path: src_str, dropbox_path: dest_str,
                status: "failed".into(), verified: false,
                error: Some(e.to_string()),
            });
            continue;
        }

        // Verify-on-write: re-hash the destination file and confirm
        // it matches the source. Catches "ditto wrote a corrupted
        // file but didn't error" rare cases + network-FS oddness if
        // someone points root at a SMB share.
        let dest_sha = sha256_file(&dest).unwrap_or_default();
        let verified = dest_sha == src_sha;

        // Upsert dropbox_copies row regardless of verify outcome —
        // we want to track what we wrote and whether it verified.
        conn.execute(
            "INSERT INTO dropbox_copies
                (bundle_uid, source_path, dropbox_path, sha256, verified, copied_at)
             VALUES (?1, ?2, ?3, ?4, ?5, datetime('now'))
             ON CONFLICT(bundle_uid, source_path, dropbox_path) DO UPDATE SET
                sha256 = excluded.sha256,
                verified = excluded.verified,
                copied_at = datetime('now')",
            params![uid, src_str, dest_str, src_sha, if verified { 1 } else { 0 }],
        )?;

        copied += 1;
        crate::processing_log::write(
            &conn, Some(&uid), None, Some("dropbox_copy"),
            if verified { crate::processing_log::Level::Info }
                else { crate::processing_log::Level::Warn },
            if verified { "copied + verified" } else { "copied but verify mismatch" },
            Some(&dest_str), None,
        );

        item_results.push(CopyResultRow {
            source_path: src_str,
            dropbox_path: dest_str,
            status: "copied".into(),
            verified,
            error: if verified { None } else { Some("sha mismatch after copy".into()) },
        });
    }

    Ok(CopyResultSummary {
        bundle_uid: uid,
        destination_dir: dest_dir.to_string_lossy().to_string(),
        copied,
        skipped,
        failed,
        items: item_results,
    })
}

#[tauri::command]
pub fn reveal_dropbox_dest<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<(), BundleError> {
    let conn = open_conn(&handle)?;
    let settings = DropboxSettings::load(&conn)?;
    if settings.root_path.is_empty() {
        return Err(BundleError::NotFound("Dropbox root not configured.".into()));
    }
    let bundle = resolve_bundle(&conn, &uid)?;
    let folder = resolve_folder_name(&settings.template, &bundle);
    let dest_dir = PathBuf::from(&settings.root_path).join(&folder);
    if !dest_dir.exists() {
        return Err(BundleError::NotFound(format!(
            "{} — run Copy to Dropbox first", dest_dir.display(),
        )));
    }
    crate::fsutil::reveal_in_file_browser(&dest_dir)?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn open_conn<R: Runtime>(handle: &AppHandle<R>) -> Result<Connection, BundleError> {
    let dir = handle.path()
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

    fn b(uid: &str, title: &str, persona: Option<&str>, when: &str) -> BundleResolution {
        BundleResolution {
            uid: uid.into(),
            title: title.into(),
            persona_code: persona.map(|s| s.into()),
            ingested_at: when.into(),
        }
    }

    #[test]
    fn date_title_template_is_the_default_layout() {
        let r = b("2026-05-22-0002", "and before too soon it was JUNE",
                  Some("CoC"), "2026-05-22 18:34:21");
        // v0.13.1 default: `{date} {title}` — unbracketed, single
        // space between. Matches `2025-12-31 Mary Poppins` per
        // Robert's direction.
        assert_eq!(
            resolve_folder_name("{date} {title}", &r),
            "2026-05-22 and before too soon it was JUNE",
        );
    }

    #[test]
    fn date_title_default_example_robert_specced() {
        let r = b("2025-12-31-0001", "Mary Poppins", None, "2025-12-31 09:00:00");
        assert_eq!(
            resolve_folder_name("{date} {title}", &r),
            "2025-12-31 Mary Poppins",
        );
    }

    #[test]
    fn template_resolves_every_variable() {
        let r = b("u1", "x/y:z", Some("PoA"), "2026-01-02 03:04:05");
        assert_eq!(
            resolve_folder_name("{date}_{uid}_{persona}_{title}", &r),
            "2026-01-02_u1_PoA_x-y-z",
        );
    }

    #[test]
    fn missing_persona_falls_back_to_nopersona() {
        let r = b("u1", "t", None, "2026-01-02 00:00:00");
        assert_eq!(
            resolve_folder_name("{persona}/{title}", &r),
            "nopersona-t",
        );
    }

    #[test]
    fn sanitize_replaces_filesystem_hostile_chars() {
        assert_eq!(sanitize_filename("a/b:c*d?e"), "a-b-c-d-e");
        assert_eq!(sanitize_filename("normal title"), "normal title");
        assert_eq!(sanitize_filename(" trimmed  "), "trimmed");
    }

    #[test]
    fn extract_date_drops_time() {
        assert_eq!(extract_date("2026-05-22 18:34:21"), "2026-05-22");
        assert_eq!(extract_date("2026-05-22"), "2026-05-22");
    }
}
