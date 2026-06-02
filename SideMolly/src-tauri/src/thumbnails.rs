// Per-file thumbnail generation — Phase 1c.
//
// Two backends behind a single `generate_for_file` entry point:
//
//   - **Image**  — JPEG/PNG/GIF/WebP via the `image` crate. Decoded
//                  in-process, resized to MAX_DIM preserving aspect,
//                  written out as quality-80 JPEG.
//   - **Video**  — `ffmpeg -ss 1 -i <in> -frames:v 1 -vf scale=<dim>:-1
//                  -q:v 5 <out.jpg>`. Spawned via std::process::Command
//                  with a wait_with_output() that's bounded by a kill
//                  timer in a separate thread. If `ffmpeg` isn't on
//                  PATH or any step fails, returns Ok(None) — the
//                  caller falls back to the kind glyph.
//
// All other file kinds (info / log / manifest / other / HEIC images
// we don't yet decode) return Ok(None).

use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Duration;

/// Long edge of the thumbnail image in px. 256 reads cleanly at every
/// S / M / L size in the Bundle workspace + is small enough on disk
/// (~10–30 KB per JPEG) to ship in Phase 11 post-bundle ZIPs.
const MAX_DIM: u32 = 256;

/// Hard cap on ffmpeg's elapsed time. Verified-hash Molly bundles
/// finish in milliseconds; 10s is a safety net for the pathological
/// case (corrupt file, ffmpeg hang).
const FFMPEG_TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Debug, thiserror::Error)]
pub enum ThumbnailError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("image: {0}")]
    Image(String),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThumbnailKind {
    Image,
    Video,
}

/// Generate a thumbnail for `working_path` of kind `kind` ("image" /
/// "video" / anything else) into `output_dir`. Filename is a sha256-
/// truncated prefix of `in_zip_path` so it's stable across re-ingests
/// and easy to grep in the work/ dir.
///
/// Returns `Ok(Some(path))` when a thumbnail was successfully written,
/// `Ok(None)` for unsupported kinds or non-fatal failures (no ffmpeg,
/// ffmpeg timeout, HEIC decode etc.). Only filesystem-level errors
/// propagate as `Err`.
pub fn generate_for_file(
    kind: &str,
    in_zip_path: &str,
    working_path: &Path,
    output_dir: &Path,
) -> Result<Option<PathBuf>, ThumbnailError> {
    std::fs::create_dir_all(output_dir)?;
    let key = thumb_key(in_zip_path);
    let out_path = output_dir.join(format!("{key}.jpg"));

    // Idempotency: if the thumbnail already exists and is non-empty,
    // skip regeneration. The hash key ties to the in_zip_path so a
    // change to the source file inside the bundle invalidates the
    // older sha-prefix and we'd write a new file.
    if let Ok(meta) = std::fs::metadata(&out_path) {
        if meta.is_file() && meta.len() > 0 {
            return Ok(Some(out_path));
        }
    }

    match kind {
        "image" => match generate_image_thumb(working_path, &out_path) {
            Ok(()) => Ok(Some(out_path)),
            // Unsupported codecs (e.g. HEIC) are not fatal.
            Err(ThumbnailError::Image(_)) => Ok(None),
            Err(other) => Err(other),
        },
        "video" => Ok(generate_video_thumb(working_path, &out_path)),
        _ => Ok(None),
    }
}

fn generate_image_thumb(src: &Path, dst: &Path) -> Result<(), ThumbnailError> {
    let img = image::open(src).map_err(|e| ThumbnailError::Image(e.to_string()))?;
    let resized = img.thumbnail(MAX_DIM, MAX_DIM);
    // Write JPEG at quality 80. The `image` crate's JpegEncoder takes
    // a quality 1..=100; 80 is a comfortable balance for these sizes.
    //
    // Tmp suffix: `.sm-tmp.jpg` (not `.jpg.sm-tmp`) so the final
    // extension is still `.jpg`. ffmpeg sniffs the LAST extension to
    // pick an output muxer; `.sm-tmp` confuses it.
    let tmp = dst.with_extension("sm-tmp.jpg");
    {
        let mut file = std::fs::File::create(&tmp)?;
        let mut encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut file, 80);
        encoder
            .encode_image(&resized.to_rgb8())
            .map_err(|e| ThumbnailError::Image(e.to_string()))?;
        file.flush()?;
    }
    if dst.exists() { let _ = std::fs::remove_file(dst); }
    std::fs::rename(&tmp, dst)?;
    Ok(())
}

/// macOS apps launched from Finder inherit a minimal PATH (`/usr/bin:/bin:
/// /usr/sbin:/sbin`) that doesn't include `/opt/homebrew/bin` or
/// `/usr/local/bin` where Homebrew ffmpeg lives. Probing the conventional
/// locations directly is more reliable than relying on the spawned
/// command picking it up via PATH. Falls back to bare "ffmpeg" so a
/// custom PATH (set in tauri.conf.json or via a shim) still works.
pub fn ffmpeg_bin() -> &'static str {
    use std::sync::OnceLock;
    static FOUND: OnceLock<String> = OnceLock::new();
    FOUND
        .get_or_init(|| {
            for candidate in &[
                "/opt/homebrew/bin/ffmpeg",
                "/usr/local/bin/ffmpeg",
                "/usr/bin/ffmpeg",
            ] {
                if std::path::Path::new(candidate).is_file() {
                    return (*candidate).to_string();
                }
            }
            "ffmpeg".to_string()
        })
        .as_str()
}

/// Sibling of `ffmpeg_bin` — same Finder-PATH probe but for `ffprobe`.
/// Homebrew ships them in the same `bin/` directory so the candidate
/// list mirrors ffmpeg.
pub fn ffprobe_bin() -> &'static str {
    use std::sync::OnceLock;
    static FOUND: OnceLock<String> = OnceLock::new();
    FOUND
        .get_or_init(|| {
            for candidate in &[
                "/opt/homebrew/bin/ffprobe",
                "/usr/local/bin/ffprobe",
                "/usr/bin/ffprobe",
            ] {
                if std::path::Path::new(candidate).is_file() {
                    return (*candidate).to_string();
                }
            }
            "ffprobe".to_string()
        })
        .as_str()
}

/// Optional locator for the `deep-filter` CLI binary (DeepFilterNet).
/// Returns the resolved path if found in any conventional install
/// location; `None` otherwise. Cached via `OnceLock` on first call.
///
/// Why optional: DeepFilterNet is a heavy dep (Rust binary + bundled
/// ONNX model, ~75MB on macOS arm64). We don't bundle it — users
/// install via `cargo install --git https://github.com/Rikorose/DeepFilterNet
/// --bin deep-filter` or download a GitHub Release. Auto-assemble's
/// voice-isolation step is wired to use it when present, and the
/// Settings → Auto-Assembly panel shows install status.
pub fn deep_filter_bin() -> Option<&'static str> {
    use std::sync::OnceLock;
    static FOUND: OnceLock<Option<String>> = OnceLock::new();
    FOUND.get_or_init(|| {
        // Standard install paths Homebrew/cargo write to, plus the
        // PATH default. We probe absolute paths first because Finder-
        // launched macOS apps inherit a stripped PATH that excludes
        // `/opt/homebrew/bin` and `~/.cargo/bin` (same issue we hit
        // with ffmpeg in Phase 4).
        let candidates: Vec<std::path::PathBuf> = vec![
            "/opt/homebrew/bin/deep-filter".into(),
            "/usr/local/bin/deep-filter".into(),
            "/usr/bin/deep-filter".into(),
            dirs::home_dir()
                .map(|h| h.join(".cargo/bin/deep-filter"))
                .unwrap_or_default(),
        ];
        for c in &candidates {
            if c.is_file() {
                return Some(c.to_string_lossy().to_string());
            }
        }
        // Last-resort PATH lookup. Most reliable when sidemolly is
        // launched from a shell rather than Finder.
        if let Ok(out) = Command::new("which").arg("deep-filter").output() {
            if out.status.success() {
                let p = String::from_utf8_lossy(&out.stdout).trim().to_string();
                if !p.is_empty() && std::path::Path::new(&p).is_file() {
                    return Some(p);
                }
            }
        }
        None
    }).as_deref()
}

/// Run `deep-filter --version` and return the trimmed first line. Used
/// by the Settings panel status indicator.
pub fn deep_filter_version() -> Option<String> {
    let bin = deep_filter_bin()?;
    let out = Command::new(bin).arg("--version").output().ok()?;
    if !out.status.success() { return None; }
    let raw = String::from_utf8(out.stdout).ok()?;
    raw.lines().next().map(|s| s.trim().to_string())
}

/// Probe a video file for its first video-stream height (pixels). Used
/// by the Phase 4 watermark pipeline to size the overlay PNG against
/// the actual frame — not a hardcoded 1080-px reference (the bug
/// caught 2026-05-24: 720p videos got watermark text rendered for a
/// 1080-tall frame, making the glyphs ~1/3rd the size of the image
/// watermark on iPhone-sized photos).
///
/// Returns `None` when ffprobe is unavailable, errors, or returns an
/// unparseable height. Caller decides the fallback (currently 1080).
pub fn probe_video_height(path: &Path) -> Option<u32> {
    let bin = ffprobe_bin();
    let output = Command::new(bin)
        .args([
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=height",
            "-of", "csv=p=0",
        ])
        .arg(path)
        .output()
        .ok()?;
    if !output.status.success() { return None; }
    let s = String::from_utf8(output.stdout).ok()?;
    s.trim().parse::<u32>().ok()
}

/// Probe a video's coded pixel dimensions `(width, height)` via ffprobe.
/// Returns `None` when ffprobe is unavailable, errors, or the output is
/// unparseable. Note: this is the *coded* size and ignores any
/// rotation/display-matrix metadata — callers that care about visual
/// orientation must fold in the file's `rotation_degrees`.
pub fn probe_video_dimensions(path: &Path) -> Option<(u32, u32)> {
    let bin = ffprobe_bin();
    let output = Command::new(bin)
        .args([
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height",
            "-of", "csv=p=0:s=x",
        ])
        .arg(path)
        .output()
        .ok()?;
    if !output.status.success() { return None; }
    let s = String::from_utf8(output.stdout).ok()?;
    let (w, h) = s.trim().split_once('x')?;
    Some((w.trim().parse().ok()?, h.trim().parse().ok()?))
}

/// Probe a video's duration in seconds via ffprobe. `None` when ffprobe is
/// unavailable, errors, or the value is unparseable / non-positive.
pub fn probe_video_duration(path: &Path) -> Option<f64> {
    let bin = ffprobe_bin();
    let output = Command::new(bin)
        .args([
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "csv=p=0",
        ])
        .arg(path)
        .output()
        .ok()?;
    if !output.status.success() { return None; }
    let s = String::from_utf8(output.stdout).ok()?;
    let d: f64 = s.trim().parse().ok()?;
    if d.is_finite() && d > 0.0 { Some(d) } else { None }
}

/// ffmpeg `transpose` filter chain for a per-file rotation (0/90/180/270),
/// matching auto-assembly's orientation. Empty when no rotation.
pub fn transpose_filter(rotation_degrees: i64) -> Option<&'static str> {
    match rotation_degrees {
        90 => Some("transpose=1"),               // 90° clockwise
        270 => Some("transpose=2"),              // 90° counter-clockwise
        180 => Some("transpose=1,transpose=1"),  // 180°
        _ => None,
    }
}

/// Read a JPEG and apply a per-file rotation (0/90/180/270) so it displays
/// upright, returning re-encoded JPEG bytes. Rotation 0 (or a decode failure)
/// returns the original bytes unchanged. Used to right thumbnails for the
/// summary grid and the processed-output previews.
pub fn rotated_jpeg_bytes(path: &Path, rotation_degrees: i64) -> Option<Vec<u8>> {
    let original = std::fs::read(path).ok()?;
    if rotation_degrees % 360 == 0 {
        return Some(original);
    }
    let img = match image::load_from_memory(&original) {
        Ok(i) => i,
        Err(_) => return Some(original), // hand back what we have
    };
    let rotated = match rotation_degrees.rem_euclid(360) {
        90 => img.rotate90(),
        180 => img.rotate180(),
        270 => img.rotate270(),
        _ => img,
    };
    let mut out = std::io::Cursor::new(Vec::new());
    match rotated.write_to(&mut out, image::ImageFormat::Jpeg) {
        Ok(()) => Some(out.into_inner()),
        Err(_) => Some(original),
    }
}

fn generate_video_thumb(src: &Path, dst: &Path) -> Option<PathBuf> {
    let bin = ffmpeg_bin();
    // Tmp suffix ends in `.jpg` so ffmpeg can sniff the output muxer
    // (image2/mjpeg). Earlier `.jpg.sm-tmp` made ffmpeg exit 234 with
    // "Unable to choose an output format" — confirmed via stderr capture.
    let tmp = dst.with_extension("sm-tmp.jpg");
    let spawn_result = Command::new(bin)
        .args([
            "-y",
            "-loglevel", "error",
            "-ss", "1",
            "-i",
        ])
        .arg(src)
        .args([
            "-frames:v", "1",
            "-vf", &format!("scale={MAX_DIM}:-1:flags=lanczos"),
            "-q:v", "5",
        ])
        .arg(&tmp)
        .stdin(Stdio::null())
        // Capture stderr so failures surface in stderr/Console.app
        // instead of silently producing a kind-glyph fallback.
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn();
    let mut child = match spawn_result {
        Ok(c) => c,
        Err(e) => {
            eprintln!("[sidemolly:thumb] ffmpeg spawn failed (bin={bin}): {e}");
            return None;
        }
    };

    let started = std::time::Instant::now();
    let outcome = loop {
        match child.try_wait() {
            Ok(Some(status)) => break Some(status),
            Ok(None) => {
                if started.elapsed() > FFMPEG_TIMEOUT {
                    let _ = child.kill();
                    break None;
                }
                std::thread::sleep(Duration::from_millis(50));
            }
            Err(_) => break None,
        }
    };

    // Drain stderr for diagnostics regardless of success.
    let mut stderr_buf = String::new();
    if let Some(mut s) = child.stderr.take() {
        use std::io::Read;
        let _ = s.read_to_string(&mut stderr_buf);
    }

    match outcome {
        Some(status) if status.success() => {
            if dst.exists() { let _ = std::fs::remove_file(dst); }
            match std::fs::rename(&tmp, dst) {
                Ok(()) => Some(dst.to_path_buf()),
                Err(e) => {
                    eprintln!("[sidemolly:thumb] rename {tmp:?} -> {dst:?} failed: {e}");
                    None
                }
            }
        }
        Some(status) => {
            eprintln!(
                "[sidemolly:thumb] ffmpeg {bin} {src:?} exited {status}: {}",
                stderr_buf.trim()
            );
            let _ = std::fs::remove_file(&tmp);
            None
        }
        None => {
            eprintln!("[sidemolly:thumb] ffmpeg {bin} {src:?} killed (timeout)");
            let _ = std::fs::remove_file(&tmp);
            None
        }
    }
}

/// Stable filename for the thumbnail. We don't need cryptographic
/// strength — just a deterministic, filesystem-safe key derived from
/// the in-zip path.
fn thumb_key(in_zip_path: &str) -> String {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(in_zip_path.as_bytes());
    let digest = hasher.finalize();
    let mut s = String::with_capacity(16);
    const HEX: &[u8; 16] = b"0123456789abcdef";
    for b in digest.iter().take(8) {
        s.push(HEX[(b >> 4) as usize] as char);
        s.push(HEX[(b & 0x0f) as usize] as char);
    }
    s
}

/// True for kinds we'd at least try to thumbnail. Used by the ingest
/// caller to filter the bundle_files list before calling
/// `generate_for_file` per row.
#[inline]
pub fn is_thumbnailable_kind(kind: &str) -> bool {
    matches!(kind, "image" | "video")
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write as _;
    use tempfile::TempDir;

    /// Build a 4×4 RGB JPEG in memory so we don't depend on a binary fixture.
    fn write_tiny_jpeg(path: &Path) {
        let img = image::ImageBuffer::from_fn(8u32, 8u32, |x, _| {
            image::Rgb([(x * 32) as u8, 0, 0])
        });
        let mut file = std::fs::File::create(path).unwrap();
        let mut enc = image::codecs::jpeg::JpegEncoder::new(&mut file);
        enc.encode_image(&img).unwrap();
        file.flush().unwrap();
    }

    #[test]
    fn image_thumb_writes_a_smaller_jpeg() {
        let dir = TempDir::new().unwrap();
        let src = dir.path().join("source.jpg");
        write_tiny_jpeg(&src);
        let out_dir = dir.path().join("thumbs");
        let r = generate_for_file("image", "Photos/00001_source.jpg", &src, &out_dir).unwrap();
        let r = r.expect("image thumb returned a path");
        assert!(r.exists());
        assert!(r.starts_with(&out_dir));
        assert_eq!(r.extension().and_then(|e| e.to_str()), Some("jpg"));
    }

    #[test]
    fn idempotent_skip_when_thumb_exists() {
        let dir = TempDir::new().unwrap();
        let src = dir.path().join("source.jpg");
        write_tiny_jpeg(&src);
        let out_dir = dir.path().join("thumbs");
        let first = generate_for_file("image", "p.jpg", &src, &out_dir).unwrap().unwrap();
        let mtime1 = std::fs::metadata(&first).unwrap().modified().unwrap();
        std::thread::sleep(Duration::from_millis(50));
        // Re-run with the source removed — if the path-existence check
        // didn't short-circuit, image::open() would explode.
        std::fs::remove_file(&src).unwrap();
        let second = generate_for_file("image", "p.jpg", &src, &out_dir).unwrap().unwrap();
        assert_eq!(first, second);
        let mtime2 = std::fs::metadata(&second).unwrap().modified().unwrap();
        assert_eq!(mtime1, mtime2, "second call must not rewrite the file");
    }

    #[test]
    fn corrupt_image_returns_none_not_err() {
        let dir = TempDir::new().unwrap();
        let src = dir.path().join("corrupt.jpg");
        std::fs::write(&src, b"not a real jpeg, lol").unwrap();
        let out_dir = dir.path().join("thumbs");
        // Image::open fails; we map that to Ok(None) so ingest doesn't abort.
        let r = generate_for_file("image", "Photos/00001_corrupt.jpg", &src, &out_dir).unwrap();
        assert!(r.is_none());
    }

    #[test]
    fn non_media_kinds_return_none() {
        let dir = TempDir::new().unwrap();
        let src = dir.path().join("info.md");
        std::fs::write(&src, b"# hi").unwrap();
        let out_dir = dir.path().join("thumbs");
        assert!(generate_for_file("info", "info.md", &src, &out_dir).unwrap().is_none());
        assert!(generate_for_file("log",  "Molly.log", &src, &out_dir).unwrap().is_none());
        assert!(generate_for_file("other", "x", &src, &out_dir).unwrap().is_none());
    }

    #[test]
    fn video_no_ffmpeg_returns_none() {
        // We can't easily guarantee ffmpeg is absent in test env, but
        // we can at least exercise the path with a non-video file to
        // confirm it doesn't propagate an error when the binary errors
        // out or is missing.
        let dir = TempDir::new().unwrap();
        let src = dir.path().join("fake.mp4");
        std::fs::write(&src, b"not a real mp4").unwrap();
        let out_dir = dir.path().join("thumbs");
        let r = generate_for_file("video", "Video/00001_x.mp4", &src, &out_dir).unwrap();
        // Either None (ffmpeg failed or missing) or Some (ffmpeg present
        // and somehow extracted… very unlikely from garbage). Both OK.
        assert!(r.is_none() || r.unwrap().exists());
    }

    #[test]
    fn thumb_key_is_stable() {
        let a = thumb_key("FanSite/01_01_IMG_3488.jpg");
        let b = thumb_key("FanSite/01_01_IMG_3488.jpg");
        let c = thumb_key("FanSite/01_02_other.jpg");
        assert_eq!(a, b);
        assert_ne!(a, c);
        assert_eq!(a.len(), 16);
    }
}
