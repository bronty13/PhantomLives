/** Format a number as USD currency. Defaults to no decimals for round totals. */
export function fmtMoney(n: number, opts?: { decimals?: number }): string {
  const decimals = opts?.decimals ?? 2;
  const sign = n < 0 ? '-' : '';
  const abs = Math.abs(n);
  return `${sign}$${abs.toLocaleString(undefined, { minimumFractionDigits: decimals, maximumFractionDigits: decimals })}`;
}

/** Parse a money input that may include `$` or commas. */
export function parseMoney(s: string): number {
  const cleaned = s.replace(/[$,\s]/g, '');
  const n = parseFloat(cleaned);
  return Number.isFinite(n) ? n : 0;
}

/** Return the current month as (year, month, day) ints in local time. */
export function todayParts(): { year: number; month: number; day: number } {
  const d = new Date();
  return { year: d.getFullYear(), month: d.getMonth() + 1, day: d.getDate() };
}

/** Previous month relative to the given (year, month). */
export function prevMonth(year: number, month: number): { year: number; month: number } {
  if (month === 1) return { year: year - 1, month: 12 };
  return { year, month: month - 1 };
}

export const MONTH_NAMES = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

export function monthLabel(year: number, month: number): string {
  return `${MONTH_NAMES[month - 1]} ${year}`;
}
