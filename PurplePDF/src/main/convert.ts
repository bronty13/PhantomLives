// Creation & conversion utilities (Phase 4).
//
// Runs entirely in the main process (Node + Electron BrowserWindow). The
// renderer talks to these via IPC. Heavy lifting is delegated to:
//   • pdf-lib            — image embedding for image→PDF
//   • Electron printToPDF — web page capture
//   • sips (macOS)       — raster format conversion (HEIC/TIFF/… → JPEG)
//   • LibreOffice CLI    — Office ⇄ PDF (best-effort, graceful when missing)

import { BrowserWindow } from 'electron';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdir, readFile, stat, unlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { basename, extname, join } from 'node:path';
import { PDFDocument } from 'pdf-lib';

const JPG_EXTS = new Set(['.jpg', '.jpeg']);
const PNG_EXTS = new Set(['.png']);
const SIPS_INPUT_EXTS = new Set(['.heic', '.heif', '.tiff', '.tif', '.gif', '.bmp', '.webp']);

const LIBREOFFICE_PATHS = [
  '/Applications/LibreOffice.app/Contents/MacOS/soffice',
  '/opt/homebrew/bin/soffice',
  '/usr/local/bin/soffice',
  '/usr/bin/soffice',
  'C:\\Program Files\\LibreOffice\\program\\soffice.exe',
  'C:\\Program Files (x86)\\LibreOffice\\program\\soffice.exe'
];

export function findLibreOffice(): string | null {
  for (const p of LIBREOFFICE_PATHS) {
    if (existsSync(p)) return p;
  }
  return null;
}

interface RunResult {
  code: number;
  stdout: string;
  stderr: string;
}

function run(cmd: string, args: string[], timeoutMs = 120_000): Promise<RunResult> {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      reject(new Error(`${cmd} timed out after ${timeoutMs}ms`));
    }, timeoutMs);
    child.stdout.on('data', (d) => {
      stdout += d.toString();
    });
    child.stderr.on('data', (d) => {
      stderr += d.toString();
    });
    child.on('error', (err) => {
      clearTimeout(timer);
      reject(err);
    });
    child.on('exit', (code) => {
      clearTimeout(timer);
      resolve({ code: code ?? -1, stdout, stderr });
    });
  });
}

async function preprocessImage(
  input: string
): Promise<{ path: string; cleanup?: () => Promise<void> }> {
  const ext = extname(input).toLowerCase();
  if (JPG_EXTS.has(ext) || PNG_EXTS.has(ext)) return { path: input };
  if (process.platform === 'darwin' && SIPS_INPUT_EXTS.has(ext)) {
    const out = join(
      tmpdir(),
      `purplepdf-${Date.now()}-${Math.random().toString(36).slice(2, 8)}.jpg`
    );
    const res = await run('sips', ['-s', 'format', 'jpeg', input, '--out', out]);
    if (res.code !== 0) {
      throw new Error(`sips failed (${res.code}): ${res.stderr || res.stdout}`);
    }
    return {
      path: out,
      cleanup: async () => {
        await unlink(out).catch(() => undefined);
      }
    };
  }
  throw new Error(
    `Unsupported image format: ${ext}. Supported: .jpg .jpeg .png` +
      (process.platform === 'darwin' ? ' (plus .heic .tiff .gif .bmp .webp via sips)' : '')
  );
}

/**
 * Embed a list of images (one per page) into a new PDF.
 * Each page is sized to the image's native pixel dimensions (1px = 1pt).
 */
export async function imagesToPdf(imagePaths: string[], outPath: string): Promise<void> {
  if (imagePaths.length === 0) throw new Error('No images to convert.');
  const doc = await PDFDocument.create();
  for (const original of imagePaths) {
    const { path: prepared, cleanup } = await preprocessImage(original);
    try {
      const bytes = await readFile(prepared);
      const ext = extname(prepared).toLowerCase();
      const img = PNG_EXTS.has(ext)
        ? await doc.embedPng(bytes)
        : await doc.embedJpg(bytes);
      const page = doc.addPage([img.width, img.height]);
      page.drawImage(img, { x: 0, y: 0, width: img.width, height: img.height });
    } finally {
      if (cleanup) await cleanup();
    }
  }
  const out = await doc.save();
  await writeFile(outPath, out);
}

/**
 * Capture a URL as a PDF using Electron's offscreen rendering + printToPDF.
 */
export async function urlToPdf(url: string, outPath: string): Promise<void> {
  const win = new BrowserWindow({
    show: false,
    width: 1280,
    height: 1600,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
      javascript: true
    }
  });
  try {
    await win.loadURL(url, { userAgent: 'Mozilla/5.0 (Purple PDF Capture)' });
    // Allow late-loading content (web fonts, lazy images) to settle.
    await new Promise((resolve) => setTimeout(resolve, 1500));
    const pdf = await win.webContents.printToPDF({
      printBackground: true,
      pageSize: 'Letter',
      margins: { top: 0.4, bottom: 0.4, left: 0.4, right: 0.4 }
    });
    await writeFile(outPath, pdf);
  } finally {
    if (!win.isDestroyed()) win.destroy();
  }
}

/**
 * Convert a file using LibreOffice headless. Returns the output path.
 * `toFormat` follows LibreOffice's --convert-to syntax, e.g. "pdf", "docx",
 * "xlsx", "pptx", or with an explicit filter: "docx:MS Word 2007 XML".
 */
export async function convertViaLibreOffice(
  input: string,
  outDir: string,
  toFormat: string
): Promise<string> {
  const soffice = findLibreOffice();
  if (!soffice) {
    throw new Error(
      'LibreOffice not found. Install LibreOffice (https://www.libreoffice.org/) to enable Office ⇄ PDF conversion.'
    );
  }
  await mkdir(outDir, { recursive: true });

  // Isolate the soffice user profile so we don't collide with the user's
  // running LibreOffice instance.
  const userProfile = join(
    tmpdir(),
    `purplepdf-soffice-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`
  );

  const args = [
    `-env:UserInstallation=file://${userProfile}`,
    '--headless',
    '--norestore',
    '--nologo',
    '--nofirststartwizard',
    '--convert-to',
    toFormat,
    '--outdir',
    outDir,
    input
  ];

  const res = await run(soffice, args, 180_000);
  if (res.code !== 0) {
    throw new Error(`LibreOffice failed (${res.code}): ${res.stderr || res.stdout}`);
  }

  // LibreOffice writes <basename>.<targetExt> into outDir.
  const targetExt = toFormat.split(':')[0];
  const out = join(outDir, `${basename(input, extname(input))}.${targetExt}`);
  try {
    await stat(out);
  } catch {
    throw new Error(
      `LibreOffice ran but expected output was not found: ${out}\n${res.stdout}\n${res.stderr}`
    );
  }
  return out;
}

/** Write an ArrayBuffer/Uint8Array to a temp file and return its path. */
export async function writeTempPdf(bytes: ArrayBuffer | Uint8Array): Promise<string> {
  const buf = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  const p = join(
    tmpdir(),
    `purplepdf-${Date.now()}-${Math.random().toString(36).slice(2, 8)}.pdf`
  );
  await writeFile(p, buf);
  return p;
}
