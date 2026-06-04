import { describe, it, expect } from 'vitest';
import { diffSizes } from '../../src/main/scan/diff';

type SizeMap = Map<string, { size: number; isDir: boolean }>;
const dir = (size: number) => ({ size, isDir: true });
const file = (size: number) => ({ size, isDir: false });

describe('diffSizes', () => {
  const older: SizeMap = new Map([
    ['/r', dir(100)],
    ['/r/keep', dir(50)],
    ['/r/grow', dir(20)],
    ['/r/shrink.bin', file(30)],
    ['/r/gone.bin', file(10)]
  ]);
  const newer: SizeMap = new Map([
    ['/r', dir(130)],
    ['/r/keep', dir(50)], // unchanged -> dropped
    ['/r/grow', dir(60)], // +40
    ['/r/shrink.bin', file(5)], // -25
    ['/r/new.bin', file(15)] // added
  ]);

  it('classifies grew / shrank / added / removed and drops unchanged', () => {
    const byPath = Object.fromEntries(diffSizes(older, newer).map((e) => [e.path, e]));
    expect(byPath['/r/keep']).toBeUndefined();
    expect(byPath['/r/grow'].status).toBe('grew');
    expect(byPath['/r/grow'].delta).toBe(40);
    expect(byPath['/r/shrink.bin'].status).toBe('shrank');
    expect(byPath['/r/shrink.bin'].delta).toBe(-25);
    expect(byPath['/r/new.bin'].status).toBe('added');
    expect(byPath['/r/gone.bin'].status).toBe('removed');
  });

  it('preserves the file/folder type of each entry', () => {
    const byPath = Object.fromEntries(diffSizes(older, newer).map((e) => [e.path, e]));
    expect(byPath['/r/grow'].isDir).toBe(true); // folder
    expect(byPath['/r/new.bin'].isDir).toBe(false); // file
    expect(byPath['/r/gone.bin'].isDir).toBe(false); // removed file keeps its type
  });

  it('sorts by absolute delta, biggest first', () => {
    const deltas = diffSizes(older, newer).map((e) => Math.abs(e.delta));
    for (let i = 1; i < deltas.length; i++) expect(deltas[i - 1]).toBeGreaterThanOrEqual(deltas[i]);
  });

  it('honors the limit', () => {
    expect(diffSizes(older, newer, 2)).toHaveLength(2);
  });
});
