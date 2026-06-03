import { invoke, Channel } from '@tauri-apps/api/core';
import type { CropBox } from '../views/GifStudio/encodeGif';

// Thin wrappers over the native-ffmpeg media engine (src-tauri/src/media).
// The frontend pre-computes output geometry (computeOutputSize) and sends
// pixels + an HDR flag + an optional full-frame caption PNG; Rust runs ffmpeg
// on the ORIGINAL source and returns the output bytes.

export interface ProbeResult {
  width: number;
  height: number;
  durationSec: number;
  isHdr: boolean;
  hasAudio: boolean;
  codec: string;
}

/** Source crop rectangle in pixels (from computeOutputSize's sx/sy/sw/sh). */
export interface CropPx {
  sx: number;
  sy: number;
  sw: number;
  sh: number;
}

/** Progress streamed from ffmpeg's -progress parse, fraction in [0,1]. */
export interface MediaProgress {
  fraction: number;
}

export async function probeVideo(absolutePath: string): Promise<ProbeResult> {
  return invoke<ProbeResult>('probe_video', { absolutePath });
}

/** Build (and cache) a low-res H.264 proxy for scrubbing an undecodable
 * source (e.g. iPhone HEVC on Windows). Returns the proxy's absolute path. */
export async function makePreviewProxy(absolutePath: string): Promise<string> {
  return invoke<string>('make_preview_proxy', { absolutePath });
}

export interface GifParams {
  absolutePath: string;
  startSec: number;
  endSec: number;
  fps: number;
  outWidth: number;
  outHeight: number;
  crop: CropPx | null;
  isHdr: boolean;
  quality: 'high' | 'medium' | 'low';
  captionPng: number[] | null;
}

export interface TeaserParams {
  absolutePath: string;
  startSec: number;
  endSec: number;
  outWidth: number;
  outHeight: number;
  crop: CropPx | null;
  isHdr: boolean;
  includeAudio: boolean;
  captionPng: number[] | null;
}

export interface FrameParams {
  absolutePath: string;
  timeSec: number;
  outWidth: number;
  outHeight: number;
  crop: CropPx | null;
  isHdr: boolean;
  captionPng: number[] | null;
}

function progressChannel(onProgress?: (fraction: number) => void): Channel<MediaProgress> {
  const ch = new Channel<MediaProgress>();
  if (onProgress) ch.onmessage = (m) => onProgress(m.fraction);
  return ch;
}

export async function generateGif(params: GifParams, onProgress?: (f: number) => void): Promise<Uint8Array> {
  const buf = await invoke<ArrayBuffer>('generate_gif', { params, onProgress: progressChannel(onProgress) });
  return new Uint8Array(buf);
}

export async function generateTeaserMp4(params: TeaserParams, onProgress?: (f: number) => void): Promise<Uint8Array> {
  const buf = await invoke<ArrayBuffer>('generate_teaser_mp4', { params, onProgress: progressChannel(onProgress) });
  return new Uint8Array(buf);
}

export async function grabFrame(params: FrameParams): Promise<Uint8Array> {
  const buf = await invoke<ArrayBuffer>('grab_frame', { params });
  return new Uint8Array(buf);
}

/** Map a normalized CropBox + source dims to the pixel rect the engine wants,
 * matching computeOutputSize's sx/sy/sw/sh. Returns null when there's no crop. */
export function cropToPixels(crop: CropBox | null | undefined, srcW: number, srcH: number): CropPx | null {
  if (!crop) return null;
  return {
    sx: Math.round(crop.x * srcW),
    sy: Math.round(crop.y * srcH),
    sw: Math.max(1, Math.round(crop.w * srcW)),
    sh: Math.max(1, Math.round(crop.h * srcH)),
  };
}
