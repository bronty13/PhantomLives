import { describe, it, expect } from 'vitest';
import { TreeBuilder, Tree, spliceSubtree } from '../../src/main/scan/tree';
import { FLAG_DIR, FLAG_HARDLINK_DUP, FLAG_PERM_DENIED } from '../../src/shared/types';
import type { SerializedTree } from '../../src/shared/protocol';

/**
 * Build this tree:
 *   /root            (dir)
 *     a.txt          100
 *     sub            (dir)
 *       b.txt        50
 *       c.txt        25
 */
function buildSample(): Tree {
  const b = new TreeBuilder('/root', '/');
  b.addNode({ parent: -1, name: '/root', selfSize: 0, mtimeMs: 0, atimeMs: 0, flags: FLAG_DIR });
  b.addNode({ parent: 0, name: 'a.txt', selfSize: 100, mtimeMs: 10, atimeMs: 10, flags: 0 });
  const sub = b.addNode({ parent: 0, name: 'sub', selfSize: 0, mtimeMs: 0, atimeMs: 0, flags: FLAG_DIR });
  b.addNode({ parent: sub, name: 'b.txt', selfSize: 50, mtimeMs: 20, atimeMs: 20, flags: 0 });
  b.addNode({ parent: sub, name: 'c.txt', selfSize: 25, mtimeMs: 30, atimeMs: 30, flags: 0 });
  return new Tree(b.finalize());
}

describe('Tree aggregation', () => {
  it('rolls up sizes and file counts post-order', () => {
    const t = buildSample();
    const root = t.row(0);
    expect(root.aggSize).toBe(175);
    expect(root.fileCount).toBe(3);
    const sub = t.row(2);
    expect(sub.aggSize).toBe(75);
    expect(sub.fileCount).toBe(2);
  });

  it('reconstructs absolute paths', () => {
    const t = buildSample();
    expect(t.row(0).path).toBe('/root');
    expect(t.row(1).path).toBe('/root/a.txt');
    expect(t.row(4).path).toBe('/root/sub/c.txt');
  });

  it('getChildren sorts by size desc and reports childCount', () => {
    const t = buildSample();
    const kids = t.getChildren(0, { key: 'size', dir: 'desc' }, 100, 0);
    expect(kids.map((k) => k.name)).toEqual(['a.txt', 'sub']);
    const sub = kids.find((k) => k.name === 'sub')!;
    expect(sub.childCount).toBe(2);
  });

  it('getBreadcrumb walks root -> node', () => {
    const t = buildSample();
    expect(t.getBreadcrumb(4).map((r) => r.name)).toEqual(['/root', 'sub', 'c.txt']);
  });

  it('getTopFiles returns files largest-first with own sizes', () => {
    const t = buildSample();
    const top = t.getTopFiles(10);
    expect(top.map((f) => f.name)).toEqual(['a.txt', 'b.txt', 'c.txt']);
    expect(top[0].aggSize).toBe(100);
  });

  it('honors a minBytes filter', () => {
    const t = buildSample();
    const top = t.getTopFiles(10, { minBytes: 40, notAccessedDays: 0, extensions: [] });
    expect(top.map((f) => f.name)).toEqual(['a.txt', 'b.txt']);
  });

  it('excludes hard-link duplicates from folder totals but keeps the node', () => {
    const b = new TreeBuilder('/r', '/');
    b.addNode({ parent: -1, name: '/r', selfSize: 0, mtimeMs: 0, atimeMs: 0, flags: FLAG_DIR });
    b.addNode({ parent: 0, name: 'orig', selfSize: 100, mtimeMs: 0, atimeMs: 0, flags: 0 });
    b.addNode({ parent: 0, name: 'link', selfSize: 100, mtimeMs: 0, atimeMs: 0, flags: FLAG_HARDLINK_DUP });
    const t = new Tree(b.finalize());
    expect(t.row(0).aggSize).toBe(100); // deduped
    expect(t.row(0).fileCount).toBe(2); // both still counted as nodes
    expect(t.getChildren(0, { key: 'name', dir: 'asc' }, 10, 0)).toHaveLength(2);
  });

  it('reports on-disk vs logical size per the active metric', () => {
    const b = new TreeBuilder('/r', '/');
    b.addNode({ parent: -1, name: '/r', selfSize: 0, mtimeMs: 0, atimeMs: 0, flags: FLAG_DIR });
    // A "cloud placeholder": 1 MB logical, but only 4 KB actually on disk.
    b.addNode({
      parent: 0,
      name: 'cloud.bin',
      selfSize: 1_000_000,
      allocSize: 4096,
      mtimeMs: 0,
      atimeMs: 0,
      flags: 0
    });
    const t = new Tree(b.finalize());
    t.setMetric('logical');
    expect(t.row(0).aggSize).toBe(1_000_000);
    t.setMetric('alloc');
    expect(t.row(0).aggSize).toBe(4096);
    // getTopFiles also follows the metric.
    expect(t.getTopFiles(1)[0].aggSize).toBe(4096);
  });

  it('defaults allocSize to logical size when omitted', () => {
    const t = buildSample(); // built without allocSize
    t.setMetric('alloc');
    expect(t.row(0).aggSize).toBe(175); // same as logical
  });

  it('collectFiles returns every file path + size', () => {
    const t = buildSample();
    const files = t.collectFiles().sort((a, b) => a.path.localeCompare(b.path));
    expect(files).toEqual([
      { path: '/root/a.txt', size: 100 },
      { path: '/root/sub/b.txt', size: 50 },
      { path: '/root/sub/c.txt', size: 25 }
    ]);
  });
});

describe('Tree.findByPath', () => {
  it('resolves the root, a folder, and a file; -1 for misses', () => {
    const b = new TreeBuilder('/root', '/');
    b.addNode({ parent: -1, name: '/root', selfSize: 0, mtimeMs: 0, atimeMs: 0, flags: FLAG_DIR });
    b.addNode({ parent: 0, name: 'a.txt', selfSize: 100, mtimeMs: 0, atimeMs: 0, flags: 0 });
    const sub = b.addNode({ parent: 0, name: 'sub', selfSize: 0, mtimeMs: 0, atimeMs: 0, flags: FLAG_DIR });
    b.addNode({ parent: sub, name: 'c.txt', selfSize: 25, mtimeMs: 0, atimeMs: 0, flags: 0 });
    const t = new Tree(b.finalize());
    expect(t.findByPath('/root')).toBe(0);
    expect(t.findByPath('/root/')).toBe(0); // trailing-separator tolerant
    expect(t.findByPath('/root/sub')).toBe(sub);
    expect(t.findByPath('/root/sub/c.txt')).toBe(3);
    expect(t.findByPath('/root/missing')).toBe(-1);
    expect(t.findByPath('/elsewhere')).toBe(-1);
  });
});

describe('spliceSubtree', () => {
  // /root { a.txt 100, sub { b.txt 50, c.txt 25 } }  (root agg 175)
  function buildOld(): SerializedTree {
    const b = new TreeBuilder('/root', '/');
    b.addNode({ parent: -1, name: '/root', selfSize: 0, mtimeMs: 0, atimeMs: 0, flags: FLAG_DIR });
    b.addNode({ parent: 0, name: 'a.txt', selfSize: 100, mtimeMs: 0, atimeMs: 0, flags: 0 });
    const sub = b.addNode({ parent: 0, name: 'sub', selfSize: 0, mtimeMs: 0, atimeMs: 0, flags: FLAG_DIR });
    b.addNode({ parent: sub, name: 'b.txt', selfSize: 50, mtimeMs: 0, atimeMs: 0, flags: 0 });
    b.addNode({ parent: sub, name: 'c.txt', selfSize: 25, mtimeMs: 0, atimeMs: 0, flags: 0 });
    return b.finalize();
  }

  // Fresh scan of /root/sub: c.txt gone, d.txt (200) added.  (its agg 250)
  function buildFreshSub(): SerializedTree {
    const b = new TreeBuilder('/root/sub', '/');
    b.addNode({ parent: -1, name: '/root/sub', selfSize: 0, mtimeMs: 0, atimeMs: 0, flags: FLAG_DIR });
    b.addNode({ parent: 0, name: 'b.txt', selfSize: 50, mtimeMs: 0, atimeMs: 0, flags: 0 });
    b.addNode({ parent: 0, name: 'd.txt', selfSize: 200, mtimeMs: 0, atimeMs: 0, flags: 0 });
    return b.finalize();
  }

  it('replaces a subtree in place and re-rolls ancestor aggregates', () => {
    const merged = new Tree(spliceSubtree(buildOld(), 2, buildFreshSub()));
    // 100 (a.txt) + 250 (refreshed sub) = 350; 3 files total.
    expect(merged.row(0).aggSize).toBe(350);
    expect(merged.row(0).fileCount).toBe(3);

    const subId = merged.findByPath('/root/sub');
    expect(subId).toBeGreaterThan(0);
    const sub = merged.row(subId);
    expect(sub.name).toBe('sub'); // grafted root renamed to its basename
    expect(sub.aggSize).toBe(250);
    expect(sub.childCount).toBe(2);

    const kids = merged
      .getChildren(subId, { key: 'name', dir: 'asc' }, 10, 0)
      .map((k) => k.name);
    expect(kids).toEqual(['b.txt', 'd.txt']); // c.txt removed, d.txt added
    expect(merged.findByPath('/root/sub/c.txt')).toBe(-1);
    expect(merged.findByPath('/root/sub/d.txt')).toBeGreaterThan(0);
    // The sibling outside the refreshed subtree is untouched.
    expect(merged.findByPath('/root/a.txt')).toBeGreaterThan(0);
  });

  it('carries the freshly-scanned flags onto the grafted folder', () => {
    const b = new TreeBuilder('/root/sub', '/');
    b.addNode({
      parent: -1,
      name: '/root/sub',
      selfSize: 0,
      mtimeMs: 0,
      atimeMs: 0,
      flags: FLAG_DIR | FLAG_PERM_DENIED
    });
    const merged = new Tree(spliceSubtree(buildOld(), 2, b.finalize()));
    expect(merged.row(merged.findByPath('/root/sub')).permDenied).toBe(true);
  });

  it('returns the fresh tree unchanged when refreshing the root (id 0)', () => {
    const fresh = buildFreshSub();
    expect(spliceSubtree(buildOld(), 0, fresh)).toBe(fresh);
  });

  it('recountStats re-derives totals after a splice', () => {
    const merged = new Tree(spliceSubtree(buildOld(), 2, buildFreshSub()));
    const rc = merged.recountStats();
    expect(rc.totalBytes).toBe(350);
    expect(rc.totalFiles).toBe(3);
    expect(rc.totalDirs).toBe(2); // /root and /root/sub
  });
});
