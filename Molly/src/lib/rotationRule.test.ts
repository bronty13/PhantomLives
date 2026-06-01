import { describe, it, expect } from 'vitest';
import {
  effectiveRotation,
  daysBetween,
  clampRestDays,
  REST_DAYS_DEFAULT,
} from './rotationRule';

describe('daysBetween', () => {
  it('counts whole days b − a', () => {
    expect(daysBetween('2026-06-01', '2026-06-01')).toBe(0);
    expect(daysBetween('2026-06-01', '2026-06-02')).toBe(1);
    expect(daysBetween('2026-06-01', '2026-06-04')).toBe(3);
  });
  it('is timezone-safe across month/year/DST boundaries', () => {
    expect(daysBetween('2026-02-28', '2026-03-01')).toBe(1); // 2026 not leap
    expect(daysBetween('2025-12-31', '2026-01-01')).toBe(1);
    expect(daysBetween('2026-03-07', '2026-03-09')).toBe(2); // spans US DST switch
  });
  it('returns 0 on malformed input', () => {
    expect(daysBetween('nope', '2026-06-01')).toBe(0);
  });
});

describe('clampRestDays', () => {
  it('clamps to 0..30 and rounds', () => {
    expect(clampRestDays(-5)).toBe(0);
    expect(clampRestDays(99)).toBe(30);
    expect(clampRestDays(2.6)).toBe(3);
  });
  it('falls back to the default on non-finite', () => {
    expect(clampRestDays(NaN)).toBe(REST_DAYS_DEFAULT);
  });
});

describe('effectiveRotation — manual mode', () => {
  it('returns the stored flag untouched', () => {
    for (const stored of ['fresh', 'soon', 'wait'] as const) {
      expect(
        effectiveRotation({ mode: 'manual', restDays: 2, stored, lastPostedAt: '2026-06-01', today: '2026-06-01' }),
      ).toBe(stored);
    }
  });
});

describe('effectiveRotation — auto mode', () => {
  const auto = (lastPostedAt: string | null, today: string, restDays = 2) =>
    effectiveRotation({ mode: 'auto', restDays, stored: 'wait', lastPostedAt, today });

  it('never-posted is always Ready', () => {
    expect(auto(null, '2026-06-01')).toBe('fresh');
  });

  it('2-day rest walks Resting → Tomorrow → Ready', () => {
    expect(auto('2026-06-01', '2026-06-01')).toBe('wait'); // posted today
    expect(auto('2026-06-01', '2026-06-02')).toBe('soon'); // yesterday → Tomorrow
    expect(auto('2026-06-01', '2026-06-03')).toBe('fresh'); // 2 days → Ready
    expect(auto('2026-06-01', '2026-06-10')).toBe('fresh'); // long past → Ready
  });

  it('1-day rest skips Resting (today shows Tomorrow)', () => {
    expect(auto('2026-06-01', '2026-06-01', 1)).toBe('soon');
    expect(auto('2026-06-01', '2026-06-02', 1)).toBe('fresh');
  });

  it('0-day rest is always Ready', () => {
    expect(auto('2026-06-01', '2026-06-01', 0)).toBe('fresh');
  });

  it('longer rest (5 days) keeps Resting until the penultimate day', () => {
    expect(auto('2026-06-01', '2026-06-03', 5)).toBe('wait'); // 2 days in
    expect(auto('2026-06-01', '2026-06-05', 5)).toBe('soon'); // 4 days → Tomorrow
    expect(auto('2026-06-01', '2026-06-06', 5)).toBe('fresh'); // 5 days → Ready
  });

  it('ignores the stored flag entirely', () => {
    expect(
      effectiveRotation({ mode: 'auto', restDays: 2, stored: 'fresh', lastPostedAt: '2026-06-01', today: '2026-06-01' }),
    ).toBe('wait');
  });
});
