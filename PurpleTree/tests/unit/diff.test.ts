import { describe, it, expect } from 'vitest';
import { diffDirSizes } from '../../src/main/scan/diff';

describe('diffDirSizes', () => {
  const older = new Map([
    ['/r', 100],
    ['/r/keep', 50],
    ['/r/grow', 20],
    ['/r/shrink', 30],
    ['/r/gone', 10]
  ]);
  const newer = new Map([
    ['/r', 130],
    ['/r/keep', 50], // unchanged -> dropped
    ['/r/grow', 60], // +40
    ['/r/shrink', 5], // -25
    ['/r/new', 15] // added
  ]);

  it('classifies grew / shrank / added / removed and drops unchanged', () => {
    const d = diffDirSizes(older, newer);
    const byPath = Object.fromEntries(d.map((e) => [e.path, e]));
    expect(byPath['/r/keep']).toBeUndefined(); // unchanged
    expect(byPath['/r/grow'].status).toBe('grew');
    expect(byPath['/r/grow'].delta).toBe(40);
    expect(byPath['/r/shrink'].status).toBe('shrank');
    expect(byPath['/r/shrink'].delta).toBe(-25);
    expect(byPath['/r/new'].status).toBe('added');
    expect(byPath['/r/new'].sizeA).toBe(0);
    expect(byPath['/r/gone'].status).toBe('removed');
    expect(byPath['/r/gone'].sizeB).toBe(0);
  });

  it('sorts by absolute delta, biggest first', () => {
    const d = diffDirSizes(older, newer);
    const deltas = d.map((e) => Math.abs(e.delta));
    for (let i = 1; i < deltas.length; i++) expect(deltas[i - 1]).toBeGreaterThanOrEqual(deltas[i]);
  });

  it('honors the limit', () => {
    expect(diffDirSizes(older, newer, 2)).toHaveLength(2);
  });
});
