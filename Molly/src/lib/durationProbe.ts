import { convertFileSrc } from '@tauri-apps/api/core';
import { probeVideo } from '../data/gifStudio';
import type { BundleFileInfo } from '../data/bundles';

// Sum the durations of a bundle's videos so we can suggest a default price.
//
// Two ways to read a duration, tried in order:
//   1. ffprobe (the bundled native engine) — reliable everywhere a real build
//      ships the binary (notably Windows, where the WebView can't decode HEVC).
//   2. A hidden <video> element via convertFileSrc — the SAME way GIF Studio
//      reads duration. This is the fallback for when ffprobe isn't available,
//      e.g. a locally-built macOS app whose `resources/ffmpeg/` is just a
//      .gitkeep placeholder (the real binaries are CI-downloaded). On macOS
//      AVFoundation decodes the file natively, so duration reads fine.
//
// Memoized by absolute path (a saved file's path is stable, and the content
// form + publish wizard both probe the same files). A duration that can't be
// read by EITHER method isn't cached (so a transient failure can recover) and
// is counted so the UI can warn the estimate may be low. Never throws.

const durationCache = new Map<string, number>();

export interface DurationTotal {
  totalSeconds: number;
  videoCount: number;
  /** Videos whose duration couldn't be read by ffprobe OR the video element. */
  failedCount: number;
}

/** Read a video's duration via a detached <video> element. Resolves 0 on any failure. */
function probeDurationViaElement(absolutePath: string, timeoutMs = 8000): Promise<number> {
  return new Promise((resolve) => {
    const v = document.createElement('video');
    v.preload = 'metadata';
    v.muted = true;
    let settled = false;
    const finish = (d: number) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      v.onloadedmetadata = null;
      v.onerror = null;
      v.removeAttribute('src');
      try { v.load(); } catch { /* ignore */ }
      resolve(Number.isFinite(d) && d > 0 ? d : 0);
    };
    const timer = setTimeout(() => finish(0), timeoutMs);
    v.onloadedmetadata = () => finish(v.duration);
    v.onerror = () => finish(0);
    try {
      v.src = convertFileSrc(absolutePath);
    } catch {
      finish(0);
    }
  });
}

/** Read one video's duration in seconds (ffprobe first, <video> fallback). 0 = unreadable. */
async function readDuration(absolutePath: string): Promise<number> {
  try {
    const r = await probeVideo(absolutePath);
    if (Number.isFinite(r.durationSec) && r.durationSec > 0) return r.durationSec;
  } catch {
    /* ffprobe missing or failed — fall through to the element */
  }
  return probeDurationViaElement(absolutePath);
}

/** Probe every `kind === 'video'` file and sum the readable durations. Never throws. */
export async function sumVideoDurations(files: BundleFileInfo[]): Promise<DurationTotal> {
  const videos = files.filter((f) => f.kind === 'video');
  let totalSeconds = 0;
  let failedCount = 0;
  for (const f of videos) {
    const cached = durationCache.get(f.absolutePath);
    if (cached != null) {
      totalSeconds += cached;
      continue;
    }
    const d = await readDuration(f.absolutePath);
    if (d > 0) {
      durationCache.set(f.absolutePath, d);
      totalSeconds += d;
    } else {
      failedCount += 1;
    }
  }
  return { totalSeconds, videoCount: videos.length, failedCount };
}
