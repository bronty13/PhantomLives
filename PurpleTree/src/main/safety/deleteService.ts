/**
 * @file deleteService.ts — trash (default) and guarded permanent deletion.
 *
 * Every path passes through the protected-path guard *after* realpath
 * resolution (so symlink/.. traversal can't dodge it). Trash is the default
 * and recoverable; permanent deletion is a separate, explicitly-requested
 * path that also requires the guard to pass.
 */
import { app, shell } from 'electron';
import { rm, realpath } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';
import type { DeleteResult } from '../../shared/types';
import { isProtected, type GuardOpts } from './protectedPaths';

/** Guard options bound to this machine + this app's own directories. */
export function guardOpts(backupDir?: string): GuardOpts {
  return {
    platform: process.platform,
    homeDir: homedir(),
    appSupportDir: app.getPath('userData'),
    backupDir
  };
}

/** Resolve symlinks/.. before guarding; fall back to the raw path if missing. */
async function resolveForGuard(p: string): Promise<string> {
  try {
    return await realpath(p);
  } catch {
    return p;
  }
}

async function remove(
  paths: string[],
  remover: (p: string) => Promise<void>,
  backupDir?: string
): Promise<DeleteResult> {
  const opts = guardOpts(backupDir);
  const removed: string[] = [];
  const failed: Array<{ path: string; reason: string }> = [];
  for (const p of paths) {
    const resolved = await resolveForGuard(p);
    const guard = isProtected(resolved, opts);
    if (guard.blocked) {
      failed.push({ path: p, reason: guard.reason ?? 'Protected path' });
      continue;
    }
    try {
      await remover(p);
      removed.push(p);
    } catch (err) {
      failed.push({ path: p, reason: err instanceof Error ? err.message : String(err) });
    }
  }
  return { ok: failed.length === 0, removed, failed };
}

/** Move paths to the OS Trash / Recycle Bin (recoverable). */
export function trashPaths(paths: string[], backupDir?: string): Promise<DeleteResult> {
  return remove(paths, (p) => shell.trashItem(p), backupDir);
}

/** Permanently delete paths (irrecoverable). Guarded identically to trash. */
export function permanentDelete(paths: string[], backupDir?: string): Promise<DeleteResult> {
  return remove(paths, (p) => rm(p, { recursive: true, force: true }), backupDir);
}

/** The app's default backup directory (~/Downloads/Purple Tree backup/). */
export function defaultBackupDir(): string {
  return join(homedir(), 'Downloads', `${app.getName()} backup`);
}
