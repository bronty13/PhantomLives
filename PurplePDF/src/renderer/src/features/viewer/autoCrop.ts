import type { PDFDocumentProxy } from './pdfjs';

export interface CropResult {
  x: number;
  y: number;
  width: number;
  height: number;
}

/**
 * Render `pageNumber` (1-based) of `doc` at a modest scale, then walk the
 * rasterized pixels to find the bounding box of non-near-white content.
 * Returns the crop rectangle in PDF point units (origin bottom-left,
 * page-relative), padded by `paddingPt` on every side. Returns null when
 * the page is effectively blank.
 *
 * Threshold: a pixel counts as "content" when the per-channel sum
 * R+G+B < 720 (i.e. average below ~240) OR alpha < 250. Tunable via
 * `threshold`.
 */
export async function detectContentBounds(
  doc: PDFDocumentProxy,
  pageNumber: number,
  options?: { scale?: number; paddingPt?: number; threshold?: number }
): Promise<CropResult | null> {
  const scale = options?.scale ?? 1.0;
  const paddingPt = options?.paddingPt ?? 6;
  const threshold = options?.threshold ?? 720;

  const page = await doc.getPage(pageNumber);
  const viewport = page.getViewport({ scale });
  const canvas = document.createElement('canvas');
  canvas.width = Math.ceil(viewport.width);
  canvas.height = Math.ceil(viewport.height);
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  if (!ctx) return null;
  // Fill white so transparent areas don't count as content.
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  await page.render({ canvasContext: ctx, viewport }).promise;

  const { data, width: W, height: H } = ctx.getImageData(0, 0, canvas.width, canvas.height);
  let minX = W;
  let minY = H;
  let maxX = -1;
  let maxY = -1;
  // Walk every 2nd pixel to keep this fast on large pages.
  const step = 2;
  for (let y = 0; y < H; y += step) {
    const rowOff = y * W * 4;
    for (let x = 0; x < W; x += step) {
      const i = rowOff + x * 4;
      const r = data[i];
      const g = data[i + 1];
      const b = data[i + 2];
      const a = data[i + 3];
      if (a < 250 || r + g + b < threshold) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) return null;

  // The pdfjs viewport at scale=1 maps 1 PDF pt → 1 canvas px.
  // Convert pixel bounds → PDF points, flipping Y (PDF origin = bottom-left).
  const pageHpt = page.getViewport({ scale: 1 }).height;
  const pageWpt = page.getViewport({ scale: 1 }).width;

  const xPt = minX / scale;
  const wPt = (maxX - minX + 1) / scale;
  const topPt = minY / scale; // distance from top edge in PDF pts
  const hPt = (maxY - minY + 1) / scale;
  const yPt = pageHpt - topPt - hPt; // PDF y from bottom

  // Apply padding and clamp to page bounds.
  const px = Math.max(0, xPt - paddingPt);
  const py = Math.max(0, yPt - paddingPt);
  const pw = Math.min(pageWpt - px, wPt + paddingPt * 2);
  const ph = Math.min(pageHpt - py, hPt + paddingPt * 2);
  return { x: px, y: py, width: pw, height: ph };
}
