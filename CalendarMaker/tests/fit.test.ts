import { describe, it, expect } from 'vitest';
import { classifyDay, isMonthEligible, chipLineCount, chipHeight, type FitContext } from '../src/calendar/fit';
import { monthGeometry, CELL } from '../src/pdf/geometry';
import { SEED_THEMES } from '../src/model/seedThemes';
import { makeItem } from '../src/model/factory';
import type { Day } from '../src/model/types';

const theme = SEED_THEMES[0];
// Worst case: a 6-week month → smallest cells.
const ctx: FitContext = { geo: monthGeometry(6, false), theme, cap: 5 };

function day(date: string, texts: string[]): Day {
  return {
    date,
    holidayIds: [],
    items: texts.map((t, i) => makeItem(i % 2 === 0 ? 'prayer' : 'reminder', i, t)),
  };
}

describe('fit / overflow', () => {
  it('short items are month-eligible; a very long item is not', () => {
    const short = makeItem('reminder', 0, 'Choir');
    const long = makeItem(
      'reminder',
      0,
      'This is an extremely long reminder that absolutely cannot fit inside a tiny calendar day cell on the month grid no matter what',
    );
    expect(isMonthEligible(short, ctx)).toBe(true);
    expect(isMonthEligible(long, ctx)).toBe(false);
    expect(chipLineCount(long, ctx)).toBeGreaterThan(CELL.CHIP_MAX_LINES);
  });

  it('INVARIANT: month items never overflow the cell content height', () => {
    const d = day('2026-06-10', ['Pray for rain', 'Choir', 'Bake sale', 'Visit Grandma', 'Board meeting', 'Cleanup', 'Potluck']);
    const { monthItems } = classifyDay(d, ctx, 0);
    let total = 0;
    for (const item of monthItems) total += chipHeight(chipLineCount(item, ctx));
    expect(total).toBeLessThanOrEqual(ctx.geo.cellContentH);
    expect(monthItems.length).toBeLessThanOrEqual(ctx.cap);
  });

  it('respects holiday lines reducing capacity', () => {
    const texts = ['Pray', 'Choir', 'Bake sale', 'Visit', 'Meeting', 'Cleanup'];
    const d = day('2026-12-25', texts);
    const without = classifyDay(d, ctx, 0).monthItems.length;
    const withHoliday = classifyDay(d, ctx, 2).monthItems.length;
    expect(withHoliday).toBeLessThanOrEqual(without);
  });

  it('pinned items take priority for the month slots', () => {
    const d = day('2026-06-11', ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']);
    // Pin the last item; it should appear in monthItems despite low order.
    d.items[7].pinned = true;
    const { monthItems } = classifyDay(d, ctx, 0);
    expect(monthItems.some((i) => i.id === d.items[7].id)).toBe(true);
  });

  it('flags overflow when more items than fit', () => {
    const d = day('2026-06-12', Array.from({ length: 12 }, (_, i) => `Event ${i + 1}`));
    const res = classifyDay(d, ctx, 0);
    expect(res.hasOverflow).toBe(true);
    expect(res.detailOnly.length).toBeGreaterThan(0);
    expect(res.monthItems.length + res.detailOnly.length).toBe(12);
  });

  it('force mode: verse items always appear in monthItems', () => {
    const d = day('2026-06-13', ['Event 1', 'Event 2']);
    const verse = makeItem('bibleVerse', 2, 'John 3:16 — For God so loved the world...', 'John 3:16');
    d.items.push(verse);
    const res = classifyDay(d, ctx, 0, 'force');
    expect(res.forceItems).toContainEqual(verse);
    expect(res.monthItems).toContainEqual(verse);
  });

  it('force mode: reserved height reduces chip capacity', () => {
    const texts = Array.from({ length: 8 }, (_, i) => `Event ${i + 1}`);
    const d = day('2026-06-14', texts);
    const verse = makeItem('bibleVerse', 8, 'Some verse text that takes up space', 'John 1:1');
    d.items.push(verse);

    const separateRes = classifyDay(d, ctx, 0, 'separate');
    const forceRes = classifyDay(d, ctx, 0, 'force');

    // Force mode should have fewer non-verse items than separate mode
    const separateNonVerse = separateRes.monthItems.filter((i) => i.type !== 'bibleVerse');
    const forceNonVerse = forceRes.monthItems.filter((i) => i.type !== 'bibleVerse');
    expect(forceNonVerse.length).toBeLessThanOrEqual(separateNonVerse.length);
  });

  it('force mode: forceItems is subset of monthItems', () => {
    const d = day('2026-06-15', ['Event 1']);
    const verse = makeItem('bibleVerse', 1, 'Verse text', 'John 1:1');
    const saying = makeItem('saying', 2, 'Saying text', 'Author');
    d.items.push(verse, saying);

    const res = classifyDay(d, ctx, 0, 'force');
    const monthIds = new Set(res.monthItems.map((i) => i.id));
    for (const item of res.forceItems) {
      expect(monthIds.has(item.id)).toBe(true);
    }
  });

  it('separate mode: verse/saying items treated as normal chips', () => {
    const d = day('2026-06-16', []);
    const verse = makeItem('bibleVerse', 0, 'Short verse', 'John 3:16');
    d.items.push(verse);

    const res = classifyDay(d, ctx, 0, 'separate');
    expect(res.forceItems).toEqual([]);
    expect(res.monthItems).toContainEqual(verse);
  });
});
