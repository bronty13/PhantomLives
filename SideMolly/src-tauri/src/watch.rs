// Watched-folder ingest — Phase 1b.
//
// On launch: scan the configured watch dir (default
// ~/Downloads/Molly bundles/), ingest every `.zip` not already in the
// bundles table. After launch, a `notify` watcher fires for any new or
// changed `.zip` in the dir; we sleep briefly to let the file finish
// flushing, then call ingest_bundle (UPSERT-safe, idempotent extract).
//
// Frontend stays in sync via the `bundle-ingested` Tauri event emitted
// after each successful ingest. The Inbox's `bundle-ingested` listener
// (App.tsx) bumps a refresh signal whenever it lands.

use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

use notify::{RecommendedWatcher, RecursiveMode, Watcher};
use rusqlite::{params, Connection, OptionalExtension};
use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, Runtime};

use crate::bundles::{ingest_bundle_inner, BundleError};
use crate::extract::bundle_workspace_dir;
use crate::fsutil;

const DEFAULT_SUBDIR: &str = "Molly bundles";
const SETTING_KEY_WATCH_DIR: &str = "bundle_watch_dir";
/// notify-event debounce: 1 second after the last write before we try
/// to verify. Molly's deterministic build produces a complete file in
/// one shot, but the OS may still be syncing buffers on slower disks.
const FS_EVENT_DEBOUNCE_MS: u64 = 1_000;

#[derive(Debug, Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct WatchSettings {
    /// What the user actually configured (may be empty = use default).
    pub configured_path: String,
    /// What ingest will actually use right now (default applied if empty).
    pub resolved_path: String,
    /// True when configured_path is empty so the default applies.
    pub using_default: bool,
}

#[derive(Debug, Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ScanResult {
    pub scanned_path: String,
    pub considered: i64,
    pub ingested: i64,
    pub skipped: i64,
    pub failed: i64,
    pub errors: Vec<String>,
}

/// Resolve `~/Downloads/Molly bundles/` cross-platform.
fn default_watch_dir() -> PathBuf {
    fsutil::downloads_subdir(DEFAULT_SUBDIR)
}

fn open_conn<R: Runtime>(handle: &AppHandle<R>) -> Result<Connection, BundleError> {
    let app_data = handle
        .path()
        .app_data_dir()
        .map_err(|e| BundleError::AppData(e.to_string()))?;
    let conn = Connection::open(app_data.join("sidemolly.db"))?;
    conn.execute_batch("PRAGMA foreign_keys = ON;")?;
    Ok(conn)
}

fn read_setting(conn: &Connection, key: &str) -> Result<Option<String>, BundleError> {
    Ok(conn
        .query_row(
            "SELECT value FROM app_settings WHERE key = ?1",
            params![key],
            |r| r.get::<_, String>(0),
        )
        .optional()?)
}

fn write_setting(conn: &Connection, key: &str, value: &str) -> Result<(), BundleError> {
    conn.execute(
        "INSERT INTO app_settings (key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![key, value],
    )?;
    Ok(())
}

fn current_watch_dir<R: Runtime>(handle: &AppHandle<R>) -> Result<(PathBuf, bool), BundleError> {
    let conn = open_conn(handle)?;
    match read_setting(&conn, SETTING_KEY_WATCH_DIR)? {
        Some(p) if !p.trim().is_empty() => Ok((PathBuf::from(p), false)),
        _ => Ok((default_watch_dir(), true)),
    }
}

/// `true` if we already have a bundles row pointing at this path AND
/// the extracted workspace is still present on disk AND (since v0.4.0)
/// the thumbnail pass has been run.
///
/// Returning false here triggers a re-ingest, which idempotently
/// restores both the extracted workspace (via size-match in extract)
/// and the thumbnails (via path-keyed skip in thumbnails). The three
/// "missing" conditions all collapse to the same recovery path —
/// useful for SideMolly version upgrades (v0.3.0 → v0.4.0 fills in
/// thumbnails for already-ingested bundles without any user action).
///
/// Notify-driven re-scans bypass this entirely; an FS event = something
/// changed, force a re-ingest.
fn already_ingested(conn: &Connection, work_root: &Path, path: &Path) -> bool {
    let path_str = path.to_string_lossy();
    let uid: Option<String> = conn
        .query_row(
            "SELECT uid FROM bundles WHERE source_zip_path = ?1",
            params![path_str.as_ref()],
            |r| r.get(0),
        )
        .optional()
        .unwrap_or(None);
    let Some(uid) = uid else { return false; };

    // info.md is the canonical "extract happened" sentinel — Molly
    // always writes it as the first inner-zip entry.
    if !bundle_workspace_dir(work_root, &uid).join("info.md").exists() {
        return false;
    }

    // v0.4.0 thumbnail upgrade check. Three failure modes trigger
    // re-ingest:
    //   1. Bundle has media but zero export thumbs (pre-Phase-1c data).
    //   2. Bundle has video files but zero of them carry a
    //      thumbnail_path — this catches the v0.4.0 → v0.4.0+ffmpeg-fix
    //      upgrade where Finder-launched apps' empty PATH meant ffmpeg
    //      never ran on the first try. Now that we probe explicit
    //      paths, a re-ingest picks up the videos.
    let media: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM bundle_files
              WHERE bundle_uid = ?1 AND kind IN ('image','video')",
            params![uid],
            |r| r.get(0),
        )
        .unwrap_or(0);
    if media == 0 { return true; }
    let exports: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM bundle_export_thumbs WHERE bundle_uid = ?1",
            params![uid],
            |r| r.get(0),
        )
        .unwrap_or(0);
    if exports == 0 { return false; }

    let videos: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM bundle_files
              WHERE bundle_uid = ?1 AND kind = 'video'",
            params![uid],
            |r| r.get(0),
        )
        .unwrap_or(0);
    if videos == 0 { return true; }
    let videos_with_thumbs: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM bundle_files
              WHERE bundle_uid = ?1 AND kind = 'video'
                AND thumbnail_path IS NOT NULL AND thumbnail_path != ''",
            params![uid],
            |r| r.get(0),
        )
        .unwrap_or(0);
    videos_with_thumbs > 0
}

fn is_bundle_zip(path: &Path) -> bool {
    path.is_file()
        && path
            .extension()
            .and_then(|e| e.to_str())
            .map(|e| e.eq_ignore_ascii_case("zip"))
            .unwrap_or(false)
}

fn scan_dir<R: Runtime>(
    handle: &AppHandle<R>,
    dir: &Path,
    force_reingest: bool,
) -> ScanResult {
    let mut result = ScanResult {
        scanned_path: dir.to_string_lossy().to_string(),
        considered: 0,
        ingested: 0,
        skipped: 0,
        failed: 0,
        errors: Vec::new(),
    };

    let conn = match open_conn(handle) {
        Ok(c) => c,
        Err(e) => {
            result.errors.push(format!("open conn: {e}"));
            return result;
        }
    };

    // Resolve the work root once so already_ingested can check for the
    // extracted workspace alongside the DB row. Routes through the
    // canonical helper (~/Downloads/SideMolly/work/), not a local
    // app_data_dir join — those diverged once the workspace moved.
    let work_root = match crate::bundles::work_root(handle) {
        Ok(p) => p,
        Err(e) => {
            result.errors.push(format!("work root: {e}"));
            return result;
        }
    };

    let Ok(entries) = std::fs::read_dir(dir) else {
        // Watch dir doesn't exist yet — that's OK, it'll be created on
        // first publish from Molly. No error, just nothing to scan.
        return result;
    };

    for entry in entries.flatten() {
        let path = entry.path();
        if !is_bundle_zip(&path) { continue; }
        result.considered += 1;

        if !force_reingest && already_ingested(&conn, &work_root, &path) {
            result.skipped += 1;
            continue;
        }

        let path_str = path.to_string_lossy().to_string();
        match ingest_bundle_inner(handle, &path_str) {
            Ok(r) => {
                result.ingested += 1;
                let _ = handle.emit("bundle-ingested", &r);
            }
            Err(e) => {
                result.failed += 1;
                result.errors.push(format!("{}: {e}", path.display()));
                eprintln!("[sidemolly:watch] ingest failed for {}: {e}", path.display());
            }
        }
    }
    result
}

/// Launched once from lib.rs::setup. Owns its own thread + a notify
/// RecommendedWatcher for the configured dir. Re-scans the dir on any
/// FS event, coalesced through a 1s debounce.
pub fn spawn_watcher<R: Runtime>(handle: AppHandle<R>) {
    thread::spawn(move || run_watcher(handle));
}

fn run_watcher<R: Runtime>(handle: AppHandle<R>) {
    let (watch_dir, _) = match current_watch_dir(&handle) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("[sidemolly:watch] resolve dir failed: {e}");
            return;
        }
    };

    // mkdir -p so the watcher has something to watch (and so Molly can
    // drop bundles even if SideMolly is launched first).
    if let Err(e) = std::fs::create_dir_all(&watch_dir) {
        eprintln!("[sidemolly:watch] create_dir_all {watch_dir:?} failed: {e}");
        return;
    }

    eprintln!("[sidemolly:watch] watching {}", watch_dir.display());

    // ---- Initial scan: ingest anything that landed while we were closed.
    let result = scan_dir(&handle, &watch_dir, false);
    if result.ingested > 0 || result.failed > 0 {
        eprintln!(
            "[sidemolly:watch] launch scan: {} considered, {} ingested, {} skipped, {} failed",
            result.considered, result.ingested, result.skipped, result.failed,
        );
    }

    // ---- notify watcher. We don't need per-file precision; any FS
    // event on the dir is just a "rescan please" signal.
    let (tx, rx) = mpsc::channel::<notify::Result<notify::Event>>();
    let mut watcher: RecommendedWatcher = match notify::recommended_watcher(move |ev| {
        let _ = tx.send(ev);
    }) {
        Ok(w) => w,
        Err(e) => {
            eprintln!("[sidemolly:watch] create watcher failed: {e}");
            return;
        }
    };
    if let Err(e) = watcher.watch(&watch_dir, RecursiveMode::NonRecursive) {
        eprintln!("[sidemolly:watch] watch failed: {e}");
        return;
    }

    for ev in rx {
        match ev {
            Ok(event) if has_interesting_path(&event) => {
                // Debounce: any file may still be flushing.
                thread::sleep(Duration::from_millis(FS_EVENT_DEBOUNCE_MS));
                // FS events trigger a re-scan (force re-ingest is fine —
                // the underlying UPSERT keeps things consistent).
                let _ = scan_dir(&handle, &watch_dir, true);
            }
            Ok(_) => {}
            Err(e) => eprintln!("[sidemolly:watch] event err: {e}"),
        }
    }
    // Channel closed → watcher dropped → exit thread. Drop watcher
    // explicitly so it's clear the lifetime ends here.
    drop(watcher);
}

fn has_interesting_path(event: &notify::Event) -> bool {
    event.paths.iter().any(|p| is_bundle_zip(p))
}

// ---------------------------------------------------------------------------
// Tauri commands — Settings → Watched folder pane + manual scan trigger.
// ---------------------------------------------------------------------------

#[tauri::command]
pub fn get_watch_settings<R: Runtime>(handle: AppHandle<R>) -> Result<WatchSettings, BundleError> {
    let conn = open_conn(&handle)?;
    let configured = read_setting(&conn, SETTING_KEY_WATCH_DIR)?.unwrap_or_default();
    let using_default = configured.trim().is_empty();
    let resolved = if using_default {
        default_watch_dir()
    } else {
        PathBuf::from(&configured)
    };
    Ok(WatchSettings {
        configured_path: configured,
        resolved_path: resolved.to_string_lossy().to_string(),
        using_default,
    })
}

#[tauri::command]
pub fn set_watch_dir<R: Runtime>(
    handle: AppHandle<R>,
    path: Option<String>,
) -> Result<WatchSettings, BundleError> {
    let conn = open_conn(&handle)?;
    let value = path.unwrap_or_default();
    write_setting(&conn, SETTING_KEY_WATCH_DIR, value.trim())?;
    get_watch_settings(handle)
}

#[tauri::command]
pub fn scan_watch_dir_now<R: Runtime>(handle: AppHandle<R>) -> Result<ScanResult, BundleError> {
    let (dir, _) = current_watch_dir(&handle)?;
    std::fs::create_dir_all(&dir)?;
    Ok(scan_dir(&handle, &dir, true))
}

#[tauri::command]
pub fn reveal_watch_dir<R: Runtime>(handle: AppHandle<R>) -> Result<(), BundleError> {
    let (dir, _) = current_watch_dir(&handle)?;
    std::fs::create_dir_all(&dir)?;
    fsutil::reveal_in_file_browser(&dir)?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    #[test]
    fn is_bundle_zip_filter() {
        let dir = TempDir::new().unwrap();
        let zip = dir.path().join("2026-05-22-0002.zip");
        let txt = dir.path().join("notes.txt");
        let nested = dir.path().join("subdir");
        fs::write(&zip, b"x").unwrap();
        fs::write(&txt, b"x").unwrap();
        fs::create_dir(&nested).unwrap();
        assert!(is_bundle_zip(&zip));
        assert!(!is_bundle_zip(&txt));
        assert!(!is_bundle_zip(&nested));
        assert!(!is_bundle_zip(&dir.path().join("does-not-exist.zip")));
    }

    #[test]
    fn case_insensitive_extension() {
        let dir = TempDir::new().unwrap();
        let upper = dir.path().join("Bundle.ZIP");
        let mixed = dir.path().join("Bundle.Zip");
        fs::write(&upper, b"x").unwrap();
        fs::write(&mixed, b"x").unwrap();
        assert!(is_bundle_zip(&upper));
        assert!(is_bundle_zip(&mixed));
    }

    #[test]
    fn default_watch_dir_ends_with_molly_bundles() {
        let p = default_watch_dir();
        assert!(p.to_string_lossy().ends_with("Molly bundles"));
    }
}
