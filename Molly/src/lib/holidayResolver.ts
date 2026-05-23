import type { Holiday } from '../data/holidays';

// Phase 14 PR1 — Holiday date resolver.
//
// Given a list of holidays + a target year+month, return an
// ISO-date → Holiday[] map for that month. Handles:
//   - 'fixed' (clamped to the actual length of the month)
//   - 'nth_weekday' for nth = 1..4 and nth = -1 (last)
//
// All math is done in local time. Calendars are user-facing so DST
// drift inside a single date doesn't matter — we work with date
// components only, never timestamps.

export function isoDateKey(y: number, m: number, d: number): string {
  const yy = y.toString().padStart(4, '0');
  const mm = m.toString().padStart(2, '0');
  const dd = d.toString().padStart(2, '0');
  return `${yy}-${mm}-${dd}`;
}

export function daysInMonth(year: number, month: number): number {
  // month is 1..12; new Date(y, m, 0) returns the last day of (m-1+1).
  return new Date(year, month, 0).getDate();
}

/** Returns the day-of-month for the nth (or -1=last) occurrence of
 *  `weekday` in (year, month). Returns null if `nth >= 1` and there
 *  aren't that many of `weekday` in the month (shouldn't happen for
 *  any month — every weekday occurs at least 4 times — so this is
 *  belt-and-braces). */
export function resolveNthWeekday(
  year: number,
  month: number,
  weekday: number,
  nth: number,
): number | null {
  const firstWeekday = new Date(year, month - 1, 1).getDay();
  const offset = (weekday - firstWeekday + 7) % 7;
  const firstOccurrence = 1 + offset; // day-of-month of the first matching weekday
  if (nth === -1) {
    // Walk forward in 7-day steps until past the end of month.
    let day = firstOccurrence;
    const last = daysInMonth(year, month);
    while (day + 7 <= last) day += 7;
    return day;
  }
  if (nth < 1) return null;
  const day = firstOccurrence + (nth - 1) * 7;
  return day <= daysInMonth(year, month) ? day : null;
}

/** Resolve a single holiday to its date in `year`/`month` if it falls
 *  in that month, otherwise null. */
export function resolveHolidayForMonth(
  h: Holiday,
  year: number,
  month: number,
): string | null {
  if (h.month !== month) return null;
  if (!h.enabled) return null;
  if (h.kind === 'fixed') {
    if (h.day == null) return null;
    const clamped = Math.min(h.day, daysInMonth(year, month));
    return isoDateKey(year, month, clamped);
  }
  if (h.kind === 'nth_weekday') {
    if (h.weekday == null || h.nth == null) return null;
    const day = resolveNthWeekday(year, month, h.weekday, h.nth);
    return day == null ? null : isoDateKey(year, month, day);
  }
  return null;
}

/** Build an `ISO date → holidays on that date` map for one month.
 *  Used by Calendar to overlay holiday pills. */
export function resolveHolidaysForMonth(
  holidays: Holiday[],
  year: number,
  month: number,
): Map<string, Holiday[]> {
  const map = new Map<string, Holiday[]>();
  for (const h of holidays) {
    const key = resolveHolidayForMonth(h, year, month);
    if (!key) continue;
    const arr = map.get(key) ?? [];
    arr.push(h);
    map.set(key, arr);
  }
  return map;
}

/** Tailwind-free pill style for a holiday. Two-color holidays render
 *  as a 45° gradient; single-color holidays stay flat. */
export function holidayPillStyle(h: Holiday): React.CSSProperties {
  const base: React.CSSProperties = {
    color: h.colorText,
    border: `1px solid ${h.colorPrimary}`,
  };
  if (h.colorSecondary && h.colorSecondary !== h.colorPrimary) {
    base.background = `linear-gradient(135deg, ${h.colorPrimary} 0%, ${h.colorPrimary} 48%, ${h.colorSecondary} 52%, ${h.colorSecondary} 100%)`;
  } else {
    base.background = h.colorPrimary;
  }
  return base;
}
