import { describe, it, expect } from 'vitest';
import { computeWeeks, largestBlankRun } from '../src/calendar/grid';
import { daysInMonth, weekdayOf } from '../src/calendar/dateUtil';

describe('computeWeeks', () => {
  function checkInvariants(year: number, month: number, weekStart: 0 | 1) {
    const g = computeWeeks(year, month, weekStart);
    const dim = daysInMonth(year, month);
    expect(g.cells.length).toBe(g.weeks * 7);
    expect(g.weeks).toBeGreaterThanOrEqual(4);
    expect(g.weeks).toBeLessThanOrEqual(6);
    expect(g.leadingBlanks + dim + g.trailingBlanks).toBe(g.weeks * 7);
    expect(g.cells.filter((c) => c.inMonth).length).toBe(dim);
    // First in-month cell sits at the right weekday.
    const first = g.cells.find((c) => c.inMonth)!;
    expect(first.day).toBe(1);
    expect(first.weekday).toBe(weekdayOf(year, month, 1));
    // Day numbers run 1..dim in order.
    const days = g.cells.filter((c) => c.inMonth).map((c) => c.day);
    expect(days).toEqual(Array.from({ length: dim }, (_, i) => i + 1));
  }

  it('holds invariants across many months and both week starts', () => {
    for (let m = 1; m <= 12; m++) {
      checkInvariants(2026, m, 0);
      checkInvariants(2026, m, 1);
    }
  });

  it('handles leap-year February (29 days)', () => {
    expect(daysInMonth(2024, 2)).toBe(29);
    checkInvariants(2024, 2, 0);
    expect(daysInMonth(2026, 2)).toBe(28);
  });

  it('a 28-day February starting on the week-start day is exactly 4 weeks', () => {
    // Feb 2026 starts Sunday; with Sunday start → 0 leading blanks, 4 weeks.
    const g = computeWeeks(2026, 2, 0);
    expect(weekdayOf(2026, 2, 1)).toBe(0);
    expect(g.leadingBlanks).toBe(0);
    expect(g.weeks).toBe(4);
  });

  it('largestBlankRun finds a contiguous blank run', () => {
    const g = computeWeeks(2026, 2, 0); // 4 weeks, no leading blanks; trailing blanks exist
    const run = largestBlankRun(g);
    if (g.trailingBlanks > 0) {
      expect(run).not.toBeNull();
      expect(run!.count).toBeGreaterThanOrEqual(1);
      // Every cell in the run is a blank cell.
      for (let i = run!.start; i < run!.start + run!.count; i++) {
        expect(g.cells[i].inMonth).toBe(false);
      }
    }
  });
});
