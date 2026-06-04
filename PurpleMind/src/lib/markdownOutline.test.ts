import { describe, expect, it } from 'vitest';
import { fromMarkdown, toMarkdown } from './markdownOutline';
import type { MindGraph } from './graph';

function g(nodes: [string, string][], edges: [string, string][]): MindGraph {
  return {
    nodes: nodes.map(([id, label]) => ({ id, label, x: 0, y: 0 })),
    edges: edges.map(([source, target], i) => ({ id: `e${i}`, source, target })),
  };
}

describe('toMarkdown', () => {
  it('indents children under their parent', () => {
    const graph = g(
      [
        ['r', 'Root'],
        ['a', 'Alpha'],
        ['b', 'Beta'],
      ],
      [
        ['r', 'a'],
        ['r', 'b'],
      ],
    );
    expect(toMarkdown(graph)).toBe('- Root\n  - Alpha\n  - Beta\n');
  });
});

describe('fromMarkdown', () => {
  it('parses indentation into parent/child edges', () => {
    const parsed = fromMarkdown('- Root\n  - Alpha\n  - Beta\n');
    expect(parsed.nodes.map((n) => n.label)).toEqual(['Root', 'Alpha', 'Beta']);
    expect(parsed.edges).toHaveLength(2);
    // Both Alpha and Beta hang off Root (t0).
    expect(parsed.edges.every((e) => e.source === 't0')).toBe(true);
  });

  it('accepts *, +, tabs, and blank lines', () => {
    const parsed = fromMarkdown('* Root\n\n\t+ Child\n');
    expect(parsed.nodes.map((n) => n.label)).toEqual(['Root', 'Child']);
    expect(parsed.edges).toEqual([{ source: 't0', target: 't1' }]);
  });

  it('handles a deeper grandchild chain', () => {
    const parsed = fromMarkdown('- A\n  - B\n    - C\n');
    expect(parsed.edges).toEqual([
      { source: 't0', target: 't1' },
      { source: 't1', target: 't2' },
    ]);
  });
});

describe('round-trip', () => {
  it('toMarkdown → fromMarkdown preserves labels and tree shape', () => {
    const graph = g(
      [
        ['r', 'Project'],
        ['a', 'Design'],
        ['b', 'Build'],
        ['c', 'Tests'],
      ],
      [
        ['r', 'a'],
        ['r', 'b'],
        ['b', 'c'],
      ],
    );
    const md = toMarkdown(graph);
    const parsed = fromMarkdown(md);

    expect(parsed.nodes.map((n) => n.label)).toEqual([
      'Project',
      'Design',
      'Build',
      'Tests',
    ]);
    // 4 nodes → 3 tree edges.
    expect(parsed.edges).toHaveLength(3);
    // 'Tests' (t3) hangs under 'Build' (t2).
    expect(parsed.edges).toContainEqual({ source: 't2', target: 't3' });
  });
});
