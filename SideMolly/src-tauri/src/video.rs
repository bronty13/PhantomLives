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
//     -c:v libx264 -crf 23 -preset medium (H.264 transcode)
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
use crate::images::WatermarkPosition;
use crate::jobs::JobRow;
use crate::thumbnails::ffmpeg_bin;

/// Max wall-clock for one video. Real ffmpeg transcodes on Apple Silicon
/// hit ~5x realtime for H.264 CRF 23 medium preset, so a 5-minute clip
/// finishes in ~1 min. 30 min cap covers a 2-hour clip with margin and
/// gives us a hard ceiling against hung jobs.
const FFMPEG_TIMEOUT: Duration = Duration::from_secs(30 * 60);

/// JSON payload persisted in jobs.params_json for kind='process_video'.
/// Keeping it self-contained means the worker can run a job months
/// later even if the source paths or watermark settings have moved.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProcessVideoParams {
    pub working_path: String,
    pub output_path: String,
    pub op_kind: String,         // e.g. "watermark_strip"
    pub watermark: bool,
    pub strip_metadata: bool,
    pub rename: bool,            // currently informational only
    pub watermark_text: Option<String>,
    pub opacity_percent: u8,
    pub position: String,        // 9-grid string
    pub font_size_pct: f32,
    pub margin_pct: f32,
    pub font_path: Option<String>,
    pub bundle_file_id: i64,
}

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
    let mut argv: Vec<String> = vec![
        "-y".into(),
        "-loglevel".into(), "error".into(),
        "-i".into(), src.to_string_lossy().to_string(),
        "-map_metadata".into(), "-1".into(),
    ];

    if params.watermark {
        let Some(text) = params.watermark_text.as_deref().filter(|t| !t.is_empty()) else {
            return Err(BundleError::NotFound("watermark text missing".into()));
        };
        let Some(font_path) = params.font_path.as_deref() else {
            return Err(BundleError::NotFound("font path missing".into()));
        };
        let pos = WatermarkPosition::parse(&params.position)
            .map_err(crate::images::ImageOpError::from)?;
        let filter = build_drawtext_filter(
            font_path,
            text,
            params.opacity_percent,
            params.font_size_pct,
            params.margin_pct,
            pos,
        );
        argv.push("-vf".into());
        argv.push(filter);
    }

    // Encoders + container flags.
    argv.extend([
        "-c:v".into(), "libx264".into(),
        "-crf".into(), "23".into(),
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

/// Build the `drawtext` filter expression for ffmpeg.
///
/// Variables ffmpeg evaluates per frame: `w` (frame width), `h`
/// (frame height), `tw` (text width), `th` (text height). Margin and
/// font size are expressed as percentages of frame height so output
/// scales sensibly across 720p / 1080p / 4K.
///
/// Path escaping for ffmpeg filter syntax: paths are single-quoted to
/// protect spaces; literal `:` is escaped (would otherwise be a filter
/// argument separator). See:
/// https://ffmpeg.org/ffmpeg-filters.html#Notes-on-filtergraph-escaping
pub fn build_drawtext_filter(
    font_path: &str,
    text: &str,
    opacity_percent: u8,
    font_size_pct: f32,
    margin_pct: f32,
    position: WatermarkPosition,
) -> String {
    let alpha = (opacity_percent.min(100) as f32) / 100.0;
    let fontfile = escape_filter_value(font_path);
    let escaped_text = escape_filter_value(text);

    // Position as ffmpeg expressions. `tw` / `th` are the rendered
    // text bounds; `w` / `h` are the frame.
    let margin = format!("h*{:.4}", margin_pct / 100.0);
    let font_size_expr = format!("h*{:.4}", font_size_pct / 100.0);
    let (x_expr, y_expr) = match position {
        WatermarkPosition::TopLeft      => (margin.clone(),                       margin.clone()),
        WatermarkPosition::TopCenter    => (format!("(w-tw)/2"),                   margin.clone()),
        WatermarkPosition::TopRight     => (format!("w-tw-{margin}"),              margin.clone()),
        WatermarkPosition::MiddleLeft   => (margin.clone(),                       format!("(h-th)/2")),
        WatermarkPosition::MiddleCenter => (format!("(w-tw)/2"),                   format!("(h-th)/2")),
        WatermarkPosition::MiddleRight  => (format!("w-tw-{margin}"),              format!("(h-th)/2")),
        WatermarkPosition::BottomLeft   => (margin.clone(),                       format!("h-th-{margin}")),
        WatermarkPosition::BottomCenter => (format!("(w-tw)/2"),                   format!("h-th-{margin}")),
        WatermarkPosition::BottomRight  => (format!("w-tw-{margin}"),              format!("h-th-{margin}")),
    };

    format!(
        "drawtext=fontfile='{fontfile}':text='{escaped_text}':fontcolor=white@{alpha:.2}:fontsize={font_size_expr}:x={x_expr}:y={y_expr}"
    )
}

/// Escape a value for use inside a single-quoted ffmpeg filter argument.
/// Backslashes and single quotes are the dangerous ones; backslash-escape
/// both. The `:` separator is harmless inside single quotes.
fn escape_filter_value(value: &str) -> String {
    value.replace('\\', "\\\\").replace('\'', "\\'")
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

    #[test]
    fn drawtext_bottom_right_uses_subtract_for_x_and_y() {
        let s = build_drawtext_filter(
            "/path/to/font.ttf", "CurseOfCurves", 20, 4.0, 2.5,
            WatermarkPosition::BottomRight,
        );
        assert!(s.contains("fontfile='/path/to/font.ttf'"));
        assert!(s.contains("text='CurseOfCurves'"));
        assert!(s.contains("fontcolor=white@0.20"));
        assert!(s.contains("fontsize=h*0.0400"));
        // Margin = h*0.0250 because 2.5/100.
        assert!(s.contains("x=w-tw-h*0.0250"), "missing x expr; got: {s}");
        assert!(s.contains("y=h-th-h*0.0250"), "missing y expr; got: {s}");
    }

    #[test]
    fn drawtext_middle_center_uses_centered_x_and_y() {
        let s = build_drawtext_filter(
            "/path/font.ttf", "T", 50, 5.0, 2.0,
            WatermarkPosition::MiddleCenter,
        );
        assert!(s.contains("x=(w-tw)/2"), "missing centered x; got: {s}");
        assert!(s.contains("y=(h-th)/2"), "missing centered y; got: {s}");
        assert!(s.contains("fontcolor=white@0.50"));
    }

    #[test]
    fn escape_filter_value_handles_quotes_and_backslashes() {
        assert_eq!(escape_filter_value("plain"), "plain");
        assert_eq!(escape_filter_value("with 'quote'"), "with \\'quote\\'");
        assert_eq!(escape_filter_value("back\\slash"), "back\\\\slash");
        // Space + colon are harmless inside the single-quoted value.
        assert_eq!(escape_filter_value("/Users/me/Application Support/font.ttf"),
                   "/Users/me/Application Support/font.ttf");
    }

    #[test]
    fn drawtext_opacity_clamps_above_100_via_min() {
        // 120 is invalid; we min-clamp to 100 which yields alpha=1.00.
        let s = build_drawtext_filter("/f.ttf", "X", 120, 4.0, 2.5, WatermarkPosition::BottomRight);
        assert!(s.contains("fontcolor=white@1.00"), "got: {s}");
    }

    #[test]
    fn drawtext_top_left_uses_margin_for_both_x_and_y() {
        let s = build_drawtext_filter("/f.ttf", "X", 20, 4.0, 2.5, WatermarkPosition::TopLeft);
        // Both expressions equal the margin value h*0.0250.
        let occurrences = s.matches("h*0.0250").count();
        assert!(occurrences >= 2, "top-left should use margin for both axes; got: {s}");
    }
}
