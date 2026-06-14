import { describe, expect, it } from 'vitest';
import {
  DEFAULT_PRICING,
  computeDefaultPriceCents,
  formatPriceCents,
} from './pricing';

const mins = (m: number) => m * 60;

describe('computeDefaultPriceCents (default settings)', () => {
  it('tracks the typical-price table at the documented lengths', () => {
    expect(computeDefaultPriceCents(mins(4), DEFAULT_PRICING)).toBe(899); // $8.99
    expect(computeDefaultPriceCents(mins(6), DEFAULT_PRICING)).toBe(1099); // $10.99
    expect(computeDefaultPriceCents(mins(8), DEFAULT_PRICING)).toBe(1299); // $12.99
    expect(computeDefaultPriceCents(mins(12), DEFAULT_PRICING)).toBe(1699); // $16.99
  });

  it('always snaps to a whole dollar minus a penny ($X.99)', () => {
    for (let m = 0; m <= 30; m += 0.5) {
      const cents = computeDefaultPriceCents(mins(m), DEFAULT_PRICING);
      expect(cents % 100).toBe(99);
    }
  });

  it('clamps to the floor for short or empty bundles', () => {
    expect(computeDefaultPriceCents(mins(1), DEFAULT_PRICING)).toBe(799); // floor $8 → $7.99
    expect(computeDefaultPriceCents(0, DEFAULT_PRICING)).toBe(799);
    expect(computeDefaultPriceCents(-50, DEFAULT_PRICING)).toBe(799); // negative is treated as 0
  });

  it('respects custom base / per-minute / floor settings', () => {
    const codified = { // the user's original Python: $7.71 + $0.61/min, floor $8
      contentPriceBaseCents: 771,
      contentPricePerMinuteCents: 61,
      contentPriceFloorCents: 800,
    };
    // 6 min: 771 + 61*6 = 1137 → round(11.37) = 11 → $10.99
    expect(computeDefaultPriceCents(mins(6), codified)).toBe(1099);
    // 2 min: 771 + 122 = 893 → round(8.93) = 9 → $8.99
    expect(computeDefaultPriceCents(mins(2), codified)).toBe(899);
  });
});

describe('formatPriceCents', () => {
  it('renders Free / dash / dollars', () => {
    expect(formatPriceCents(0)).toBe('Free');
    expect(formatPriceCents(null)).toBe('—');
    expect(formatPriceCents(899)).toBe('$8.99');
    expect(formatPriceCents(1699)).toBe('$16.99');
    expect(formatPriceCents(500)).toBe('$5.00');
  });
});
