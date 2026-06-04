import { describe, expect, it } from 'vitest';
import { layoutBilateral } from './autoLayout';
import type { MindGraph } from './graph';

function g(nodes: string[], edges: [string, string][]): MindGraph {
  return {
    nodes: nodes.map((id) => ({ id, label: id, x: 0, y: 0 })),
    edges: edges.map(([source, target], i) => ({ id: `e${i}`, source, target })),
  };
}

describe('layoutBilateral', () => {
  it('places the root at x=0 and splits branches to both sides', () => {
    const graph = g(['r', 'a', 'b', 'c', 'd'], [
      ['r', 'a'],
      ['r', 'b'],
      ['r', 'c'],
      ['r', 'd'],
    ]);
    const pos = new Map(layoutBilateral(graph).map((p) => [p.id, p]));
    expect(pos.get('r')!.x).toBe(0);
    const xs = ['a', 'b', 'c', 'd'].map((id) => pos.get(id)!.x);
    expect(xs.some((x) => x > 0)).toBe(true);
    expect(xs.some((x) => x < 0)).toBe(true);
  });

  it('grows a left-side branch leftward (deeper = more negative x)', () => {
    // Two single-child branches: one lands right, one left; the left one's
    // grandchild should be further left than its child.
    const graph = g(['r', 'a', 'a1', 'b', 'b1'], [
      ['r', 'a'],
      ['a', 'a1'],
      ['r', 'b'],
      ['b', 'b1'],
    ]);
    const pos = new Map(layoutBilateral(graph).map((p) => [p.id, p]));
    // 'a' goes right (first branch), 'b' goes left.
    expect(pos.get('a')!.x).toBeGreaterThan(0);
    expect(pos.get('a1')!.x).toBeGreaterThan(pos.get('a')!.x);
    expect(pos.get('b')!.x).toBeLessThan(0);
    expect(pos.get('b1')!.x).toBeLessThan(pos.get('b')!.x);
  });

  it('roughly balances leaf-heavy branches across sides', () => {
    // One heavy branch (3 leaves) and three light ones (1 leaf each):
    // the heavy branch should end up alone on one side.
    const graph = g(['r', 'h', 'h1', 'h2', 'h3', 'x', 'y', 'z'], [
      ['r', 'h'],
      ['h', 'h1'],
      ['h', 'h2'],
      ['h', 'h3'],
      ['r', 'x'],
      ['r', 'y'],
      ['r', 'z'],
    ]);
    const pos = new Map(layoutBilateral(graph).map((p) => [p.id, p]));
    const right = ['h', 'x', 'y', 'z'].filter((id) => pos.get(id)!.x > 0);
    const left = ['h', 'x', 'y', 'z'].filter((id) => pos.get(id)!.x < 0);
    // Both sides used.
    expect(right.length).toBeGreaterThan(0);
    expect(left.length).toBeGreaterThan(0);
  });

  it('returns a position for every node and mutates nothing', () => {
    const graph = g(['r', 'a'], [['r', 'a']]);
    const before = JSON.stringify(graph);
    const out = layoutBilateral(graph);
    expect(out).toHaveLength(2);
    expect(JSON.stringify(graph)).toBe(before);
  });
});
