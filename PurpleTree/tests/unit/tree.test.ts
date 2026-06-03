import { describe, it, expect } from 'vitest';
import { TreeBuilder, Tree } from '../../src/main/scan/tree';
import { FLAG_DIR, FLAG_HARDLINK_DUP } from '../../src/shared/types';

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
