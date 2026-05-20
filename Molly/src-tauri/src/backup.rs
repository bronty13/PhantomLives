// Auto-backup-on-launch — PhantomLives standard, ported from
// Timeliner/Sources/Timeliner/Services/BackupService.swift to Rust so it
// runs on both macOS and Windows.
//
// Convention (CLAUDE.md): every app that owns persistent user data zips
// its app-data directory on launch into `~/Downloads/<App> backup/` (and
// the Windows equivalent), retains for 14 days by default, debounces
// repeat runs within 5 minutes, never panics, and exposes Settings UI
// for toggling / overriding / reveal / Run Now / Test / Restore.

use std::fs;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};

use chrono::{DateTime, Duration, Local, NaiveDateTime, TimeZone, Utc};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, Runtime};
use walkdir::WalkDir;
use zip::write::SimpleFileOptions;

use crate::fsutil;

pub(crate) const ARCHIVE_PREFIX: &str = "Molly-";
const DEBOUNCE_SECONDS: i64 = 5 * 60;
const SETTINGS_FILENAME: &str = "backup-settings.json";
const APP_NAME: &str = "Molly";

#[derive(Debug, thiserror::Error)]
#[allow(dead_code)] // InvalidDatabase / NoBytes reserved for verify expansion in Phase 5.
pub enum BackupError {
    #[error("io: {0}")]
    Io(#[from] io::Error),
    #[error("zip: {0}")]
    Zip(#[from] zip::result::ZipError),
    #[error("walkdir: {0}")]
    Walk(#[from] walkdir::Error),
    #[error("missing database in archive")]
    MissingDatabase,
    #[error("invalid database: {0}")]
    InvalidDatabase(String),
    #[error("empty archive — nothing was written")]
    NoBytes,
    #[error("settings: {0}")]
    Settings(String),
}

impl serde::Serialize for BackupError {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.to_string())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Settings {
    pub auto_backup_enabled: bool,
    /// Absolute path; if empty/missing, use the default `~/Downloads/Molly backup/`.
    pub backup_path: Option<String>,
    /// Days to keep backups; 0 = keep forever.
    pub backup_retention_days: u32,
    /// ISO 8601 timestamp of the last successful backup (for debounce).
    pub last_backup_at: Option<String>,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            auto_backup_enabled: true,
            backup_path: None,
            backup_retention_days: 14,
            last_backup_at: None,
        }
    }
}

impl Settings {
    fn resolved_backup_path(&self) -> PathBuf {
        match &self.backup_path {
            Some(p) if !p.is_empty() => PathBuf::from(p),
            _ => fsutil::downloads_subdir(&format!("{APP_NAME} backup")),
        }
    }
}

fn settings_path(app_data_dir: &Path) -> PathBuf {
    app_data_dir.join(SETTINGS_FILENAME)
}

pub(crate) fn load_settings(app_data_dir: &Path) -> Settings {
    let path = settings_path(app_data_dir);
    let Ok(bytes) = fs::read(&path) else {
        return Settings::default();
    };
    serde_json::from_slice::<Settings>(&bytes).unwrap_or_default()
}

pub(crate) fn save_settings(app_data_dir: &Path, settings: &Settings) -> Result<(), BackupError> {
    fs::create_dir_all(app_data_dir)?;
    let path = settings_path(app_data_dir);
    let bytes = serde_json::to_vec_pretty(settings)
        .map_err(|e| BackupError::Settings(e.to_string()))?;
    let tmp = path.with_extension("json.tmp");
    fs::write(&tmp, &bytes)?;
    fs::rename(&tmp, &path)?;
    Ok(())
}

fn app_data_dir<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, BackupError> {
    handle
        .path()
        .app_data_dir()
        .map_err(|e| BackupError::Settings(e.to_string()))
}

fn parse_iso(s: &str) -> Option<DateTime<Local>> {
    NaiveDateTime::parse_from_str(s, "%Y-%m-%dT%H:%M:%S")
        .ok()
        .and_then(|naive| Local.from_local_datetime(&naive).single())
}

fn iso_now() -> String {
    Local::now().format("%Y-%m-%dT%H:%M:%S").to_string()
}

fn timestamp() -> String {
    Local::now().format("%Y-%m-%d-%H%M%S").to_string()
}

// ---------------------------------------------------------------------------
// Core backup logic — pure, no Tauri dependency.
// ---------------------------------------------------------------------------

pub(crate) fn run_backup(support_dir: &Path, backup_dir: &Path) -> Result<PathBuf, BackupError> {
    fs::create_dir_all(backup_dir)?;
    fs::create_dir_all(support_dir)?;

    let archive_name = format!("{ARCHIVE_PREFIX}{}.zip", timestamp());
    let out_path = backup_dir.join(archive_name);
    let tmp_path = out_path.with_extension("zip.tmp");

    {
        let file = fs::File::create(&tmp_path)?;
        let mut zip = zip::ZipWriter::new(file);
        let options = SimpleFileOptions::default()
            .compression_method(zip::CompressionMethod::Deflated)
            .unix_permissions(0o644);

        let mut buf = Vec::with_capacity(64 * 1024);
        for entry in WalkDir::new(support_dir).into_iter().filter_map(|e| e.ok()) {
            let path = entry.path();
            let Ok(rel) = path.strip_prefix(support_dir) else { continue };
            if rel.as_os_str().is_empty() { continue; }
            // Skip macOS junk + our own settings tmp.
            let name = rel.to_string_lossy();
            if name.ends_with(".DS_Store") || name.ends_with(".json.tmp") {
                continue;
            }

            if entry.file_type().is_dir() {
                // Tolerate Windows backslashes — zip format uses '/'.
                let dir_name = format!("{}/", name.replace('\\', "/"));
                zip.add_directory(dir_name, options)?;
            } else if entry.file_type().is_file() {
                let file_name = name.replace('\\', "/");
                zip.start_file(file_name, options)?;
                buf.clear();
                fs::File::open(path)?.read_to_end(&mut buf)?;
                zip.write_all(&buf)?;
            }
        }
        zip.finish()?;
    }

    // Atomic rename (best-effort on Windows where rename over existing fails).
    if out_path.exists() { let _ = fs::remove_file(&out_path); }
    fs::rename(&tmp_path, &out_path)?;
    Ok(out_path)
}

/// Trim archives whose mtime is older than `retention_days`. Only touches
/// files whose name starts with `Molly-` and ends `.zip` — never nukes
/// unrelated files a user dropped into the same folder.
pub(crate) fn trim_old_backups(backup_dir: &Path, retention_days: u32) -> usize {
    if retention_days == 0 { return 0; }
    let cutoff = Utc::now() - Duration::days(retention_days as i64);
    let mut removed = 0;
    let Ok(entries) = fs::read_dir(backup_dir) else { return 0 };
    for entry in entries.flatten() {
        let path = entry.path();
        let name = entry.file_name();
        let name_str = name.to_string_lossy();
        if !name_str.starts_with(ARCHIVE_PREFIX) || !name_str.ends_with(".zip") { continue; }
        let Ok(meta) = entry.metadata() else { continue };
        let Ok(modified) = meta.modified() else { continue };
        let modified_chrono: DateTime<Utc> = modified.into();
        if modified_chrono < cutoff {
            if fs::remove_file(&path).is_ok() { removed += 1; }
        }
    }
    removed
}

#[derive(Debug, Clone, Serialize)]
pub struct BackupRow {
    pub path: String,
    pub filename: String,
    pub modified_at: String,
    pub size_bytes: u64,
}

pub(crate) fn list_backups_in(backup_dir: &Path) -> Vec<BackupRow> {
    let Ok(entries) = fs::read_dir(backup_dir) else { return Vec::new() };
    let mut rows: Vec<(PathBuf, std::time::SystemTime, u64)> = Vec::new();
    for entry in entries.flatten() {
        let name = entry.file_name();
        let name_str = name.to_string_lossy();
        if !name_str.starts_with(ARCHIVE_PREFIX) || !name_str.ends_with(".zip") { continue; }
        let Ok(meta) = entry.metadata() else { continue };
        let modified = meta.modified().unwrap_or(std::time::UNIX_EPOCH);
        rows.push((entry.path(), modified, meta.len()));
    }
    rows.sort_by(|a, b| b.1.cmp(&a.1));
    rows.into_iter()
        .map(|(path, modified, size)| {
            let modified_chrono: DateTime<Local> = modified.into();
            BackupRow {
                filename: path
                    .file_name()
                    .map(|s| s.to_string_lossy().to_string())
                    .unwrap_or_default(),
                path: path.to_string_lossy().to_string(),
                modified_at: modified_chrono.format("%Y-%m-%d %H:%M:%S").to_string(),
                size_bytes: size,
            }
        })
        .collect()
}

#[derive(Debug, Serialize)]
pub struct VerifyResult {
    pub archive_path: String,
    pub archive_size: u64,
    pub file_count: usize,
    pub total_bytes: u64,
    pub has_database: bool,
    pub entries: Vec<String>,
}

pub(crate) fn verify_archive(archive_path: &Path) -> Result<VerifyResult, BackupError> {
    let file = fs::File::open(archive_path)?;
    let mut archive = zip::ZipArchive::new(file)?;
    let mut total_bytes = 0u64;
    let mut entries = Vec::new();
    let mut has_database = false;
    for i in 0..archive.len() {
        let entry = archive.by_index(i)?;
        if entry.is_file() {
            let name = entry.name().to_string();
            total_bytes += entry.size();
            if name == "molly.db" || name.ends_with("/molly.db") {
                has_database = true;
            }
            if entries.len() < 25 {
                entries.push(name);
            }
        }
    }
    let archive_size = fs::metadata(archive_path)?.len();
    entries.sort();
    Ok(VerifyResult {
        archive_path: archive_path.to_string_lossy().to_string(),
        archive_size,
        file_count: archive.len(),
        total_bytes,
        has_database,
        entries,
    })
}

/// Destructive: write a safety pre-restore backup, then unpack the archive
/// over the support directory. Caller must close DB connections first.
pub(crate) fn restore_archive(archive_path: &Path, support_dir: &Path) -> Result<PathBuf, BackupError> {
    let verify = verify_archive(archive_path)?;
    if !verify.has_database {
        return Err(BackupError::MissingDatabase);
    }

    // Pre-restore safety archive lives in the same dir as the chosen
    // archive so it's easy to find.
    let parent = archive_path
        .parent()
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| PathBuf::from("."));
    let safety_name = format!("{ARCHIVE_PREFIX}pre-restore-{}.zip", timestamp());
    let safety_path = parent.join(safety_name);
    if support_dir.exists() {
        // Only write a safety archive if there's something to save.
        if let Err(err) = run_backup(support_dir, &parent) {
            eprintln!("[molly] safety backup failed (continuing): {err}");
        } else {
            // run_backup wrote a fresh Molly-<ts>.zip; rename to make its
            // purpose obvious in the listing.
            let listed = list_backups_in(&parent);
            if let Some(first) = listed.first() {
                let _ = fs::rename(&first.path, &safety_path);
            }
        }
    }

    fs::create_dir_all(support_dir)?;
    // Wipe existing contents.
    if let Ok(entries) = fs::read_dir(support_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() { let _ = fs::remove_dir_all(&path); }
            else            { let _ = fs::remove_file(&path); }
        }
    }

    // Unpack.
    let file = fs::File::open(archive_path)?;
    let mut archive = zip::ZipArchive::new(file)?;
    for i in 0..archive.len() {
        let mut entry = archive.by_index(i)?;
        let Some(rel) = entry.enclosed_name() else { continue };
        let out_path = support_dir.join(rel);
        if entry.is_dir() {
            fs::create_dir_all(&out_path)?;
        } else {
            if let Some(parent) = out_path.parent() { fs::create_dir_all(parent)?; }
            let mut out = fs::File::create(&out_path)?;
            io::copy(&mut entry, &mut out)?;
        }
    }
    Ok(safety_path)
}

// ---------------------------------------------------------------------------
// Launch entry — call from app setup.
// ---------------------------------------------------------------------------

pub async fn run_on_launch_if_due<R: Runtime>(handle: &AppHandle<R>) -> Result<(), BackupError> {
    let app_data = app_data_dir(handle)?;
    fs::create_dir_all(&app_data)?;
    let settings = load_settings(&app_data);
    if !settings.auto_backup_enabled { return Ok(()); }
    if let Some(last) = settings.last_backup_at.as_deref().and_then(parse_iso) {
        let elapsed = Local::now().signed_duration_since(last).num_seconds();
        if elapsed < DEBOUNCE_SECONDS {
            return Ok(());
        }
    }
    do_backup(handle).await?;
    Ok(())
}

async fn do_backup<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, BackupError> {
    let app_data = app_data_dir(handle)?;
    let mut settings = load_settings(&app_data);
    let backup_dir = settings.resolved_backup_path();
    let out = run_backup(&app_data, &backup_dir)?;
    let _ = trim_old_backups(&backup_dir, settings.backup_retention_days);
    settings.last_backup_at = Some(iso_now());
    save_settings(&app_data, &settings)?;
    Ok(out)
}

// ---------------------------------------------------------------------------
// Tauri command surface.
// ---------------------------------------------------------------------------

#[tauri::command]
pub async fn run_backup_now<R: Runtime>(handle: AppHandle<R>) -> Result<String, BackupError> {
    let out = do_backup(&handle).await?;
    Ok(out.to_string_lossy().to_string())
}

#[tauri::command]
pub fn list_backups<R: Runtime>(handle: AppHandle<R>) -> Result<Vec<BackupRow>, BackupError> {
    let app_data = app_data_dir(&handle)?;
    let settings = load_settings(&app_data);
    Ok(list_backups_in(&settings.resolved_backup_path()))
}

#[tauri::command]
pub fn test_backup(path: String) -> Result<VerifyResult, BackupError> {
    verify_archive(Path::new(&path))
}

#[tauri::command]
pub fn restore_backup<R: Runtime>(handle: AppHandle<R>, path: String) -> Result<String, BackupError> {
    let app_data = app_data_dir(&handle)?;
    let safety = restore_archive(Path::new(&path), &app_data)?;
    Ok(safety.to_string_lossy().to_string())
}

#[tauri::command]
pub fn reveal_backup_dir<R: Runtime>(handle: AppHandle<R>) -> Result<(), BackupError> {
    let app_data = app_data_dir(&handle)?;
    let settings = load_settings(&app_data);
    let dir = settings.resolved_backup_path();
    fs::create_dir_all(&dir)?;
    fsutil::reveal_in_file_browser(&dir)?;
    Ok(())
}

#[tauri::command]
pub fn reveal_path(path: String) -> Result<(), BackupError> {
    fsutil::reveal_in_file_browser(Path::new(&path))?;
    Ok(())
}

#[tauri::command]
pub fn get_backup_settings<R: Runtime>(handle: AppHandle<R>) -> Result<Settings, BackupError> {
    let app_data = app_data_dir(&handle)?;
    Ok(load_settings(&app_data))
}

#[tauri::command]
pub fn set_backup_settings<R: Runtime>(handle: AppHandle<R>, settings: Settings) -> Result<(), BackupError> {
    let app_data = app_data_dir(&handle)?;
    save_settings(&app_data, &settings)
}

// ---------------------------------------------------------------------------
// Tests — required per CLAUDE.md backup standard.
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration as StdDuration;
    use std::time::SystemTime;
    use tempfile::TempDir;

    fn touch_age(path: &Path, days_ago: i64) {
        let when = SystemTime::now() - StdDuration::from_secs((days_ago as u64) * 86400);
        let file = filetime::FileTime::from_system_time(when);
        let _ = filetime::set_file_mtime(path, file);
    }

    #[test]
    fn debounce_skips_recent_backups() {
        // We unit-test the pure helper: parse + Δ logic.
        let now = Local::now();
        let recent = now - Duration::seconds(60);
        let formatted = recent.format("%Y-%m-%dT%H:%M:%S").to_string();
        let parsed = parse_iso(&formatted).expect("round-trip parses");
        let elapsed = Local::now().signed_duration_since(parsed).num_seconds();
        assert!(elapsed < DEBOUNCE_SECONDS, "freshly-stamped timestamp should be within debounce window");
    }

    #[test]
    fn retention_trims_only_molly_prefixed_zips() {
        let dir = TempDir::new().unwrap();
        let molly_old = dir.path().join("Molly-2020-01-01-000000.zip");
        let molly_new = dir.path().join("Molly-2099-01-01-000000.zip");
        let unrelated = dir.path().join("vacation-photos.zip");
        let txt = dir.path().join("notes.txt");
        for p in [&molly_old, &molly_new, &unrelated, &txt] {
            fs::write(p, b"x").unwrap();
        }
        touch_age(&molly_old, 100);
        touch_age(&unrelated, 1000);

        let removed = trim_old_backups(dir.path(), 14);
        assert_eq!(removed, 1, "exactly one Molly-prefixed old archive removed");
        assert!(!molly_old.exists(), "old Molly zip is gone");
        assert!(molly_new.exists(), "new Molly zip kept");
        assert!(unrelated.exists(), "unrelated zip is NOT touched");
        assert!(txt.exists(), "txt file is NOT touched");
    }

    #[test]
    fn retention_zero_means_keep_forever() {
        let dir = TempDir::new().unwrap();
        let p = dir.path().join("Molly-2020-01-01-000000.zip");
        fs::write(&p, b"x").unwrap();
        touch_age(&p, 10_000);
        assert_eq!(trim_old_backups(dir.path(), 0), 0);
        assert!(p.exists(), "retention=0 keeps everything");
    }

    #[test]
    fn run_backup_creates_target_dir_when_missing() {
        let support = TempDir::new().unwrap();
        fs::write(support.path().join("molly.db"), b"\xff hello").unwrap();
        fs::write(support.path().join("settings.json"), b"{}").unwrap();

        // Use a non-existent backup dir.
        let backup_root = TempDir::new().unwrap();
        let backup_dir = backup_root.path().join("nested/Molly backup");
        assert!(!backup_dir.exists());

        let out = run_backup(support.path(), &backup_dir).expect("backup succeeds");
        assert!(backup_dir.exists(), "backup dir auto-created");
        assert!(out.exists(), "archive written");
        let verify = verify_archive(&out).expect("archive verifies");
        assert!(verify.has_database, "archive contains molly.db");
        assert_eq!(verify.file_count, 2);
    }

    #[test]
    fn list_returns_newest_first() {
        let dir = TempDir::new().unwrap();
        let a = dir.path().join("Molly-2024-01-01-000000.zip");
        let b = dir.path().join("Molly-2024-06-01-000000.zip");
        let c = dir.path().join("Molly-2024-12-01-000000.zip");
        for p in [&a, &b, &c] { fs::write(p, b"x").unwrap(); }
        // mtime ordering: oldest = a, newest = c.
        touch_age(&a, 300);
        touch_age(&b, 200);
        touch_age(&c, 1);

        let rows = list_backups_in(dir.path());
        assert_eq!(rows.len(), 3);
        assert!(rows[0].filename.contains("2024-12"));
        assert!(rows[2].filename.contains("2024-01"));
    }

    #[test]
    fn verify_flags_missing_database() {
        let support = TempDir::new().unwrap();
        // No molly.db — only a settings file.
        fs::write(support.path().join("settings.json"), b"{}").unwrap();
        let backup_dir = TempDir::new().unwrap();
        let out = run_backup(support.path(), backup_dir.path()).unwrap();
        let v = verify_archive(&out).unwrap();
        assert!(!v.has_database);
    }

    #[test]
    fn debounce_seconds_matches_spec() {
        // CLAUDE.md mandates a 5-min debounce.
        assert_eq!(DEBOUNCE_SECONDS, 5 * 60);
    }
}
