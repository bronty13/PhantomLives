import { GIFEncoder, quantize, applyPalette } from 'gifenc';

// Caps mirror what a browser video→GIF tool enforces: keep the encode
// snappy and memory bounded. Stated in the UI so Sallie isn't surprised.
export const MAX_DURATION_S = 15;
export const MIN_FPS = 2;
export const MAX_FPS = 25;
export const MIN_WIDTH = 64;
export const MAX_WIDTH = 640;

export type GifQuality = 'high' | 'medium' | 'low';

/** Normalized crop box (fractions of the source frame, 0..1). */
export interface CropBox {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface CaptionSettings {
  text: string;
  position: 'top' | 'bottom';
  /** Font size as a fraction of output height (e.g. 0.09). */
  sizeFrac: number;
}

export interface GifSettings {
  startSec: number;
  endSec: number;
  fps: number;
  /** Desired output width in px; height derives from the (cropped) aspect. */
  outputWidth: number;
  quality: GifQuality;
  crop?: CropBox | null;
  caption?: CaptionSettings | null;
}

/** Per-frame delay in milliseconds for a given fps (GIF stores centiseconds,
 * but gifenc takes ms and rounds internally). Pure — unit-tested. */
export function frameDelayMs(fps: number): number {
  return Math.round(1000 / fps);
}

/** Number of frames captured across [start, end] at fps, inclusive of the
 * first frame. Pure — unit-tested. */
export function frameCount(startSec: number, endSec: number, fps: number): number {
  const span = Math.max(0, endSec - startSec);
  return Math.max(1, Math.round(span * fps));
}

/** Map the quality knob to a max palette size. Fewer colors = smaller GIF. */
export function paletteColors(quality: GifQuality): number {
  switch (quality) {
    case 'high': return 256;
    case 'medium': return 128;
    case 'low': return 64;
  }
}

/** Clamp raw user settings into the supported ranges. Pure — unit-tested. */
export function clampSettings(raw: GifSettings, sourceDurationSec: number): GifSettings {
  const dur = Number.isFinite(sourceDurationSec) && sourceDurationSec > 0 ? sourceDurationSec : MAX_DURATION_S;
  let start = Math.max(0, Math.min(raw.startSec, dur));
  let end = Math.max(start, Math.min(raw.endSec, dur));
  // Enforce the max clip length by trimming the end.
  if (end - start > MAX_DURATION_S) end = start + MAX_DURATION_S;
  const fps = Math.max(MIN_FPS, Math.min(MAX_FPS, Math.round(raw.fps)));
  const outputWidth = Math.max(MIN_WIDTH, Math.min(MAX_WIDTH, Math.round(raw.outputWidth)));
  return { ...raw, startSec: start, endSec: end, fps, outputWidth };
}

/** Compute the even output dimensions from the source size, optional crop,
 * and target width. Height keeps the cropped aspect ratio. Pure. */
export function computeOutputSize(
  srcW: number,
  srcH: number,
  crop: CropBox | null | undefined,
  targetWidth: number,
): { width: number; height: number; sx: number; sy: number; sw: number; sh: number } {
  const sx = crop ? Math.round(crop.x * srcW) : 0;
  const sy = crop ? Math.round(crop.y * srcH) : 0;
  const sw = crop ? Math.max(1, Math.round(crop.w * srcW)) : srcW;
  const sh = crop ? Math.max(1, Math.round(crop.h * srcH)) : srcH;
  const width = Math.max(2, Math.min(targetWidth, sw));
  // Keep aspect; force even to avoid odd-row artifacts.
  let height = Math.max(2, Math.round((sh / sw) * width));
  if (height % 2 === 1) height += 1;
  return { width, height, sx, sy, sw, sh };
}

function seek(video: HTMLVideoElement, time: number): Promise<void> {
  return new Promise((resolve, reject) => {
    const onSeeked = () => { cleanup(); resolve(); };
    const onError = () => { cleanup(); reject(new Error('seek failed')); };
    const cleanup = () => {
      video.removeEventListener('seeked', onSeeked);
      video.removeEventListener('error', onError);
    };
    video.addEventListener('seeked', onSeeked);
    video.addEventListener('error', onError);
    // Clamp into a safely-seekable range.
    video.currentTime = Math.max(0, Math.min(time, (video.duration || time) - 0.001));
  });
}

function drawCaption(
  ctx: CanvasRenderingContext2D,
  caption: CaptionSettings,
  width: number,
  height: number,
) {
  const fontPx = Math.max(10, Math.round(caption.sizeFrac * height));
  ctx.font = `bold ${fontPx}px sans-serif`;
  ctx.textAlign = 'center';
  ctx.textBaseline = caption.position === 'top' ? 'top' : 'bottom';
  ctx.lineJoin = 'round';
  ctx.lineWidth = Math.max(2, Math.round(fontPx / 6));
  const x = width / 2;
  const y = caption.position === 'top' ? Math.round(fontPx * 0.25) : height - Math.round(fontPx * 0.25);
  ctx.strokeStyle = 'rgba(0,0,0,0.85)';
  ctx.fillStyle = '#ffffff';
  ctx.strokeText(caption.text, x, y);
  ctx.fillText(caption.text, x, y);
}

/** Capture frames from a (loaded, seekable) <video> across the trim range
 * and encode an animated GIF. DOM-dependent (the seek loop); the math it
 * relies on lives in the pure helpers above so it stays test-light. */
export async function captureAndEncode(
  video: HTMLVideoElement,
  rawSettings: GifSettings,
  onProgress?: (done: number, total: number) => void,
): Promise<Uint8Array> {
  const settings = clampSettings(rawSettings, video.duration);
  const srcW = video.videoWidth;
  const srcH = video.videoHeight;
  if (!srcW || !srcH) throw new Error('Video has no decodable dimensions yet.');

  const { width, height, sx, sy, sw, sh } = computeOutputSize(srcW, srcH, settings.crop, settings.outputWidth);
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  if (!ctx) throw new Error('Could not get a 2D canvas context.');

  const total = frameCount(settings.startSec, settings.endSec, settings.fps);
  const delay = frameDelayMs(settings.fps);
  const maxColors = paletteColors(settings.quality);
  const step = total > 1 ? (settings.endSec - settings.startSec) / (total - 1) : 0;

  const gif = GIFEncoder();
  for (let i = 0; i < total; i++) {
    const t = settings.startSec + step * i;
    await seek(video, t);
    ctx.drawImage(video, sx, sy, sw, sh, 0, 0, width, height);
    if (settings.caption && settings.caption.text.trim()) {
      drawCaption(ctx, settings.caption, width, height);
    }
    const { data } = ctx.getImageData(0, 0, width, height);
    const palette = quantize(data, maxColors);
    const index = applyPalette(data, palette);
    gif.writeFrame(index, width, height, { palette, delay, repeat: 0 });
    onProgress?.(i + 1, total);
  }
  gif.finish();
  return gif.bytes();
}
