import { describe, expect, it } from 'vitest';
import { hiddenNodeIds } from './visibility';
import type { MindGraph } from './graph';

function g(nodes: string[], edges: [string, string][]): MindGraph {
  return {
    nodes: nodes.map((id) => ({ id, label: id, x: 0, y: 0 })),
    edges: edges.map(([source, target], i) => ({ id: `e${i}`, source, target })),
  };
}

const graph = g(['r', 'a', 'a1', 'a2', 'b'], [
  ['r', 'a'],
  ['a', 'a1'],
  ['a', 'a2'],
  ['r', 'b'],
]);

describe('hiddenNodeIds', () => {
  it('returns nothing when nothing is collapsed', () => {
    expect(hiddenNodeIds(graph, new Set()).size).toBe(0);
  });

  it('hides the whole subtree of a collapsed node (but not the node itself)', () => {
    const hidden = hiddenNodeIds(graph, new Set(['a']));
    expect(hidden.has('a')).toBe(false);
    expect(hidden.has('a1')).toBe(true);
    expect(hidden.has('a2')).toBe(true);
    expect(hidden.has('b')).toBe(false);
  });

  it('hides nested descendants when an ancestor is collapsed', () => {
    const deep = g(['r', 'a', 'a1', 'a1x'], [
      ['r', 'a'],
      ['a', 'a1'],
      ['a1', 'a1x'],
    ]);
    const hidden = hiddenNodeIds(deep, new Set(['a']));
    expect(hidden.has('a1')).toBe(true);
    expect(hidden.has('a1x')).toBe(true);
  });
});
