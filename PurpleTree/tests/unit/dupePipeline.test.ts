import { describe, it, expect } from 'vitest';
import { findDuplicates } from '../../src/main/dup/dupePipeline';

// Synthetic "filesystem": map path -> content string. The injected hashers
// hash the first N chars (partial) and the whole string (full).
function makeDeps(fs: Record<string, string>) {
  return {
    hashPartial: async (path: string, maxBytes: number): Promise<string> =>
      `p:${fs[path].slice(0, maxBytes)}`,
    hashFull: async (path: string): Promise<string> => `f:${fs[path]}`
  };
}

describe('findDuplicates', () => {
  it('finds byte-identical files of the same size', async () => {
    const fs = {
      '/a': 'hello',
      '/b': 'hello', // dup of /a
      '/c': 'world', // same size as a/b, different content
      '/d': 'xy' // unique size
    };
    const res = await findDuplicates(
      [
        { path: '/a', size: 5 },
        { path: '/b', size: 5 },
        { path: '/c', size: 5 },
        { path: '/d', size: 2 }
      ],
      makeDeps(fs)
    );
    expect(res.sets).toHaveLength(1);
    expect(res.sets[0].paths.sort()).toEqual(['/a', '/b']);
    expect(res.sets[0].size).toBe(5);
    expect(res.sets[0].wastedBytes).toBe(5);
    expect(res.totalWasted).toBe(5);
  });

  it('discards unique sizes without hashing them', async () => {
    let hashed = 0;
    await findDuplicates(
      [
        { path: '/a', size: 1 },
        { path: '/b', size: 2 },
        { path: '/c', size: 3 }
      ],
      {
        hashPartial: async (p) => {
          hashed++;
          return p;
        },
        hashFull: async (p) => p
      }
    );
    expect(hashed).toBe(0); // all unique sizes -> nothing hashed
  });

  it('ignores zero-byte files', async () => {
    const res = await findDuplicates(
      [
        { path: '/a', size: 0 },
        { path: '/b', size: 0 }
      ],
      makeDeps({ '/a': '', '/b': '' })
    );
    expect(res.sets).toHaveLength(0);
  });

  it('separates same-size files that differ only past the partial window', async () => {
    // Two pairs share size; within each pair content matches, across differs.
    const fs = { '/a': 'AAAA', '/b': 'AAAA', '/c': 'BBBB', '/d': 'BBBB' };
    const res = await findDuplicates(
      [
        { path: '/a', size: 4 },
        { path: '/b', size: 4 },
        { path: '/c', size: 4 },
        { path: '/d', size: 4 }
      ],
      makeDeps(fs)
    );
    expect(res.sets).toHaveLength(2);
    expect(res.totalWasted).toBe(8);
  });

  it('reports three-copy sets with correct wasted bytes', async () => {
    const fs = { '/a': 'zzz', '/b': 'zzz', '/c': 'zzz' };
    const res = await findDuplicates(
      [
        { path: '/a', size: 3 },
        { path: '/b', size: 3 },
        { path: '/c', size: 3 }
      ],
      makeDeps(fs)
    );
    expect(res.sets[0].paths).toHaveLength(3);
    expect(res.sets[0].wastedBytes).toBe(6); // (3-1)*3
  });
});
