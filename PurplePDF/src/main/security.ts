import { spawn } from 'node:child_process';
import { promises as fs } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomBytes } from 'node:crypto';

export interface QpdfPermissions {
  print: boolean;
  copy: boolean;
  modify: boolean;
  annotate: boolean;
}

export interface EncryptArgs {
  /** Already-flattened PDF bytes to encrypt. */
  bytes: Uint8Array;
  userPassword: string;
  ownerPassword: string;
  permissions: QpdfPermissions;
  /** Output path chosen by user via showSaveDialog. */
  outputPath: string;
}

/** Returns the qpdf version string if qpdf is on PATH, otherwise null. */
export async function detectQpdf(): Promise<string | null> {
  return new Promise((resolve) => {
    const p = spawn('qpdf', ['--version']);
    let out = '';
    p.stdout.on('data', (b) => {
      out += b.toString();
    });
    p.on('error', () => resolve(null));
    p.on('close', (code) => {
      if (code === 0) {
        const m = /qpdf version ([\d.]+)/i.exec(out);
        resolve(m ? m[1] : out.trim().split('\n')[0]);
      } else {
        resolve(null);
      }
    });
  });
}

/**
 * Encrypt with AES-256 using qpdf. Passwords are passed via @password-file
 * syntax (NOT argv) so they don't appear in process listings.
 */
export async function encryptWithQpdf(args: EncryptArgs): Promise<void> {
  const version = await detectQpdf();
  if (!version) {
    throw new Error(
      'qpdf is not installed. Install it with `brew install qpdf` (macOS) or from https://qpdf.sourceforge.io/ (Windows), then try again.'
    );
  }

  const sessionId = randomBytes(8).toString('hex');
  const tmpInput = join(tmpdir(), `purplepdf-protect-in-${sessionId}.pdf`);
  const userPwFile = join(tmpdir(), `purplepdf-protect-u-${sessionId}.txt`);
  const ownerPwFile = join(tmpdir(), `purplepdf-protect-o-${sessionId}.txt`);

  try {
    await fs.writeFile(tmpInput, args.bytes);
    await fs.writeFile(userPwFile, args.userPassword, { mode: 0o600 });
    await fs.writeFile(ownerPwFile, args.ownerPassword, { mode: 0o600 });

    const perms: string[] = [];
    perms.push(`--print=${args.permissions.print ? 'full' : 'none'}`);
    perms.push(`--modify=${args.permissions.modify ? 'all' : 'none'}`);
    perms.push(`--extract=${args.permissions.copy ? 'y' : 'n'}`);
    perms.push(`--annotate=${args.permissions.annotate ? 'y' : 'n'}`);

    const cmdArgs = [
      `--encrypt`,
      `@${userPwFile}`,
      `@${ownerPwFile}`,
      `256`,
      ...perms,
      `--`,
      tmpInput,
      args.outputPath
    ];

    await new Promise<void>((resolve, reject) => {
      const p = spawn('qpdf', cmdArgs);
      let stderr = '';
      p.stderr.on('data', (b) => {
        stderr += b.toString();
      });
      p.on('error', (e) => reject(e));
      p.on('close', (code) => {
        // qpdf exit code 3 is "warnings but ok"
        if (code === 0 || code === 3) resolve();
        else reject(new Error(`qpdf exited with code ${code}: ${stderr || '(no output)'}`));
      });
    });
  } finally {
    // Best-effort cleanup of any password material on disk.
    await Promise.allSettled([
      fs.rm(tmpInput, { force: true }),
      fs.rm(userPwFile, { force: true }),
      fs.rm(ownerPwFile, { force: true })
    ]);
  }
}
