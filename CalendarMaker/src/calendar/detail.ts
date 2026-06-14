// Pure builder for the detail view: a date-ordered list of every day that has a
// holiday or item. Each item is flagged detailOnly when it was demoted off the
// month grid (so the renderer can mark it).

import type { CalendarBundle, Item } from '../model/types';
import { WEEKDAY_NAMES } from '../model/types';
import { daysInMonth, isoDate, weekdayOf } from './dateUtil';
import { classifyDay, type FitContext } from './fit';

export interface DetailLine {
  item: Item;
  detailOnly: boolean;
}

export interface DetailSection {
  date: string;
  dayNum: number;
  weekdayName: string;
  holidayNames: string[];
  lines: DetailLine[];
}

export function buildDetailSections(
  bundle: CalendarBundle,
  ctx: FitContext,
  holidayNamesFor: (date: string) => string[],
): DetailSection[] {
  const sections: DetailSection[] = [];
  const dim = daysInMonth(bundle.year, bundle.month);
  const verseMode = bundle.verseMode ?? 'force';
  const isVerseOrSaying = (t: string) => t === 'bibleVerse' || t === 'saying';
  for (let d = 1; d <= dim; d++) {
    const date = isoDate(bundle.year, bundle.month, d);
    const holidayNames = holidayNamesFor(date);
    const day = bundle.days[date];
    const items = day?.items ?? [];
    if (holidayNames.length === 0 && items.length === 0) continue;

    let lines: DetailLine[] = [];
    if (day && items.length) {
      const { monthItems } = classifyDay(day, ctx, holidayNames.length, verseMode);
      const monthIds = new Set(monthItems.map((i) => i.id));
      lines = [...items]
        .sort((a, b) => a.order - b.order)
        .map((item) => ({
          item,
          // Verses/sayings are placed intentionally (forced into cells, or on the
          // dedicated Scripture calendar in separate mode), so they're never the
          // "demoted / overflow" ⊘ case — only regular items can be detail-only.
          detailOnly: isVerseOrSaying(item.type) ? false : !monthIds.has(item.id),
        }));
    }

    sections.push({
      date,
      dayNum: d,
      weekdayName: WEEKDAY_NAMES[weekdayOf(bundle.year, bundle.month, d)],
      holidayNames,
      lines,
    });
  }
  return sections;
}
