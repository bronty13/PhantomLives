import { describe, it, expect } from 'vitest';
import { buildCalendarPdf } from '../src/pdf/exportPdf';
import { SEED_THEMES } from '../src/model/seedThemes';
import { makeBundle, makeItem } from '../src/model/factory';
import type { CalendarBundle } from '../src/model/types';

function sampleBundle(): CalendarBundle {
  const b = makeBundle({ title: 'Test', year: 2026, month: 6, themeId: 'theme-classic', weekStartsOn: 0 });
  b.days['2026-06-10'] = {
    date: '2026-06-10',
    holidayIds: ['flag-day'],
    items: [
      makeItem('prayer', 0, 'Pray for the Smiths'),
      makeItem('birthday', 1, 'Grandma turns 80'),
      makeItem('reminder', 2, 'A very long reminder that will not fit on the month grid and must move to the detail view instead'),
    ],
  };
  b.fillers = [{ slot: 'footer', entry: { id: 'v1', kind: 'verse', text: 'For God so loved the world', reference: 'John 3:16' } }];
  return b;
}

describe('buildCalendarPdf', () => {
  const theme = SEED_THEMES[0];

  it('builds a single-page month PDF', () => {
    const doc = buildCalendarPdf(sampleBundle(), theme, 'month', 5);
    expect(doc.getNumberOfPages()).toBe(1);
  });

  it('builds a detail PDF', () => {
    const doc = buildCalendarPdf(sampleBundle(), theme, 'detail', 5);
    expect(doc.getNumberOfPages()).toBeGreaterThanOrEqual(1);
  });

  it('builds a combined "both" PDF (month then detail)', () => {
    const doc = buildCalendarPdf(sampleBundle(), theme, 'both', 5);
    expect(doc.getNumberOfPages()).toBeGreaterThanOrEqual(2);
  });

  it('produces a non-empty blob', () => {
    const doc = buildCalendarPdf(sampleBundle(), theme, 'both', 5);
    const blob = doc.output('blob');
    expect(blob.size).toBeGreaterThan(1000);
  });
});
