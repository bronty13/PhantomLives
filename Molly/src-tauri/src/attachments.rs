// Attachment storage — copies user-picked files into a subtree of the
// app data directory so they survive moves/deletions of the original.
// Returns a path relative to app_data_dir so the DB can store a stable
// pointer that re-resolves cleanly on Windows AND macOS.

use std::fs;
use std::path::{Path, PathBuf};

use chrono::Local;
use serde::Serialize;
use tauri::{AppHandle, Manager, Runtime};
use uuid::Uuid;

use crate::fsutil;

#[derive(Debug, thiserror::Error)]
pub enum AttachmentError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("settings: {0}")]
    Settings(String),
    #[error("invalid path: {0}")]
    Invalid(String),
}

impl serde::Serialize for AttachmentError {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.to_string())
    }
}

fn app_data_dir<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, AttachmentError> {
    handle
        .path()
        .app_data_dir()
        .map_err(|e| AttachmentError::Settings(e.to_string()))
}

/// Sanitize a string for use as a single path component (basename).
/// Strips path separators and a small set of OS-unfriendly characters.
fn sanitize_component(s: &str) -> String {
    s.chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '\0' | '?' | '*' | '"' | '<' | '>' | '|' => '_',
            _ => c,
        })
        .collect()
}

/// Sanitize a category string so it can only be a leaf folder name.
fn sanitize_category(s: &str) -> String {
    let clean = sanitize_component(s);
    if clean.is_empty() { "misc".to_string() } else { clean }
}

#[derive(Debug, Serialize)]
pub struct AttachmentInfo {
    pub relative_path: String,
    pub absolute_path: String,
    pub size_bytes: u64,
}

#[tauri::command]
pub fn save_attachment<R: Runtime>(
    handle: AppHandle<R>,
    src_path: String,
    category: String,
) -> Result<AttachmentInfo, AttachmentError> {
    let src = Path::new(&src_path);
    if !src.exists() || !src.is_file() {
        return Err(AttachmentError::Invalid(src_path));
    }
    let basename = src
        .file_name()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "attachment".to_string());
    let safe_base = sanitize_component(&basename);
    let cat = sanitize_category(&category);

    let now = Local::now();
    let year = now.format("%Y").to_string();
    let month = now.format("%m").to_string();

    let app_data = app_data_dir(&handle)?;
    let target_dir = app_data
        .join("attachments")
        .join(&cat)
        .join(&year)
        .join(&month);
    fs::create_dir_all(&target_dir)?;

    let uuid = Uuid::new_v4().simple().to_string();
    let target_name = format!("{uuid}_{safe_base}");
    let target_path = target_dir.join(&target_name);

    fs::copy(src, &target_path)?;
    let meta = fs::metadata(&target_path)?;

    // Build the relative path. Use forward slashes for portability — we
    // resolve it back with PathBuf which handles both.
    let relative = format!("attachments/{cat}/{year}/{month}/{target_name}");

    Ok(AttachmentInfo {
        relative_path: relative,
        absolute_path: target_path.to_string_lossy().to_string(),
        size_bytes: meta.len(),
    })
}

fn resolve_relative<R: Runtime>(handle: &AppHandle<R>, relative: &str) -> Result<PathBuf, AttachmentError> {
    if relative.starts_with('/') || relative.contains("..") {
        return Err(AttachmentError::Invalid(relative.to_string()));
    }
    let app_data = app_data_dir(handle)?;
    Ok(app_data.join(relative))
}

#[tauri::command]
pub fn delete_attachment<R: Runtime>(handle: AppHandle<R>, relative_path: String) -> Result<(), AttachmentError> {
    let p = resolve_relative(&handle, &relative_path)?;
    if p.exists() {
        fs::remove_file(&p)?;
    }
    Ok(())
}

#[tauri::command]
pub fn reveal_attachment<R: Runtime>(handle: AppHandle<R>, relative_path: String) -> Result<(), AttachmentError> {
    let p = resolve_relative(&handle, &relative_path)?;
    fsutil::reveal_in_file_browser(&p)?;
    Ok(())
}

#[tauri::command]
pub fn open_attachment<R: Runtime>(handle: AppHandle<R>, relative_path: String) -> Result<(), AttachmentError> {
    let p = resolve_relative(&handle, &relative_path)?;
    #[cfg(target_os = "macos")]
    {
        std::process::Command::new("open").arg(&p).status()?;
    }
    #[cfg(target_os = "windows")]
    {
        std::process::Command::new("cmd").args(["/C", "start", "", &p.to_string_lossy()]).status()?;
    }
    #[cfg(all(not(target_os = "macos"), not(target_os = "windows")))]
    {
        std::process::Command::new("xdg-open").arg(&p).status()?;
    }
    Ok(())
}
