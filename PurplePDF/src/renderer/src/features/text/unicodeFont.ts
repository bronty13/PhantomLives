import type { PDFDocument, PDFFont } from 'pdf-lib';

let regularBytesPromise: Promise<ArrayBuffer> | null = null;
let boldBytesPromise: Promise<ArrayBuffer> | null = null;
const fontkitRegistered = new WeakSet<PDFDocument>();

async function loadFontBytes(rel: string): Promise<ArrayBuffer> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const api = (window as any).purplePDF;
  if (api?.assetBytes) return api.assetBytes(rel);
  const url = api?.assetUrl ? api.assetUrl(rel) : `pp-asset://local/${rel}`;
  const res = await fetch(url);
  return await res.arrayBuffer();
}

async function getRegular(): Promise<ArrayBuffer> {
  if (!regularBytesPromise) regularBytesPromise = loadFontBytes('fonts/NotoSans-Regular.ttf');
  return regularBytesPromise;
}
async function getBold(): Promise<ArrayBuffer> {
  if (!boldBytesPromise) boldBytesPromise = loadFontBytes('fonts/NotoSans-Bold.ttf');
  return boldBytesPromise;
}

async function ensureFontkit(doc: PDFDocument): Promise<void> {
  if (fontkitRegistered.has(doc)) return;
  const mod = await import('@pdf-lib/fontkit');
  const fontkit = (mod as unknown as { default: unknown }).default ?? mod;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (doc as any).registerFontkit(fontkit);
  fontkitRegistered.add(doc);
}

/**
 * Embed Noto Sans (full Unicode) into the document. Falls back to the caller-
 * provided fallback (typically Helvetica) on any error so stamping still
 * succeeds for installations where the bundled font is unavailable.
 */
export async function embedUnicodeFont(
  doc: PDFDocument,
  options?: { bold?: boolean; fallback?: PDFFont }
): Promise<PDFFont> {
  try {
    await ensureFontkit(doc);
    const bytes = options?.bold ? await getBold() : await getRegular();
    return await doc.embedFont(new Uint8Array(bytes), { subset: true });
  } catch (err) {
    if (options?.fallback) return options.fallback;
    throw err;
  }
}
