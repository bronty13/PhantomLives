/**
 * @file diff.ts — compare two scanned trees by folder.
 *
 * Pure: takes two `dirSizes()` maps (path → aggregate size) and returns the
 * biggest folder changes between them. A folder that grew, shrank, appeared,
 * or vanished shows up; folders with no change are dropped. Sorted by absolute
 * delta so the most significant changes lead.
 */
import type { DiffEntry } from '../../shared/types';

export function diffDirSizes(
  older: Map<string, number>,
  newer: Map<string, number>,
  limit = 500
): DiffEntry[] {
  const paths = new Set<string>([...older.keys(), ...newer.keys()]);
  const entries: DiffEntry[] = [];
  for (const path of paths) {
    const sizeA = older.get(path) ?? 0;
    const sizeB = newer.get(path) ?? 0;
    const delta = sizeB - sizeA;
    if (delta === 0) continue;
    const status: DiffEntry['status'] = !older.has(path)
      ? 'added'
      : !newer.has(path)
        ? 'removed'
        : delta > 0
          ? 'grew'
          : 'shrank';
    entries.push({ path, sizeA, sizeB, delta, status });
  }
  entries.sort((x, y) => Math.abs(y.delta) - Math.abs(x.delta));
  return entries.slice(0, limit);
}
