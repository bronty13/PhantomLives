/**
 * End-to-end snapshot-diff test: scan a temp dir, change a file + add a file,
 * scan again, and confirm the diff reveals the FILE-level changes (not just the
 * folder rollup). Uses the built worker for the crawl. Skipped if not built.
 */
import { describe, it, expect } from 'vitest';
import { Worker } from 'node:worker_threads';
import { mkdtempSync, writeFileSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { Tree } from '../../src/main/scan/tree';
import { diffSizes } from '../../src/main/scan/diff';
import type { ScanEvent } from '../../src/shared/protocol';
import { DEFAULT_SCAN_OPTIONS } from '../../src/shared/types';

const WORKER = resolve(__dirname, '../../out/main/scanWorker.js');
const built = existsSync(WORKER);

function scan(root: string): Promise<Tree> {
  const cancelFlag = new SharedArrayBuffer(4);
  const worker = new Worker(WORKER);
  return new Promise<Tree>((res, rej) => {
    worker.on('message', (evt: ScanEvent) => {
      if (evt.type === 'done') {
        const t = new Tree(evt.tree);
        t.setMetric('logical'); // byte-exact so a small change is visible
        void worker.terminate().then(() => res(t));
      } else if (evt.type === 'error') {
        void worker.terminate().then(() => rej(new Error(evt.message)));
      }
    });
    worker.on('error', rej);
    worker.postMessage({
      type: 'start',
      scanId: 's',
      rootPath: root,
      opts: DEFAULT_SCAN_OPTIONS,
      cancelFlag
    });
  });
}

describe.skipIf(!built)('snapshot diff (built worker) reveals file changes', () => {
  it('shows added, removed, and resized files', async () => {
    const base = mkdtempSync(join(tmpdir(), 'pt-diff-'));
    try {
      writeFileSync(join(base, 'a.bin'), Buffer.alloc(1000));
      writeFileSync(join(base, 'old.bin'), Buffer.alloc(2000));
      const before = await scan(base);

      writeFileSync(join(base, 'a.bin'), Buffer.alloc(3000)); // a grew +2000
      rmSync(join(base, 'old.bin')); // removed
      writeFileSync(join(base, 'new.bin'), Buffer.alloc(5000)); // added
      const after = await scan(base);

      const entries = diffSizes(before.allSizes(), after.allSizes());
      const byPath = Object.fromEntries(entries.map((e) => [e.path, e]));

      const a = byPath[join(base, 'a.bin')];
      expect(a.isDir).toBe(false);
      expect(a.status).toBe('grew');
      expect(a.delta).toBe(2000);

      const removed = byPath[join(base, 'old.bin')];
      expect(removed.status).toBe('removed');
      expect(removed.isDir).toBe(false);

      const added = byPath[join(base, 'new.bin')];
      expect(added.status).toBe('added');
      expect(added.sizeB).toBe(5000);

      // The folder rollup is still present too.
      expect(byPath[base].isDir).toBe(true);
      expect(byPath[base].status).toBe('grew'); // +2000 -2000 +5000 = +5000
      expect(byPath[base].delta).toBe(5000);
    } finally {
      rmSync(base, { recursive: true, force: true });
    }
  }, 20_000);
});
