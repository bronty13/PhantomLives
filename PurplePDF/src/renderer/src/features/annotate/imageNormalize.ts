/**
 * @file imageNormalize.ts — convert any browser-decodable image (PNG /
 * JPEG / GIF / WebP / SVG) plus HEIC into PNG or JPEG bytes the way
 * `pdf-lib` expects, along with intrinsic pixel dimensions.
 *
 * Runs entirely in the renderer (no native deps). HEIC is decoded with
 * `heic2any` (pure JS); everything else round-trips through an
 * `<img>` + `<canvas>`.
 */

export interface NormalizedImage {
  bytes: Uint8Array;
  mime: 'image/png' | 'image/jpeg';
  width: number;
  height: number;
}

/** Strict extension → MIME mapping used as a hint when sniffing fails. */
const EXT_TO_MIME: Record<string, string> = {
  png: 'image/png',
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  gif: 'image/gif',
  webp: 'image/webp',
  svg: 'image/svg+xml',
  heic: 'image/heic',
  heif: 'image/heif'
};

export function mimeForExt(ext: string): string | null {
  return EXT_TO_MIME[ext.toLowerCase()] ?? null;
}

/** Sniff a magic number from the first bytes; fall back to ext hint. */
export function sniffMime(bytes: Uint8Array, extHint?: string): string {
  if (bytes.length >= 8) {
    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (
      bytes[0] === 0x89 &&
      bytes[1] === 0x50 &&
      bytes[2] === 0x4e &&
      bytes[3] === 0x47
    )
      return 'image/png';
    // JPEG: FF D8 FF
    if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return 'image/jpeg';
    // GIF87a / GIF89a
    if (
      bytes[0] === 0x47 &&
      bytes[1] === 0x49 &&
      bytes[2] === 0x46 &&
      bytes[3] === 0x38
    )
      return 'image/gif';
    // WebP: RIFF????WEBP
    if (
      bytes[0] === 0x52 &&
      bytes[1] === 0x49 &&
      bytes[2] === 0x46 &&
      bytes[3] === 0x46 &&
      bytes.length >= 12 &&
      bytes[8] === 0x57 &&
      bytes[9] === 0x45 &&
      bytes[10] === 0x42 &&
      bytes[11] === 0x50
    )
      return 'image/webp';
    // HEIC has a complex ftyp box; sniff "ftyp" at offset 4
    if (
      bytes[4] === 0x66 &&
      bytes[5] === 0x74 &&
      bytes[6] === 0x79 &&
      bytes[7] === 0x70
    ) {
      return 'image/heic';
    }
  }
  // SVG: text starting with "<" possibly with BOM/whitespace
  if (bytes.length > 0) {
    const head = new TextDecoder().decode(bytes.slice(0, Math.min(256, bytes.length))).trim();
    if (head.startsWith('<?xml') || head.startsWith('<svg')) return 'image/svg+xml';
  }
  return mimeForExt(extHint ?? '') ?? 'application/octet-stream';
}

function decodeImageElement(blob: Blob): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(blob);
    const img = new Image();
    img.onload = () => {
      URL.revokeObjectURL(url);
      resolve(img);
    };
    img.onerror = (e) => {
      URL.revokeObjectURL(url);
      reject(new Error(`Image decode failed: ${String(e)}`));
    };
    img.src = url;
  });
}

async function canvasToPng(canvas: HTMLCanvasElement): Promise<Uint8Array> {
  return await new Promise<Uint8Array>((resolve, reject) => {
    canvas.toBlob(async (b) => {
      if (!b) return reject(new Error('Canvas toBlob returned null'));
      const buf = await b.arrayBuffer();
      resolve(new Uint8Array(buf));
    }, 'image/png');
  });
}

function toBlobPart(bytes: Uint8Array): ArrayBuffer {
  // Copy into a fresh, definitely-non-shared ArrayBuffer so the Blob ctor
  // type-checks under strict TS lib types (Uint8Array<SharedArrayBuffer>
  // is no longer assignable to BlobPart).
  const out = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(out).set(bytes);
  return out;
}

/**
 * Normalize raw image bytes into PNG (preserves alpha) or pass-through
 * JPEG. The resulting bytes embed cleanly into pdf-lib via embedPng /
 * embedJpg, and the returned width/height give the intrinsic pixel
 * size so callers can pick a sensible default placement rect.
 */
export async function normalizeImage(
  bytes: Uint8Array,
  extHint?: string
): Promise<NormalizedImage> {
  const mime = sniffMime(bytes, extHint);

  // Pass-through: PNG and JPEG can go straight into pdf-lib.
  if (mime === 'image/png' || mime === 'image/jpeg') {
    const blob = new Blob([toBlobPart(bytes)], { type: mime });
    const img = await decodeImageElement(blob);
    return { bytes, mime, width: img.naturalWidth, height: img.naturalHeight };
  }

  // HEIC needs heic2any (pure JS) before the canvas can touch it.
  if (mime === 'image/heic' || mime === 'image/heif') {
    const { default: heic2any } = await import('heic2any');
    const converted = (await heic2any({
      blob: new Blob([toBlobPart(bytes)], { type: mime }),
      toType: 'image/png',
      quality: 1
    })) as Blob | Blob[];
    const pngBlob = Array.isArray(converted) ? converted[0] : converted;
    const img = await decodeImageElement(pngBlob);
    const pngBytes = new Uint8Array(await pngBlob.arrayBuffer());
    return { bytes: pngBytes, mime: 'image/png', width: img.naturalWidth, height: img.naturalHeight };
  }

  // SVG / GIF / WebP / unknown: render via <img> and snapshot to canvas.
  const blobMime = mime === 'application/octet-stream' ? 'image/png' : mime;
  const blob = new Blob([toBlobPart(bytes)], { type: blobMime });
  const img = await decodeImageElement(blob);
  // SVGs without intrinsic size report 0×0 — fall back to a sane default.
  const w = img.naturalWidth || 512;
  const h = img.naturalHeight || 512;
  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('No 2D canvas context');
  ctx.drawImage(img, 0, 0, w, h);
  const out = await canvasToPng(canvas);
  return { bytes: out, mime: 'image/png', width: w, height: h };
}
