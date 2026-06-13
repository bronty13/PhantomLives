// Phase 4 — ffmpeg-driven video ops.
//
// Used by the jobs worker (jobs.rs) — sequential, one ffmpeg
// subprocess at a time. Each job operates on one video file from a
// bundle, writes a single processed output to
// `work/<UID>/processed/<basename>__<op>.mp4`, atomically via
// `.sm-tmp.mp4` + rename.
//
// Pipeline (single ffmpeg invocation per video):
//   ffmpeg
//     -i <src>
//     -map_metadata -1                    (strip global metadata)
//     [-vf drawtext=...]                  (when watermark is on)
//     -c:v libx264 -crf 18 -preset medium (H.264 transcode, near-lossless)
//     -c:a aac -b:a 128k                  (AAC audio)
//     -movflags +faststart                (metadata at start for streaming)
//     -y <dst.mp4>
//
// ffmpeg binary path is probed via `ffmpeg_bin()` from thumbnails.rs —
// Finder-launched macOS apps have a stripped PATH that excludes
// /opt/homebrew/bin, so we look for the binary in conventional
// locations first.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Runtime};

use crate::bundles::{paper_daisy_path, BundleError};
use crate::images::{overlay_xy_expr, WatermarkPosition};
use crate::jobs::JobRow;
use crate::thumbnails::ffmpeg_bin;

/// Max wall-clock for one video. Real ffmpeg transcodes on Apple Silicon
/// run several times realtime for H.264 CRF 18 medium preset (encode speed
/// is dominated by the preset, not the CRF), so a 5-minute clip finishes in
/// a couple of minutes. 30 min cap covers a 2-hour clip with margin and
/// gives us a hard ceiling against hung jobs.
const FFMPEG_TIMEOUT: Duration = Duration::from_secs(30 * 60);

/// JSON payload persisted in jobs.params_json for kind='process_video'.
/// Keeping it self-contained means the worker can run a job months
/// later even if the source paths or watermark settings have moved.
///
/// `watermark_png_path` points at a pre-rendered RGBA PNG produced by
/// `images::render_watermark_png` at enqueue time. We composite it via
/// ffmpeg's `overlay` filter (always available) instead of `drawtext`
/// (which requires libfreetype that Homebrew's stock ffmpeg lacks —
/// caught by the v0.6.0 jobs failure 2026-05-24).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProcessVideoParams {
    pub working_path: String,
    pub output_path: String,
    pub op_kind: String,         // e.g. "video_watermark_strip"
    pub watermark: bool,
    pub strip_metadata: bool,
    pub rename: bool,            // currently informational only
    pub position: String,        // 9-grid string, used by overlay xy
    pub margin_pct: f32,         // converted to absolute px against an 1080p ref
    pub watermark_png_path: Option<String>,
    pub bundle_file_id: i64,
    /// "none" | "cw" | "ccw" | "180" — pre-overlay ffmpeg transpose so
    /// the watermark lands in the corrected orientation.
    #[serde(default = "default_rotation")]
    pub rotation: String,
}

fn default_rotation() -> String { "none".to_string() }

/// Run ffmpeg synchronously. Caller is responsible for kicking this
/// off the main thread (jobs.rs worker spawns a dedicated thread).
pub fn process_video(params: &ProcessVideoParams) -> Result<(), BundleError> {
    let src = Path::new(&params.working_path);
    if !src.exists() {
        return Err(BundleError::NotFound(params.working_path.clone()));
    }
    let dst = PathBuf::from(&params.output_path);
    if let Some(parent) = dst.parent() {
        fs::create_dir_all(parent)?;
    }
    let tmp = dst.with_extension("sm-tmp.mp4");

    // Assemble argv. Build the vector so we can log it on failure.
    // Inputs:
    //   [0:v] = source video at `src`
    //   [1:v] = watermark PNG (only when params.watermark is on)
    let mut argv: Vec<String> = vec![
        "-y".into(),
        "-loglevel".into(), "error".into(),
        "-i".into(), src.to_string_lossy().to_string(),
    ];

    // Rotation step — applied to [0:v] before the watermark overlay
    // so the watermark lands in the corrected orientation. ffmpeg's
    // `transpose` filter handles 90° rotations; 180° chains two CW
    // rotations (cheap, no quality loss). When rotation is "none" we
    // skip the filter entirely.
    let rotation_filter: Option<&'static str> = match params.rotation.as_str() {
        "cw"  => Some("transpose=1"),                  // 90° clockwise
        "ccw" => Some("transpose=2"),                  // 90° counter-clockwise
        "180" => Some("transpose=1,transpose=1"),      // 180° flip
        _ => None,
    };

    if params.watermark {
        let Some(wm_path) = params.watermark_png_path.as_deref() else {
            return Err(BundleError::NotFound("watermark PNG path missing".into()));
        };
        if !Path::new(wm_path).exists() {
            return Err(BundleError::NotFound(format!("watermark PNG not at {wm_path}")));
        }
        argv.extend(["-i".into(), wm_path.to_string()]);

        let pos = WatermarkPosition::parse(&params.position)
            .map_err(crate::images::ImageOpError::from)?;
        // Probe actual video height for margin sizing — falls back to
        // 1080 when ffprobe is unavailable. Note: when rotation swaps
        // dimensions (cw/ccw), the rotated frame's "height" is the
        // source width; ffmpeg `overlay` references the rotated stream
        // so the margin is still proportional to the visible frame.
        let video_height = crate::thumbnails::probe_video_height(src).unwrap_or(1080) as f32;
        let margin_px = ((video_height * params.margin_pct / 100.0).round() as i32).max(8);
        let (x, y) = overlay_xy_expr(pos, margin_px);
        // `format=rgb` forces ffmpeg to convert the video frame to RGB
        // for the composite (vs the default `yuv420` which subsamples
        // chroma and visually attenuates white watermark text, and
        // vs `format=auto` which keeps yuv when both inputs are
        // yuv-compatible). The downstream `-pix_fmt yuv420p` converts
        // back to yuv420p for x264 encoding.
        let filter_complex = if let Some(rot) = rotation_filter {
            format!("[0:v]{rot}[rot];[rot][1:v]overlay=x={x}:y={y}:format=rgb")
        } else {
            format!("[0:v][1:v]overlay=x={x}:y={y}:format=rgb")
        };
        argv.extend(["-filter_complex".into(), filter_complex]);
    } else if let Some(rot) = rotation_filter {
        // Rotation-only path (no watermark).
        argv.extend(["-vf".into(), rot.to_string()]);
    }

    // Strip metadata after the filter graph so it applies to the final
    // muxed output. ffmpeg accepts the flag at any position; keeping
    // it after -filter_complex matches the ffmpeg-cli conventions.
    argv.extend(["-map_metadata".into(), "-1".into()]);

    // Encoders + container flags.
    argv.extend([
        "-c:v".into(), "libx264".into(),
        // CRF 18 — visually-lossless to the source. The bundle videos are
        // already-compressed phone footage (~3.5 Mbps 720p); a re-encode
        // stacks a second generation of loss, so we keep the quality target
        // high. CRF 23 (the old value) roughly halved the source bitrate and
        // softened fine detail (skin/hair/fabric). Larger files are an
        // accepted trade for posting-grade quality. (v0.27.2)
        "-crf".into(), "18".into(),
        "-preset".into(), "medium".into(),
        "-pix_fmt".into(), "yuv420p".into(),
        "-c:a".into(), "aac".into(),
        "-b:a".into(), "128k".into(),
        "-movflags".into(), "+faststart".into(),
    ]);
    argv.push(tmp.to_string_lossy().to_string());

    let bin = ffmpeg_bin();
    let started = Instant::now();
    let mut child = Command::new(bin)
        .args(&argv)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| BundleError::Io(std::io::Error::other(
            format!("ffmpeg spawn failed (bin={bin}): {e}"),
        )))?;

    // Bound the wall-clock; kill on timeout.
    let status = loop {
        match child.try_wait()? {
            Some(s) => break s,
            None => {
                if started.elapsed() > FFMPEG_TIMEOUT {
                    let _ = child.kill();
                    let _ = fs::remove_file(&tmp);
                    return Err(BundleError::Io(std::io::Error::other(
                        format!("ffmpeg killed after {}s timeout", FFMPEG_TIMEOUT.as_secs()),
                    )));
                }
                std::thread::sleep(Duration::from_millis(250));
            }
        }
    };

    let mut stderr = String::new();
    if let Some(mut s) = child.stderr.take() {
        use std::io::Read;
        let _ = s.read_to_string(&mut stderr);
    }

    if !status.success() {
        let _ = fs::remove_file(&tmp);
        return Err(BundleError::Io(std::io::Error::other(
            format!(
                "ffmpeg exit {:?}: {}",
                status.code(),
                stderr.trim().chars().take(800).collect::<String>(),
            ),
        )));
    }

    // Atomic rename to final destination.
    if dst.exists() { let _ = fs::remove_file(&dst); }
    fs::rename(&tmp, &dst)?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Jobs dispatcher — invoked by jobs.rs when a row of kind='process_video'
// claims the worker. Reads the params JSON, calls process_video, writes
// the processed_files row on success.
// ---------------------------------------------------------------------------

pub fn dispatch_process_video<R: Runtime>(
    handle: &AppHandle<R>,
    conn: &Connection,
    job: &JobRow,
) -> Result<(), BundleError> {
    let _ = handle; // reserved for future emit progress
    let params: ProcessVideoParams = serde_json::from_str(&job.params_json)
        .map_err(|e| BundleError::Io(std::io::Error::other(format!("bad params: {e}"))))?;

    process_video(&params)?;

    // Record the processed file (UPSERT keyed on bundle_file_id + op_kind).
    conn.execute(
        "INSERT INTO processed_files (bundle_file_id, op_kind, output_path)
         VALUES (?1, ?2, ?3)
         ON CONFLICT(bundle_file_id, op_kind) DO UPDATE SET
             output_path = excluded.output_path,
             created_at = datetime('now')",
        params![params.bundle_file_id, params.op_kind, params.output_path],
    )?;
    Ok(())
}

/// Public re-export so bundles.rs can resolve the bundled font path
/// without re-implementing the resource fallback.
pub fn resolve_font_path<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, BundleError> {
    paper_daisy_path(handle)
}

// ---------------------------------------------------------------------------
// Tests — drawtext filter assembly is pure + deterministic, so we lock
// the expression syntax we send to ffmpeg here. Actual end-to-end
// ffmpeg invocation is verified at build-time against Robert's real
// bundles (see the universal end-of-task rule).
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    /// The serialized ProcessVideoParams must round-trip cleanly —
    /// jobs.params_json stores this and the worker pulls it back out
    /// later. camelCase contract verified in lib.rs.
    #[test]
    fn process_video_params_round_trips_via_json() {
        let p = ProcessVideoParams {
            working_path: "/work/in.mov".into(),
            output_path: "/work/out.mp4".into(),
            op_kind: "video_watermark_strip_rotcw".into(),
            watermark: true, strip_metadata: true, rename: false,
            position: "bottom-right".into(),
            margin_pct: 2.5,
            watermark_png_path: Some("/work/.wm/abc.png".into()),
            bundle_file_id: 42,
            rotation: "cw".into(),
        };
        let json = serde_json::to_string(&p).unwrap();
        // camelCase over the wire.
        assert!(json.contains("\"watermarkPngPath\""), "got: {json}");
        assert!(json.contains("\"marginPct\""), "got: {json}");
        let back: ProcessVideoParams = serde_json::from_str(&json).unwrap();
        assert_eq!(back.bundle_file_id, 42);
        assert_eq!(back.position, "bottom-right");
    }
}
