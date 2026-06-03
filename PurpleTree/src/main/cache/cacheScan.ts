/**
 * @file cacheScan.ts — measure how much a cache preset would reclaim.
 *
 * A scoped, non-destructive recursive size walk over a preset's resolved
 * paths. Used to show "≈ 4.2 GB in 12,041 files" *before* the user is
 * allowed to act. Symlinks are not followed; errors are skipped.
 */
import { opendir, lstat } from 'node:fs/promises';
import { join } from 'node:path';
import type { ResolvedCachePreset } from '../../shared/types';
import { resolvePresetPaths, type ResolvedPresetPaths } from './presets';

/** Recursively sum file bytes + count under a directory (or a single file). */
async function measure(path: string): Promise<{ bytes: number; files: number }> {
  let bytes = 0;
  let files = 0;
  const stack: string[] = [path];
  while (stack.length > 0) {
    const dir = stack.pop()!;
    let st;
    try {
      st = await lstat(dir);
    } catch {
      continue;
    }
    if (st.isSymbolicLink()) continue;
    if (!st.isDirectory()) {
      bytes += st.size;
      files += 1;
      continue;
    }
    let handle;
    try {
      handle = await opendir(dir);
    } catch {
      continue;
    }
    try {
      for await (const entry of handle) {
        const child = join(dir, entry.name);
        if (entry.isDirectory()) {
          stack.push(child);
        } else if (entry.isSymbolicLink()) {
          // skip
        } else {
          try {
            const fst = await lstat(child);
            bytes += fst.size;
            files += 1;
          } catch {
            // skip
          }
        }
      }
    } catch {
      // opendir iteration error — skip the rest of this dir
    }
  }
  return { bytes, files };
}

async function measurePreset(p: ResolvedPresetPaths): Promise<ResolvedCachePreset> {
  let totalBytes = 0;
  let fileCount = 0;
  for (const path of p.paths) {
    const r = await measure(path);
    totalBytes += r.bytes;
    fileCount += r.files;
  }
  return {
    id: p.id,
    label: p.label,
    description: p.description,
    riskLevel: p.riskLevel,
    paths: p.paths,
    totalBytes,
    fileCount
  };
}

/** Resolve + measure every applicable preset for this machine. */
export async function scanCachePresets(): Promise<ResolvedCachePreset[]> {
  const resolved = resolvePresetPaths();
  return Promise.all(resolved.map(measurePreset));
}
