// Virtual "Print to Purple PDF" printer.
//
// macOS implementation uses the system's PDF Workflow / PDF Services mechanism:
//   ~/Library/PDF Services/<name>
// is shown as an entry in any application's Print dialog under the "PDF"
// dropdown. When invoked, the system spools the document to a temporary PDF
// and runs the script with these arguments (per Apple's PDF Workflow contract):
//   $1 = job title          ($2 = options, $3 = total pages — unused here)
//   $4 = path to temporary PDF file
//
// We copy the spooled PDF to a persistent capture directory under the user's
// Documents folder, then open it with Purple PDF (which will appear as a new
// tab via the existing `open-file` IPC path).
//
// Windows: a true virtual printer requires a kernel-mode driver / port
// monitor, which is well outside the scope of this iteration. We document that
// and no-op gracefully.

import { app } from 'electron';
import { access, chmod, mkdir, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { homedir } from 'node:os';

const SERVICE_NAME = 'Print to Purple PDF';

export function pdfServicePath(): string {
  return join(homedir(), 'Library', 'PDF Services', SERVICE_NAME);
}

export function captureDir(): string {
  return join(app.getPath('documents'), 'Purple PDF', 'Captures');
}

/**
 * Shell script body installed at ~/Library/PDF Services/Print to Purple PDF.
 * Receives a spooled PDF from the system print dialog and routes it to
 * Purple PDF.
 *
 * Notes:
 * - The temp PDF is deleted by the system once we exit, so we copy first.
 * - The script does not assume Purple PDF is at any particular path; it relies
 *   on macOS LaunchServices to find the registered "Purple PDF" application
 *   by name (works for both /Applications and ~/Applications installs).
 */
function pdfServiceScript(): string {
  // Built line-by-line to avoid TS template-literal escaping for $ signs.
  return [
    '#!/bin/bash',
    '# Purple PDF — macOS PDF Service',
    '# Installed automatically by Purple PDF. Re-run "Install Print to Purple PDF…"',
    '# from the Purple PDF File menu to refresh.',
    'set -u',
    '',
    'title="${1:-Document}"',
    'src="${4:-}"',
    '',
    'if [ -z "$src" ] || [ ! -f "$src" ]; then',
    '  exit 1',
    'fi',
    '',
    '# Sanitize the job title into a safe filename.',
    "safe=$(printf '%s' \"$title\" | tr -c 'A-Za-z0-9._- ' '_')",
    'ts=$(date +%Y%m%d-%H%M%S)',
    'dest_dir="$HOME/Documents/Purple PDF/Captures"',
    'mkdir -p "$dest_dir"',
    'dest="$dest_dir/${safe}-${ts}.pdf"',
    '',
    'cp "$src" "$dest"',
    '',
    '# Hand off to Purple PDF (LaunchServices finds the app by display name).',
    'open -a "Purple PDF" "$dest"',
    ''
  ].join('\n');
}

export interface InstallResult {
  ok: boolean;
  path: string;
  alreadyInstalled: boolean;
  reason?: string;
}

/**
 * Install (or refresh) the macOS PDF Service. Idempotent — safe to call on
 * every app launch. Returns {ok:false} with a reason on non-macOS platforms or
 * if the write fails (e.g. sandbox restrictions, missing home dir).
 */
export async function installPdfService(force = false): Promise<InstallResult> {
  if (process.platform !== 'darwin') {
    return {
      ok: false,
      path: '',
      alreadyInstalled: false,
      reason: 'PDF Service is macOS-only. Windows virtual printer is not yet implemented.'
    };
  }

  const dest = pdfServicePath();
  let alreadyInstalled = false;
  try {
    await access(dest);
    alreadyInstalled = true;
  } catch {
    /* not installed */
  }

  if (alreadyInstalled && !force) {
    return { ok: true, path: dest, alreadyInstalled: true };
  }

  try {
    await mkdir(dirname(dest), { recursive: true });
    await mkdir(captureDir(), { recursive: true });
    await writeFile(dest, pdfServiceScript(), { encoding: 'utf8' });
    await chmod(dest, 0o755);
    return { ok: true, path: dest, alreadyInstalled };
  } catch (err) {
    return {
      ok: false,
      path: dest,
      alreadyInstalled,
      reason: err instanceof Error ? err.message : String(err)
    };
  }
}

/** Check whether the PDF Service is installed (without writing anything). */
export async function isPdfServiceInstalled(): Promise<boolean> {
  if (process.platform !== 'darwin') return false;
  try {
    await access(pdfServicePath());
    return true;
  } catch {
    return false;
  }
}
