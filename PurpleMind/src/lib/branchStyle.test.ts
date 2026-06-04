import { describe, expect, it } from 'vitest';
import { BRANCH_PALETTE, ROOT_COLOR, computeBranchStyles } from './branchStyle';
import type { MindGraph } from './graph';

function g(nodes: string[], edges: [string, string][]): MindGraph {
  return {
    nodes: nodes.map((id) => ({ id, label: id, x: 0, y: 0 })),
    edges: edges.map(([source, target], i) => ({ id: `e${i}`, source, target })),
  };
}

describe('computeBranchStyles', () => {
  it('assigns tiers by depth (root / topic / item)', () => {
    const graph = g(['r', 'a', 'a1'], [
      ['r', 'a'],
      ['a', 'a1'],
    ]);
    const s = computeBranchStyles(graph);
    expect(s.get('r')!.tier).toBe('root');
    expect(s.get('a')!.tier).toBe('topic');
    expect(s.get('a1')!.tier).toBe('item');
    expect(s.get('a1')!.depth).toBe(2);
  });

  it('gives each top-level branch its own palette colour, inherited by descendants', () => {
    const graph = g(['r', 'a', 'b', 'a1'], [
      ['r', 'a'],
      ['r', 'b'],
      ['a', 'a1'],
    ]);
    const s = computeBranchStyles(graph);
    expect(s.get('a')!.branchColor).toBe(BRANCH_PALETTE[0]);
    expect(s.get('b')!.branchColor).toBe(BRANCH_PALETTE[1]);
    // Descendant inherits its branch colour.
    expect(s.get('a1')!.branchColor).toBe(BRANCH_PALETTE[0]);
    expect(s.get('a1')!.color).toBe(BRANCH_PALETTE[0]);
  });

  it('root uses ROOT_COLOR', () => {
    const s = computeBranchStyles(g(['r', 'a'], [['r', 'a']]));
    expect(s.get('r')!.color).toBe(ROOT_COLOR);
  });

  it('a manual override on a depth-1 node recolours its whole branch', () => {
    const graph = g(['r', 'a', 'a1'], [
      ['r', 'a'],
      ['a', 'a1'],
    ]);
    const overrides = new Map<string, string | null>([['a', '#123456']]);
    const s = computeBranchStyles(graph, overrides);
    expect(s.get('a')!.color).toBe('#123456');
    expect(s.get('a1')!.branchColor).toBe('#123456');
    expect(s.get('a1')!.color).toBe('#123456');
  });

  it('a manual override on a deep node overrides only that node', () => {
    const graph = g(['r', 'a', 'a1'], [
      ['r', 'a'],
      ['a', 'a1'],
    ]);
    const overrides = new Map<string, string | null>([['a1', '#abcdef']]);
    const s = computeBranchStyles(graph, overrides);
    expect(s.get('a1')!.color).toBe('#abcdef');
    // The branch colour itself is unchanged (still the palette default).
    expect(s.get('a')!.color).toBe(BRANCH_PALETTE[0]);
    expect(s.get('a1')!.branchColor).toBe(BRANCH_PALETTE[0]);
  });

  it('wraps the palette when there are more branches than colours', () => {
    const n = BRANCH_PALETTE.length + 1;
    const ids = ['r', ...Array.from({ length: n }, (_, i) => `b${i}`)];
    const edges = Array.from({ length: n }, (_, i) => ['r', `b${i}`] as [string, string]);
    const s = computeBranchStyles(g(ids, edges));
    expect(s.get(`b${n - 1}`)!.branchColor).toBe(BRANCH_PALETTE[(n - 1) % BRANCH_PALETTE.length]);
  });
});
