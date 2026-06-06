import { beforeEach, describe, expect, it } from 'vitest';
import { getSpinsUsed, recordSpin } from '../src/wheel-player/spins';

describe('wheel spins counter (per-deploy scoped)', () => {
  beforeEach(() => {
    try {
      localStorage.clear();
    } catch {
      /* jsdom always has it */
    }
  });

  // Distinct ids per test: the module-level in-memory fallback is shared across
  // `it` blocks, so reusing an id would leak state (irrelevant in a real browser
  // where localStorage persists and the fallback isn't hit).
  it('starts at zero and counts up within one deploy token', () => {
    expect(getSpinsUsed('count', 'deployA')).toBe(0);
    expect(recordSpin('count', 'deployA')).toBe(1);
    expect(recordSpin('count', 'deployA')).toBe(2);
    expect(getSpinsUsed('count', 'deployA')).toBe(2);
  });

  it('keeps separate counts per deploy token (a re-deploy starts fresh)', () => {
    recordSpin('redeploy', 'deployA');
    recordSpin('redeploy', 'deployA');
    recordSpin('redeploy', 'deployA'); // exhausted a 3-spin wheel under deployA
    expect(getSpinsUsed('redeploy', 'deployA')).toBe(3);
    // Same wheel id, a NEW deploy → fresh allowance.
    expect(getSpinsUsed('redeploy', 'deployB')).toBe(0);
  });

  it('keeps separate counts per wheel id', () => {
    recordSpin('idA', 'deployA');
    expect(getSpinsUsed('idB', 'deployA')).toBe(0);
  });
});
