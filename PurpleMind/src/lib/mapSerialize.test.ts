import { describe, expect, it } from 'vitest';
import { parseMap, serializeMap } from './mapSerialize';
import type { MindGraph } from './graph';

const graph: MindGraph = {
  nodes: [
    { id: 'n1', label: 'Root', x: 0, y: 0, color: null },
    { id: 'n2', label: 'Child', x: 240, y: 0, color: '#ff8800' },
  ],
  edges: [{ id: 'e1', source: 'n1', target: 'n2' }],
};

describe('serializeMap / parseMap', () => {
  it('round-trips title, nodes, and edges', () => {
    const json = serializeMap('My Map', graph);
    const parsed = parseMap(json);
    expect(parsed.title).toBe('My Map');
    expect(parsed.nodes).toHaveLength(2);
    expect(parsed.nodes[1]).toMatchObject({ label: 'Child', color: '#ff8800' });
    expect(parsed.edges).toEqual([{ source: 'n1', target: 'n2' }]);
  });

  it('drops edges whose endpoints are missing', () => {
    const broken = JSON.stringify({
      format: 'purplemind.map',
      version: 1,
      title: 'X',
      nodes: [{ id: 'a', label: 'A', x: 0, y: 0, color: null }],
      edges: [
        { source: 'a', target: 'ghost' },
        { source: 'a', target: 'a' },
      ],
    });
    const parsed = parseMap(broken);
    expect(parsed.edges).toEqual([{ source: 'a', target: 'a' }]);
  });

  it('rejects non-PurpleMind documents', () => {
    expect(() => parseMap('{"hello":1}')).toThrow(/not a PurpleMind map/i);
    expect(() => parseMap('not json')).toThrow(/valid JSON/i);
  });

  it('falls back to a default title when absent', () => {
    const json = JSON.stringify({
      format: 'purplemind.map',
      version: 1,
      nodes: [],
      edges: [],
    });
    expect(parseMap(json).title).toBe('Imported map');
  });
});
