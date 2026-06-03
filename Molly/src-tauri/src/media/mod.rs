//! Native-ffmpeg media engine: decode/process/encode any current iPhone or
//! Windows video format into GIFs, teaser MP4s, and frame JPEGs.
//!
//! Why this exists: the WebView can't decode iPhone HEVC on Windows, and
//! ffmpeg-WASM is far too slow. We bundle a native ffmpeg (see
//! `bundle.resources` + CI) and orchestrate it from Rust, input-seeking the
//! original file so only the trimmed segment is touched. The WebView is just a
//! picker/previewer.
//!
//! Layering for the future `phantomlives-media` shared crate (SideMolly merge):
//! `filters`/`probe`/`engine` are Tauri-free; `ffmpeg_path`/`commands`/
//! `settings`/`temp` are the Molly-specific glue.

pub mod commands;
pub mod engine;
pub mod ffmpeg_path;
pub mod filters;
pub mod probe;
pub mod settings;
pub mod temp;

#[derive(Debug, thiserror::Error)]
pub enum MediaError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("ffmpeg/ffprobe not found — install ffmpeg or set a path in Settings")]
    BinaryMissing,
    #[error("could not read video info: {0}")]
    Probe(String),
    #[error("ffmpeg failed (exit {code}): {stderr}")]
    Ffmpeg { code: i32, stderr: String },
    #[error("timed out after {0}s")]
    Timeout(u64),
}

impl serde::Serialize for MediaError {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.to_string())
    }
}
