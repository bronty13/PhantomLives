import { describe, it, expect } from 'vitest';
import type { Holiday } from '../data/holidays';
import {
  daysInMonth,
  isoDateKey,
  resolveHolidayForMonth,
  resolveHolidaysForMonth,
  resolveNthWeekday,
} from './holidayResolver';

function mkFixed(name: string, month: number, day: number, enabled = true): Holiday {
  return {
    id: Math.floor(Math.random() * 1_000_000),
    name,
    kind: 'fixed',
    month,
    day,
    weekday: null,
    nth: null,
    colorPrimary: '#FF0000',
    colorSecondary: null,
    colorText: '#FFFFFF',
    emoji: null,
    enabled,
    source: 'custom',
    createdAt: '',
    updatedAt: '',
  };
}

function mkNth(name: string, month: number, weekday: number, nth: number): Holiday {
  return {
    id: Math.floor(Math.random() * 1_000_000),
    name,
    kind: 'nth_weekday',
    month,
    day: null,
    weekday,
    nth,
    colorPrimary: '#0000FF',
    colorSecondary: null,
    colorText: '#FFFFFF',
    emoji: null,
    enabled: true,
    source: 'custom',
    createdAt: '',
    updatedAt: '',
  };
}

describe('isoDateKey', () => {
  it('zero-pads month + day', () => {
    expect(isoDateKey(2026, 1, 5)).toBe('2026-01-05');
    expect(isoDateKey(2026, 12, 31)).toBe('2026-12-31');
  });
});

describe('daysInMonth', () => {
  it.each([
    [2026, 1, 31],
    [2026, 2, 28],
    [2024, 2, 29], // leap year
    [2025, 2, 28],
    [2026, 4, 30],
    [2026, 12, 31],
  ])('year=%i month=%i → %i days', (y, m, d) => {
    expect(daysInMonth(y, m)).toBe(d);
  });
});

describe('resolveNthWeekday', () => {
  it('3rd Monday of January 2026 = Jan 19', () => {
    // 2026-01-01 is a Thursday. First Monday = Jan 5. 3rd = Jan 19.
    expect(resolveNthWeekday(2026, 1, 1, 3)).toBe(19);
  });

  it('last Monday of May 2026 (Memorial Day) = May 25', () => {
    expect(resolveNthWeekday(2026, 5, 1, -1)).toBe(25);
  });

  it('4th Thursday of November 2026 (Thanksgiving) = Nov 26', () => {
    expect(resolveNthWeekday(2026, 11, 4, 4)).toBe(26);
  });

  it('2nd Sunday of May 2026 (Mother\'s Day) = May 10', () => {
    expect(resolveNthWeekday(2026, 5, 0, 2)).toBe(10);
  });

  it('1st Monday of September 2026 (Labor Day) = Sep 7', () => {
    expect(resolveNthWeekday(2026, 9, 1, 1)).toBe(7);
  });
});

describe('resolveHolidayForMonth', () => {
  it('returns null when month doesn\'t match', () => {
    expect(resolveHolidayForMonth(mkFixed('NYE', 12, 31), 2026, 11)).toBeNull();
  });

  it('returns null when disabled', () => {
    expect(resolveHolidayForMonth(mkFixed('NYE', 12, 31, false), 2026, 12)).toBeNull();
  });

  it('clamps fixed-date day to month length', () => {
    // Feb 30 → Feb 28 in a non-leap year.
    const out = resolveHolidayForMonth(mkFixed('Weird', 2, 30), 2025, 2);
    expect(out).toBe('2025-02-28');
  });

  it('handles fixed-date for July 4th', () => {
    expect(resolveHolidayForMonth(mkFixed('July 4', 7, 4), 2026, 7)).toBe('2026-07-04');
  });

  it('handles nth_weekday for MLK Day 2026', () => {
    expect(resolveHolidayForMonth(mkNth('MLK', 1, 1, 3), 2026, 1)).toBe('2026-01-19');
  });
});

describe('resolveHolidaysForMonth', () => {
  it('groups multiple holidays falling on the same day', () => {
    const a = mkFixed('A', 12, 25);
    const b = mkFixed('B', 12, 25);
    const map = resolveHolidaysForMonth([a, b], 2026, 12);
    const entry = map.get('2026-12-25');
    expect(entry).toBeDefined();
    expect(entry!.map((h) => h.name).sort()).toEqual(['A', 'B']);
  });

  it('ignores holidays from other months', () => {
    const dec = mkFixed('Christmas', 12, 25);
    const jul = mkFixed('July 4', 7, 4);
    const map = resolveHolidaysForMonth([dec, jul], 2026, 12);
    expect(map.size).toBe(1);
    expect(map.has('2026-12-25')).toBe(true);
  });

  it('returns an empty map when no holidays match', () => {
    const map = resolveHolidaysForMonth([mkFixed('A', 12, 25)], 2026, 6);
    expect(map.size).toBe(0);
  });
});
