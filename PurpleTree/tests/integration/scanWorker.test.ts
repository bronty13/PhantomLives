/**
 * End-to-end test of the BUILT scan worker (out/main/scanWorker.js): spawn it
 * as a real worker thread, scan a temp directory tree, and verify the
 * transferred SoA tree's aggregates. Skipped if the project hasn't been built.
 */
import { describe, it, expect } from 'vitest';
import { Worker } from 'node:worker_threads';
import { mkdtempSync, mkdirSync, writeFileSync, symlinkSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { Tree } from '../../src/main/scan/tree';
import type { ScanEvent } from '../../src/shared/protocol';
import { DEFAULT_SCAN_OPTIONS } from '../../src/shared/types';

const WORKER = resolve(__dirname, '../../out/main/scanWorker.js');
const built = existsSync(WORKER);

describe.skipIf(!built)('scanWorker (built) integration', () => {
  it('scans a temp tree and reports correct aggregates', async () => {
    const base = mkdtempSync(join(tmpdir(), 'pt-scan-'));
    try {
      // root/
      //   a.bin           (1000 bytes)
      //   sub/
      //     b.bin         ( 500 bytes)
      //   link -> a.bin   (symlink, not followed)
      //   empty/
      writeFileSync(join(base, 'a.bin'), Buffer.alloc(1000));
      mkdirSync(join(base, 'sub'));
      writeFileSync(join(base, 'sub', 'b.bin'), Buffer.alloc(500));
      mkdirSync(join(base, 'empty'));
      try {
        symlinkSync(join(base, 'a.bin'), join(base, 'link'));
      } catch {
        // symlink may fail on some CI; that's fine
      }

      const cancelFlag = new SharedArrayBuffer(4);
      const worker = new Worker(WORKER);
      const done = new Promise<ScanEvent>((res, rej) => {
        worker.on('message', (evt: ScanEvent) => {
          if (evt.type === 'done' || evt.type === 'error') res(evt);
        });
        worker.on('error', rej);
      });
      worker.postMessage({
        type: 'start',
        scanId: 'test',
        rootPath: base,
        opts: DEFAULT_SCAN_OPTIONS,
        cancelFlag
      });
      const evt = await done;
      await worker.terminate();

      expect(evt.type).toBe('done');
      if (evt.type !== 'done') return;

      const tree = new Tree(evt.tree);
      const root = tree.row(0);
      // 1000 + 500 = 1500 bytes of real files; symlink counted as a link,
      // not followed, and its own (path-length) size is negligible vs 1500.
      expect(root.aggSize).toBeGreaterThanOrEqual(1500);
      expect(evt.stats.totalFiles).toBeGreaterThanOrEqual(2);
      expect(evt.stats.totalBytes).toBe(1500);
      expect(evt.stats.partial).toBe(false);

      const kids = tree.getChildren(0, { key: 'size', dir: 'desc' }, 100, 0);
      const names = kids.map((k) => k.name);
      expect(names).toContain('a.bin');
      expect(names).toContain('sub');
      expect(names).toContain('empty');
    } finally {
      rmSync(base, { recursive: true, force: true });
    }
  }, 20_000);
});
