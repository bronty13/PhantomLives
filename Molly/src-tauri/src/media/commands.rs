//! Tauri command surface for the media engine. The frontend pre-computes the
//! output geometry (via `computeOutputSize`) and sends pixels + an HDR flag +
//! an optional full-frame caption PNG; Rust runs native ffmpeg from the
//! ORIGINAL source (input-seeked) and returns the output bytes.

use std::path::Path;
use tauri::ipc::{Channel, Response};
use tauri::{AppHandle, Runtime};

use crate::media::filters::{FilterSpec, Geom};
use crate::media::{engine, ffmpeg_path, filters, probe, temp, MediaError};

/// Source crop rectangle in pixels (from `computeOutputSize`).
#[derive(Debug, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CropPx {
    pub sx: u32,
    pub sy: u32,
    pub sw: u32,
    pub sh: u32,
}

impl CropPx {
    fn as_tuple(&self) -> (u32, u32, u32, u32) {
        (self.sw, self.sh, self.sx, self.sy)
    }
}

/// Progress payload streamed to the frontend over a per-call Channel.
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Progress {
    pub fraction: f64,
}

fn write_caption(job: &temp::JobDir, png: &Option<Vec<u8>>) -> Result<Option<String>, MediaError> {
    match png {
        Some(bytes) if !bytes.is_empty() => {
            let p = job.file("caption.png");
            std::fs::write(&p, bytes)?;
            Ok(Some(p.to_string_lossy().to_string()))
        }
        _ => Ok(None),
    }
}

#[tauri::command]
pub async fn probe_video<R: Runtime>(
    handle: AppHandle<R>,
    absolute_path: String,
) -> Result<probe::ProbeResult, MediaError> {
    probe::probe(&handle, &absolute_path).await
}

/// Produce (and cache) a low-res H.264 proxy for scrubbing an undecodable
/// source. Returns the proxy's absolute path.
#[tauri::command]
pub async fn make_preview_proxy<R: Runtime>(
    handle: AppHandle<R>,
    absolute_path: String,
) -> Result<String, MediaError> {
    let out = temp::proxy_cache_path(&handle, Path::new(&absolute_path))?;
    if out.is_file() {
        return Ok(out.to_string_lossy().to_string());
    }
    let info = probe::probe(&handle, &absolute_path).await?;
    let is_hdr = info.is_hdr && ffmpeg_path::supports_zscale(&handle).await;
    let bin = ffmpeg_path::ffmpeg_bin(&handle);
    let tmp = out.with_extension("partial.mp4");
    let args = filters::proxy_args(&absolute_path, &tmp.to_string_lossy(), is_hdr);
    engine::run_ffmpeg(&bin, &args, info.duration_sec, 120, |_| {}).await?;
    std::fs::rename(&tmp, &out)?;
    Ok(out.to_string_lossy().to_string())
}

#[derive(Debug, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GifParams {
    pub absolute_path: String,
    pub start_sec: f64,
    pub end_sec: f64,
    pub fps: u32,
    pub out_width: u32,
    pub out_height: u32,
    pub crop: Option<CropPx>,
    pub is_hdr: bool,
    pub quality: String,
    pub caption_png: Option<Vec<u8>>,
}

#[tauri::command]
pub async fn generate_gif<R: Runtime>(
    handle: AppHandle<R>,
    params: GifParams,
    on_progress: Channel<Progress>,
) -> Result<Response, MediaError> {
    let job = temp::JobDir::new(&handle)?;
    let out = job.file("out.gif");
    let caption = write_caption(&job, &params.caption_png)?;
    let dur = (params.end_sec - params.start_sec).max(0.05);
    let tonemap = params.is_hdr && ffmpeg_path::supports_zscale(&handle).await;
    let spec = FilterSpec {
        geom: Geom { out_w: params.out_width, out_h: params.out_height, crop: params.crop.as_ref().map(CropPx::as_tuple) },
        is_hdr: tonemap,
        fps: Some(params.fps.max(1)),
        has_caption: caption.is_some(),
    };
    let args = filters::gif_args(
        &params.absolute_path,
        &out.to_string_lossy(),
        caption.as_deref(),
        params.start_sec,
        dur,
        &spec,
        filters::gif_colors(&params.quality),
    );
    let bin = ffmpeg_path::ffmpeg_bin(&handle);
    engine::run_ffmpeg(&bin, &args, dur, 300, |f| {
        let _ = on_progress.send(Progress { fraction: f });
    })
    .await?;
    Ok(Response::new(std::fs::read(&out)?))
}

#[derive(Debug, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TeaserParams {
    pub absolute_path: String,
    pub start_sec: f64,
    pub end_sec: f64,
    pub out_width: u32,
    pub out_height: u32,
    pub crop: Option<CropPx>,
    pub is_hdr: bool,
    pub include_audio: bool,
    pub caption_png: Option<Vec<u8>>,
}

#[tauri::command]
pub async fn generate_teaser_mp4<R: Runtime>(
    handle: AppHandle<R>,
    params: TeaserParams,
    on_progress: Channel<Progress>,
) -> Result<Response, MediaError> {
    let job = temp::JobDir::new(&handle)?;
    let out = job.file("out.mp4");
    let caption = write_caption(&job, &params.caption_png)?;
    let dur = (params.end_sec - params.start_sec).clamp(0.05, 60.0);
    let tonemap = params.is_hdr && ffmpeg_path::supports_zscale(&handle).await;
    let spec = FilterSpec {
        geom: Geom { out_w: params.out_width, out_h: params.out_height, crop: params.crop.as_ref().map(CropPx::as_tuple) },
        is_hdr: tonemap,
        fps: None,
        has_caption: caption.is_some(),
    };
    let args = filters::teaser_args(
        &params.absolute_path,
        &out.to_string_lossy(),
        caption.as_deref(),
        params.start_sec,
        dur,
        &spec,
        params.include_audio,
        filters::teaser_video_max_kbps(dur, params.include_audio),
    );
    let bin = ffmpeg_path::ffmpeg_bin(&handle);
    engine::run_ffmpeg(&bin, &args, dur, 600, |f| {
        let _ = on_progress.send(Progress { fraction: f });
    })
    .await?;
    Ok(Response::new(std::fs::read(&out)?))
}

#[derive(Debug, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FrameParams {
    pub absolute_path: String,
    pub time_sec: f64,
    pub out_width: u32,
    pub out_height: u32,
    pub crop: Option<CropPx>,
    pub is_hdr: bool,
    pub caption_png: Option<Vec<u8>>,
}

#[tauri::command]
pub async fn grab_frame<R: Runtime>(
    handle: AppHandle<R>,
    params: FrameParams,
) -> Result<Response, MediaError> {
    let job = temp::JobDir::new(&handle)?;
    let out = job.file("frame.jpg");
    let caption = write_caption(&job, &params.caption_png)?;
    let tonemap = params.is_hdr && ffmpeg_path::supports_zscale(&handle).await;
    let spec = FilterSpec {
        geom: Geom { out_w: params.out_width, out_h: params.out_height, crop: params.crop.as_ref().map(CropPx::as_tuple) },
        is_hdr: tonemap,
        fps: None,
        has_caption: caption.is_some(),
    };
    let args = filters::frame_args(
        &params.absolute_path,
        &out.to_string_lossy(),
        caption.as_deref(),
        params.time_sec,
        &spec,
    );
    let bin = ffmpeg_path::ffmpeg_bin(&handle);
    engine::run_ffmpeg(&bin, &args, 1.0, 30, |_| {}).await?;
    Ok(Response::new(std::fs::read(&out)?))
}

/// Copyable plain-text diagnostics for the bundled video engine. The GIF Studio
/// surfaces this behind a "Copy diagnostics" button so Sallie can paste the
/// engine's real state (presence, size, PE header, hash, sync/security tamper
/// flags, the actual run result, registered AV) to Robert without touching any
/// files. Infallible by design — always returns a report.
#[tauri::command]
pub async fn media_diagnostics<R: Runtime>(handle: AppHandle<R>) -> String {
    crate::media::diagnostics::report(&handle).await
}
