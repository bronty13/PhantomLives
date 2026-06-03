/**
 * @file backupService.ts — launch-time auto-backup of the app's data dir.
 *
 * Ports the PhantomLives BackupService standard (Timeliner reference) to TS:
 *   - zips the entire Application Support dir (prefs + snapshots) on launch
 *   - 5-minute debounce so relaunch storms don't spam the backup folder
 *   - N-day retention trim (0 = keep forever), scoped to our `<App>-` prefix
 *   - never throws on failure — the app must launch even if backup fails
 *   - Run-Now / Test / Restore for the Settings → Backup UI
 *
 * Default location: ~/Downloads/Purple Tree backup/
 * Filename:         Purple Tree-YYYY-MM-DD-HHmmss.zip
 */
import { app } from 'electron';
import { mkdir, readdir, readFile, writeFile, stat, rm, cp } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join, relative } from 'node:path';
import { tmpdir } from 'node:os';
import JSZip from 'jszip';
import type { BackupInfo } from '../../shared/types';
import { getPreferences, setPreferences } from '../prefs';

const PREFIX = () => `${app.getName()}-`;
const DEBOUNCE_MS = 5 * 60 * 1000;

export interface BackupRunResult {
  ok: boolean;
  skipped?: boolean;
  info?: BackupInfo;
  error?: string;
}

function stamp(d = new Date()): string {
  const p = (n: number, w = 2): string => String(n).padStart(w, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}-${p(d.getHours())}${p(
    d.getMinutes()
  )}${p(d.getSeconds())}`;
}

/** Recursively add a directory's files to a JSZip folder. */
async function addDir(zip: JSZip, dir: string, base: string): Promise<void> {
  let entries;
  try {
    entries = await readdir(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const e of entries) {
    const abs = join(dir, e.name);
    if (e.isDirectory()) {
      await addDir(zip, abs, base);
    } else if (e.isFile()) {
      try {
        zip.file(relative(base, abs), await readFile(abs));
      } catch {
        // skip unreadable file
      }
    }
  }
}

/** Run a backup. `force` ignores the debounce (used by "Run Backup Now"). */
export async function runBackup(force = false): Promise<BackupRunResult> {
  try {
    const prefs = getPreferences();
    if (!force) {
      if (!prefs.autoBackupEnabled) return { ok: true, skipped: true };
      if (prefs.lastBackupMs && Date.now() - prefs.lastBackupMs < DEBOUNCE_MS) {
        return { ok: true, skipped: true };
      }
    }

    const dataDir = app.getPath('userData');
    const dest = prefs.backupPath;
    await mkdir(dest, { recursive: true });

    const zip = new JSZip();
    await addDir(zip, dataDir, dataDir);
    const buf = await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' });

    const name = `${PREFIX()}${stamp()}.zip`;
    const outPath = join(dest, name);
    await writeFile(outPath, buf);

    setPreferences({ lastBackupMs: Date.now() });
    await trimRetention();

    const st = await stat(outPath);
    return {
      ok: true,
      info: { name, path: outPath, sizeBytes: st.size, createdMs: st.mtimeMs }
    };
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    // NSLog-equivalent: log, never throw. The app must still launch.
    console.error('[PurpleTree] backup failed:', msg);
    return { ok: false, error: msg };
  }
}

/** Launch-time entry point: debounced auto-backup. */
export async function runOnLaunch(): Promise<void> {
  await runBackup(false);
}

/** List our backup archives, newest first. */
export async function listBackups(): Promise<BackupInfo[]> {
  const { backupPath } = getPreferences();
  if (!existsSync(backupPath)) return [];
  let names: string[];
  try {
    names = await readdir(backupPath);
  } catch {
    return [];
  }
  const ours = names.filter((n) => n.startsWith(PREFIX()) && n.endsWith('.zip'));
  const infos: BackupInfo[] = [];
  for (const n of ours) {
    try {
      const p = join(backupPath, n);
      const st = await stat(p);
      infos.push({ name: n, path: p, sizeBytes: st.size, createdMs: st.mtimeMs });
    } catch {
      // skip
    }
  }
  infos.sort((a, b) => b.createdMs - a.createdMs);
  return infos;
}

/** Delete our archives older than the retention window (0 = keep forever). */
export async function trimRetention(): Promise<void> {
  const { backupRetentionDays } = getPreferences();
  if (!backupRetentionDays || backupRetentionDays <= 0) return;
  const cutoff = Date.now() - backupRetentionDays * 86_400_000;
  for (const info of await listBackups()) {
    if (info.createdMs < cutoff) {
      try {
        await rm(info.path, { force: true });
      } catch {
        // skip
      }
    }
  }
}

export interface BackupTestResult {
  ok: boolean;
  fileCount: number;
  hasPrefs: boolean;
  error?: string;
}

/** Verify an archive non-destructively: it opens, has files, contains prefs. */
export async function testBackup(path: string): Promise<BackupTestResult> {
  try {
    const zip = await JSZip.loadAsync(await readFile(path));
    const files = Object.keys(zip.files).filter((f) => !zip.files[f].dir);
    const hasPrefs = files.some((f) => f.endsWith('purple-tree-prefs.json'));
    return { ok: files.length > 0, fileCount: files.length, hasPrefs };
  } catch (err) {
    return { ok: false, fileCount: 0, hasPrefs: false, error: err instanceof Error ? err.message : String(err) };
  }
}

/** Restore an archive over the live data dir, after a pre-restore safety backup. */
export async function restoreBackup(path: string): Promise<BackupRunResult> {
  try {
    // 1. Safety backup of the current state first.
    const pre = await runBackup(true);
    if (!pre.ok) return { ok: false, error: `Pre-restore backup failed: ${pre.error}` };

    // 2. Extract the archive to a temp dir.
    const zip = await JSZip.loadAsync(await readFile(path));
    const staging = join(tmpdir(), `purpletree-restore-${stamp()}`);
    await mkdir(staging, { recursive: true });
    for (const [name, file] of Object.entries(zip.files)) {
      if (file.dir) continue;
      const out = join(staging, name);
      await mkdir(join(out, '..'), { recursive: true });
      await writeFile(out, await file.async('nodebuffer'));
    }

    // 3. Swap into the live data dir.
    const dataDir = app.getPath('userData');
    await rm(dataDir, { recursive: true, force: true });
    await mkdir(dataDir, { recursive: true });
    await cp(staging, dataDir, { recursive: true });
    await rm(staging, { recursive: true, force: true });

    return { ok: true };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : String(err) };
  }
}
