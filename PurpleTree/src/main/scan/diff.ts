/**
 * @file diff.ts — compare two scanned trees by path (files and folders).
 *
 * Pure: takes two `allSizes()` maps (path → {size, isDir}) and returns the
 * biggest changes between them. A path that grew, shrank, appeared, or vanished
 * shows up; unchanged paths are dropped. Sorted by absolute delta so the most
 * significant changes lead. Both files and folders are included so the result
 * reveals which *files* changed, not just folder rollups.
 */
import type { DiffEntry } from '../../shared/types';

type SizeMap = Map<string, { size: number; isDir: boolean }>;

export function diffSizes(older: SizeMap, newer: SizeMap, limit = 1000): DiffEntry[] {
  const paths = new Set<string>([...older.keys(), ...newer.keys()]);
  const entries: DiffEntry[] = [];
  for (const path of paths) {
    const a = older.get(path);
    const b = newer.get(path);
    const sizeA = a?.size ?? 0;
    const sizeB = b?.size ?? 0;
    const delta = sizeB - sizeA;
    if (delta === 0) continue;
    const status: DiffEntry['status'] = !a ? 'added' : !b ? 'removed' : delta > 0 ? 'grew' : 'shrank';
    entries.push({ path, isDir: (b ?? a)!.isDir, sizeA, sizeB, delta, status });
  }
  entries.sort((x, y) => Math.abs(y.delta) - Math.abs(x.delta));
  return entries.slice(0, limit);
}
