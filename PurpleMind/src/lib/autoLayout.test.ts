import { describe, expect, it } from 'vitest';
import { layoutTree } from './autoLayout';
import type { MindGraph } from './graph';

function g(nodes: string[], edges: [string, string][]): MindGraph {
  return {
    nodes: nodes.map((id) => ({ id, label: id, x: 0, y: 0 })),
    edges: edges.map(([source, target], i) => ({ id: `e${i}`, source, target })),
  };
}

describe('layoutTree', () => {
  it('places the root at depth 0 and children one level right', () => {
    const graph = g(['root', 'a', 'b'], [
      ['root', 'a'],
      ['root', 'b'],
    ]);
    const pos = new Map(layoutTree(graph).map((p) => [p.id, p]));
    expect(pos.get('root')!.x).toBe(0);
    expect(pos.get('a')!.x).toBe(240);
    expect(pos.get('b')!.x).toBe(240);
    // Two children occupy adjacent vertical slots.
    expect(pos.get('a')!.y).not.toBe(pos.get('b')!.y);
  });

  it('centres a parent on its two children', () => {
    const graph = g(['root', 'a', 'b'], [
      ['root', 'a'],
      ['root', 'b'],
    ]);
    const pos = new Map(layoutTree(graph).map((p) => [p.id, p]));
    const mid = (pos.get('a')!.y + pos.get('b')!.y) / 2;
    expect(pos.get('root')!.y).toBeCloseTo(mid);
  });

  it('handles a deeper chain with increasing depth', () => {
    const graph = g(['r', 'c1', 'c2'], [
      ['r', 'c1'],
      ['c1', 'c2'],
    ]);
    const pos = new Map(layoutTree(graph).map((p) => [p.id, p]));
    expect(pos.get('r')!.x).toBe(0);
    expect(pos.get('c1')!.x).toBe(240);
    expect(pos.get('c2')!.x).toBe(480);
  });

  it('lays out disconnected components without overlapping vertically', () => {
    const graph = g(['a', 'b'], []); // two singletons, no edges
    const pos = new Map(layoutTree(graph).map((p) => [p.id, p]));
    expect(pos.get('a')!.y).not.toBe(pos.get('b')!.y);
  });

  it('returns a position for every node and mutates nothing', () => {
    const graph = g(['root', 'a'], [['root', 'a']]);
    const before = JSON.stringify(graph);
    const pos = layoutTree(graph);
    expect(pos).toHaveLength(2);
    expect(JSON.stringify(graph)).toBe(before);
  });
});
