import { describe, expect, it } from 'vitest';
import { fmtClock, fmtHM } from './hoursFmt';

describe('fmtClock', () => {
  it('renders zero as 00:00:00', () => {
    expect(fmtClock(0)).toBe('00:00:00');
  });

  it('zero-pads small values', () => {
    expect(fmtClock(1_000)).toBe('00:00:01');
    expect(fmtClock(59_000)).toBe('00:00:59');
    expect(fmtClock(60_000)).toBe('00:01:00');
    expect(fmtClock(3_600_000)).toBe('01:00:00');
  });

  it('handles multi-hour values', () => {
    expect(fmtClock(2 * 60 * 60 * 1000 + 5 * 60 * 1000 + 7 * 1000)).toBe('02:05:07');
  });

  it('clamps negative input to zero', () => {
    expect(fmtClock(-9999)).toBe('00:00:00');
  });
});

describe('fmtHM', () => {
  it('renders zero as 0m', () => {
    expect(fmtHM(0)).toBe('0m');
  });

  it('drops the hours prefix when under an hour', () => {
    expect(fmtHM(30 * 60_000)).toBe('30m');
    expect(fmtHM(59 * 60_000 + 59_000)).toBe('59m'); // 59m 59s → still 59m
  });

  it('includes the hours prefix at the boundary', () => {
    expect(fmtHM(60 * 60_000)).toBe('1h 0m');
  });

  it('handles multi-hour values', () => {
    expect(fmtHM(2 * 60 * 60_000 + 30 * 60_000)).toBe('2h 30m');
    expect(fmtHM(10 * 60 * 60_000 + 5 * 60_000)).toBe('10h 5m');
  });

  it('floors to whole minutes (no rounding-up surprise)', () => {
    // 59m 59.999s should still read as 59m, not 1h.
    expect(fmtHM(59 * 60_000 + 59_999)).toBe('59m');
  });

  it('clamps negative input to zero', () => {
    expect(fmtHM(-5000)).toBe('0m');
  });
});
