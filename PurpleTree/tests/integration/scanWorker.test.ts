/**
 * End-to-end test of the BUILT scan worker (out/main/scanWorker.js): spawn it
 * as a real worker thread, scan a temp directory tree, and verify the
 * transferred SoA tree's aggregates. Skipped if the project hasn't been built.
 */
import { describe, it, expect } from 'vitest';
import { Worker } from 'node:worker_threads';
import {
  mkdtempSync,
  mkdirSync,
  writeFileSync,
  symlinkSync,
  chmodSync,
  rmSync,
  existsSync
} from 'node:fs';
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
      // The locked dir below is restored in `finally`; ensure cleanup works.
      expect(evt.stats.partial).toBe(false);

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

  // Regression: an unreadable directory must NOT abort the whole scan.
  // (Shipped as a fix after a real ETIMEDOUT on a CloudStorage mount killed a
  // full-disk scan. We can't force ETIMEDOUT here, but a chmod-000 dir hits the
  // same "one directory errors out" resilience path and must still finish.)
  it('skips an unreadable directory and still completes', async () => {
    const base = mkdtempSync(join(tmpdir(), 'pt-locked-'));
    const locked = join(base, 'locked');
    try {
      writeFileSync(join(base, 'ok.bin'), Buffer.alloc(700));
      mkdirSync(locked);
      writeFileSync(join(locked, 'hidden.bin'), Buffer.alloc(300));
      chmodSync(locked, 0o000); // owner can't opendir -> EACCES

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
        scanId: 'locked',
        rootPath: base,
        opts: DEFAULT_SCAN_OPTIONS,
        cancelFlag
      });
      const evt = await done;
      await worker.terminate();

      // The scan completes (does NOT error out) despite the locked dir.
      expect(evt.type).toBe('done');
      if (evt.type !== 'done') return;
      expect(evt.stats.partial).toBe(false);
      expect(evt.stats.permDeniedCount).toBeGreaterThanOrEqual(1);
      // Readable file counted; locked content not (can't read it).
      expect(evt.stats.totalBytes).toBe(700);
    } finally {
      try {
        chmodSync(locked, 0o755);
      } catch {
        /* ignore */
      }
      rmSync(base, { recursive: true, force: true });
    }
  }, 20_000);

  // The cooperative cancel flag must be honored. (Pre-set before start so the
  // assertion is deterministic; the async crawl checks it every iteration, and
  // the controller's terminate() fallback covers the hung-syscall case.)
  it('honors the cancel flag and returns a partial result', async () => {
    const base = mkdtempSync(join(tmpdir(), 'pt-cancel-'));
    try {
      for (let i = 0; i < 50; i++) writeFileSync(join(base, `f${i}.bin`), Buffer.alloc(10));

      const cancelFlag = new SharedArrayBuffer(4);
      new Int32Array(cancelFlag)[0] = 1; // request cancel up front
      const worker = new Worker(WORKER);
      const done = new Promise<ScanEvent>((res, rej) => {
        worker.on('message', (evt: ScanEvent) => {
          if (evt.type === 'done' || evt.type === 'error') res(evt);
        });
        worker.on('error', rej);
      });
      worker.postMessage({
        type: 'start',
        scanId: 'cancel',
        rootPath: base,
        opts: DEFAULT_SCAN_OPTIONS,
        cancelFlag
      });
      const evt = await done;
      await worker.terminate();

      expect(evt.type).toBe('done');
      if (evt.type !== 'done') return;
      expect(evt.stats.partial).toBe(true);
      // Cancelled before descending — none of the 50 files were counted.
      expect(evt.stats.totalFiles).toBe(0);
    } finally {
      rmSync(base, { recursive: true, force: true });
    }
  }, 20_000);
});
