// Small, dependency-free date helpers. Everything works in integer y/m/d space
// to avoid timezone surprises; ISO keys are 'YYYY-MM-DD'.

export function pad2(n: number): string {
  return String(n).padStart(2, '0');
}

/** month is 1-12. */
export function isoDate(year: number, month: number, day: number): string {
  return `${year}-${pad2(month)}-${pad2(day)}`;
}

/** month is 1-12. */
export function daysInMonth(year: number, month: number): number {
  return new Date(year, month, 0).getDate();
}

/** Weekday 0=Sun..6=Sat. month is 1-12. */
export function weekdayOf(year: number, month: number, day: number): number {
  return new Date(year, month - 1, day).getDay();
}

/** Add `days` to a y/m/d and return the resulting {year,month,day} (month 1-12). */
export function addDays(year: number, month: number, day: number, days: number): { year: number; month: number; day: number } {
  const d = new Date(year, month - 1, day);
  d.setDate(d.getDate() + days);
  return { year: d.getFullYear(), month: d.getMonth() + 1, day: d.getDate() };
}

/** Parse 'YYYY-MM-DD' → {year, month, day} (month 1-12). */
export function parseIso(iso: string): { year: number; month: number; day: number } {
  const [y, m, d] = iso.split('-').map((n) => parseInt(n, 10));
  return { year: y, month: m, day: d };
}
