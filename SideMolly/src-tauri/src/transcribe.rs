// Phase 5 — per-video transcription.
//
// Probes for the PhantomLives `transcribe` CLI (MLX-based whisper
// wrapper for Apple Silicon). Per spec §10 decision #10:
// "Use PhantomLives transcribe/ (MLX) if present; else bundled
//  whisper.cpp". We currently support the MLX path only — whisper.cpp
// fallback lands in Phase 5.1 if Robert ever runs SideMolly on a
// machine without MLX availability.
//
// Engine resolution (priority order):
//   1. `transcribe` binary on PATH (installed via setup script).
//   2. Direct `transcribe.py` script at ~/dev/PhantomLives/transcribe/
//      (the PhantomLives sibling repo — most likely on Robert's box).
//   3. Anything pointed at by the `PHANTOMLIVES_HOME` env var.
//
// Cached via OnceLock. The resolver returns a `TranscribeEngine`
// describing the command + leading args so dispatch can spawn it
// uniformly.
//
// Output sidecars per video — written to
// `work/<uid>/transcripts/<stem>.{txt,srt,json}`:
//
//   .json — full whisper output (segments, timings, language probe)
//   .txt  — flat text (joined segment text, no timings)
//   .srt  — subtitle format (numbered segments + timecodes)
//
// `transcribe.py` only emits one `-f <format>` at a time, so to avoid
// running whisper 3× per video we invoke once with `-f json` and
// derive the .txt + .srt locally from the segments.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, Runtime};

use crate::bundles::{work_root, BundleError};
use crate::extract::bundle_workspace_dir;

const TRANSCRIBE_TIMEOUT: Duration = Duration::from_secs(20 * 60);

// ---------------------------------------------------------------------------
// Engine resolution
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct TranscribeEngine {
    /// Executable to spawn — typically "transcribe" (shim) or
    /// "/path/to/python3" (when we go through the script directly).
    pub command: String,
    /// Args to prepend before the user-facing -i/-o/-f. Empty for the
    /// shim path; `[script_path]` for the direct-python path.
    pub leading_args: Vec<String>,
    /// Human-readable description for the Settings status panel.
    pub description: String,
}

pub fn resolve_engine() -> Option<TranscribeEngine> {
    use std::sync::OnceLock;
    static FOUND: OnceLock<Option<TranscribeEngine>> = OnceLock::new();
    FOUND.get_or_init(|| {
        // 1. Look for an installed `transcribe` shim. Same Finder-PATH-
        //    stripped probe pattern as ffmpeg / ffprobe / deep-filter.
        for candidate in &[
            "/opt/homebrew/bin/transcribe",
            "/usr/local/bin/transcribe",
            "/usr/bin/transcribe",
        ] {
            if Path::new(candidate).is_file() {
                return Some(TranscribeEngine {
                    command: (*candidate).to_string(),
                    leading_args: vec![],
                    description: format!("PhantomLives transcribe (MLX) at {candidate}"),
                });
            }
        }
        if let Ok(out) = Command::new("which").arg("transcribe").output() {
            if out.status.success() {
                let p = String::from_utf8_lossy(&out.stdout).trim().to_string();
                if !p.is_empty() && Path::new(&p).is_file() {
                    return Some(TranscribeEngine {
                        command: p.clone(),
                        leading_args: vec![],
                        description: format!("PhantomLives transcribe (MLX) at {p}"),
                    });
                }
            }
        }

        // 2. Fall back to the script in the PhantomLives sibling repo.
        //    Robert's working directory is ~/dev/PhantomLives/SideMolly,
        //    so the sibling is at ../transcribe/transcribe.py.
        let candidates: Vec<PathBuf> = vec![
            dirs::home_dir()
                .map(|h| h.join("dev/PhantomLives/transcribe/transcribe.py"))
                .unwrap_or_default(),
            std::env::var("PHANTOMLIVES_HOME").ok()
                .map(|p| PathBuf::from(p).join("transcribe/transcribe.py"))
                .unwrap_or_default(),
        ];
        for script in &candidates {
            if script.is_file() {
                // Prefer python3 from Homebrew (3.10+) over CommandLineTools
                // 3.9 (transcribe.py requires PEP 604 union syntax).
                let py = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
                    .into_iter()
                    .find(|p| Path::new(p).is_file())
                    .map(|s| s.to_string())
                    .unwrap_or_else(|| "python3".to_string());
                return Some(TranscribeEngine {
                    command: py,
                    leading_args: vec![script.to_string_lossy().to_string()],
                    description: format!(
                        "PhantomLives transcribe.py (MLX) at {}",
                        script.display(),
                    ),
                });
            }
        }
        None
    }).clone()
}

/// Parse the `__version__` constant out of a transcribe.py source
/// file without invoking Python. Caught 2026-05-24: spawning
/// `python3 transcribe.py --version` from the status command boots
/// the script's venv, which on first run pip-installs MLX/Whisper
/// (~30+ seconds). The Edit tab's refreshProcessed fires that
/// command on every `job-updated` event, piling concurrent Python
/// processes and blocking the IPC channel. Parsing the source line
/// is a few microseconds and good enough — the version is only used
/// as a badge in the Settings UI.
pub fn engine_version(engine: &TranscribeEngine) -> Option<String> {
    // For the shim path we don't have an obvious source file to parse;
    // skip the version. For the direct-python path, leading_args[0] is
    // the script file.
    let script_path = engine.leading_args.first()?;
    let src = fs::read_to_string(script_path).ok()?;
    for line in src.lines().take(40) {
        if let Some(rest) = line.strip_prefix("__version__") {
            let v = rest.trim_start_matches([' ', '=', '"', '\''])
                       .trim_end_matches([' ', '"', '\'']);
            if !v.is_empty() {
                return Some(format!("transcribe {v}"));
            }
        }
    }
    None
}

// ---------------------------------------------------------------------------
// Job params
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TranscribeVideoParams {
    pub bundle_uid: String,
    pub bundle_file_id: i64,
    pub source_path: String,
    /// Where the JSON sidecar lands. .txt + .srt are derived from
    /// this JSON and written next to it (same stem, swapped ext).
    pub json_output_path: String,
    /// Optional whisper model name. None → CLI default ("large-v3"
    /// per transcribe.py).
    pub model: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TranscribeStatus {
    pub installed: bool,
    pub command: Option<String>,
    pub description: Option<String>,
    pub version: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EnqueueTranscriptsResult {
    pub bundle_uid: String,
    pub job_ids: Vec<i64>,
    pub video_count: i64,
    /// Number of videos skipped because they already have a .txt
    /// sidecar (smart-retry default). Always 0 when called with
    /// force_all=true.
    pub skipped: i64,
    pub errors: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TranscriptRow {
    pub bundle_uid: String,
    pub in_zip_path: String,
    pub stem: String,
    pub json_path: Option<String>,
    pub txt_path: Option<String>,
    pub srt_path: Option<String>,
    pub txt_preview: Option<String>,
}

// ---------------------------------------------------------------------------
// Tauri commands
// ---------------------------------------------------------------------------

#[tauri::command]
pub fn get_transcribe_status() -> Result<TranscribeStatus, BundleError> {
    let engine = resolve_engine();
    let version = engine.as_ref().and_then(engine_version);
    Ok(TranscribeStatus {
        installed: engine.is_some(),
        command: engine.as_ref().map(|e| {
            if e.leading_args.is_empty() {
                e.command.clone()
            } else {
                format!("{} {}", e.command, e.leading_args.join(" "))
            }
        }),
        description: engine.as_ref().map(|e| e.description.clone()),
        version,
    })
}

#[tauri::command]
pub fn enqueue_bundle_transcripts<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
    force_all: Option<bool>,
) -> Result<EnqueueTranscriptsResult, BundleError> {
    let force_all = force_all.unwrap_or(false);
    // Engine validation up front — better one clear error than N
    // silently-skipped jobs.
    if resolve_engine().is_none() {
        return Err(BundleError::NotFound(
            "transcribe (MLX) not found. Install the PhantomLives `transcribe/` \
             tool — typically at ~/dev/PhantomLives/transcribe/ — or place a \
             `transcribe` CLI on PATH. See Settings → Auto-Assembly for the \
             detected path.".into(),
        ));
    }

    let workspace = bundle_workspace_dir(&work_root(&handle)?, &uid);
    let tx_dir = workspace.join("transcripts");
    fs::create_dir_all(&tx_dir)?;

    let conn = open_conn(&handle)?;

    // Same query shape as enqueue_auto_assemble — every video with a
    // working file, ordered by fansite day + position.
    let mut stmt = conn.prepare(
        "SELECT id, in_zip_path, working_path
           FROM bundle_files
          WHERE bundle_uid = ?1 AND kind = 'video'
                AND working_path IS NOT NULL AND working_path != ''
          ORDER BY
              CASE WHEN fansite_day_of_month IS NULL THEN 0 ELSE fansite_day_of_month END,
              position,
              in_zip_path",
    )?;
    let videos: Vec<(i64, String, String)> = stmt
        .query_map(params![uid], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    drop(stmt);

    if videos.is_empty() {
        return Err(BundleError::NotFound(format!(
            "bundle {uid} has no videos to transcribe"
        )));
    }

    let mut job_ids: Vec<i64> = Vec::with_capacity(videos.len());
    let errors: Vec<String> = Vec::new();
    let mut skipped: i64 = 0;

    for (bundle_file_id, in_zip, working) in &videos {
        let stem = Path::new(in_zip).file_stem()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| in_zip.clone());
        let json_path = tx_dir.join(format!("{stem}.json"));
        let txt_path = tx_dir.join(format!("{stem}.txt"));

        // Smart skip: when force_all is false (default), already-
        // transcribed videos (i.e. the .txt sidecar exists) are
        // left alone. Failed jobs leave no .txt behind, so the user's
        // common case — "retry the broken ones" — is the default. Set
        // force_all=true from the "Re-transcribe all" button to
        // re-run every video regardless.
        if !force_all && txt_path.exists() {
            skipped += 1;
            continue;
        }

        let params_struct = TranscribeVideoParams {
            bundle_uid: uid.clone(),
            bundle_file_id: *bundle_file_id,
            source_path: working.clone(),
            json_output_path: json_path.to_string_lossy().to_string(),
            model: None,
        };
        let params_json = serde_json::to_string(&params_struct).unwrap_or_else(|_| "{}".into());
        let job_id = crate::jobs::enqueue(
            &conn,
            "transcribe_video",
            &params_json,
            Some(&uid),
            Some(in_zip),
        )?;
        job_ids.push(job_id);
    }

    Ok(EnqueueTranscriptsResult {
        bundle_uid: uid,
        job_ids,
        video_count: videos.len() as i64,
        skipped,
        errors,
    })
}

#[tauri::command]
pub fn list_transcripts<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<Vec<TranscriptRow>, BundleError> {
    let workspace = bundle_workspace_dir(&work_root(&handle)?, &uid);
    let tx_dir = workspace.join("transcripts");

    let conn = open_conn(&handle)?;
    let mut stmt = conn.prepare(
        "SELECT in_zip_path
           FROM bundle_files
          WHERE bundle_uid = ?1 AND kind = 'video'
                AND working_path IS NOT NULL AND working_path != ''
          ORDER BY
              CASE WHEN fansite_day_of_month IS NULL THEN 0 ELSE fansite_day_of_month END,
              position,
              in_zip_path",
    )?;
    let videos: Vec<String> = stmt
        .query_map(params![uid], |row| row.get(0))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    drop(stmt);

    let mut rows: Vec<TranscriptRow> = Vec::with_capacity(videos.len());
    for in_zip in videos {
        let stem = Path::new(&in_zip).file_stem()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| in_zip.clone());
        let json_path = tx_dir.join(format!("{stem}.json"));
        let txt_path = tx_dir.join(format!("{stem}.txt"));
        let srt_path = tx_dir.join(format!("{stem}.srt"));
        let txt_preview = fs::read_to_string(&txt_path).ok()
            .map(|s| s.chars().take(240).collect::<String>());
        rows.push(TranscriptRow {
            bundle_uid: uid.clone(),
            in_zip_path: in_zip,
            stem,
            json_path: json_path.exists().then(|| json_path.to_string_lossy().to_string()),
            txt_path:  txt_path.exists().then(|| txt_path.to_string_lossy().to_string()),
            srt_path:  srt_path.exists().then(|| srt_path.to_string_lossy().to_string()),
            txt_preview,
        });
    }
    Ok(rows)
}

#[tauri::command]
pub fn reveal_transcript<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
    in_zip_path: String,
) -> Result<(), BundleError> {
    let workspace = bundle_workspace_dir(&work_root(&handle)?, &uid);
    let tx_dir = workspace.join("transcripts");
    if !tx_dir.exists() {
        return Err(BundleError::NotFound(format!("no transcripts for {uid}")));
    }
    let stem = Path::new(&in_zip_path).file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| in_zip_path.clone());
    // Reveal the .txt if present (most likely to want to read), else
    // the directory itself so the user can pick a format.
    let target = tx_dir.join(format!("{stem}.txt"));
    let path = if target.exists() { target } else { tx_dir };
    crate::fsutil::reveal_in_file_browser(&path)?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Dispatcher
// ---------------------------------------------------------------------------

pub fn dispatch_transcribe_video<R: Runtime>(
    handle: &AppHandle<R>,
    params: TranscribeVideoParams,
) -> Result<(), BundleError> {
    let _ = handle;
    let engine = resolve_engine().ok_or_else(|| BundleError::NotFound(
        "transcribe engine disappeared mid-batch".into(),
    ))?;
    let src = Path::new(&params.source_path);
    if !src.exists() {
        return Err(BundleError::NotFound(params.source_path.clone()));
    }
    let dst_json = PathBuf::from(&params.json_output_path);
    if let Some(parent) = dst_json.parent() { fs::create_dir_all(parent)?; }
    let tmp_json = dst_json.with_extension("sm-tmp.json");

    // Build argv: <engine.command> <engine.leading_args> -i <src>
    //   -o <tmp.json> -f json [-m <model>]
    let mut cmd = Command::new(&engine.command);
    cmd.args(&engine.leading_args);
    cmd.args([
        "-i", src.to_str().ok_or_else(|| BundleError::Io(std::io::Error::other(
            "source path is not valid UTF-8",
        )))?,
        "-o", tmp_json.to_str().ok_or_else(|| BundleError::Io(std::io::Error::other(
            "tmp path is not valid UTF-8",
        )))?,
        "-f", "json",
    ]);
    if let Some(m) = &params.model {
        cmd.args(["-m", m]);
    }
    cmd.stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped());

    let started = Instant::now();
    let mut child = cmd.spawn()
        .map_err(|e| BundleError::Io(std::io::Error::other(
            format!("transcribe spawn ({}): {e}", engine.command),
        )))?;

    let status = loop {
        match child.try_wait()? {
            Some(s) => break s,
            None => {
                if started.elapsed() > TRANSCRIBE_TIMEOUT {
                    let _ = child.kill();
                    let _ = fs::remove_file(&tmp_json);
                    return Err(BundleError::Io(std::io::Error::other(
                        format!("transcribe killed after {}s timeout", TRANSCRIBE_TIMEOUT.as_secs()),
                    )));
                }
                std::thread::sleep(Duration::from_millis(500));
            }
        }
    };

    let mut stderr = String::new();
    if let Some(mut s) = child.stderr.take() {
        use std::io::Read;
        let _ = s.read_to_string(&mut stderr);
    }
    if !status.success() {
        let _ = fs::remove_file(&tmp_json);
        return Err(BundleError::Io(std::io::Error::other(
            format!(
                "transcribe exit {:?}: {}",
                status.code(),
                stderr.trim().chars().take(900).collect::<String>(),
            ),
        )));
    }

    // Atomic rename to the final json destination so partial files are
    // never observed by `list_transcripts`.
    if dst_json.exists() { let _ = fs::remove_file(&dst_json); }
    fs::rename(&tmp_json, &dst_json)?;

    // Parse JSON and emit .txt + .srt sidecars next to the .json.
    //
    // Python's json.dumps emits bare `NaN` / `Infinity` / `-Infinity`
    // literals for non-finite floats by default (`allow_nan=True`).
    // RFC 7159 doesn't permit those tokens, so serde_json refuses to
    // parse the file. Whisper's `avg_logprob` and `no_speech_prob`
    // fields contain NaN when a segment has no speech / weird audio.
    // We don't use those fields — strip them to `null` before parse.
    // Caught 2026-05-24 by jobs 358/360/364 failing with
    // `expected value at line 16 column 22` on otherwise-fine clips.
    let json_bytes = fs::read(&dst_json)?;
    let cleaned = sanitize_python_json_literals(&String::from_utf8_lossy(&json_bytes));
    let parsed: WhisperJson = serde_json::from_str(&cleaned)
        .map_err(|e| BundleError::Io(std::io::Error::other(
            format!("transcribe wrote non-JSON output: {e}"),
        )))?;

    let txt_path = dst_json.with_extension("txt");
    let srt_path = dst_json.with_extension("srt");
    fs::write(&txt_path, render_txt(&parsed))?;
    fs::write(&srt_path, render_srt(&parsed))?;

    Ok(())
}

// ---------------------------------------------------------------------------
// Whisper JSON → txt / srt
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
struct WhisperJson {
    #[serde(default)]
    text: String,
    #[serde(default)]
    segments: Vec<WhisperSegment>,
}

#[derive(Debug, Deserialize)]
struct WhisperSegment {
    start: f64,
    end: f64,
    #[serde(default)]
    text: String,
}

fn render_txt(w: &WhisperJson) -> String {
    // Prefer the joined `text` field when whisper provides it; fall
    // back to concatenating segment text. Trim leading whitespace
    // each segment introduces.
    if !w.text.trim().is_empty() {
        return w.text.trim().to_string() + "\n";
    }
    let mut out = String::new();
    for seg in &w.segments {
        let s = seg.text.trim();
        if !s.is_empty() {
            out.push_str(s);
            out.push('\n');
        }
    }
    out
}

fn render_srt(w: &WhisperJson) -> String {
    let mut out = String::with_capacity(w.segments.len() * 80);
    for (i, seg) in w.segments.iter().enumerate() {
        out.push_str(&format!("{}\n", i + 1));
        out.push_str(&format!("{} --> {}\n", srt_ts(seg.start), srt_ts(seg.end)));
        out.push_str(seg.text.trim());
        out.push_str("\n\n");
    }
    out
}

/// Replace Python `json.dumps(allow_nan=True)` non-finite literals
/// (`NaN`, `Infinity`, `-Infinity`) with JSON `null` so the result
/// parses as RFC-7159-compliant JSON. transcribe.py uses
/// `json.dumps(result, indent=2, ensure_ascii=False)` which always
/// emits values after `: ` and ends them with a delimiter (`,`,
/// `\n`, `}`, `]`), so a small set of bounded string replacements
/// is enough — no regex dep needed.
fn sanitize_python_json_literals(s: &str) -> String {
    // Order matters: catch `-Infinity` before plain `Infinity` so the
    // longer variant doesn't get half-eaten. The trailing delimiter
    // anchors the match to JSON value positions only (avoids
    // mangling occurrences inside transcript text strings).
    let mut out = s.to_string();
    for (find, replace) in &[
        (": -Infinity,", ": null,"),
        (": -Infinity\n", ": null\n"),
        (": -Infinity}", ": null}"),
        (": -Infinity]", ": null]"),
        (": Infinity,",  ": null,"),
        (": Infinity\n", ": null\n"),
        (": Infinity}",  ": null}"),
        (": Infinity]",  ": null]"),
        (": NaN,",  ": null,"),
        (": NaN\n", ": null\n"),
        (": NaN}",  ": null}"),
        (": NaN]",  ": null]"),
    ] {
        out = out.replace(find, replace);
    }
    out
}

fn srt_ts(seconds: f64) -> String {
    let total_ms = (seconds * 1000.0).round() as i64;
    let ms = total_ms % 1000;
    let total_s = total_ms / 1000;
    let s = total_s % 60;
    let total_m = total_s / 60;
    let m = total_m % 60;
    let h = total_m / 60;
    format!("{:02}:{:02}:{:02},{:03}", h, m, s, ms)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn open_conn<R: Runtime>(handle: &AppHandle<R>) -> Result<Connection, BundleError> {
    let dir = handle.path()
        .resolve("", tauri::path::BaseDirectory::AppLocalData)
        .map_err(|e| BundleError::Io(std::io::Error::other(format!("appdata path: {e}"))))?;
    let db_path = dir.join("sidemolly.db");
    Ok(Connection::open(db_path)?)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn transcribe_video_params_round_trips_via_json() {
        let p = TranscribeVideoParams {
            bundle_uid: "u".into(),
            bundle_file_id: 7,
            source_path: "/s".into(),
            json_output_path: "/o".into(),
            model: Some("large-v3".into()),
        };
        let json = serde_json::to_string(&p).unwrap();
        assert!(json.contains("\"jsonOutputPath\""), "{json}");
        assert!(json.contains("\"bundleFileId\""), "{json}");
        let _back: TranscribeVideoParams = serde_json::from_str(&json).unwrap();
    }

    #[test]
    fn sanitize_python_json_replaces_non_finite_literals() {
        let raw = r#"{
  "text": " hello world.",
  "segments": [
    {
      "start": 0.0,
      "end": 2.5,
      "avg_logprob": NaN,
      "compression_ratio": Infinity,
      "min_logprob": -Infinity,
      "no_speech_prob": 4.281960550023278e-11
    }
  ]
}"#;
        let cleaned = sanitize_python_json_literals(raw);
        // serde_json must accept the result.
        let parsed: serde_json::Value = serde_json::from_str(&cleaned)
            .expect("sanitized JSON should parse");
        let seg = &parsed["segments"][0];
        assert!(seg["avg_logprob"].is_null());
        assert!(seg["compression_ratio"].is_null());
        assert!(seg["min_logprob"].is_null());
        // Real numbers untouched.
        assert!(seg["no_speech_prob"].as_f64().unwrap() > 0.0);
        // Transcript text untouched (no false matches against "NaN"
        // appearing inside string values — there are none here, but
        // the anchor pattern `: NaN,` etc. would skip them anyway).
        assert_eq!(parsed["text"].as_str().unwrap(), " hello world.");
    }

    #[test]
    fn srt_timestamp_format() {
        assert_eq!(srt_ts(0.0), "00:00:00,000");
        assert_eq!(srt_ts(1.5), "00:00:01,500");
        assert_eq!(srt_ts(61.234), "00:01:01,234");
        assert_eq!(srt_ts(3661.999), "01:01:01,999");
    }

    #[test]
    fn render_srt_produces_numbered_segments() {
        let w = WhisperJson {
            text: String::new(),
            segments: vec![
                WhisperSegment { start: 0.0, end: 2.0, text: " Hello world ".into() },
                WhisperSegment { start: 2.0, end: 4.5, text: "How are you?".into() },
            ],
        };
        let srt = render_srt(&w);
        assert!(srt.starts_with("1\n00:00:00,000 --> 00:00:02,000\nHello world\n\n"), "{srt}");
        assert!(srt.contains("2\n00:00:02,000 --> 00:00:04,500\nHow are you?\n\n"), "{srt}");
    }

    #[test]
    fn render_txt_prefers_top_level_text() {
        let w = WhisperJson {
            text: "Full transcript here.\n".into(),
            segments: vec![],
        };
        assert_eq!(render_txt(&w), "Full transcript here.\n");
    }

    #[test]
    fn render_txt_falls_back_to_segments() {
        let w = WhisperJson {
            text: String::new(),
            segments: vec![
                WhisperSegment { start: 0.0, end: 1.0, text: " First. ".into() },
                WhisperSegment { start: 1.0, end: 2.0, text: "Second.".into() },
                WhisperSegment { start: 2.0, end: 3.0, text: "   ".into() }, // whitespace-only — skipped
            ],
        };
        assert_eq!(render_txt(&w), "First.\nSecond.\n");
    }
}
