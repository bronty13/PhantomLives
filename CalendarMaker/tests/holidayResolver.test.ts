import { describe, it, expect } from 'vitest';
import { computeEaster, resolveHolidaysForMonth, resolveHolidayDate } from '../src/calendar/holidayResolver';
import { HOLIDAYS } from '../src/data/holidays';
import { isoDate } from '../src/calendar/dateUtil';

function iso(d: { year: number; month: number; day: number }) {
  return isoDate(d.year, d.month, d.day);
}

describe('computeEaster', () => {
  it('matches known Easter dates', () => {
    expect(iso(computeEaster(2024))).toBe('2024-03-31');
    expect(iso(computeEaster(2025))).toBe('2025-04-20');
    expect(iso(computeEaster(2026))).toBe('2026-04-05');
    expect(iso(computeEaster(2027))).toBe('2027-03-28');
  });
});

describe('resolveHolidayDate', () => {
  const byId = (id: string) => HOLIDAYS.find((h) => h.id === id)!;

  it('resolves nth-weekday holidays', () => {
    // Thanksgiving 2026 = 4th Thursday of November = Nov 26.
    expect(iso(resolveHolidayDate(byId('thanksgiving'), 2026))).toBe('2026-11-26');
    // MLK 2026 = 3rd Monday of January = Jan 19.
    expect(iso(resolveHolidayDate(byId('mlk-day'), 2026))).toBe('2026-01-19');
    // Memorial Day 2026 = last Monday of May = May 25.
    expect(iso(resolveHolidayDate(byId('memorial-day'), 2026))).toBe('2026-05-25');
  });

  it('resolves easter-offset holidays', () => {
    // Good Friday 2026 = Easter (Apr 5) - 2 = Apr 3.
    expect(iso(resolveHolidayDate(byId('good-friday'), 2026))).toBe('2026-04-03');
    // Ash Wednesday 2026 = Easter - 46 = Feb 18.
    expect(iso(resolveHolidayDate(byId('ash-wednesday'), 2026))).toBe('2026-02-18');
  });
});

describe('resolveHolidaysForMonth', () => {
  it('includes the observed shift when a fixed holiday lands on a weekend', () => {
    // July 4, 2026 is a Saturday → observed Friday July 3.
    const july = resolveHolidaysForMonth(2026, 7);
    const ind = july.filter((h) => h.def.id === 'independence-day');
    const dates = ind.map((h) => h.date).sort();
    expect(dates).toContain('2026-07-04');
    expect(dates).toContain('2026-07-03');
    expect(ind.find((h) => h.observed)?.date).toBe('2026-07-03');
  });

  it('returns Easter holidays in the right month', () => {
    const april = resolveHolidaysForMonth(2026, 4);
    expect(april.some((h) => h.def.id === 'easter-sunday' && h.date === '2026-04-05')).toBe(true);
  });

  it('only returns holidays within the requested month', () => {
    const feb = resolveHolidaysForMonth(2026, 2);
    expect(feb.every((h) => h.date.startsWith('2026-02'))).toBe(true);
  });
});
