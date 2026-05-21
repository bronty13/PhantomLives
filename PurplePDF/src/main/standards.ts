import { spawn } from 'node:child_process';
import { promises as fs } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomBytes } from 'node:crypto';

/** Returns the Ghostscript version string if `gs` is on PATH, otherwise null. */
export async function detectGhostscript(): Promise<string | null> {
  return new Promise((resolve) => {
    const p = spawn('gs', ['--version']);
    let out = '';
    p.stdout.on('data', (b) => {
      out += b.toString();
    });
    p.on('error', () => resolve(null));
    p.on('close', (code) => resolve(code === 0 ? out.trim().split('\n')[0] : null));
  });
}

export type StandardTarget = 'PDF/A-1b' | 'PDF/A-2b' | 'PDF/A-3b' | 'PDF/X-3';

export interface ConvertArgs {
  bytes: Uint8Array;
  target: StandardTarget;
  outputPath: string;
}

/**
 * Convert a PDF to PDF/A or PDF/X via the Ghostscript pdfwrite device.
 * Throws if `gs` is missing or conversion fails.
 */
export async function convertToStandard(args: ConvertArgs): Promise<void> {
  const version = await detectGhostscript();
  if (!version) {
    throw new Error(
      'Ghostscript (gs) is not installed. Install with `brew install ghostscript` (macOS) or from https://www.ghostscript.com/ (Windows), then try again.'
    );
  }

  const sessionId = randomBytes(8).toString('hex');
  const tmpInput = join(tmpdir(), `purplepdf-std-in-${sessionId}.pdf`);
  try {
    await fs.writeFile(tmpInput, args.bytes);

    const gsArgs: string[] = [
      '-dPDFSETTINGS=/prepress',
      '-dNOPAUSE',
      '-dQUIET',
      '-dBATCH',
      '-sDEVICE=pdfwrite'
    ];

    if (args.target.startsWith('PDF/A')) {
      // Ghostscript PDFA flag: 1 = PDF/A-1b, 2 = PDF/A-2b, 3 = PDF/A-3b
      const level = Number(args.target.charAt(args.target.length - 2));
      gsArgs.push(
        `-dPDFA=${Number.isFinite(level) ? level : 2}`,
        '-dPDFACompatibilityPolicy=1',
        '-sColorConversionStrategy=RGB',
        '-sProcessColorModel=DeviceRGB'
      );
    } else if (args.target === 'PDF/X-3') {
      gsArgs.push(
        '-dPDFX',
        '-sColorConversionStrategy=CMYK',
        '-sProcessColorModel=DeviceCMYK'
      );
    }

    gsArgs.push(`-sOutputFile=${args.outputPath}`, tmpInput);

    await new Promise<void>((resolve, reject) => {
      const p = spawn('gs', gsArgs);
      let stderr = '';
      p.stderr.on('data', (b) => {
        stderr += b.toString();
      });
      p.on('error', (e) => reject(e));
      p.on('close', (code) => {
        if (code === 0) resolve();
        else reject(new Error(`gs exited with code ${code}: ${stderr || '(no output)'}`));
      });
    });
  } finally {
    await fs.rm(tmpInput, { force: true }).catch(() => undefined);
  }
}

export type OptimizeQuality = 'screen' | 'ebook' | 'printer' | 'prepress';

/**
 * Compress / optimize a PDF using Ghostscript's pdfwrite device with a
 * preset that downsamples images and recompresses streams. Returns the
 * before/after sizes in bytes.
 */
export async function optimizePdf(args: {
  bytes: Uint8Array;
  outputPath: string;
  quality?: OptimizeQuality;
}): Promise<{ before: number; after: number; outputPath: string }> {
  const version = await detectGhostscript();
  if (!version) {
    throw new Error(
      'Ghostscript (gs) is not installed. Install with `brew install ghostscript` (macOS) or from https://www.ghostscript.com/ (Windows), then try again.'
    );
  }
  const quality = args.quality ?? 'ebook';
  const sessionId = randomBytes(8).toString('hex');
  const tmpInput = join(tmpdir(), `purplepdf-opt-in-${sessionId}.pdf`);
  try {
    await fs.writeFile(tmpInput, args.bytes);
    const gsArgs: string[] = [
      `-dPDFSETTINGS=/${quality}`,
      '-dNOPAUSE',
      '-dQUIET',
      '-dBATCH',
      '-dCompatibilityLevel=1.5',
      '-sDEVICE=pdfwrite',
      `-sOutputFile=${args.outputPath}`,
      tmpInput
    ];
    await new Promise<void>((resolve, reject) => {
      const p = spawn('gs', gsArgs);
      let stderr = '';
      p.stderr.on('data', (b) => {
        stderr += b.toString();
      });
      p.on('error', (e) => reject(e));
      p.on('close', (code) => {
        if (code === 0) resolve();
        else reject(new Error(`gs exited with code ${code}: ${stderr || '(no output)'}`));
      });
    });
    const stat = await fs.stat(args.outputPath);
    return { before: args.bytes.byteLength, after: stat.size, outputPath: args.outputPath };
  } finally {
    await fs.rm(tmpInput, { force: true }).catch(() => undefined);
  }
}
