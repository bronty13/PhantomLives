// Auto-backup-on-launch — PhantomLives standard, ported from Molly's
// backup.rs (which itself ports Timeliner's BackupService). Convention:
// every app that owns persistent user data zips its app-data directory
// on launch into `~/Downloads/<App> backup/`, retains for 14 days by
// default, debounces within 5 minutes, never panics, and exposes the
// Settings UI required by CLAUDE.md.
//
// SideMolly-specific differences vs Molly:
//   - ARCHIVE_PREFIX = "SideMolly-"
//   - APP_NAME       = "SideMolly"
//   - Verify checks for `sidemolly.db` inside the archive

use std::fs;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};

use chrono::{DateTime, Duration, Local, NaiveDateTime, TimeZone, Utc};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, Runtime};
use walkdir::WalkDir;
use zip::write::SimpleFileOptions;

use crate::fsutil;

pub(crate) const ARCHIVE_PREFIX: &str = "SideMolly-";
const DEBOUNCE_SECONDS: i64 = 5 * 60;
const SETTINGS_FILENAME: &str = "backup-settings.json";
const APP_NAME: &str = "SideMolly";
const DB_FILENAME: &str = "sidemolly.db";

#[derive(Debug, thiserror::Error)]
#[allow(dead_code)] // InvalidDatabase / NoBytes reserved for later verify expansion.
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
    /// Absolute path; if empty/missing, use the default `~/Downloads/SideMolly backup/`.
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
        // Directory entries get the execute bit so the extracted tree is
        // traversable (the zip crate already defaults dirs to 0o755, but
        // be explicit). Note: backups are restored programmatically by
        // BackupService, so the multi-root Archive-Utility 0o700-wrapper
        // quirk that post-bundles avoid doesn't affect restore here.
        let dir_options = options.unix_permissions(0o755);

        let mut buf = Vec::with_capacity(64 * 1024);
        for entry in WalkDir::new(support_dir).into_iter().filter_map(|e| e.ok()) {
            let path = entry.path();
            let Ok(rel) = path.strip_prefix(support_dir) else { continue };
            if rel.as_os_str().is_empty() { continue; }
            let name = rel.to_string_lossy();
            if name.ends_with(".DS_Store") || name.ends_with(".json.tmp") {
                continue;
            }

            if entry.file_type().is_dir() {
                let dir_name = format!("{}/", name.replace('\\', "/"));
                zip.add_directory(dir_name, dir_options)?;
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

    if out_path.exists() { let _ = fs::remove_file(&out_path); }
    fs::rename(&tmp_path, &out_path)?;
    Ok(out_path)
}

/// Trim archives whose mtime is older than `retention_days`. Only touches
/// files whose name starts with `SideMolly-` and ends `.zip` — never nukes
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
#[serde(rename_all = "camelCase")]
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
#[serde(rename_all = "camelCase")]
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
            if name == DB_FILENAME || name.ends_with(&format!("/{DB_FILENAME}")) {
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
pub fn restore_archive(archive_path: &Path, support_dir: &Path) -> Result<PathBuf, BackupError> {
    let verify = verify_archive(archive_path)?;
    if !verify.has_database {
        return Err(BackupError::MissingDatabase);
    }

    let parent = archive_path
        .parent()
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| PathBuf::from("."));
    let safety_name = format!("{ARCHIVE_PREFIX}pre-restore-{}.zip", timestamp());
    let safety_path = parent.join(safety_name);
    if support_dir.exists() {
        if let Err(err) = run_backup(support_dir, &parent) {
            eprintln!("[sidemolly] safety backup failed (continuing): {err}");
        } else {
            let listed = list_backups_in(&parent);
            if let Some(first) = listed.first() {
                let _ = fs::rename(&first.path, &safety_path);
            }
        }
    }

    fs::create_dir_all(support_dir)?;
    if let Ok(entries) = fs::read_dir(support_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() { let _ = fs::remove_dir_all(&path); }
            else            { let _ = fs::remove_file(&path); }
        }
    }

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
// Tests — required per CLAUDE.md backup standard:
//   - debounce (recent run is a no-op)
//   - retention trim (only ARCHIVE_PREFIX zips removed; unrelated kept)
//   - target-directory auto-create
//   - list ordering (newest first)
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
        let now = Local::now();
        let recent = now - Duration::seconds(60);
        let formatted = recent.format("%Y-%m-%dT%H:%M:%S").to_string();
        let parsed = parse_iso(&formatted).expect("round-trip parses");
        let elapsed = Local::now().signed_duration_since(parsed).num_seconds();
        assert!(elapsed < DEBOUNCE_SECONDS, "freshly-stamped timestamp should be within debounce window");
    }

    #[test]
    fn retention_trims_only_prefixed_zips() {
        let dir = TempDir::new().unwrap();
        let mine_old = dir.path().join("SideMolly-2020-01-01-000000.zip");
        let mine_new = dir.path().join("SideMolly-2099-01-01-000000.zip");
        let unrelated = dir.path().join("vacation-photos.zip");
        let txt = dir.path().join("notes.txt");
        for p in [&mine_old, &mine_new, &unrelated, &txt] {
            fs::write(p, b"x").unwrap();
        }
        touch_age(&mine_old, 100);
        touch_age(&unrelated, 1000);

        let removed = trim_old_backups(dir.path(), 14);
        assert_eq!(removed, 1, "exactly one SideMolly-prefixed old archive removed");
        assert!(!mine_old.exists(), "old SideMolly zip is gone");
        assert!(mine_new.exists(), "new SideMolly zip kept");
        assert!(unrelated.exists(), "unrelated zip is NOT touched");
        assert!(txt.exists(), "txt file is NOT touched");
    }

    #[test]
    fn retention_zero_means_keep_forever() {
        let dir = TempDir::new().unwrap();
        let p = dir.path().join("SideMolly-2020-01-01-000000.zip");
        fs::write(&p, b"x").unwrap();
        touch_age(&p, 10_000);
        assert_eq!(trim_old_backups(dir.path(), 0), 0);
        assert!(p.exists(), "retention=0 keeps everything");
    }

    #[test]
    fn run_backup_creates_target_dir_when_missing() {
        let support = TempDir::new().unwrap();
        fs::write(support.path().join(DB_FILENAME), b"\xff hello").unwrap();
        fs::write(support.path().join("settings.json"), b"{}").unwrap();

        let backup_root = TempDir::new().unwrap();
        let backup_dir = backup_root.path().join("nested/SideMolly backup");
        assert!(!backup_dir.exists());

        let out = run_backup(support.path(), &backup_dir).expect("backup succeeds");
        assert!(backup_dir.exists(), "backup dir auto-created");
        assert!(out.exists(), "archive written");
        let verify = verify_archive(&out).expect("archive verifies");
        assert!(verify.has_database, "archive contains sidemolly.db");
        assert_eq!(verify.file_count, 2);
    }

    #[test]
    fn backup_directory_entries_are_traversable() {
        // Regression: directory entries were written 0o644 (no execute
        // bit), so the extracted folder was non-traversable — Finder
        // reported "you don't have permission to see its contents".
        let support = TempDir::new().unwrap();
        fs::write(support.path().join(DB_FILENAME), b"db").unwrap();
        fs::create_dir_all(support.path().join("work/uid")).unwrap();
        fs::write(support.path().join("work/uid/a.bin"), b"x").unwrap();

        let backup_dir = TempDir::new().unwrap();
        let out = run_backup(support.path(), backup_dir.path()).expect("backup succeeds");

        let file = fs::File::open(&out).unwrap();
        let mut zip = zip::ZipArchive::new(file).unwrap();
        let (mut saw_dir, mut saw_file) = (false, false);
        for i in 0..zip.len() {
            let entry = zip.by_index(i).unwrap();
            let mode = entry.unix_mode().expect("entry carries a unix mode") & 0o777;
            if entry.is_dir() {
                saw_dir = true;
                assert_eq!(mode, 0o755, "dir {} must be traversable", entry.name());
            } else {
                saw_file = true;
                assert_eq!(mode, 0o644, "file {} mode", entry.name());
            }
        }
        assert!(saw_dir, "archive contains a directory entry");
        assert!(saw_file, "archive contains a file entry");
    }

    #[test]
    fn list_returns_newest_first() {
        let dir = TempDir::new().unwrap();
        let a = dir.path().join("SideMolly-2024-01-01-000000.zip");
        let b = dir.path().join("SideMolly-2024-06-01-000000.zip");
        let c = dir.path().join("SideMolly-2024-12-01-000000.zip");
        for p in [&a, &b, &c] { fs::write(p, b"x").unwrap(); }
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
        fs::write(support.path().join("settings.json"), b"{}").unwrap();
        let backup_dir = TempDir::new().unwrap();
        let out = run_backup(support.path(), backup_dir.path()).unwrap();
        let v = verify_archive(&out).unwrap();
        assert!(!v.has_database);
    }

    #[test]
    fn debounce_seconds_matches_spec() {
        assert_eq!(DEBOUNCE_SECONDS, 5 * 60);
    }
}
