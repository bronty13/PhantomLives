// Full-data export + dev-only import. Pairs with the backup module
// but writes user-visible "send this to Robert" exports to
// ~/Downloads/Molly export/ (Mac) / %USERPROFILE%\Downloads\Molly export\ (Win)
// per the CLAUDE.md "default output location" convention.

use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use chrono::Local;
use serde::Serialize;
use tauri::ipc::Channel;
use tauri::{AppHandle, Manager, Runtime};
use walkdir::WalkDir;
use zip::write::SimpleFileOptions;

use crate::backup::{self};
use crate::fsutil;

const EXPORT_PREFIX: &str = "Molly-export-";
const EXPORT_FOLDER: &str = "Molly export";

#[derive(Debug, thiserror::Error)]
pub enum ExportError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("zip: {0}")]
    Zip(#[from] zip::result::ZipError),
    #[error("walkdir: {0}")]
    Walk(#[from] walkdir::Error),
    #[error("settings: {0}")]
    Settings(String),
    #[error("missing database in archive")]
    MissingDatabase,
}

impl serde::Serialize for ExportError {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.to_string())
    }
}

fn app_data_dir<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, ExportError> {
    handle
        .path()
        .app_data_dir()
        .map_err(|e| ExportError::Settings(e.to_string()))
}

fn timestamp() -> String {
    Local::now().format("%Y-%m-%d-%H%M%S").to_string()
}

fn write_manifest(zip: &mut zip::ZipWriter<fs::File>, app_version: &str) -> Result<(), ExportError> {
    let opts = SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated)
        .unix_permissions(0o644);
    zip.start_file("manifest.json", opts)?;
    let body = serde_json::json!({
        "app": "Molly",
        "version": app_version,
        "exported_at": Local::now().to_rfc3339(),
        "schema_version": 8,
        "format": "molly-export@1",
    });
    let bytes = serde_json::to_vec_pretty(&body).unwrap_or_default();
    zip.write_all(&bytes)?;
    Ok(())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ExportResult {
    pub path: String,
    pub size_bytes: u64,
    pub file_count: usize,
}

/// Streamed to the frontend so the (potentially slow) export shows a progress
/// bar instead of an unresponsive button.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ExportProgress {
    pub done: usize,
    pub total: usize,
}

fn should_skip(name: &str) -> bool {
    name.ends_with(".DS_Store") || name.ends_with(".json.tmp")
}

/// Export runs on a blocking thread (it reads + deflates the whole app-data
/// tree, which can take a while) so the UI stays responsive and progress
/// events flow. `export_full_data` is the async command wrapper.
#[tauri::command]
pub async fn export_full_data<R: Runtime>(
    handle: AppHandle<R>,
    on_progress: Channel<ExportProgress>,
) -> Result<ExportResult, ExportError> {
    tokio::task::spawn_blocking(move || export_blocking(handle, on_progress))
        .await
        .map_err(|e| ExportError::Settings(format!("export task failed: {e}")))?
}

fn export_blocking<R: Runtime>(
    handle: AppHandle<R>,
    on_progress: Channel<ExportProgress>,
) -> Result<ExportResult, ExportError> {
    let app_data = app_data_dir(&handle)?;
    fs::create_dir_all(&app_data)?;
    let export_dir = fsutil::downloads_subdir(EXPORT_FOLDER);
    fs::create_dir_all(&export_dir)?;

    let archive_name = format!("{EXPORT_PREFIX}{}.zip", timestamp());
    let out_path = export_dir.join(&archive_name);
    let tmp_path = out_path.with_extension("zip.tmp");

    let app_version = handle.package_info().version.to_string();

    // Count files up front so the frontend can show a real percentage. Cheap
    // (metadata only) relative to reading + deflating every file. +1 manifest.
    let total = WalkDir::new(&app_data)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file())
        .filter(|e| {
            !e.path()
                .strip_prefix(&app_data)
                .map(|r| should_skip(&r.to_string_lossy().replace('\\', "/")))
                .unwrap_or(true)
        })
        .count()
        + 1;
    let _ = on_progress.send(ExportProgress { done: 0, total });

    let mut file_count = 0usize;
    {
        let file = fs::File::create(&tmp_path)?;
        let mut zip = zip::ZipWriter::new(file);
        let opts = SimpleFileOptions::default()
            .compression_method(zip::CompressionMethod::Deflated)
            .unix_permissions(0o644);

        write_manifest(&mut zip, &app_version)?;
        file_count += 1;

        let mut buf = Vec::with_capacity(64 * 1024);
        for entry in WalkDir::new(&app_data).into_iter().filter_map(|e| e.ok()) {
            let path = entry.path();
            let rel = match path.strip_prefix(&app_data) {
                Ok(r) => r,
                Err(_) => continue,
            };
            if rel.as_os_str().is_empty() { continue; }
            let name = rel.to_string_lossy().replace('\\', "/");
            if should_skip(&name) { continue; }

            if entry.file_type().is_dir() {
                zip.add_directory(format!("{name}/"), opts)?;
            } else if entry.file_type().is_file() {
                zip.start_file(&name, opts)?;
                buf.clear();
                fs::File::open(path)?.read_to_end(&mut buf)?;
                zip.write_all(&buf)?;
                file_count += 1;
                // Throttle progress events (every 8 files) to avoid spamming IPC.
                if file_count % 8 == 0 {
                    let _ = on_progress.send(ExportProgress { done: file_count, total });
                }
            }
        }
        zip.finish()?;
    }
    let _ = on_progress.send(ExportProgress { done: total, total });

    if out_path.exists() { let _ = fs::remove_file(&out_path); }
    fs::rename(&tmp_path, &out_path)?;
    let size = fs::metadata(&out_path)?.len();

    Ok(ExportResult {
        path: out_path.to_string_lossy().to_string(),
        size_bytes: size,
        file_count,
    })
}

#[tauri::command]
pub fn reveal_export_dir() -> Result<(), ExportError> {
    let dir = fsutil::downloads_subdir(EXPORT_FOLDER);
    fs::create_dir_all(&dir)?;
    fsutil::reveal_in_file_browser(&dir)?;
    Ok(())
}

/// Dev-only import. Verifies the archive has molly.db, writes a safety
/// pre-import backup first (same logic as backup::restore_archive), then
/// unpacks over the app_data directory. Returns the path of the safety
/// archive. The JS side gates this behind VITE_MOLLY_DEV=1.
#[tauri::command]
pub fn import_full_export<R: Runtime>(handle: AppHandle<R>, path: String) -> Result<String, ExportError> {
    let app_data = app_data_dir(&handle)?;
    let archive = Path::new(&path);

    // Quick verification — check for molly.db before we wipe anything.
    let file = fs::File::open(archive)?;
    let mut zip_check = zip::ZipArchive::new(file)?;
    let mut has_db = false;
    for i in 0..zip_check.len() {
        if let Ok(entry) = zip_check.by_index(i) {
            let n = entry.name();
            if n == "molly.db" || n.ends_with("/molly.db") {
                has_db = true;
                break;
            }
        }
    }
    if !has_db {
        return Err(ExportError::MissingDatabase);
    }

    // Use the backup module's safety + restore flow. It writes a pre-restore
    // archive next to the picked file (or wherever backup_dir resolves to).
    let safety = backup::restore_archive(archive, &app_data)
        .map_err(|e| ExportError::Settings(e.to_string()))?;
    Ok(safety.to_string_lossy().to_string())
}
