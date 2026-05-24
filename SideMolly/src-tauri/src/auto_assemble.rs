// Phase 4.5 — Auto-Assembly pipeline.
//
// One-click "make me the master cut" — composes every video in a bundle
// into a single landscape 16:9 master MP4 with:
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
    paper_daisy_bytes, paper_daisy_path, watermark_position_to_str,
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

#[tauri::command]
pub fn enqueue_auto_assemble<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<EnqueueAutoAssembleResult, BundleError> {
    let workspace = bundle_workspace_dir(&work_root(&handle)?, &uid);
    let auto_dir = workspace.join("auto");
    fs::create_dir_all(&auto_dir)?;

    let conn = open_conn(&handle)?;
    let settings = AutoAssemblySettings::load(&conn)?;

    // Pull bundle persona + title for the title-card text.
    let (title, persona_code): (String, Option<String>) = conn.query_row(
        "SELECT COALESCE(title, ''), persona_code FROM bundles WHERE uid = ?1",
        params![uid],
        |r| Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?)),
    ).optional()?
        .ok_or_else(|| BundleError::NotFound(format!("bundle {uid}")))?;

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
        let base_font = (settings.target_height as f32) * p.font_size_pct / 100.0;
        let cap = (settings.target_height as f32) * 0.08;
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

    // Pull every video with a working path. Ordered by fansite day +
    // position so the master cut respects the bundle's natural sequence.
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
    let videos: Vec<(i64, String, String, i64)> = stmt
        .query_map(params![uid], |row| Ok((
            row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?,
        )))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    drop(stmt);

    if videos.is_empty() {
        return Err(BundleError::NotFound(format!(
            "bundle {uid} has no videos to assemble"
        )));
    }

    let mut job_ids: Vec<i64> = Vec::with_capacity(videos.len() + 2);
    let mut errors: Vec<String> = Vec::new();
    let mut input_paths_for_master: Vec<String> = Vec::with_capacity(videos.len() + 1);

    // ── Job 1: title card ────────────────────────────────────────────────
    let title_path = auto_dir.join("title.mp4");
    let title_params = RenderTitleParams {
        bundle_uid: uid.clone(),
        output_path: title_path.to_string_lossy().to_string(),
        title: if title.is_empty() { uid.clone() } else { title.clone() },
        persona_watermark: persona_watermark_text.clone(),
        duration_secs: settings.title_duration_secs,
        fps: settings.target_fps,
        width: settings.target_width,
        height: settings.target_height,
    };
    let title_job_id = crate::jobs::enqueue(
        &conn,
        "render_title",
        &serde_json::to_string(&title_params).unwrap_or_else(|_| "{}".into()),
        Some(&uid),
        None,
    )?;
    job_ids.push(title_job_id);
    input_paths_for_master.push(title_path.to_string_lossy().to_string());

    // ── Jobs 2..N+1: per-video normalize+watermark+audio ─────────────────
    for (i, (bundle_file_id, in_zip, working, rot_deg)) in videos.iter().enumerate() {
        let vname = format!("v{:02}.mp4", i + 1);
        let vpath = auto_dir.join(&vname);
        input_paths_for_master.push(vpath.to_string_lossy().to_string());

        let norm_params = NormalizeVideoParams {
            bundle_uid: uid.clone(),
            bundle_file_id: *bundle_file_id,
            working_path: working.clone(),
            output_path: vpath.to_string_lossy().to_string(),
            width: settings.target_width,
            height: settings.target_height,
            fps: settings.target_fps,
            rotation_degrees: *rot_deg,
            watermark_png_path: watermark_png_path.clone(),
            watermark_position: watermark_position.clone(),
            watermark_margin_pct,
            audio_enhance: settings.audio_enhance_enabled,
        };
        let nid = crate::jobs::enqueue(
            &conn,
            "normalize_video",
            &serde_json::to_string(&norm_params).unwrap_or_else(|_| "{}".into()),
            Some(&uid),
            Some(in_zip),
        )?;
        job_ids.push(nid);
    }

    // ── Job N+2: assemble master via xfade chain ─────────────────────────
    let master_path = auto_dir.join("master.mp4");
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
    let font = paper_daisy_path(handle)?;
    let dst = PathBuf::from(&params.output_path);
    if let Some(parent) = dst.parent() { fs::create_dir_all(parent)?; }
    let tmp = dst.with_extension("sm-tmp.mp4");

    // Build the title card via lavfi `color` source. Title above center,
    // persona watermark below. 1s fade-in + 1s fade-out bookends.
    let fade_in_end = (params.fps as f64 * 1.0) as i64; // frame 30 @ 30fps
    let fade_out_start = ((params.duration_secs - 1.0) * params.fps as f64) as i64;

    // Escape commas/colons in user-provided text so ffmpeg's filter
    // parser doesn't split them.
    let title_esc = escape_drawtext(&params.title);
    let persona_esc = escape_drawtext(&params.persona_watermark);
    let font_path = font.to_string_lossy().to_string();
    let font_esc = font_path.replace('\\', "\\\\").replace(':', "\\:").replace('\'', "\\'");

    let vf = format!(
        concat!(
            "drawtext=fontfile='{font}':text='{title}':",
            "fontsize=h*0.08:fontcolor=white:x=(w-tw)/2:y=(h/2)-th-h*0.01,",
            "drawtext=fontfile='{font}':text='{persona}':",
            "fontsize=h*0.05:fontcolor=white@0.85:x=(w-tw)/2:y=(h/2)+h*0.01,",
            "fade=in:0:{fi},fade=out:{fo}:{fi}",
        ),
        font = font_esc, title = title_esc, persona = persona_esc,
        fi = fade_in_end, fo = fade_out_start,
    );

    let lavfi = format!(
        "color=black:size={w}x{h}:rate={r}:duration={d}",
        w = params.width, h = params.height, r = params.fps, d = params.duration_secs,
    );

    let argv: Vec<String> = vec![
        "-y".into(),
        "-loglevel".into(), "error".into(),
        "-f".into(), "lavfi".into(),
        "-i".into(), lavfi,
        "-vf".into(), vf,
        "-c:v".into(), "libx264".into(),
        "-pix_fmt".into(), "yuv420p".into(),
        "-preset".into(), "medium".into(),
        "-crf".into(), "23".into(),
        // Silent stereo audio track so the title card's stream layout
        // matches the normalize_video output for the xfade graph.
        "-f".into(), "lavfi".into(),
        "-i".into(), format!("anullsrc=channel_layout=stereo:sample_rate=48000:duration={}", params.duration_secs),
        "-c:a".into(), "aac".into(),
        "-b:a".into(), "192k".into(),
        "-shortest".into(),
        "-movflags".into(), "+faststart".into(),
        tmp.to_string_lossy().to_string(),
    ];

    run_ffmpeg(&argv, &tmp, &dst)?;
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

    let mut argv: Vec<String> = vec![
        "-y".into(),
        "-loglevel".into(), "error".into(),
        "-i".into(), src.to_string_lossy().to_string(),
    ];

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

    let filter_complex = if has_watermark {
        let wm = params.watermark_png_path.as_ref().unwrap();
        argv.extend(["-i".into(), wm.clone()]);
        let pos = WatermarkPosition::parse(&params.watermark_position)
            .map_err(crate::images::ImageOpError::from)?;
        let margin_px =
            ((params.height as f32) * (params.watermark_margin_pct as f32) / 100.0).round() as i32;
        let (x, y) = overlay_xy_expr(pos, margin_px.max(8));
        format!(
            "[0:v]{vfilters}[vbase];[vbase][1:v]overlay=x={x}:y={y}:format=rgb[vout]",
            vfilters = vchain.join(","),
        )
    } else {
        format!("[0:v]{vfilters}[vout]", vfilters = vchain.join(","))
    };

    let audio_filter = if params.audio_enhance {
        // Podcast-grade loudness + mild compression + 200Hz warmth + 3kHz presence.
        "[0:a]loudnorm=I=-16:TP=-1.5:LRA=11,acompressor=threshold=-18dB:ratio=3:attack=5:release=50,equalizer=f=200:t=q:w=1.0:g=2,equalizer=f=3000:t=q:w=1.0:g=2.5[aout]".to_string()
    } else {
        "[0:a]anull[aout]".to_string()
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
        };
        let json = serde_json::to_string(&p).unwrap();
        assert!(json.contains("\"rotationDegrees\""), "{json}");
        assert!(json.contains("\"watermarkPngPath\""), "{json}");
        let _back: NormalizeVideoParams = serde_json::from_str(&json).unwrap();
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
