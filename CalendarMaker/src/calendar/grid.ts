// Pure month-grid math, shared by the on-screen preview and the PDF renderer.

import { daysInMonth, isoDate, weekdayOf } from './dateUtil';

export interface GridCell {
  /** Day-of-month for in-month cells, else null (leading/trailing blank). */
  day: number | null;
  /** ISO key for in-month cells, else null. */
  date: string | null;
  inMonth: boolean;
  /** Weekday 0=Sun..6=Sat. */
  weekday: number;
}

export interface MonthGrid {
  year: number;
  month: number; // 1-12
  weekStartsOn: 0 | 1;
  weeks: number;
  /** weeks*7 cells, row-major. */
  cells: GridCell[];
  leadingBlanks: number;
  trailingBlanks: number;
}

export function computeWeeks(year: number, month: number, weekStartsOn: 0 | 1): MonthGrid {
  const dim = daysInMonth(year, month);
  const firstWd = weekdayOf(year, month, 1);
  const leadingBlanks = (firstWd - weekStartsOn + 7) % 7;
  const weeks = Math.ceil((leadingBlanks + dim) / 7);
  const total = weeks * 7;
  const trailingBlanks = total - leadingBlanks - dim;

  const cells: GridCell[] = [];
  for (let i = 0; i < total; i++) {
    const weekday = (weekStartsOn + (i % 7)) % 7;
    const dayNum = i - leadingBlanks + 1;
    const inMonth = dayNum >= 1 && dayNum <= dim;
    cells.push({
      day: inMonth ? dayNum : null,
      date: inMonth ? isoDate(year, month, dayNum) : null,
      inMonth,
      weekday,
    });
  }

  return { year, month, weekStartsOn, weeks, cells, leadingBlanks, trailingBlanks };
}

/** Weekday header labels reordered for the chosen week start. */
export function weekdayOrder(weekStartsOn: 0 | 1): number[] {
  return Array.from({ length: 7 }, (_, i) => (weekStartsOn + i) % 7);
}

/**
 * The largest contiguous run of blank (non-month) cells, as [startIndex, count].
 * Used to place a saying/verse panel in the grid's free space. Prefers the
 * trailing run when runs tie (bottom-right looks better than top-left).
 */
export function largestBlankRun(grid: MonthGrid): { start: number; count: number } | null {
  let best: { start: number; count: number } | null = null;
  let i = 0;
  while (i < grid.cells.length) {
    if (grid.cells[i].inMonth) {
      i++;
      continue;
    }
    let j = i;
    while (j < grid.cells.length && !grid.cells[j].inMonth) j++;
    const run = { start: i, count: j - i };
    if (!best || run.count >= best.count) best = run;
    i = j;
  }
  return best;
}
