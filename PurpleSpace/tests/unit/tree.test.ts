import { describe, it, expect } from 'vitest';
import { buildTree, breadcrumb, orderForIndex, isSelfOrDescendant, type PageMeta } from '../../src/shared/tree';

function page(p: Partial<PageMeta> & { _id: string }): PageMeta {
  return {
    title: p._id,
    type: 'doc',
    parentId: null,
    order: 0,
    icon: null,
    favorite: false,
    updatedAt: 0,
    ...p
  };
}

describe('buildTree', () => {
  it('nests children under parents, sorted by order', () => {
    const pages = [
      page({ _id: 'b', order: 2048 }),
      page({ _id: 'a', order: 1024 }),
      page({ _id: 'a1', parentId: 'a', order: 1024 }),
      page({ _id: 'a2', parentId: 'a', order: 512 })
    ];
    const tree = buildTree(pages);
    expect(tree.map((n) => n._id)).toEqual(['a', 'b']);
    expect(tree[0].children.map((n) => n._id)).toEqual(['a2', 'a1']);
  });

  it('excludes database rows from the tree but keeps the database itself', () => {
    const pages = [
      page({ _id: 'db', type: 'database', order: 1 }),
      page({ _id: 'row1', parentId: 'db', order: 1 })
    ];
    const tree = buildTree(pages);
    expect(tree).toHaveLength(1);
    expect(tree[0]._id).toBe('db');
    expect(tree[0].children).toHaveLength(0);
  });

  it('treats children of missing parents as roots (defensive)', () => {
    const tree = buildTree([page({ _id: 'orphan', parentId: 'gone', order: 1 })]);
    expect(tree.map((n) => n._id)).toEqual(['orphan']);
  });
});

describe('breadcrumb', () => {
  it('returns the root→page chain', () => {
    const pages = [
      page({ _id: 'a' }),
      page({ _id: 'b', parentId: 'a' }),
      page({ _id: 'c', parentId: 'b' })
    ];
    expect(breadcrumb(pages, 'c').map((p) => p._id)).toEqual(['a', 'b', 'c']);
  });

  it('survives a parent cycle without hanging', () => {
    const pages = [page({ _id: 'a', parentId: 'b' }), page({ _id: 'b', parentId: 'a' })];
    const chain = breadcrumb(pages, 'a');
    expect(chain.length).toBeLessThanOrEqual(2);
  });
});

describe('orderForIndex', () => {
  const sib = [{ order: 1000 }, { order: 2000 }, { order: 3000 }];
  it('places before the first', () => {
    expect(orderForIndex(sib, 0)).toBeLessThan(1000);
  });
  it('places between neighbours', () => {
    expect(orderForIndex(sib, 1)).toBe(1500);
  });
  it('places after the last', () => {
    expect(orderForIndex(sib, 3)).toBeGreaterThan(3000);
  });
  it('handles an empty sibling list', () => {
    expect(orderForIndex([], 0)).toBeGreaterThan(0);
  });
});

describe('isSelfOrDescendant', () => {
  const pages = [
    page({ _id: 'a' }),
    page({ _id: 'b', parentId: 'a' }),
    page({ _id: 'c', parentId: 'b' }),
    page({ _id: 'x' })
  ];
  it('detects self', () => {
    expect(isSelfOrDescendant(pages, 'a', 'a')).toBe(true);
  });
  it('detects deep descendants', () => {
    expect(isSelfOrDescendant(pages, 'a', 'c')).toBe(true);
  });
  it('rejects unrelated pages', () => {
    expect(isSelfOrDescendant(pages, 'a', 'x')).toBe(false);
  });
});
