import { describe, it, expect } from 'vitest';
import { TreeBuilder, Tree } from '../../src/main/scan/tree';
import { computeSunburst } from '../../src/main/scan/sunburst';
import { FLAG_DIR } from '../../src/shared/types';

function sampleTree(): Tree {
  // /root (dir) with two files: big=75, small=25
  const b = new TreeBuilder('/root', '/');
  b.addNode({ parent: -1, name: '/root', selfSize: 0, mtimeMs: 0, atimeMs: 0, flags: FLAG_DIR });
  b.addNode({ parent: 0, name: 'big', selfSize: 75, mtimeMs: 0, atimeMs: 0, flags: 0 });
  b.addNode({ parent: 0, name: 'small', selfSize: 25, mtimeMs: 0, atimeMs: 0, flags: 0 });
  return new Tree(b.finalize());
}

describe('computeSunburst', () => {
  it('center arc spans the full circle and starts at radius 0', () => {
    const arcs = computeSunburst(sampleTree(), 0);
    const center = arcs.find((a) => a.depth === 0)!;
    expect(center.r0).toBe(0);
    expect(center.a0).toBeCloseTo(0, 5);
    expect(center.a1).toBeCloseTo(2 * Math.PI, 5);
  });

  it('child arc angles are proportional to size and tile the full circle', () => {
    const arcs = computeSunburst(sampleTree(), 0);
    const ring1 = arcs.filter((a) => a.depth === 1).sort((a, b) => a.a0 - b.a0);
    expect(ring1).toHaveLength(2);
    const spans = ring1.map((a) => a.a1 - a.a0);
    // 75/25 split of 2π
    const total = spans[0] + spans[1];
    expect(total).toBeCloseTo(2 * Math.PI, 5);
    const bigSpan = Math.max(...spans);
    expect(bigSpan / total).toBeCloseTo(0.75, 2);
  });

  it('all radii are normalized within [0,1] and rings are nested', () => {
    const arcs = computeSunburst(sampleTree(), 0);
    for (const a of arcs) {
      expect(a.r0).toBeGreaterThanOrEqual(0);
      expect(a.r1).toBeLessThanOrEqual(1.000001);
      expect(a.r1).toBeGreaterThan(a.r0);
    }
    // Ring 1 sits outside the center disc.
    const center = arcs.find((a) => a.depth === 0)!;
    const child = arcs.find((a) => a.depth === 1)!;
    expect(child.r0).toBeGreaterThanOrEqual(center.r1 - 1e-9);
  });

  it('returns empty for an out-of-range focus', () => {
    expect(computeSunburst(sampleTree(), 999)).toEqual([]);
  });
});
