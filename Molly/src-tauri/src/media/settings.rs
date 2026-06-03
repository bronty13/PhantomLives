//! Tiny persisted settings for the media engine. Mirrors the
//! `atw_settings`/`bundles` settings-file pattern. Currently just an optional
//! ffmpeg directory override (for power users or a non-bundled install).

use std::path::Path;

const FILENAME: &str = "media_settings.json";

#[derive(Debug, Default, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MediaSettings {
    /// Directory containing `ffmpeg`/`ffprobe` to use instead of the bundled
    /// binaries. `None` = use bundled (then PATH).
    #[serde(default)]
    pub ffmpeg_dir: Option<String>,
}

pub fn load(app_data_dir: &Path) -> MediaSettings {
    let p = app_data_dir.join(FILENAME);
    std::fs::read(&p)
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok())
        .unwrap_or_default()
}

#[allow(dead_code)]
pub fn save(app_data_dir: &Path, s: &MediaSettings) -> std::io::Result<()> {
    let p = app_data_dir.join(FILENAME);
    std::fs::write(p, serde_json::to_vec_pretty(s).unwrap_or_default())
}
