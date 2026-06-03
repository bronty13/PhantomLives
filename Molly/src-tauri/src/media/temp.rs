//! Temp/cache file management for media jobs. Per-job dirs auto-delete on drop;
//! preview proxies are cached under a stable key (source path + mtime) so
//! re-editing the same source reuses the proxy.

use std::path::{Path, PathBuf};
use tauri::{AppHandle, Manager, Runtime};

use crate::media::MediaError;

fn media_cache<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, MediaError> {
    let dir = handle
        .path()
        .app_cache_dir()
        .map_err(|e| MediaError::Probe(format!("app_cache_dir: {e}")))?
        .join("media");
    std::fs::create_dir_all(&dir)?;
    Ok(dir)
}

/// A scratch directory for a single render; removed when dropped.
pub struct JobDir {
    pub path: PathBuf,
}

impl JobDir {
    pub fn new<R: Runtime>(handle: &AppHandle<R>) -> Result<Self, MediaError> {
        let path = media_cache(handle)?.join(uuid::Uuid::new_v4().simple().to_string());
        std::fs::create_dir_all(&path)?;
        Ok(Self { path })
    }

    pub fn file(&self, name: &str) -> PathBuf {
        self.path.join(name)
    }
}

impl Drop for JobDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.path);
    }
}

/// Stable cache path for a source's preview proxy: keyed on absolute path +
/// last-modified time so edits to the file invalidate it.
pub fn proxy_cache_path<R: Runtime>(handle: &AppHandle<R>, src: &Path) -> Result<PathBuf, MediaError> {
    use sha2::{Digest, Sha256};
    let dir = media_cache(handle)?.join("proxies");
    std::fs::create_dir_all(&dir)?;
    let mtime = std::fs::metadata(src)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_millis())
        .unwrap_or(0);
    let mut h = Sha256::new();
    h.update(src.to_string_lossy().as_bytes());
    h.update(mtime.to_le_bytes());
    let key = &format!("{:x}", h.finalize())[..16];
    Ok(dir.join(format!("{key}.mp4")))
}
