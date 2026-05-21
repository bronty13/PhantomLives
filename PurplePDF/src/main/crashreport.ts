// Opt-in local crash reporting.
//
// We don't ship a remote endpoint — the Electron crash reporter is configured
// to write minidumps and a JSON sidecar to `<userData>/CrashReports/` so the
// user can attach them when filing a GitHub issue.
//
// Enabled by default but trivially disable-able via the `PURPLE_PDF_DISABLE_CRASH_REPORTS=1`
// environment variable, or by removing the directory.

import { app, crashReporter } from 'electron';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';

let started = false;

export function startCrashReporter(): void {
  if (started) return;
  if (process.env['PURPLE_PDF_DISABLE_CRASH_REPORTS'] === '1') return;
  try {
    const dir = join(app.getPath('userData'), 'CrashReports');
    mkdirSync(dir, { recursive: true });
    app.setPath('crashDumps', dir);
    crashReporter.start({
      productName: 'Purple PDF',
      companyName: 'Purple PDF',
      submitURL: 'https://localhost/invalid', // never actually used
      uploadToServer: false,
      ignoreSystemCrashHandler: false,
      compress: true,
      extra: {
        version: app.getVersion(),
        platform: process.platform,
        arch: process.arch
      }
    });
    started = true;
  } catch {
    // Best-effort; never block app launch.
  }
}

export function crashReportsDir(): string {
  return join(app.getPath('userData'), 'CrashReports');
}
