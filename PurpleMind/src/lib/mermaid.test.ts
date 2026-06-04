import { describe, expect, it } from 'vitest';
import { toMermaidMindmap, toMermaidMarkdownDoc } from './mermaid';
import type { MindGraph } from './graph';

function g(nodes: [string, string][], edges: [string, string][]): MindGraph {
  return {
    nodes: nodes.map(([id, label]) => ({ id, label, x: 0, y: 0 })),
    edges: edges.map(([source, target], i) => ({ id: `e${i}`, source, target })),
  };
}

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

describe('toMermaidMindmap', () => {
  it('starts with the mindmap keyword and a circular root', () => {
    const out = toMermaidMindmap('My Map', graph);
    const lines = out.split('\n');
    expect(lines[0]).toBe('mindmap');
    expect(lines[1]).toBe('  rootNode((Project))');
  });

  it('indents descendants by depth', () => {
    const out = toMermaidMindmap('My Map', graph);
    expect(out).toContain('\n    Design');
    expect(out).toContain('\n    Build');
    expect(out).toContain('\n      Tests'); // grandchild deeper
  });

  it('strips characters that would break mermaid', () => {
    const dirty = g([['r', 'Hello (world) [x]: "q"']], []);
    const out = toMermaidMindmap('t', dirty);
    expect(out).toContain('rootNode((Hello world x q))');
  });

  it('uses a synthetic title root when there are multiple roots', () => {
    const multi = g([['a', 'A'], ['b', 'B']], []); // two singletons → two roots
    const out = toMermaidMindmap('Title', multi);
    expect(out.split('\n')[1]).toBe('  rootNode((Title))');
    expect(out).toContain('\n    A');
    expect(out).toContain('\n    B');
  });
});

describe('toMermaidMarkdownDoc', () => {
  it('wraps the diagram in a heading + mermaid fence', () => {
    const out = toMermaidMarkdownDoc('My Map', graph);
    expect(out).toContain('# My Map');
    expect(out).toContain('```mermaid');
    expect(out).toContain('mindmap');
    expect(out.trimEnd().endsWith('```')).toBe(true);
  });
});
