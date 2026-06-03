import { computeOutputSize, drawCaption, type CaptionSettings, type CropBox } from './encodeGif';

// MP4 clip spec (per requirements): max 60s, max 100 MB.
export const MP4_MAX_DURATION_S = 60;
export const MP4_MAX_BYTES = 100 * 1024 * 1024;

const AUDIO_BPS = 128_000;
const MAX_VIDEO_BPS = 8_000_000;
const MIN_VIDEO_BPS = 1_000_000;

export interface ClipSettings {
  startSec: number;
  endSec: number;
  fps: number;
  outputWidth: number;
  crop?: CropBox | null;
  caption?: CaptionSettings | null;
  includeAudio: boolean;
}

/** Pick the best available recorder container, preferring real MP4 (H.264).
 * Returns null when the WebView can't record video at all. */
export function supportedClipType(): { mimeType: string; ext: string } | null {
  if (typeof MediaRecorder === 'undefined') return null;
  const candidates: { mimeType: string; ext: string }[] = [
    { mimeType: 'video/mp4;codecs=avc1.42E01E,mp4a.40.2', ext: 'mp4' },
    { mimeType: 'video/mp4;codecs=avc1.640028,mp4a.40.2', ext: 'mp4' },
    { mimeType: 'video/mp4;codecs=h264,aac', ext: 'mp4' },
    { mimeType: 'video/mp4', ext: 'mp4' },
    { mimeType: 'video/webm;codecs=vp9,opus', ext: 'webm' },
    { mimeType: 'video/webm;codecs=vp8,opus', ext: 'webm' },
    { mimeType: 'video/webm', ext: 'webm' },
  ];
  for (const c of candidates) {
    try { if (MediaRecorder.isTypeSupported(c.mimeType)) return c; } catch { /* keep trying */ }
  }
  return null;
}

/** Video bitrate (bps) that keeps `durationSec` of clip under the 100 MB cap,
 * leaving room for audio. Clamped to a sane [1, 8] Mbps range. Pure —
 * unit-tested. */
export function clipVideoBitrate(durationSec: number, includeAudio: boolean): number {
  const d = Math.max(0.2, durationSec);
  const budgetTotalBps = (MP4_MAX_BYTES * 8 * 0.9) / d;
  const forVideo = budgetTotalBps - (includeAudio ? AUDIO_BPS : 0);
  return Math.max(MIN_VIDEO_BPS, Math.min(MAX_VIDEO_BPS, Math.floor(forVideo)));
}

// HTMLMediaElement.captureStream is unprefixed in Chromium and prefixed in
// some WebKit builds; treat both.
interface CapturableVideo extends HTMLVideoElement {
  captureStream?: () => MediaStream;
  mozCaptureStream?: () => MediaStream;
}

function elementAudioTracks(video: CapturableVideo): MediaStreamTrack[] {
  try {
    const s = video.captureStream ? video.captureStream() : video.mozCaptureStream?.();
    return s ? s.getAudioTracks() : [];
  } catch {
    return [];
  }
}

/** Record the trimmed/cropped/captioned clip in real time via MediaRecorder.
 * Video comes from a canvas we redraw each frame (so crop + caption match the
 * GIF exactly); audio is the source element's own track. Returns the encoded
 * bytes plus the container actually used. Real-time: takes ~clip length. */
export async function recordClip(
  video: HTMLVideoElement,
  raw: ClipSettings,
  onProgress?: (fraction: number) => void,
): Promise<{ bytes: Uint8Array; mimeType: string; ext: string; audioIncluded: boolean }> {
  const type = supportedClipType();
  if (!type) throw new Error("This system's browser engine can't record video.");

  const srcW = video.videoWidth;
  const srcH = video.videoHeight;
  if (!srcW || !srcH) throw new Error('Video has no decodable dimensions yet.');

  const start = Math.max(0, Math.min(raw.startSec, video.duration || raw.startSec));
  const end = Math.min(raw.endSec, start + MP4_MAX_DURATION_S, video.duration || raw.endSec);
  const durationSec = Math.max(0.2, end - start);

  const { width, height, sx, sy, sw, sh } = computeOutputSize(srcW, srcH, raw.crop, raw.outputWidth);
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('Could not get a 2D canvas context.');

  const canvasStream = canvas.captureStream(raw.fps);
  let tracks: MediaStreamTrack[] = [...canvasStream.getVideoTracks()];
  let audioIncluded = false;
  const wasMuted = video.muted;
  if (raw.includeAudio) {
    video.muted = false; // a muted element captures a silent audio track
    const aTracks = elementAudioTracks(video);
    if (aTracks.length) { tracks = tracks.concat(aTracks); audioIncluded = true; }
  }
  const stream = new MediaStream(tracks);

  // Bitrate budget so duration * total_bps / 8 stays comfortably under 100 MB.
  const videoBps = clipVideoBitrate(durationSec, audioIncluded);

  const rec = new MediaRecorder(stream, {
    mimeType: type.mimeType,
    videoBitsPerSecond: videoBps,
    ...(audioIncluded ? { audioBitsPerSecond: AUDIO_BPS } : {}),
  });
  const chunks: BlobPart[] = [];
  rec.ondataavailable = (e) => { if (e.data && e.data.size) chunks.push(e.data); };

  return await new Promise((resolve, reject) => {
    let rafId = 0;
    let hardStop: ReturnType<typeof setTimeout> | null = null;
    const restore = () => { video.muted = wasMuted; };
    const stop = () => {
      if (rafId) cancelAnimationFrame(rafId);
      if (hardStop) { clearTimeout(hardStop); hardStop = null; }
      if (rec.state !== 'inactive') rec.stop();
    };
    const cleanup = () => {
      if (rafId) cancelAnimationFrame(rafId);
      if (hardStop) { clearTimeout(hardStop); hardStop = null; }
      try { video.pause(); } catch { /* */ }
      restore();
    };

    const draw = () => {
      ctx.drawImage(video, sx, sy, sw, sh, 0, 0, width, height);
      if (raw.caption && raw.caption.text.trim()) drawCaption(ctx, raw.caption, width, height);
      const t = video.currentTime;
      onProgress?.(Math.min(1, (t - start) / durationSec));
      // Stop at the trim end. `>=` against the absolute end-time handles the
      // common case; the wall-clock backstop below guarantees the clip can
      // never exceed durationSec (≤ 60s) even if playback didn't begin
      // exactly at `start` (a missed/slow seek).
      if (t >= end - 0.02 || video.ended) { stop(); return; }
      rafId = requestAnimationFrame(draw);
    };

    rec.onstop = async () => {
      cleanup();
      try {
        const blob = new Blob(chunks, { type: type.mimeType });
        const bytes = new Uint8Array(await blob.arrayBuffer());
        resolve({ bytes, mimeType: type.mimeType, ext: type.ext, audioIncluded });
      } catch (e) { reject(e); }
    };
    rec.onerror = () => { cleanup(); reject(new Error('Recording failed.')); };

    const begin = () => {
      try {
        rec.start();
        // Hard ceiling: never record longer than the clamped duration,
        // regardless of where playback actually started. +300ms covers the
        // MediaRecorder stop tail.
        hardStop = setTimeout(stop, durationSec * 1000 + 300);
        video.play()
          .then(() => { rafId = requestAnimationFrame(draw); })
          .catch((e) => { cleanup(); reject(e); });
      } catch (e) { cleanup(); reject(e as Error); }
    };

    const onSeeked = () => { video.removeEventListener('seeked', onSeeked); begin(); };
    // Setting currentTime to its current value fires no 'seeked' event, so
    // start directly when we're already at (or essentially at) `start`.
    if (Math.abs(video.currentTime - start) < 0.05) {
      begin();
    } else {
      video.addEventListener('seeked', onSeeked);
      try { video.currentTime = start; } catch (e) { video.removeEventListener('seeked', onSeeked); reject(e as Error); }
    }
  });
}
