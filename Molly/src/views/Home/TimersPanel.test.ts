import { describe, expect, it } from 'vitest';
import { daysUntil, formatStopwatch, stopwatchElapsedMs } from './TimersPanel';

describe('daysUntil', () => {
  const today = new Date(2026, 4, 26); // May 26 2026 local

  it('returns 0 for today', () => {
    expect(daysUntil('2026-05-26', today)).toBe(0);
  });

  it('counts forward across month boundaries', () => {
    // May 26 → Jun 1 = 6 days
    expect(daysUntil('2026-06-01', today)).toBe(6);
  });

  it('handles far-future dates', () => {
    // May 26 2026 → Dec 6 2026 = 194 days
    expect(daysUntil('2026-12-06', today)).toBe(194);
  });

  it('returns negative for past dates', () => {
    expect(daysUntil('2026-05-25', today)).toBe(-1);
    expect(daysUntil('2026-04-26', today)).toBe(-30);
  });
});

describe('formatStopwatch', () => {
  it('renders zero', () => {
    expect(formatStopwatch(0)).toBe('00:00:00.00');
  });

  it('pads centiseconds and seconds', () => {
    expect(formatStopwatch(50)).toBe('00:00:00.05');
    expect(formatStopwatch(1230)).toBe('00:00:01.23');
  });

  it('rolls into minutes and hours', () => {
    expect(formatStopwatch(65_120)).toBe('00:01:05.12');     // 1m 5.12s
    expect(formatStopwatch(3_600_000)).toBe('01:00:00.00');  // 1h flat
    expect(formatStopwatch(3_725_990)).toBe('01:02:05.99');  // 1h 2m 5.99s
  });

  it('clamps negative inputs to zero', () => {
    expect(formatStopwatch(-50)).toBe('00:00:00.00');
  });
});

describe('stopwatchElapsedMs', () => {
  it('returns accumulated value when stopped', () => {
    expect(
      stopwatchElapsedMs({ running: false, startedAt: null, accumulatedMs: 1234 }, 999_999),
    ).toBe(1234);
  });

  it('adds the current segment when running', () => {
    expect(
      stopwatchElapsedMs(
        { running: true, startedAt: 1_000_000, accumulatedMs: 500 },
        1_002_345,
      ),
    ).toBe(500 + 2345);
  });

  it('treats a missing startedAt while running as no segment', () => {
    expect(
      stopwatchElapsedMs(
        { running: true, startedAt: null, accumulatedMs: 7 },
        9_999_999,
      ),
    ).toBe(7);
  });
});
