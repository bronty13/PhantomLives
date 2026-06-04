import { describe, expect, it } from 'vitest';
import { taperedRibbonPath } from './ribbon';

describe('taperedRibbonPath', () => {
  it('produces a closed path starting with M and ending with Z', () => {
    const d = taperedRibbonPath({ sx: 0, sy: 0, tx: 200, ty: 80, w0: 10, w1: 4, samples: 12 });
    expect(d.startsWith('M ')).toBe(true);
    expect(d.trim().endsWith('Z')).toBe(true);
  });

  it('has 2*(samples+1) vertices (top forward + bottom back)', () => {
    const samples = 10;
    const d = taperedRibbonPath({ sx: 0, sy: 0, tx: 100, ty: 0, w0: 8, w1: 8, samples });
    const points = (d.match(/[ML] /g) || []).length;
    expect(points).toBe(2 * (samples + 1));
  });

  it('is wider at the source than the target when tapering', () => {
    // For a straight horizontal segment the ribbon half-width at the start
    // is w0/2 above the centreline; at the end it is w1/2.
    const d = taperedRibbonPath({ sx: 0, sy: 0, tx: 100, ty: 0, w0: 20, w1: 4, samples: 4 });
    const nums = d.match(/-?\d+(\.\d+)?/g)!.map(Number);
    // First vertex is the top offset at the source: y ≈ +10 (w0/2).
    const firstY = nums[1];
    expect(Math.abs(firstY)).toBeCloseTo(10, 1);
  });
});
