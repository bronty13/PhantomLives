import { describe, it, expect } from 'vitest';
import {
  forecast,
  fmtFollowers,
  daysBetween,
  addDays,
  type LoggedPoint,
} from './followerForecast';

const series = (pairs: Array<[string, number]>): LoggedPoint[] =>
  pairs.map(([date, count]) => ({ date, count }));

describe('daysBetween / addDays', () => {
  it('counts whole days and adds them, timezone-safe', () => {
    expect(daysBetween('2026-06-01', '2026-06-04')).toBe(3);
    expect(daysBetween('2026-02-28', '2026-03-01')).toBe(1); // 2026 not leap
    expect(addDays('2026-06-01', 33)).toBe('2026-07-04');
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01');
  });
});

describe('fmtFollowers', () => {
  it('formats across the k / M boundaries and trims zeros', () => {
    expect(fmtFollowers(9_999)).toBe('9,999');
    expect(fmtFollowers(10_000)).toBe('10k');
    expect(fmtFollowers(12_340)).toBe('12.3k');
    expect(fmtFollowers(999_900)).toBe('999.9k');
    expect(fmtFollowers(1_000_000)).toBe('1M');
    expect(fmtFollowers(1_250_000)).toBe('1.25M');
    expect(fmtFollowers(-50)).toBe('-50');
  });
});

describe('forecast', () => {
  it('insufficient with < 2 points', () => {
    expect(forecast([], 1000, '2026-06-01').status).toBe('insufficient');
    expect(forecast(series([['2026-06-01', 100]]), 1000, '2026-06-01').status).toBe('insufficient');
  });

  it('recovers a clean slope', () => {
    const r = forecast(series([['2026-06-01', 100], ['2026-06-03', 200], ['2026-06-05', 300]]), 0, '2026-06-05');
    expect(r.slopePerDay).toBeCloseTo(50, 5);
    expect(r.status).toBe('no-goal');
  });

  it('handles irregular spacing (gap weights correctly)', () => {
    // +100 over 10 days = 10/day, despite only 2 logged points.
    const r = forecast(series([['2026-06-01', 1000], ['2026-06-11', 1100]]), 0, '2026-06-11');
    expect(r.slopePerDay).toBeCloseTo(10, 5);
    expect(r.avgPerDay).toBeCloseTo(10, 5);
  });

  it('on-track computes an ETA date', () => {
    // 1000 → 1100 over 10 days = 10/day; need 400 more to hit 1500 → 40 days.
    const r = forecast(series([['2026-06-01', 1000], ['2026-06-11', 1100]]), 1500, '2026-06-11');
    expect(r.status).toBe('on-track');
    expect(r.daysToGoal).toBe(40);
    expect(r.etaDate).toBe(addDays('2026-06-11', 40));
  });

  it('crosses a month boundary in the ETA', () => {
    const r = forecast(series([['2026-06-20', 100], ['2026-06-30', 200]]), 500, '2026-06-30');
    // +10/day, need 300 more → 30 days from 06-30 = 07-30.
    expect(r.etaDate).toBe('2026-07-30');
  });

  it('reached when already at/past goal', () => {
    const r = forecast(series([['2026-06-01', 900], ['2026-06-02', 1050]]), 1000, '2026-06-02');
    expect(r.status).toBe('reached');
    expect(r.surplus).toBe(50);
  });

  it('flat reads as steady, never an ETA', () => {
    const r = forecast(series([['2026-06-01', 1000], ['2026-06-05', 1000]]), 2000, '2026-06-05');
    expect(r.status).toBe('flat-or-declining');
    expect(r.etaDate).toBeNull();
    expect(r.message).toMatch(/steady/i);
  });

  it('declining stays kind, no negative/∞ ETA', () => {
    const r = forecast(series([['2026-06-01', 1200], ['2026-06-05', 1000]]), 2000, '2026-06-05');
    expect(r.status).toBe('flat-or-declining');
    expect(r.daysToGoal).toBeNull();
    expect(r.etaDate).toBeNull();
    expect(r.message).not.toMatch(/-/); // no scary minus in the copy
  });

  it('caps a far-off ETA instead of showing a date decades out', () => {
    // +1/day, need 10000 more → ~10000 days > 5y cap.
    const r = forecast(series([['2026-06-01', 100], ['2026-06-11', 110]]), 10_110, '2026-06-11');
    expect(r.status).toBe('far-off');
    expect(r.etaDate).toBeNull();
  });
});
