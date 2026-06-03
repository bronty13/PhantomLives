/**
 * End-to-end test of the BUILT worker's duplicate-finder command: spawn it,
 * hand it real files, and verify it confirms byte-identical duplicates. This
 * exercises the full path the unit tests can't: xxhash-wasm loading inside the
 * packaged worker + chunked file hashing + the staged pipeline wiring.
 */
import { describe, it, expect } from 'vitest';
import { Worker } from 'node:worker_threads';
import { mkdtempSync, writeFileSync, rmSync, existsSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import type { ScanEvent } from '../../src/shared/protocol';

const WORKER = resolve(__dirname, '../../out/main/scanWorker.js');
const built = existsSync(WORKER);

describe.skipIf(!built)('duplicate finder (built worker) integration', () => {
  it('confirms byte-identical duplicates and ignores look-alikes', async () => {
    const base = mkdtempSync(join(tmpdir(), 'pt-dup-'));
    try {
      const A = 'the quick brown fox jumps over the lazy dog\n'.repeat(2000); // ~86 KB
      const B = A.slice(0, -2) + 'X\n'; // same size, differs past the 64 KB window
      writeFileSync(join(base, 'a1.txt'), A);
      writeFileSync(join(base, 'a2.txt'), A); // exact dup of a1
      writeFileSync(join(base, 'a3.txt'), A); // exact dup of a1
      writeFileSync(join(base, 'b1.txt'), B); // same size, NOT a dup
      writeFileSync(join(base, 'uniq.txt'), 'tiny'); // unique size

      const files = ['a1.txt', 'a2.txt', 'a3.txt', 'b1.txt', 'uniq.txt'].map((n) => {
        const path = join(base, n);
        return { path, size: statSync(path).size };
      });

      const cancelFlag = new SharedArrayBuffer(4);
      const worker = new Worker(WORKER);
      const done = new Promise<ScanEvent>((res, rej) => {
        worker.on('message', (evt: ScanEvent) => {
          if (evt.type === 'dup-done' || evt.type === 'error') res(evt);
        });
        worker.on('error', rej);
      });
      worker.postMessage({ type: 'find-duplicates', scanId: 'dup', files, cancelFlag });
      const evt = await done;
      await worker.terminate();

      expect(evt.type).toBe('dup-done');
      if (evt.type !== 'dup-done') return;
      const { sets } = evt.result;
      expect(sets).toHaveLength(1); // only the a1/a2/a3 set
      expect(sets[0].paths.map((p) => p.split('/').pop()).sort()).toEqual([
        'a1.txt',
        'a2.txt',
        'a3.txt'
      ]);
      expect(sets[0].wastedBytes).toBe(sets[0].size * 2); // 3 copies -> 2 wasted
    } finally {
      rmSync(base, { recursive: true, force: true });
    }
  }, 20_000);
});
