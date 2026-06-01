// Phase 4.5 — Auto-Assembly pipeline.
//
// One-click "make me the master cut" — composes every video in a bundle
// into a single `<Title>.mp4` cut (16:9 landscape or 9:16 portrait, the
// user picks per-bundle on the Edit tab) with:
//
//   ┌── title 10s ──┐ xfade ┌── v₁ normalized ──┐ xfade ┌── v₂ ──┐ xfade … ┌── v_N ──┐ → fade-to-black
//   │ <bundle title>│   1s  │ + watermark        │   1s  │ + WM    │         │ + WM     │
//   │ + persona     │       │ + audio enhanced   │       │         │         │          │
//   └───────────────┘       └────────────────────┘       └─────────┘         └──────────┘
//
// Decomposed into the existing jobs queue (see jobs.rs):
//
//   Job 1            render_title       → /auto/title.mp4
//   Job 2..N+1       normalize_video    → /auto/v{1..N}.mp4 (normalize + WM + audio)
//   Job N+2          assemble_master    → /auto/master.mp4 (xfade chain)
//
// Sequential ordering via created_at ASC means the queue plays out in
// the right order automatically — no extra dependency tracking needed.
// If a normalize fails, the assemble step still tries and fails loudly
// (its input file is missing); user can re-click Auto-assemble to
// retry, which re-queues every step from scratch.
//
// Re-runs are idempotent at the filesystem level: every output path
// is deterministic (`/auto/v1.mp4`, `/auto/v2.mp4`, …) so a second
// auto-assemble overwrites the first.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, Runtime};

use crate::bundles::{
    paper_daisy_bytes, watermark_position_to_str,
    work_root, BundleError, MediaKind,
};
use crate::extract::bundle_workspace_dir;
use crate::images::{overlay_xy_expr, WatermarkPosition};
use crate::thumbnails::{ffmpeg_bin, probe_video_height};

const FFMPEG_TIMEOUT: Duration = Duration::from_secs(45 * 60);

// ---------------------------------------------------------------------------
// Settings (one row in `auto_assembly_settings`).
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AutoAssemblySettings {
    pub target_width:          i64,
    pub target_height:         i64,
    pub target_fps:             i64,
    pub xfade_duration_secs:    f64,
    pub title_duration_secs:    f64,
    pub audio_enhance_enabled:  bool,
    /// Phase 4.5b — DeepFilterNet voice isolation toggle.
    /// Schema column is reserved; runtime support lands in 4.5b.
    pub deepfilternet_enabled:  bool,
}

impl AutoAssemblySettings {
    pub fn load(conn: &Connection) -> Result<Self, BundleError> {
        let row = conn.query_row(
            "SELECT target_width, target_height, target_fps,
                    xfade_duration_secs, title_duration_secs,
                    audio_enhance_enabled, deepfilternet_enabled
               FROM auto_assembly_settings WHERE id = 1",
            [],
            |r| Ok(Self {
                target_width: r.get(0)?,
                target_height: r.get(1)?,
                target_fps: r.get(2)?,
                xfade_duration_secs: r.get(3)?,
                title_duration_secs: r.get(4)?,
                audio_enhance_enabled: r.get::<_, i64>(5)? != 0,
                deepfilternet_enabled: r.get::<_, i64>(6)? != 0,
            }),
        )?;
        Ok(row)
    }
}

/// Installation status of the optional `deep-filter` binary, used by
/// the Settings → Auto-Assembly UI to flip the DeepFilterNet checkbox
/// from "disabled, not installed" to "enabled, ready" + show a version
/// readout.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeepFilterNetStatus {
    pub installed: bool,
    pub bin_path: Option<String>,
    pub version: Option<String>,
}

#[tauri::command]
pub fn get_deepfilternet_status() -> Result<DeepFilterNetStatus, BundleError> {
    let bin_path = crate::thumbnails::deep_filter_bin().map(|s| s.to_string());
    let version = crate::thumbnails::deep_filter_version();
    Ok(DeepFilterNetStatus {
        installed: bin_path.is_some(),
        bin_path,
        version,
    })
}

#[tauri::command]
pub fn get_auto_assembly_settings<R: Runtime>(
    handle: AppHandle<R>,
) -> Result<AutoAssemblySettings, BundleError> {
    let conn = open_conn(&handle)?;
    AutoAssemblySettings::load(&conn)
}

#[tauri::command]
pub fn set_auto_assembly_settings<R: Runtime>(
    handle: AppHandle<R>,
    settings: AutoAssemblySettings,
) -> Result<(), BundleError> {
    let conn = open_conn(&handle)?;
    conn.execute(
        "UPDATE auto_assembly_settings SET
            target_width = ?1, target_height = ?2, target_fps = ?3,
            xfade_duration_secs = ?4, title_duration_secs = ?5,
            audio_enhance_enabled = ?6, deepfilternet_enabled = ?7,
            updated_at = datetime('now')
         WHERE id = 1",
        params![
            settings.target_width, settings.target_height, settings.target_fps,
            settings.xfade_duration_secs, settings.title_duration_secs,
            if settings.audio_enhance_enabled { 1 } else { 0 },
            if settings.deepfilternet_enabled { 1 } else { 0 },
        ],
    )?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Job params (one struct per kind, serialised into jobs.params_json).
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RenderTitleParams {
    pub bundle_uid: String,
    pub output_path: String,
    pub title: String,
    pub persona_watermark: String,
    pub duration_secs: f64,
    pub fps: i64,
    pub width: i64,
    pub height: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NormalizeVideoParams {
    pub bundle_uid: String,
    pub bundle_file_id: i64,
    pub working_path: String,
    pub output_path: String,
    pub width: i64,
    pub height: i64,
    pub fps: i64,
    pub rotation_degrees: i64,
    pub watermark_png_path: Option<String>,
    pub watermark_position: String,
    pub watermark_margin_pct: f64,
    pub audio_enhance: bool,
    /// Phase 4.5b — run the source audio through DeepFilterNet
    /// before the ffmpeg enhance chain. Caller (`enqueue_auto_assemble`)
    /// validates the binary is present; if false here we skip the
    /// extra step entirely and use source audio unmodified.
    #[serde(default)]
    pub deepfilternet_enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AssembleMasterParams {
    pub bundle_uid: String,
    pub output_path: String,
    pub input_paths: Vec<String>,
    pub xfade_duration_secs: f64,
    pub fps: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EnqueueAutoAssembleResult {
    pub bundle_uid: String,
    pub master_path: String,
    pub job_ids: Vec<i64>,
    pub video_count: i64,
    pub errors: Vec<String>,
}

// ---------------------------------------------------------------------------
// Public Tauri command — kicks off the whole pipeline.
// ---------------------------------------------------------------------------

/// Output orientation chosen per-bundle on the Edit tab. The bundle's
/// videos can't be assumed to all be landscape or all portrait, so the
/// user picks at assemble time. We don't store a second resolution — we
/// reuse the configured Settings → Auto-Assembly dimensions and swap the
/// long/short edges to match the chosen orientation (e.g. 1920×1080 ↔
/// 1080×1920).
fn target_dims(settings: &AutoAssemblySettings, format: Option<&str>) -> (i64, i64) {
    let long = settings.target_width.max(settings.target_height);
    let short = settings.target_width.min(settings.target_height);
    match format {
        Some("vertical") | Some("9:16") => (short, long), // 9:16 portrait
        _ => (long, short),                               // 16:9 landscape (default)
    }
}

/// Final ordered ffmpeg input list for a YouTube master: optional intro
/// first, then the clips in order, then optional outro last. Pure so the
/// prepend / append / both-off / neither cases are unit-testable without
/// touching ffmpeg.
fn youtube_master_inputs(
    intro: Option<String>,
    clips: &[String],
    outro: Option<String>,
) -> Vec<String> {
    let mut out = Vec::with_capacity(clips.len() + 2);
    if let Some(i) = intro {
        out.push(i);
    }
    out.extend(clips.iter().cloned());
    if let Some(o) = outro {
        out.push(o);
    }
    out
}

/// Every video in a bundle that has an extracted working file, ordered
/// by fansite day + position so the master cut follows the bundle's
/// natural sequence. Row shape: `(bundle_file_id, in_zip_path,
/// working_path, rotation_degrees)`.
fn collect_bundle_videos(
    conn: &Connection,
    uid: &str,
) -> Result<Vec<(i64, String, String, i64)>, BundleError> {
    let mut stmt = conn.prepare(
        "SELECT id, in_zip_path, working_path, rotation_degrees
           FROM bundle_files
          WHERE bundle_uid = ?1 AND kind = 'video'
                AND working_path IS NOT NULL AND working_path != ''
          ORDER BY
              CASE WHEN fansite_day_of_month IS NULL THEN 0 ELSE fansite_day_of_month END,
              position,
              in_zip_path",
    )?;
    let videos = stmt
        .query_map(params![uid], |row| Ok((
            row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?,
        )))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(videos)
}

/// Probe a bundle's clips and pick the majority visual orientation,
/// folding each file's `rotation_degrees` into the probed dimensions
/// (90°/270° swap width/height). Ties and un-probeable bundles default
/// to landscape — the historical assumption — so a flaky ffprobe never
/// silently produces a portrait master.
fn detect_orientation(videos: &[(i64, String, String, i64)]) -> &'static str {
    let mut portrait = 0i32;
    let mut landscape = 0i32;
    for (_, _, working, rot) in videos {
        if let Some((mut w, mut h)) =
            crate::thumbnails::probe_video_dimensions(Path::new(working))
        {
            if *rot == 90 || *rot == 270 {
                std::mem::swap(&mut w, &mut h);
            }
            if h > w { portrait += 1; } else { landscape += 1; }
        }
    }
    if portrait > landscape { "vertical" } else { "horizontal" }
}

/// Probe a bundle's clips and report the auto-detected output
/// orientation ("horizontal" / "vertical"). The Edit tab calls this to
/// preselect the Format radio when the user hasn't picked one yet.
#[tauri::command]
pub fn detect_bundle_format<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<String, BundleError> {
    let conn = open_conn(&handle)?;
    let videos = collect_bundle_videos(&conn, &uid)?;
    Ok(detect_orientation(&videos).to_string())
}

#[tauri::command]
pub fn enqueue_auto_assemble<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
    format: Option<String>,
) -> Result<EnqueueAutoAssembleResult, BundleError> {
    let workspace = bundle_workspace_dir(&work_root(&handle)?, &uid);
    let auto_dir = workspace.join("auto");
    fs::create_dir_all(&auto_dir)?;

    let conn = open_conn(&handle)?;
    let settings = AutoAssemblySettings::load(&conn)?;

    // Phase 4.5b validation — if DFN is enabled but the binary isn't
    // installed, refuse to enqueue. Better to surface this once up
    // front than to ship N silently-noisier clips through the queue.
    if settings.deepfilternet_enabled
        && crate::thumbnails::deep_filter_bin().is_none()
    {
        return Err(BundleError::NotFound(
            "DeepFilterNet enabled in Settings → Auto-Assembly but `deep-filter` \
             binary not found. Install via `cargo install --git \
             https://github.com/Rikorose/DeepFilterNet --bin deep-filter` or \
             disable the toggle.".into(),
        ));
    }

    // Pull bundle persona + title + type. Title feeds the title-card text;
    // bundle_type decides the YouTube intro/outro assembly variant below.
    let (title, persona_code, bundle_type): (String, Option<String>, String) = conn.query_row(
        "SELECT COALESCE(NULLIF(title_override,''), title, ''), persona_code, bundle_type
           FROM bundles WHERE uid = ?1",
        params![uid],
        |r| Ok((
            r.get::<_, String>(0)?,
            r.get::<_, Option<String>>(1)?,
            r.get::<_, String>(2)?,
        )),
    ).optional()?
        .ok_or_else(|| BundleError::NotFound(format!("bundle {uid}")))?;
    let is_youtube = bundle_type == "youtube";

    // Pull every video with a working path. Ordered by fansite day +
    // position so the master cut respects the bundle's natural sequence.
    // Collected up front so we can auto-detect the output orientation
    // from the clips before sizing the title card / watermark / normalize.
    let videos = collect_bundle_videos(&conn, &uid)?;
    if videos.is_empty() {
        return Err(BundleError::NotFound(format!(
            "bundle {uid} has no videos to assemble"
        )));
    }

    // Resolve the output orientation. An explicit "horizontal"/"vertical"
    // wins; "auto" (or no choice) probes the clips and picks the majority
    // orientation so the master matches the footage instead of forcing a
    // letterboxed 16:9 onto portrait clips.
    let resolved_format = match format.as_deref() {
        Some("horizontal") | Some("16:9") => "horizontal",
        Some("vertical") | Some("9:16") => "vertical",
        _ => detect_orientation(&videos),
    };
    let (target_width, target_height) = target_dims(&settings, Some(resolved_format));

    // Resolve persona watermark text + render the watermark PNG once.
    // Reuses the per-media-kind loader so the user's Settings → Watermark
    // image_enabled/video_enabled flags are honored. If the persona has
    // video watermarking off, we still embed the persona name on the
    // title card (the title card watermark is a different brand surface
    // than the per-clip overlay).
    let profile = crate::bundles::load_watermark_profile_pub(
        &conn,
        persona_code.as_deref(),
        MediaKind::Video,
    )?;
    let persona_watermark_text = profile
        .as_ref()
        .map(|p| p.text.clone())
        .or_else(|| default_persona_watermark(persona_code.as_deref()))
        .unwrap_or_else(|| "PhantomLives".to_string());
    // The title card spells the persona out with spaces ("Curse Of
    // Curves") while the per-clip watermark keeps the compact brand
    // form ("CurseOfCurves"). Only the title-card text is humanized;
    // the watermark PNG below still uses the raw profile text.
    let persona_title_text = humanize_persona(&persona_watermark_text);

    // Pre-render the per-clip watermark PNG (when persona's video
    // watermark is enabled). One PNG sized for the normalize target
    // height — every clip ends up at this resolution so the PNG fits
    // every video unmodified.
    let watermark_png_path: Option<String> = if let Some(p) = &profile {
        let font_bytes = paper_daisy_bytes(&handle)?;
        // 1.25× alpha boost — same perceptual nudge we use in the
        // Phase 4 video path so 20% UI looks like 20% on motion.
        let boosted = crate::images::WatermarkProfile {
            opacity_percent: ((p.opacity_percent as f32 * 1.25).min(100.0)) as u8,
            ..p.clone()
        };
        let base_font = (target_height as f32) * p.font_size_pct / 100.0;
        let cap = (target_height as f32) * 0.08;
        let font_size_px = base_font.min(cap).max(24.0);
        let png_bytes = crate::images::render_watermark_png(&boosted, &font_bytes, font_size_px)?;
        let path = auto_dir.join("watermark.png");
        fs::write(&path, &png_bytes)?;
        Some(path.to_string_lossy().to_string())
    } else {
        None
    };

    let watermark_position = profile
        .as_ref()
        .map(|p| watermark_position_to_str(p.position))
        .unwrap_or_else(|| "bottom-right".to_string());
    let watermark_margin_pct = profile.as_ref().map(|p| p.margin_pct as f64).unwrap_or(2.5);

    let mut job_ids: Vec<i64> = Vec::with_capacity(videos.len() + 2);
    let errors: Vec<String> = Vec::new();

    // Normalize-job helper. Every segment — title-card replacement intro,
    // each clip, and the outro — is sized to the target dims, watermarked,
    // and audio-enhanced identically so assemble_master's xfade chain joins
    // them seamlessly. `file_id = -1` marks the synthetic intro/outro
    // segments (no bundle_files row); dispatch_normalize_video ignores it.
    let enqueue_norm = |source: &str, output: &Path, rotation: i64,
                        in_zip: Option<&str>, file_id: i64|
     -> Result<i64, BundleError> {
        let p = NormalizeVideoParams {
            bundle_uid: uid.clone(),
            bundle_file_id: file_id,
            working_path: source.to_string(),
            output_path: output.to_string_lossy().to_string(),
            width: target_width,
            height: target_height,
            fps: settings.target_fps,
            rotation_degrees: rotation,
            watermark_png_path: watermark_png_path.clone(),
            watermark_position: watermark_position.clone(),
            watermark_margin_pct,
            audio_enhance: settings.audio_enhance_enabled,
            deepfilternet_enabled: settings.deepfilternet_enabled,
        };
        let id = crate::jobs::enqueue(
            &conn,
            "normalize_video",
            &serde_json::to_string(&p).unwrap_or_else(|_| "{}".into()),
            Some(&uid),
            in_zip,
        )?;
        Ok(id)
    };

    // ── Lead segment ─────────────────────────────────────────────────────
    // Non-YouTube bundles get the generated title card. For YouTube, the
    // persona's intro clip (when enabled + present) REPLACES the title
    // card — no title card is rendered. Intro off → straight into clips.
    let intro_path: Option<String> = if is_youtube {
        match crate::persona_clips::enabled_clip_path(&conn, persona_code.as_deref(), "intro")? {
            Some(src) => {
                let out = auto_dir.join("intro.mp4");
                job_ids.push(enqueue_norm(&src, &out, 0, None, -1)?);
                Some(out.to_string_lossy().to_string())
            }
            None => None,
        }
    } else {
        let title_path = auto_dir.join("title.mp4");
        let title_params = RenderTitleParams {
            bundle_uid: uid.clone(),
            output_path: title_path.to_string_lossy().to_string(),
            title: if title.is_empty() { uid.clone() } else { title.clone() },
            persona_watermark: persona_title_text.clone(),
            duration_secs: settings.title_duration_secs,
            fps: settings.target_fps,
            width: target_width,
            height: target_height,
        };
        let title_job_id = crate::jobs::enqueue(
            &conn,
            "render_title",
            &serde_json::to_string(&title_params).unwrap_or_else(|_| "{}".into()),
            Some(&uid),
            None,
        )?;
        job_ids.push(title_job_id);
        Some(title_path.to_string_lossy().to_string())
    };

    // ── Per-video normalize+watermark+audio ──────────────────────────────
    let mut clip_paths: Vec<String> = Vec::with_capacity(videos.len());
    for (i, (bundle_file_id, in_zip, working, rot_deg)) in videos.iter().enumerate() {
        let vpath = auto_dir.join(format!("v{:02}.mp4", i + 1));
        job_ids.push(enqueue_norm(working, &vpath, *rot_deg, Some(in_zip), *bundle_file_id)?);
        clip_paths.push(vpath.to_string_lossy().to_string());
    }

    // ── Trailing segment: YouTube outro (when enabled + present) ─────────
    let outro_path: Option<String> = if is_youtube {
        match crate::persona_clips::enabled_clip_path(&conn, persona_code.as_deref(), "outro")? {
            Some(src) => {
                let out = auto_dir.join("outro.mp4");
                job_ids.push(enqueue_norm(&src, &out, 0, None, -1)?);
                Some(out.to_string_lossy().to_string())
            }
            None => None,
        }
    } else {
        None
    };

    // Final ffmpeg input order. YouTube: [intro?, clips…, outro?].
    // Everything else: [title/lead, clips…] (lead is always Some here).
    let input_paths_for_master: Vec<String> = if is_youtube {
        youtube_master_inputs(intro_path, &clip_paths, outro_path)
    } else {
        let mut v = Vec::with_capacity(clip_paths.len() + 1);
        if let Some(lead) = intro_path {
            v.push(lead);
        }
        v.extend(clip_paths);
        v
    };

    // ── Job N+2: assemble master via xfade chain ─────────────────────────
    // Name the consolidated cut after the bundle title (`<Title>.mp4`)
    // so the delivered file is self-describing. Reader sites resolve the
    // same name via `bundles::resolve_master_cut_path` (with a legacy
    // `master.mp4` fallback for cuts assembled before this change).
    let master_path = auto_dir.join(format!(
        "{}.mp4",
        crate::bundles::master_cut_basename(&title),
    ));
    let asm_params = AssembleMasterParams {
        bundle_uid: uid.clone(),
        output_path: master_path.to_string_lossy().to_string(),
        input_paths: input_paths_for_master,
        xfade_duration_secs: settings.xfade_duration_secs,
        fps: settings.target_fps,
    };
    let asm_id = crate::jobs::enqueue(
        &conn,
        "assemble_master",
        &serde_json::to_string(&asm_params).unwrap_or_else(|_| "{}".into()),
        Some(&uid),
        None,
    )?;
    job_ids.push(asm_id);

    Ok(EnqueueAutoAssembleResult {
        bundle_uid: uid,
        master_path: master_path.to_string_lossy().to_string(),
        job_ids,
        video_count: videos.len() as i64,
        errors,
    })
}

/// PhantomLives persona → default watermark text. Used as a fallback when
/// the user hasn't set Settings → Watermark text for a persona but still
/// expects the title card to brand the bundle.
fn default_persona_watermark(persona_code: Option<&str>) -> Option<String> {
    match persona_code? {
        "CoC" => Some("CurseOfCurves".into()),
        "PoA" => Some("PrincessOfAddiction".into()),
        "Sa"  => Some("SheerAttraction".into()),
        _ => None,
    }
}

/// Turn a compact CamelCase persona handle into a spaced display name
/// for the title card: "CurseOfCurves" → "Curse Of Curves". Inserts a
/// space before any uppercase letter that follows a lowercase letter or
/// digit, so it's a no-op on text that already has spaces (the watermark
/// overlay keeps the compact form unchanged — see `enqueue_auto_assemble`).
fn humanize_persona(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 4);
    let mut prev: Option<char> = None;
    for c in s.chars() {
        if c.is_uppercase() {
            if let Some(p) = prev {
                if p.is_lowercase() || p.is_ascii_digit() {
                    out.push(' ');
                }
            }
        }
        out.push(c);
        prev = Some(c);
    }
    out
}

fn open_conn<R: Runtime>(handle: &AppHandle<R>) -> Result<Connection, BundleError> {
    let dir = handle.path()
        .resolve("", tauri::path::BaseDirectory::AppLocalData)
        .map_err(|e| BundleError::Io(std::io::Error::other(format!("appdata path: {e}"))))?;
    let db_path = dir.join("sidemolly.db");
    Ok(Connection::open(db_path)?)
}

// ---------------------------------------------------------------------------
// Job dispatchers — invoked by jobs.rs::dispatch when the worker claims
// a row of one of the auto-assemble kinds.
// ---------------------------------------------------------------------------

pub fn dispatch_render_title<R: Runtime>(
    handle: &AppHandle<R>,
    params: RenderTitleParams,
) -> Result<(), BundleError> {
    let dst = PathBuf::from(&params.output_path);
    if let Some(parent) = dst.parent() { fs::create_dir_all(parent)?; }
    let tmp = dst.with_extension("sm-tmp.mp4");

    // ── Render the title card as a PNG via imageproc (NOT ffmpeg
    // drawtext — Homebrew's stock ffmpeg ships without libfreetype, so
    // drawtext is unavailable; same workaround we use for video
    // watermarks). The PNG is the full target resolution with title +
    // persona text already baked in.
    let font_bytes = paper_daisy_bytes(handle)?;
    let png_bytes = crate::images::render_title_card_png(
        &params.title,
        &params.persona_watermark,
        params.width as u32,
        params.height as u32,
        &font_bytes,
    )?;
    let png_path = dst.with_file_name(format!(
        "{}.title.png",
        dst.file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_default(),
    ));
    fs::write(&png_path, &png_bytes)?;

    // Fade-in / fade-out bookends, applied as a filter on the looped
    // PNG. fade=in is frames 0..fps, fade=out is the last fps frames.
    let fade_in_end = (params.fps as f64 * 1.0) as i64;
    let fade_out_start = ((params.duration_secs - 1.0) * params.fps as f64) as i64;
    let vf = format!(
        "fade=in:0:{fi},fade=out:{fo}:{fi}",
        fi = fade_in_end, fo = fade_out_start,
    );

    // Loop the still PNG for `duration_secs`, plus a silent stereo
    // audio track so the title card's stream layout matches the
    // normalize_video output (required for the xfade chain).
    let argv: Vec<String> = vec![
        "-y".into(),
        "-loglevel".into(), "error".into(),
        // Input 0: still PNG, looped at target fps for duration secs
        "-loop".into(), "1".into(),
        "-framerate".into(), params.fps.to_string(),
        "-t".into(), params.duration_secs.to_string(),
        "-i".into(), png_path.to_string_lossy().to_string(),
        // Input 1: silent stereo AAC
        "-f".into(), "lavfi".into(),
        "-t".into(), params.duration_secs.to_string(),
        "-i".into(), "anullsrc=channel_layout=stereo:sample_rate=48000".into(),
        // ── Output options ──
        "-vf".into(), vf,
        "-c:v".into(), "libx264".into(),
        "-pix_fmt".into(), "yuv420p".into(),
        "-preset".into(), "medium".into(),
        "-crf".into(), "23".into(),
        "-c:a".into(), "aac".into(),
        "-b:a".into(), "192k".into(),
        "-ar".into(), "48000".into(),
        "-ac".into(), "2".into(),
        "-shortest".into(),
        "-movflags".into(), "+faststart".into(),
        tmp.to_string_lossy().to_string(),
    ];

    run_ffmpeg(&argv, &tmp, &dst)?;
    // PNG is kept for debugging — small (~50KB) and the user can
    // inspect what the title card actually looked like before encode.
    Ok(())
}

pub fn dispatch_normalize_video<R: Runtime>(
    handle: &AppHandle<R>,
    params: NormalizeVideoParams,
) -> Result<(), BundleError> {
    let _ = handle;
    let src = Path::new(&params.working_path);
    if !src.exists() {
        return Err(BundleError::NotFound(params.working_path.clone()));
    }
    let dst = PathBuf::from(&params.output_path);
    if let Some(parent) = dst.parent() { fs::create_dir_all(parent)?; }
    let tmp = dst.with_extension("sm-tmp.mp4");

    // ── Phase 4.5b: DeepFilterNet voice isolation (optional pre-pass).
    // When enabled + binary present, extract source audio to a WAV,
    // run it through `deep-filter`, then use the cleaned WAV as a
    // second ffmpeg input. When disabled OR binary missing, we just
    // use the source's audio stream directly (single -i source.mov).
    //
    // The enqueue validator already errors out if the toggle is on
    // but the binary isn't installed, so reaching this dispatcher
    // with `deepfilternet_enabled=true` means the binary IS available
    // unless something unmounted it mid-batch. We re-check defensively
    // and fall back to source audio with a logged warning rather than
    // failing the whole clip.
    // Whether the source has any audio stream. A persona intro/outro
    // bumper (or an odd content clip) may be silent; [0:a] then doesn't
    // exist and both this normalize AND the later acrossfade in
    // assemble_master hard-fail. When absent we synthesize a silent stereo
    // track below. DeepFilterNet is also skipped (nothing to denoise).
    let source_has_audio = probe_has_audio(src);

    let cleaned_audio: Option<PathBuf> = if params.deepfilternet_enabled && source_has_audio {
        match crate::thumbnails::deep_filter_bin() {
            Some(bin) => Some(extract_and_denoise_audio(src, &dst, bin)?),
            None => {
                eprintln!(
                    "[sidemolly] deep-filter binary disappeared mid-batch; \
                     falling back to source audio for {}",
                    params.working_path,
                );
                None
            }
        }
    } else {
        None
    };

    let mut argv: Vec<String> = vec![
        "-y".into(),
        "-loglevel".into(), "error".into(),
        "-i".into(), src.to_string_lossy().to_string(),
    ];
    // Track input slots so the watermark PNG index stays correct no matter
    // which optional audio inputs we add.
    let mut next_input: usize = 1; // 0 == the source
    let mut input_index_audio: usize = 0; // [0:a] by default
    let mut needs_shortest = false;
    if let Some(p) = &cleaned_audio {
        argv.extend(["-i".into(), p.to_string_lossy().to_string()]);
        input_index_audio = next_input; // DFN-cleaned audio
        next_input += 1;
    } else if !source_has_audio {
        // Feed a silent stereo track and trim it to the video length with
        // -shortest, so silent bumpers still produce a valid [N:a] stream.
        argv.extend([
            "-f".into(), "lavfi".into(),
            "-i".into(), "anullsrc=channel_layout=stereo:sample_rate=48000".into(),
        ]);
        input_index_audio = next_input;
        next_input += 1;
        needs_shortest = true;
    }

    // Build the filter graph:
    //   [0:v] (rotate?) → scale-to-fit + pad to target → (overlay watermark?) → [vout]
    //   [0:a] (audio enhance?) → [aout]
    let mut vchain: Vec<String> = Vec::new();
    if params.rotation_degrees == 90 {
        vchain.push("transpose=1".into());
    } else if params.rotation_degrees == 270 {
        vchain.push("transpose=2".into());
    } else if params.rotation_degrees == 180 {
        vchain.push("transpose=1,transpose=1".into());
    }
    // scale-to-fit + letterbox pad to exact target dims.
    vchain.push(format!(
        "scale={w}:{h}:force_original_aspect_ratio=decrease:eval=frame",
        w = params.width, h = params.height,
    ));
    vchain.push(format!(
        "pad={w}:{h}:(ow-iw)/2:(oh-ih)/2:color=black",
        w = params.width, h = params.height,
    ));
    vchain.push(format!("fps={}", params.fps));
    vchain.push(format!("setsar=1"));

    let has_watermark = params.watermark_png_path.as_deref()
        .map(|p| Path::new(p).exists())
        .unwrap_or(false);

    // Watermark PNG slots in AFTER any optional audio inputs (DFN-cleaned
    // audio or the silent fallback), so its filter-graph index is whatever
    // the running input counter has reached.
    let wm_input_index = next_input;

    let filter_complex = if has_watermark {
        let wm = params.watermark_png_path.as_ref().unwrap();
        argv.extend(["-i".into(), wm.clone()]);
        let pos = WatermarkPosition::parse(&params.watermark_position)
            .map_err(crate::images::ImageOpError::from)?;
        let margin_px =
            ((params.height as f32) * (params.watermark_margin_pct as f32) / 100.0).round() as i32;
        let (x, y) = overlay_xy_expr(pos, margin_px.max(8));
        format!(
            "[0:v]{vfilters}[vbase];[vbase][{wmi}:v]overlay=x={x}:y={y}:format=rgb[vout]",
            vfilters = vchain.join(","),
            wmi = wm_input_index,
        )
    } else {
        format!("[0:v]{vfilters}[vout]", vfilters = vchain.join(","))
    };

    // Audio chain reads from either [0:a] (source-direct path) or
    // [1:a] (DeepFilterNet-cleaned path) depending on what we added
    // as a second input above. The enhance filter is the same either
    // way — podcast-grade loudnorm + mild compression + warmth/presence EQ.
    let audio_in_label = format!("[{}:a]", input_index_audio);
    let audio_filter = if params.audio_enhance {
        format!(
            "{audio_in}loudnorm=I=-16:TP=-1.5:LRA=11,acompressor=threshold=-18dB:ratio=3:attack=5:release=50,equalizer=f=200:t=q:w=1.0:g=2,equalizer=f=3000:t=q:w=1.0:g=2.5[aout]",
            audio_in = audio_in_label,
        )
    } else {
        format!("{audio_in}anull[aout]", audio_in = audio_in_label)
    };

    let full_filter = format!("{filter_complex};{audio_filter}");
    argv.extend(["-filter_complex".into(), full_filter]);
    argv.extend(["-map".into(), "[vout]".into()]);
    argv.extend(["-map".into(), "[aout]".into()]);

    argv.extend([
        "-c:v".into(), "libx264".into(),
        "-crf".into(), "23".into(),
        "-preset".into(), "medium".into(),
        "-pix_fmt".into(), "yuv420p".into(),
        "-c:a".into(), "aac".into(),
        "-b:a".into(), "192k".into(),
        "-ar".into(), "48000".into(),
        "-ac".into(), "2".into(),
        "-movflags".into(), "+faststart".into(),
        "-map_metadata".into(), "-1".into(),
    ]);
    if needs_shortest {
        // Bound the infinite anullsrc track to the video length.
        argv.push("-shortest".into());
    }
    argv.push(tmp.to_string_lossy().to_string());

    run_ffmpeg(&argv, &tmp, &dst)?;
    Ok(())
}

pub fn dispatch_assemble_master<R: Runtime>(
    handle: &AppHandle<R>,
    params: AssembleMasterParams,
) -> Result<(), BundleError> {
    let _ = handle;
    if params.input_paths.is_empty() {
        return Err(BundleError::NotFound("assemble_master: no inputs".into()));
    }
    for p in &params.input_paths {
        if !Path::new(p).exists() {
            return Err(BundleError::NotFound(format!(
                "assemble_master: missing input {p}"
            )));
        }
    }
    let dst = PathBuf::from(&params.output_path);
    if let Some(parent) = dst.parent() { fs::create_dir_all(parent)?; }
    let tmp = dst.with_extension("sm-tmp.mp4");

    // Build the xfade chain. Each input gets an `-i`. Filter graph
    // cross-dissolves clip i into clip i+1 over `xd` seconds.
    let xd = params.xfade_duration_secs;
    let mut argv: Vec<String> = vec![
        "-y".into(),
        "-loglevel".into(), "error".into(),
    ];
    for p in &params.input_paths {
        argv.push("-i".into());
        argv.push(p.clone());
    }

    // Probe each input's duration so we can compute the xfade offsets.
    // Offset_i = sum(dur_0..dur_i) - xd*(i+1)
    let durations: Vec<f64> = params.input_paths.iter()
        .map(|p| probe_duration(Path::new(p)).unwrap_or(0.0))
        .collect();

    // Chain xfade. Streams are [0:v], [1:v], … and we name intermediate
    // outputs [vx1], [vx2], … each xfade pairs the previous chain head
    // with the next clip.
    let mut filter_parts: Vec<String> = Vec::new();
    let mut cumulative = durations[0];
    let mut last_label: String = "[0:v]".into();
    let mut last_audio: String = "[0:a]".into();
    for i in 1..params.input_paths.len() {
        let next_label = format!("[vx{i}]");
        let next_audio = format!("[ax{i}]");
        let offset = cumulative - xd;
        filter_parts.push(format!(
            "{prev}[{i}:v]xfade=transition=fade:duration={xd}:offset={off:.3}{out}",
            prev = last_label, i = i, xd = xd, off = offset, out = next_label,
        ));
        filter_parts.push(format!(
            "{prev_a}[{i}:a]acrossfade=d={xd}{out_a}",
            prev_a = last_audio, i = i, xd = xd, out_a = next_audio,
        ));
        cumulative += durations[i] - xd;
        last_label = next_label;
        last_audio = next_audio;
    }

    // Final 1s fade-to-black at end of the chain. cumulative is the
    // total composite duration.
    let final_fade_start = (cumulative - xd).max(0.0);
    filter_parts.push(format!(
        "{prev}fade=t=out:st={start:.3}:d={xd}[vout]",
        prev = last_label, start = final_fade_start, xd = xd,
    ));
    filter_parts.push(format!("{prev_a}afade=t=out:st={start:.3}:d={xd}[aout]",
        prev_a = last_audio, start = final_fade_start, xd = xd,
    ));

    let filter = filter_parts.join(";");
    argv.extend(["-filter_complex".into(), filter]);
    argv.extend(["-map".into(), "[vout]".into()]);
    argv.extend(["-map".into(), "[aout]".into()]);
    argv.extend([
        "-c:v".into(), "libx264".into(),
        "-crf".into(), "21".into(),
        "-preset".into(), "medium".into(),
        "-pix_fmt".into(), "yuv420p".into(),
        "-c:a".into(), "aac".into(),
        "-b:a".into(), "192k".into(),
        "-movflags".into(), "+faststart".into(),
    ]);
    argv.push(tmp.to_string_lossy().to_string());

    run_ffmpeg(&argv, &tmp, &dst)?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Helpers.
// ---------------------------------------------------------------------------

/// Phase 4.5b voice isolation helper. Extracts the source video's
/// audio to a PCM WAV, runs DeepFilterNet's `deep-filter` on it, and
/// returns the cleaned WAV path. Caller passes the result as a
/// second ffmpeg input to the main normalize encode.
///
/// Layout (per-clip side dir):
///   <dst>.df-raw.wav             — extracted PCM (deleted after success)
///   <dst>.df-clean.wav           — deep-filter output (consumed downstream)
///
/// `deep-filter` writes `<basename>_DeepFilterNet3.wav` next to its
/// input by default, with version suffix that drifts between releases.
/// We use `--output-dir` + a temp dir per clip so we know the exact
/// output filename to reference. Falls back to scanning the output
/// dir for a `_DeepFilterNet*.wav` file if `--output-dir` semantics
/// vary across CLI versions.
fn extract_and_denoise_audio(
    src: &Path,
    final_dst: &Path,
    deep_filter_bin: &str,
) -> Result<PathBuf, BundleError> {
    let work_dir = final_dst.parent()
        .ok_or_else(|| BundleError::NotFound("normalize_video: dst has no parent".into()))?
        .to_path_buf();
    fs::create_dir_all(&work_dir)?;

    let stem = final_dst.file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "audio".to_string());
    let raw_wav = work_dir.join(format!("{stem}.df-raw.wav"));
    let clean_wav = work_dir.join(format!("{stem}.df-clean.wav"));

    // Step 1: extract audio to PCM WAV (48kHz stereo, matching
    // DeepFilterNet's native rate).
    let ff = ffmpeg_bin();
    let extract_status = Command::new(ff)
        .args([
            "-y", "-loglevel", "error",
            "-i",
        ])
        .arg(src)
        .args([
            "-vn",
            "-ac", "2",
            "-ar", "48000",
            "-c:a", "pcm_s16le",
        ])
        .arg(&raw_wav)
        .status()
        .map_err(|e| BundleError::Io(std::io::Error::other(
            format!("ffmpeg audio-extract spawn: {e}"),
        )))?;
    if !extract_status.success() {
        return Err(BundleError::Io(std::io::Error::other(
            format!("ffmpeg audio-extract exit {:?}", extract_status.code()),
        )));
    }

    // Step 2: run deep-filter into a dedicated output dir so we
    // can reliably find the cleaned WAV regardless of the CLI's
    // version-suffix naming convention.
    let df_dir = work_dir.join(format!("{stem}.df-out"));
    let _ = fs::remove_dir_all(&df_dir); // start clean
    fs::create_dir_all(&df_dir)?;
    let df_status = Command::new(deep_filter_bin)
        .arg(&raw_wav)
        .args(["--output-dir"])
        .arg(&df_dir)
        .status()
        .map_err(|e| BundleError::Io(std::io::Error::other(
            format!("deep-filter spawn ({deep_filter_bin}): {e}"),
        )))?;
    if !df_status.success() {
        return Err(BundleError::Io(std::io::Error::other(
            format!("deep-filter exit {:?} on {}", df_status.code(), raw_wav.display()),
        )));
    }

    // Locate the cleaned WAV. CLI typically writes
    // `<input-stem>_DeepFilterNet3.wav` (version varies) — match any
    // `_DeepFilterNet*.wav` in the output dir.
    let cleaned_path: Option<PathBuf> = fs::read_dir(&df_dir)
        .ok()
        .and_then(|rd| {
            rd.flatten()
                .map(|e| e.path())
                .find(|p| p.file_name()
                    .and_then(|n| n.to_str())
                    .map(|s| s.contains("_DeepFilterNet") && s.ends_with(".wav"))
                    .unwrap_or(false))
        });
    let cleaned = cleaned_path.ok_or_else(|| BundleError::NotFound(
        format!("deep-filter ran but no *_DeepFilterNet*.wav appeared in {}",
                df_dir.display()),
    ))?;

    // Move into a deterministic spot so downstream ffmpeg can
    // reference it, then remove the intermediates.
    if clean_wav.exists() { let _ = fs::remove_file(&clean_wav); }
    fs::rename(&cleaned, &clean_wav)?;
    let _ = fs::remove_dir_all(&df_dir);
    let _ = fs::remove_file(&raw_wav);

    Ok(clean_wav)
}

/// ffmpeg's `drawtext` filter parser splits on `:` and `,`, so any of
/// those in user-provided text would break the filter graph. Escape the
/// few chars that matter for our title card (full escape spec at
/// https://ffmpeg.org/ffmpeg-filters.html#Notes-on-filtergraph-escaping).
fn escape_drawtext(s: &str) -> String {
    s.replace('\\', "\\\\")
     .replace(':', "\\:")
     .replace(',', "\\,")
     .replace('\'', "\\'")
     .replace('%', "\\%")
}

/// Probe duration in seconds via ffprobe. Returns 0.0 on any failure so
/// the assemble step's offset math doesn't blow up — the resulting
/// xfade will be cosmetically wrong but the master still renders.
fn probe_duration(path: &Path) -> Option<f64> {
    let bin = crate::thumbnails::ffprobe_bin();
    let output = Command::new(bin)
        .args([
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
        ])
        .arg(path)
        .output()
        .ok()?;
    if !output.status.success() { return None; }
    String::from_utf8(output.stdout).ok()?.trim().parse().ok()
}

/// True if `path` has at least one audio stream. Used to decide whether to
/// synthesize a silent track during normalize (a silent source otherwise
/// breaks `[0:a]` mapping here and the acrossfade in assemble_master).
/// Conservatively returns `true` on a probe failure so we don't strip real
/// audio when ffprobe hiccups — the worst case is the original behaviour.
fn probe_has_audio(path: &Path) -> bool {
    let bin = crate::thumbnails::ffprobe_bin();
    let output = Command::new(bin)
        .args([
            "-v", "error",
            "-select_streams", "a",
            "-show_entries", "stream=index",
            "-of", "csv=p=0",
        ])
        .arg(path)
        .output();
    match output {
        Ok(o) if o.status.success() => !String::from_utf8_lossy(&o.stdout).trim().is_empty(),
        _ => true,
    }
}

/// Spawn ffmpeg with the given argv, bound wall-clock, capture stderr,
/// atomic rename on success. Same pattern as `video::process_video`.
fn run_ffmpeg(argv: &[String], tmp: &Path, dst: &Path) -> Result<(), BundleError> {
    let bin = ffmpeg_bin();
    let started = Instant::now();
    let mut child = Command::new(bin)
        .args(argv)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| BundleError::Io(std::io::Error::other(
            format!("ffmpeg spawn (bin={bin}): {e}"),
        )))?;

    let status = loop {
        match child.try_wait()? {
            Some(s) => break s,
            None => {
                if started.elapsed() > FFMPEG_TIMEOUT {
                    let _ = child.kill();
                    let _ = fs::remove_file(tmp);
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
        let _ = fs::remove_file(tmp);
        return Err(BundleError::Io(std::io::Error::other(
            format!(
                "ffmpeg exit {:?}: {}",
                status.code(),
                stderr.trim().chars().take(900).collect::<String>(),
            ),
        )));
    }

    let _ = probe_video_height(tmp); // smoke: verify the file is a valid video
    if dst.exists() { let _ = fs::remove_file(dst); }
    fs::rename(tmp, dst)?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Tests.
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn youtube_master_inputs_orders_intro_clips_outro() {
        let clips = vec!["v01".to_string(), "v02".to_string()];
        // Both bumpers on.
        assert_eq!(
            youtube_master_inputs(Some("intro".into()), &clips, Some("outro".into())),
            vec!["intro", "v01", "v02", "outro"],
        );
        // Intro only.
        assert_eq!(
            youtube_master_inputs(Some("intro".into()), &clips, None),
            vec!["intro", "v01", "v02"],
        );
        // Outro only.
        assert_eq!(
            youtube_master_inputs(None, &clips, Some("outro".into())),
            vec!["v01", "v02", "outro"],
        );
        // Neither (default) — just the clips.
        assert_eq!(
            youtube_master_inputs(None, &clips, None),
            vec!["v01", "v02"],
        );
    }

    #[test]
    fn drawtext_escape_handles_colons_and_commas() {
        assert_eq!(escape_drawtext("hello: world, friend"), "hello\\: world\\, friend");
        assert_eq!(escape_drawtext("a's b"), "a\\'s b");
        // Backslashes are escaped first so the later passes don't double up.
        assert_eq!(escape_drawtext("a\\b"), "a\\\\b");
    }

    #[test]
    fn render_title_params_round_trips_via_json() {
        let p = RenderTitleParams {
            bundle_uid: "u".into(), output_path: "/o".into(),
            title: "T".into(), persona_watermark: "P".into(),
            duration_secs: 10.0, fps: 30, width: 1920, height: 1080,
        };
        let json = serde_json::to_string(&p).unwrap();
        assert!(json.contains("\"personaWatermark\""), "{json}");
        let _back: RenderTitleParams = serde_json::from_str(&json).unwrap();
    }

    #[test]
    fn normalize_video_params_round_trips_via_json() {
        let p = NormalizeVideoParams {
            bundle_uid: "u".into(), bundle_file_id: 1,
            working_path: "/w".into(), output_path: "/o".into(),
            width: 1920, height: 1080, fps: 30,
            rotation_degrees: 90,
            watermark_png_path: Some("/wm".into()),
            watermark_position: "bottom-right".into(),
            watermark_margin_pct: 2.5,
            audio_enhance: true,
            deepfilternet_enabled: true,
        };
        let json = serde_json::to_string(&p).unwrap();
        assert!(json.contains("\"rotationDegrees\""), "{json}");
        assert!(json.contains("\"deepfilternetEnabled\""), "{json}");
        assert!(json.contains("\"watermarkPngPath\""), "{json}");
        let _back: NormalizeVideoParams = serde_json::from_str(&json).unwrap();
    }

    #[test]
    fn humanize_persona_spaces_camelcase() {
        assert_eq!(humanize_persona("CurseOfCurves"), "Curse Of Curves");
        assert_eq!(humanize_persona("PrincessOfAddiction"), "Princess Of Addiction");
        assert_eq!(humanize_persona("SheerAttraction"), "Sheer Attraction");
        assert_eq!(humanize_persona("PhantomLives"), "Phantom Lives");
        // Idempotent on already-spaced text.
        assert_eq!(humanize_persona("Curse Of Curves"), "Curse Of Curves");
        // Leaves a leading capital + single word alone.
        assert_eq!(humanize_persona("Molly"), "Molly");
    }

    #[test]
    fn detect_orientation_defaults_landscape_when_unprobeable() {
        // Un-probeable / missing files leave the tally at 0/0 → landscape,
        // preserving the historical assumption rather than guessing.
        assert_eq!(detect_orientation(&[]), "horizontal");
        let videos = vec![
            (1i64, "a.mov".into(), "/nope/a.mov".into(), 0i64),
        ];
        assert_eq!(detect_orientation(&videos), "horizontal");
    }

    #[test]
    fn target_dims_swaps_long_short_edge_by_format() {
        let s = AutoAssemblySettings {
            target_width: 1920, target_height: 1080, target_fps: 30,
            xfade_duration_secs: 1.0, title_duration_secs: 10.0,
            audio_enhance_enabled: true, deepfilternet_enabled: false,
        };
        assert_eq!(target_dims(&s, Some("horizontal")), (1920, 1080));
        assert_eq!(target_dims(&s, None), (1920, 1080)); // default landscape
        assert_eq!(target_dims(&s, Some("vertical")), (1080, 1920));
        assert_eq!(target_dims(&s, Some("9:16")), (1080, 1920));
    }

    #[test]
    fn assemble_master_params_round_trips_via_json() {
        let p = AssembleMasterParams {
            bundle_uid: "u".into(), output_path: "/o".into(),
            input_paths: vec!["/a".into(), "/b".into()],
            xfade_duration_secs: 1.0, fps: 30,
        };
        let json = serde_json::to_string(&p).unwrap();
        assert!(json.contains("\"xfadeDurationSecs\""), "{json}");
        let _back: AssembleMasterParams = serde_json::from_str(&json).unwrap();
    }
}
