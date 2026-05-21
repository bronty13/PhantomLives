import { createWorker, type Worker } from 'tesseract.js';
import { PDFDocument, StandardFonts } from 'pdf-lib';
import { embedUnicodeFont } from '../text/unicodeFont';
import type { PDFDocumentProxy } from '../viewer/pdfjs';

export interface OcrProgress {
  page: number;
  total: number;
  phase: 'render' | 'recognize' | 'embed';
}

let cached: Worker | null = null;
let workerBlobUrl: string | null = null;
async function getWorker(): Promise<Worker> {
  if (cached) return cached;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const api = (window as any).purplePDF;
  const assetUrl = (rel: string): string =>
    api?.assetUrl ? api.assetUrl(rel) : `pp-asset://local/${rel}`;
  // Web Workers can be picky about custom-protocol script URLs; fetch the
  // worker script via the pp-asset protocol and instantiate from a blob URL
  // so the renderer's origin treats it as same-origin.
  if (!workerBlobUrl) {
    try {
      const res = await fetch(assetUrl('tesseract/worker.min.js'));
      const blob = await res.blob();
      workerBlobUrl = URL.createObjectURL(blob);
    } catch {
      workerBlobUrl = assetUrl('tesseract/worker.min.js');
    }
  }
  cached = await createWorker('eng', undefined, {
    workerPath: workerBlobUrl,
    // corePath is a directory URL; tesseract.js appends the appropriate
    // core filename (tesseract-core-simd.js etc) based on browser capability.
    corePath: assetUrl('tesseract'),
    langPath: assetUrl('tesseract'),
    // Cache disabled — local files are already on disk.
    cacheMethod: 'none'
  });
  return cached;
}

/** Free Tesseract resources between runs. */
export async function destroyOcrWorker(): Promise<void> {
  if (cached) {
    await cached.terminate();
    cached = null;
  }
}

/**
 * Run OCR over `pageNumbers` (1-based) of the provided pdfjs doc and bake an
 * invisible text layer back into a copy of `originalBytes`. Returns new PDF
 * bytes whose pages now have searchable/selectable text overlaying the image.
 */
export async function ocrPages(args: {
  originalBytes: ArrayBuffer;
  doc: PDFDocumentProxy;
  pageNumbers: number[];
  scale?: number;
  onProgress?: (p: OcrProgress) => void;
}): Promise<Uint8Array> {
  const { originalBytes, doc, pageNumbers, onProgress } = args;
  const scale = args.scale ?? 2;
  const worker = await getWorker();
  const out = await PDFDocument.load(originalBytes);
  const fallbackFont = await out.embedFont(StandardFonts.Helvetica);
  const font = await embedUnicodeFont(out, { fallback: fallbackFont });
  const total = pageNumbers.length;
  let i = 0;
  for (const pageNumber of pageNumbers) {
    i++;
    onProgress?.({ page: i, total, phase: 'render' });
    const page = await doc.getPage(pageNumber);
    const viewport = page.getViewport({ scale });
    const canvas = document.createElement('canvas');
    canvas.width = Math.ceil(viewport.width);
    canvas.height = Math.ceil(viewport.height);
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    if (!ctx) continue;
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    await page.render({ canvasContext: ctx, viewport }).promise;
    onProgress?.({ page: i, total, phase: 'recognize' });
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const result = await worker.recognize(canvas as any);
    onProgress?.({ page: i, total, phase: 'embed' });
    const targetPage = out.getPage(pageNumber - 1);
    const pageH = targetPage.getSize().height;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const words: any[] = collectWords(result.data);
    for (const w of words) {
      const text: string = w.text ?? '';
      if (!text.trim()) continue;
      const bbox = w.bbox;
      if (!bbox) continue;
      const x = bbox.x0 / scale;
      const wpx = (bbox.x1 - bbox.x0) / scale;
      const hpx = (bbox.y1 - bbox.y0) / scale;
      // Flip Y: tesseract origin is top-left; PDF is bottom-left.
      const y = pageH - bbox.y1 / scale;
      const size = Math.max(2, hpx * 0.9);
      try {
        targetPage.drawText(text, {
          x,
          y,
          size,
          font,
          opacity: 0,
          maxWidth: wpx
        });
      } catch {
        // pdf-lib throws on certain unicode points outside WinAnsi; skip silently.
      }
    }
  }
  return await out.save();
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function collectWords(data: any): any[] {
  if (Array.isArray(data?.words)) return data.words;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const out: any[] = [];
  const blocks = data?.blocks ?? [];
  for (const b of blocks) {
    const paragraphs = b?.paragraphs ?? [];
    for (const p of paragraphs) {
      const lines = p?.lines ?? [];
      for (const l of lines) {
        const ws = l?.words ?? [];
        for (const w of ws) out.push(w);
      }
    }
  }
  return out;
}
