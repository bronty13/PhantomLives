// Resolve rule-based holiday definitions to concrete dates for a given month/year.

import type { HolidayDef, ResolvedHoliday } from '../model/types';
import { HOLIDAYS } from '../data/holidays';
import { addDays, daysInMonth, isoDate, weekdayOf } from './dateUtil';

/** Easter Sunday for a Gregorian year (Anonymous Gregorian / Meeus-Jones-Butcher). */
export function computeEaster(year: number): { year: number; month: number; day: number } {
  const a = year % 19;
  const b = Math.floor(year / 100);
  const c = year % 100;
  const d = Math.floor(b / 4);
  const e = b % 4;
  const f = Math.floor((b + 8) / 25);
  const g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4);
  const k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7;
  const m = Math.floor((a + 11 * h + 22 * l) / 451);
  const month = Math.floor((h + l - 7 * m + 114) / 31); // 3=March, 4=April
  const day = ((h + l - 7 * m + 114) % 31) + 1;
  return { year, month, day };
}

/** nth (1-based) `weekday` of month/year; n=-1 → last. Returns day-of-month. */
function nthWeekdayOfMonth(year: number, month: number, weekday: number, n: number): number {
  const dim = daysInMonth(year, month);
  if (n > 0) {
    const firstWd = weekdayOf(year, month, 1);
    const offset = (weekday - firstWd + 7) % 7;
    return 1 + offset + (n - 1) * 7;
  }
  // last
  const lastWd = weekdayOf(year, month, dim);
  const offset = (lastWd - weekday + 7) % 7;
  return dim - offset;
}

/** The actual date a holiday falls on in a given year (month 1-12). */
export function resolveHolidayDate(def: HolidayDef, year: number): { year: number; month: number; day: number } {
  switch (def.rule.kind) {
    case 'fixed':
      return { year, month: def.rule.month, day: def.rule.day };
    case 'nthWeekday':
      return { year, month: def.rule.month, day: nthWeekdayOfMonth(year, def.rule.month, def.rule.weekday, def.rule.n) };
    case 'easterOffset': {
      const e = computeEaster(year);
      return addDays(e.year, e.month, e.day, def.rule.days);
    }
  }
}

/** Federal observed shift: Saturday → preceding Friday, Sunday → following Monday. */
function observedShift(year: number, month: number, day: number): { year: number; month: number; day: number } | null {
  const wd = weekdayOf(year, month, day);
  if (wd === 6) return addDays(year, month, day, -1); // Sat → Fri
  if (wd === 0) return addDays(year, month, day, 1); // Sun → Mon
  return null;
}

/**
 * All holidays (actual, plus observed shift when distinct) that fall within the
 * given month/year, sorted by day. Each entry's `date` is its ISO key.
 */
export function resolveHolidaysForMonth(year: number, month: number, defs: HolidayDef[] = HOLIDAYS): ResolvedHoliday[] {
  const out: ResolvedHoliday[] = [];
  for (const def of defs) {
    const actual = resolveHolidayDate(def, year);
    if (actual.year === year && actual.month === month) {
      out.push({ def, date: isoDate(actual.year, actual.month, actual.day) });
    }
    if (def.observed) {
      const shifted = observedShift(actual.year, actual.month, actual.day);
      if (shifted && shifted.year === year && shifted.month === month) {
        out.push({ def, date: isoDate(shifted.year, shifted.month, shifted.day), observed: true });
      }
    }
  }
  return out.sort((a, b) => a.date.localeCompare(b.date));
}
