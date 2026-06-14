// The overflow system — the core guarantee that a month cell never becomes a
// visual mess. Every item is classified into month-visible vs detail-only using
// the SAME font metrics the PDF uses. The renderer only ever draws month-visible
// items, so a cell physically cannot overflow its borders.

import type { Day, Item, Theme, VerseDisplayMode } from '../model/types';
import { CELL, type MonthGeometry } from '../pdf/geometry';
import { wrapLines } from './measure';

export interface FitContext {
  geo: MonthGeometry;
  theme: Theme;
  /** Hard cap on items shown per cell (settings.maxItemsPerMonthCell). */
  cap: number;
}

/** Number of wrapped lines a chip would occupy in a cell. */
export function chipLineCount(item: Item, ctx: FitContext): number {
  const font = ctx.theme.itemStyles[item.type].font;
  return wrapLines(item.text, font, CELL.CHIP_FONT, ctx.geo.cellContentW).length;
}

/** Rendered height (points) of a chip occupying `lines` lines. */
export function chipHeight(lines: number): number {
  return lines * CELL.CHIP_LINE_H + CELL.CHIP_GAP;
}

/**
 * Can this item EVER show on the month view? It must wrap within CHIP_MAX_LINES
 * and fit (alone) in an empty cell's content height. An intrinsically-too-long
 * item is force-detail-only regardless of competition.
 */
export function isMonthEligible(item: Item, ctx: FitContext): boolean {
  const lines = chipLineCount(item, ctx);
  if (lines === 0) return false;
  if (lines > CELL.CHIP_MAX_LINES) return false;
  return chipHeight(lines) <= ctx.geo.cellContentH;
}

function pinnedThenOrder(a: Item, b: Item): number {
  if (a.pinned !== b.pinned) return a.pinned ? -1 : 1;
  return a.order - b.order;
}

/** Greedily pack items (in priority order) into `available` height, up to `cap`. */
function pack(items: Item[], heights: Map<string, number>, available: number, cap: number): Item[] {
  const out: Item[] = [];
  let used = 0;
  for (const item of items) {
    if (out.length >= cap) break;
    const h = heights.get(item.id) ?? 0;
    if (used + h > available) continue; // skip this one; a shorter later item may still fit
    out.push(item);
    used += h;
  }
  return out;
}

export interface DayClassification {
  /** Items shown on the month grid (in render order). */
  monthItems: Item[];
  /** Subset of monthItems rendered with shrink-to-fit (force mode: verse/saying types). */
  forceItems: Item[];
  /** Items shown only in the detail view (⊘ marked). */
  detailOnly: Item[];
  /** True when at least one item was demoted to detail-only. */
  hasOverflow: boolean;
}

/**
 * Classify a day's items into month-visible vs detail-only. `holidayLines` is how
 * many holiday lines occupy the top of the cell (each consumes HOLIDAY_LINE_H).
 * In force mode, verse/saying items always go to monthItems; other items compete for remaining space.
 */
export function classifyDay(
  day: Day,
  ctx: FitContext,
  holidayLines = 0,
  verseMode: VerseDisplayMode = 'separate',
): DayClassification {
  const sorted = [...day.items].sort(pinnedThenOrder);

  // In force mode, partition verse/saying items first
  let forceItems: Item[] = [];
  let otherItems: Item[] = sorted;

  if (verseMode === 'force') {
    forceItems = sorted.filter((i) => i.type === 'bibleVerse' || i.type === 'saying');
    otherItems = sorted.filter((i) => i.type !== 'bibleVerse' && i.type !== 'saying');
  }

  const eligible: Item[] = [];
  const heights = new Map<string, number>();
  const ineligible: Item[] = [];

  for (const item of otherItems) {
    const lines = chipLineCount(item, ctx);
    if (lines === 0 || lines > CELL.CHIP_MAX_LINES || chipHeight(lines) > ctx.geo.cellContentH) {
      ineligible.push(item);
    } else {
      eligible.push(item);
      heights.set(item.id, chipHeight(lines));
    }
  }

  let baseAvail = ctx.geo.cellContentH - holidayLines * CELL.HOLIDAY_LINE_H;

  // In force mode, reserve space for the force block (assume ~3 lines per verse + gap)
  if (verseMode === 'force' && forceItems.length > 0) {
    const forceBlockH = Math.min(forceItems.length * CELL.CHIP_LINE_H * 3, baseAvail * 0.5);
    baseAvail -= forceBlockH;
  }

  // First try without reserving a "+N more" line.
  let monthItems = pack(eligible, heights, baseAvail, ctx.cap);
  let overflow = monthItems.length < eligible.length || ineligible.length > 0;

  // If anything overflows, reserve space for the "+N more" indicator and re-pack.
  if (overflow) {
    const monthSet = new Set(pack(eligible, heights, baseAvail - CELL.MORE_LINE_H, ctx.cap).map((i) => i.id));
    monthItems = eligible.filter((i) => monthSet.has(i.id));
  }

  // In force mode, force items + packed other items
  const renderedItems = verseMode === 'force' ? [...forceItems, ...monthItems] : monthItems;

  const monthIds = new Set(renderedItems.map((i) => i.id));
  const detailOnly = sorted.filter((i) => !monthIds.has(i.id));
  overflow = detailOnly.length > 0;

  return { monthItems: renderedItems, forceItems, detailOnly, hasOverflow: overflow };
}

/**
 * Recompute and persist `showOnMonth` for every item in the bundle's days.
 * Returns a new days map (caller persists it).
 */
export function applyFit(
  days: Record<string, Day>,
  ctx: FitContext,
  holidayLinesFor: (date: string) => number,
): Record<string, Day> {
  const out: Record<string, Day> = {};
  for (const [date, day] of Object.entries(days)) {
    const { monthItems } = classifyDay(day, ctx, holidayLinesFor(date));
    const monthIds = new Set(monthItems.map((i) => i.id));
    out[date] = {
      ...day,
      items: day.items.map((i) => ({ ...i, showOnMonth: monthIds.has(i.id) })),
    };
  }
  return out;
}
