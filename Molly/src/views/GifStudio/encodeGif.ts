// Caps mirror what a video→GIF tool enforces: keep the encode snappy and the
// output small. Stated in the UI so Sallie isn't surprised.
export const MAX_DURATION_S = 15;
export const MIN_FPS = 2;
export const MAX_FPS = 25;
export const MIN_WIDTH = 64;
// GIFs balloon with resolution (palette per frame), so the cap is well below
// the MP4's — but high enough for a crisp teaser loop.
export const MAX_WIDTH = 960;
/** Thumbnail images must stay under 5 MB (JPG/PNG spec). */
export const THUMBNAIL_MAX_BYTES = 5 * 1024 * 1024;

// Teaser MP4 caps (enforced in the native engine + surfaced in the UI).
export const MP4_MAX_DURATION_S = 60;
export const MP4_MAX_BYTES = 100 * 1024 * 1024;

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

export function drawCaption(
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

export interface FrameSettings {
  /** Time in the source video to grab, in seconds. */
  timeSec: number;
  /** Desired output width in px; height derives from the (cropped) aspect. */
  outputWidth: number;
  quality: GifQuality;
  crop?: CropBox | null;
  caption?: CaptionSettings | null;
  /** JPEG quality 0..1 (default 0.92). */
  jpegQuality?: number;
}

/** Render a caption onto a transparent PNG sized to the OUTPUT W×H, so the
 * native ffmpeg engine can composite it with `overlay`. Reuses the exact
 * `drawCaption` look (white fill + black stroke, top/bottom). DOM-dependent. */
export async function renderCaptionPng(
  caption: CaptionSettings,
  width: number,
  height: number,
): Promise<Uint8Array> {
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('Could not get a 2D canvas context.');
  ctx.clearRect(0, 0, width, height); // transparent background
  drawCaption(ctx, caption, width, height);
  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/png'));
  if (!blob) throw new Error('Could not encode the caption overlay.');
  return new Uint8Array(await blob.arrayBuffer());
}
