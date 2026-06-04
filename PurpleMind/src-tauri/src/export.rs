// Export sink — writes a map export (PNG / SVG / PDF / JSON / Markdown) into
// the PhantomLives default output location, `~/Downloads/PurpleMind/`, unless
// the user has overridden it. The frontend renders the bytes (React Flow →
// html-to-image for raster/vector, jsPDF for PDF, pure serializers for
// JSON/Markdown), base64-encodes them, and hands them here so a single place
// owns directory creation, filename sanitisation, and reveal-in-Finder.

use std::fs;
use std::path::PathBuf;

use base64::Engine;
use serde::Serialize;

use crate::fsutil;

const APP_NAME: &str = "PurpleMind";

#[derive(Debug, thiserror::Error)]
pub enum ExportError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("decode: {0}")]
    Decode(String),
}

impl serde::Serialize for ExportError {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.to_string())
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ExportResult {
    pub output_path: String,
    pub directory: String,
}

fn resolve_dir(dir_override: Option<String>) -> PathBuf {
    match dir_override {
        Some(p) if !p.trim().is_empty() => PathBuf::from(p),
        _ => fsutil::downloads_subdir(APP_NAME),
    }
}

/// Strip path separators and other awkward characters so a map title can be
/// used as a filename stem on both macOS and Windows.
fn sanitize_stem(stem: &str) -> String {
    let cleaned: String = stem
        .chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '-',
            c if c.is_control() => '-',
            c => c,
        })
        .collect();
    let trimmed = cleaned.trim().trim_matches('.').trim();
    if trimmed.is_empty() { "untitled-map".to_string() } else { trimmed.to_string() }
}

/// Resolve the default export directory as a string (for display in the UI).
#[tauri::command]
pub fn export_dir(dir_override: Option<String>) -> String {
    resolve_dir(dir_override).to_string_lossy().to_string()
}

/// Write a base64-encoded export payload to `<dir>/<stem>.<ext>`.
///
/// `dir_override` empty/None → `~/Downloads/PurpleMind/`. The directory is
/// created on demand. Returns the absolute path written.
#[tauri::command]
pub fn save_export(
    filename: String,
    content_base64: String,
    dir_override: Option<String>,
) -> Result<ExportResult, ExportError> {
    let dir = resolve_dir(dir_override);
    fs::create_dir_all(&dir)?;

    let safe = sanitize_filename(&filename);
    let out_path = dir.join(&safe);

    let bytes = base64::engine::general_purpose::STANDARD
        .decode(content_base64.as_bytes())
        .map_err(|e| ExportError::Decode(e.to_string()))?;
    fs::write(&out_path, &bytes)?;

    Ok(ExportResult {
        output_path: out_path.to_string_lossy().to_string(),
        directory: dir.to_string_lossy().to_string(),
    })
}

/// Split a `name.ext` on the final dot (NOT via `Path`, so directory
/// separators in a map title get sanitised rather than silently dropped),
/// sanitise the stem, and keep the extension.
fn sanitize_filename(filename: &str) -> String {
    let (stem, ext) = match filename.rsplit_once('.') {
        Some((s, e)) if !s.is_empty() => (s, Some(e.to_ascii_lowercase())),
        _ => (filename, None),
    };
    let safe_stem = sanitize_stem(stem);
    match ext {
        Some(e) => format!("{safe_stem}.{e}"),
        None => safe_stem,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitize_stem_strips_separators() {
        assert_eq!(sanitize_stem("a/b:c"), "a-b-c");
        assert_eq!(sanitize_stem("   "), "untitled-map");
        assert_eq!(sanitize_stem("My Ideas"), "My Ideas");
    }

    #[test]
    fn sanitize_filename_keeps_extension() {
        assert_eq!(sanitize_filename("My Map_20260604.png"), "My Map_20260604.png");
        assert_eq!(sanitize_filename("we/ird:.svg"), "we-ird-.svg");
    }

    #[test]
    fn save_export_writes_decoded_bytes() {
        let dir = tempfile::TempDir::new().unwrap();
        let payload = base64::engine::general_purpose::STANDARD.encode(b"hello world");
        let res = save_export(
            "note.json".into(),
            payload,
            Some(dir.path().to_string_lossy().to_string()),
        )
        .expect("save succeeds");
        let written = fs::read(&res.output_path).unwrap();
        assert_eq!(written, b"hello world");
    }
}
