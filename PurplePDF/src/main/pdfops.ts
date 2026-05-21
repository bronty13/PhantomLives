import { readFile, writeFile } from 'node:fs/promises';
import { PDFDocument } from 'pdf-lib';

/**
 * Merge an ordered list of PDF files into a single PDF written to outPath.
 * Pages are appended in the order the inputs are listed. Form fields and
 * annotation widgets are copied along with the page content via pdf-lib's
 * copyPages.
 */
export async function combinePdfs(inputPaths: string[], outPath: string): Promise<{
  outPath: string;
  pageCount: number;
  inputCount: number;
}> {
  if (inputPaths.length === 0) {
    throw new Error('combinePdfs: at least one input PDF is required.');
  }
  const out = await PDFDocument.create();
  let total = 0;
  for (const p of inputPaths) {
    const bytes = await readFile(p);
    const src = await PDFDocument.load(bytes, { ignoreEncryption: false });
    const indices = src.getPageIndices();
    const copied = await out.copyPages(src, indices);
    for (const page of copied) {
      out.addPage(page);
      total++;
    }
  }
  const outBytes = await out.save();
  await writeFile(outPath, outBytes);
  return { outPath, pageCount: total, inputCount: inputPaths.length };
}

/**
 * Split a single PDF into one PDF per page. Returns the list of written file
 * paths. Output naming: `${prefix}_page_${n}.pdf` in outDir.
 */
export async function splitPdfPerPage(
  inputPath: string,
  outDir: string,
  prefix: string
): Promise<string[]> {
  const bytes = await readFile(inputPath);
  const src = await PDFDocument.load(bytes);
  const total = src.getPageCount();
  const written: string[] = [];
  for (let i = 0; i < total; i++) {
    const out = await PDFDocument.create();
    const [copied] = await out.copyPages(src, [i]);
    out.addPage(copied);
    const outBytes = await out.save();
    const padWidth = String(total).length;
    const num = String(i + 1).padStart(padWidth, '0');
    const path = `${outDir}/${prefix}_page_${num}.pdf`;
    await writeFile(path, outBytes);
    written.push(path);
  }
  return written;
}

/**
 * Extract a list of 1-based page ranges (e.g. [[1,3],[5,5],[8,10]]) from
 * inputPath into a new PDF at outPath.
 */
export async function extractPages(
  inputPath: string,
  ranges: Array<[number, number]>,
  outPath: string
): Promise<{ outPath: string; pageCount: number }> {
  const bytes = await readFile(inputPath);
  const src = await PDFDocument.load(bytes);
  const total = src.getPageCount();
  const indices: number[] = [];
  for (const [a, b] of ranges) {
    const lo = Math.max(1, Math.min(a, b));
    const hi = Math.min(total, Math.max(a, b));
    for (let i = lo; i <= hi; i++) indices.push(i - 1);
  }
  if (indices.length === 0) {
    throw new Error('extractPages: no pages selected.');
  }
  const out = await PDFDocument.create();
  const copied = await out.copyPages(src, indices);
  for (const p of copied) out.addPage(p);
  const outBytes = await out.save();
  await writeFile(outPath, outBytes);
  return { outPath, pageCount: indices.length };
}

/** Parse a human range string like "1-3, 5, 8-10" into [[1,3],[5,5],[8,10]]. */
export function parseRangeString(s: string): Array<[number, number]> {
  const out: Array<[number, number]> = [];
  const parts = s
    .split(/[,\s]+/)
    .map((p) => p.trim())
    .filter(Boolean);
  for (const p of parts) {
    const m = /^(\d+)(?:\s*-\s*(\d+))?$/.exec(p);
    if (!m) throw new Error(`Invalid range token: "${p}"`);
    const a = parseInt(m[1], 10);
    const b = m[2] ? parseInt(m[2], 10) : a;
    out.push([a, b]);
  }
  return out;
}
