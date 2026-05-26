import { describe, expect, it } from 'vitest';
import { milestoneCrossed, tierForAmount, MILESTONES } from './celebration';

describe('tierForAmount', () => {
  it('maps amounts to the five canonical tiers', () => {
    expect(tierForAmount(0)).toBe(1);
    expect(tierForAmount(5)).toBe(1);
    expect(tierForAmount(9.99)).toBe(1);
    expect(tierForAmount(10)).toBe(2);
    expect(tierForAmount(25)).toBe(2);
    expect(tierForAmount(49.99)).toBe(2);
    expect(tierForAmount(50)).toBe(3);
    expect(tierForAmount(199.99)).toBe(3);
    expect(tierForAmount(200)).toBe(4);
    expect(tierForAmount(999.99)).toBe(4);
    expect(tierForAmount(1000)).toBe(5);
    expect(tierForAmount(5000)).toBe(5);
  });
});

describe('milestoneCrossed', () => {
  it('returns null when goal is zero or negative', () => {
    expect(milestoneCrossed(0, 500, 0)).toBeNull();
    expect(milestoneCrossed(100, 500, -1)).toBeNull();
  });

  it('returns null when nothing crossed', () => {
    // 24% → 24.5% stays below 25%
    expect(milestoneCrossed(240, 245, 1000)).toBeNull();
    // 26% → 49% stays in same bucket
    expect(milestoneCrossed(260, 490, 1000)).toBeNull();
  });

  it('detects each milestone crossing', () => {
    // 24% → 26% crosses 25
    expect(milestoneCrossed(240, 260, 1000)).toBe(25);
    // 49% → 51% crosses 50
    expect(milestoneCrossed(490, 510, 1000)).toBe(50);
    // 74% → 76% crosses 75
    expect(milestoneCrossed(740, 760, 1000)).toBe(75);
    // 99% → 101% crosses 100
    expect(milestoneCrossed(990, 1010, 1000)).toBe(100);
    // 149% → 151% crosses 150
    expect(milestoneCrossed(1490, 1510, 1000)).toBe(150);
    // 199% → 201% crosses 200
    expect(milestoneCrossed(1990, 2010, 1000)).toBe(200);
  });

  it('returns the highest milestone when a single save crosses several', () => {
    // 24% → 76% crosses 25, 50, and 75 — should report 75
    expect(milestoneCrossed(240, 760, 1000)).toBe(75);
    // 0 → goal hit in one shot — should report 100
    expect(milestoneCrossed(0, 1000, 1000)).toBe(100);
    // 0 → way over goal — should report 200
    expect(milestoneCrossed(0, 2500, 1000)).toBe(200);
  });

  it('treats exactly hitting a milestone as a crossing', () => {
    // 24.9% → exactly 25% counts
    expect(milestoneCrossed(249, 250, 1000)).toBe(25);
    // exactly 100% counts
    expect(milestoneCrossed(999, 1000, 1000)).toBe(100);
  });

  it('does not re-fire milestones already passed', () => {
    // 30% → 40% — already past 25%, doesn't reach 50%
    expect(milestoneCrossed(300, 400, 1000)).toBeNull();
    // 60% → 70% — past 50%, doesn't reach 75%
    expect(milestoneCrossed(600, 700, 1000)).toBeNull();
  });
});

describe('MILESTONES', () => {
  it('is exactly [25, 50, 75, 100, 150, 200]', () => {
    expect(MILESTONES).toEqual([25, 50, 75, 100, 150, 200]);
  });
});
