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
    /// The binary exists but the OS refused to launch it. The detail names the
    /// binary + the likely cause so a (copyable) error pinpoints it. Notably
    /// Windows `os error 193` (ERROR_BAD_EXE_FORMAT): ffmpeg.exe was blocked by
    /// antivirus, didn't fully install, or is the wrong architecture.
    #[error("{0}")]
    EngineWontStart(String),
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

/// Map a process-spawn failure into an actionable `MediaError`. `NotFound`
/// means the binary is absent (install/Settings problem). Otherwise the file
/// was found but the OS refused to run it — most importantly Windows
/// `os error 193` (ERROR_BAD_EXE_FORMAT), where ffmpeg.exe exists but won't
/// launch because antivirus neutered it, a manual install left it truncated,
/// or it's the wrong architecture. We name the binary path so the (now
/// copyable) error tells Robert exactly which file and why, instead of the
/// bare, mystifying "io: %1 is not a valid Win32 application (os error 193)".
pub(crate) fn spawn_error(bin: &std::path::Path, e: std::io::Error) -> MediaError {
    if e.kind() == std::io::ErrorKind::NotFound {
        return MediaError::BinaryMissing;
    }
    let path = bin.display();
    if e.raw_os_error() == Some(193) {
        MediaError::EngineWontStart(format!(
            "Molly's video engine wouldn't start: {path} isn't runnable on this PC \
             (os error 193). Windows or antivirus most likely blocked it, or Molly \
             didn't fully install. Try reinstalling Molly, or add Molly's folder as \
             an antivirus exception."
        ))
    } else {
        MediaError::EngineWontStart(format!("Molly's video engine wouldn't start ({path}): {e}"))
    }
}

/// Apply Windows' `CREATE_NO_WINDOW` so spawning the bundled console-subsystem
/// `ffmpeg.exe`/`ffprobe.exe` from Molly's GUI process doesn't flash a black
/// console window over the UI during every render/probe. No-op off Windows.
/// Every spawn site in this module routes through here.
#[cfg(windows)]
pub(crate) fn no_window(cmd: &mut tokio::process::Command) -> &mut tokio::process::Command {
    // winbase.h CREATE_NO_WINDOW. tokio::process::Command exposes this inherent
    // method on Windows (no CommandExt import needed).
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    cmd.creation_flags(CREATE_NO_WINDOW)
}

#[cfg(not(windows))]
pub(crate) fn no_window(cmd: &mut tokio::process::Command) -> &mut tokio::process::Command {
    cmd
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    #[test]
    fn spawn_error_193_names_binary_and_is_actionable() {
        // ERROR_BAD_EXE_FORMAT — the Sallie-on-Windows case.
        let e = std::io::Error::from_raw_os_error(193);
        let s = spawn_error(Path::new("/Applications/Molly/ffmpeg.exe"), e).to_string();
        assert!(s.contains("193"), "got: {s}");
        assert!(s.contains("ffmpeg.exe"), "got: {s}");
        assert!(s.to_lowercase().contains("antivirus"), "got: {s}");
    }

    #[test]
    fn spawn_error_not_found_is_binary_missing() {
        let e = std::io::Error::new(std::io::ErrorKind::NotFound, "nope");
        assert!(matches!(spawn_error(Path::new("ffmpeg"), e), MediaError::BinaryMissing));
    }
}
