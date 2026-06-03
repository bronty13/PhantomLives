/**
 * @file dupePipeline.ts — the staged duplicate-detection algorithm, pure.
 *
 * Stages, each cheaper-first so we hash as few bytes as possible:
 *   1. group by exact size            (free — sizes come from the scan)
 *   2. group survivors by partial hash (first PARTIAL_BYTES of each file)
 *   3. group survivors by full hash    (whole file, streamed)
 * Singletons are discarded after every stage. Zero-byte files are ignored.
 *
 * The fs + hashing dependencies are injected so this module is unit-testable
 * with synthetic inputs and no real filesystem.
 */
import type { DuplicateScanResult, DuplicateSet, DuplicateProgress } from '../../shared/types';

export const PARTIAL_BYTES = 64 * 1024;

export interface DupDeps {
  hashPartial: (path: string, maxBytes: number) => Promise<string>;
  hashFull: (path: string) => Promise<string>;
  onProgress?: (p: DuplicateProgress) => void;
  shouldCancel?: () => boolean;
}

interface FileEntry {
  path: string;
  size: number;
}

function groupBy<T>(items: T[], key: (t: T) => string): Map<string, T[]> {
  const m = new Map<string, T[]>();
  for (const it of items) {
    const k = key(it);
    const arr = m.get(k);
    if (arr) arr.push(it);
    else m.set(k, [it]);
  }
  return m;
}

/** Keep only buckets with 2+ members. */
function multiBuckets<T>(m: Map<string, T[]>): T[][] {
  const out: T[][] = [];
  for (const v of m.values()) if (v.length > 1) out.push(v);
  return out;
}

export async function findDuplicates(
  files: FileEntry[],
  deps: DupDeps
): Promise<DuplicateScanResult> {
  const cancelled = (): boolean => deps.shouldCancel?.() ?? false;
  let filesHashed = 0;
  let bytesHashed = 0;

  // Stage 1: size buckets (skip zero-byte and unique sizes).
  const sized = files.filter((f) => f.size > 0);
  const sizeBuckets = multiBuckets(groupBy(sized, (f) => String(f.size)));
  deps.onProgress?.({
    phase: 'sizing',
    filesHashed,
    bytesHashed,
    candidateSets: sizeBuckets.length
  });

  // Stage 2: partial-hash buckets.
  const partialSurvivors: FileEntry[][] = [];
  for (const bucket of sizeBuckets) {
    if (cancelled()) return assemble([], filesHashed, bytesHashed);
    const tagged: Array<{ f: FileEntry; key: string }> = [];
    for (const f of bucket) {
      let ph: string;
      try {
        ph = await deps.hashPartial(f.path, PARTIAL_BYTES);
      } catch {
        continue; // unreadable — drop from consideration
      }
      filesHashed++;
      bytesHashed += Math.min(f.size, PARTIAL_BYTES);
      tagged.push({ f, key: `${f.size}:${ph}` });
      if ((filesHashed & 63) === 0) {
        deps.onProgress?.({
          phase: 'partial-hash',
          filesHashed,
          bytesHashed,
          candidateSets: partialSurvivors.length
        });
      }
    }
    for (const grp of multiBuckets(groupBy(tagged, (t) => t.key))) {
      partialSurvivors.push(grp.map((t) => t.f));
    }
  }

  // Stage 3: full-hash confirmation.
  const sets: DuplicateSet[] = [];
  for (const bucket of partialSurvivors) {
    if (cancelled()) return assemble(sets, filesHashed, bytesHashed);
    const tagged: Array<{ f: FileEntry; key: string }> = [];
    for (const f of bucket) {
      let fh: string;
      try {
        fh = await deps.hashFull(f.path);
      } catch {
        continue;
      }
      filesHashed++;
      bytesHashed += f.size;
      tagged.push({ f, key: fh });
      if ((filesHashed & 31) === 0) {
        deps.onProgress?.({
          phase: 'full-hash',
          filesHashed,
          bytesHashed,
          candidateSets: sets.length
        });
      }
    }
    for (const grp of multiBuckets(groupBy(tagged, (t) => t.key))) {
      const size = grp[0].f.size;
      sets.push({
        hash: grp[0].key,
        size,
        paths: grp.map((t) => t.f.path),
        wastedBytes: (grp.length - 1) * size
      });
    }
  }

  return assemble(sets, filesHashed, bytesHashed);
}

function assemble(
  sets: DuplicateSet[],
  filesHashed: number,
  bytesHashed: number
): DuplicateScanResult {
  sets.sort((a, b) => b.wastedBytes - a.wastedBytes);
  return {
    sets,
    filesHashed,
    bytesHashed,
    totalWasted: sets.reduce((s, d) => s + d.wastedBytes, 0)
  };
}
