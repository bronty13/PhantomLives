// Orchestrates the three export modes into one jsPDF document:
//   month  → a single landscape grid page
//   detail → portrait, date-ordered list pages
//   both   → month page(s) first, then detail pages, in one document

import { jsPDF } from 'jspdf';
import type { CalendarBundle, ExportMode, Theme } from '../model/types';
import { computeWeeks } from '../calendar/grid';
import type { FitContext } from '../calendar/fit';
import { registerFontsInDoc, setPdfFont } from '../data/fonts';
import { monthGeometry, LETTER_PORTRAIT } from './geometry';
import { renderMonth } from './monthPdf';
import { renderDetail } from './detailPdf';
import { setText } from './util';

export function buildCalendarPdf(bundle: CalendarBundle, theme: Theme, mode: ExportMode, cap: number): jsPDF {
  const grid = computeWeeks(bundle.year, bundle.month, bundle.weekStartsOn);
  const hasFooter = bundle.fillers.some((f) => f.slot === 'footer');
  const geo = monthGeometry(grid.weeks, hasFooter);
  const ctx: FitContext = { geo, theme, cap };

  const startLandscape = mode !== 'detail';
  const doc = new jsPDF({ unit: 'pt', format: 'letter', orientation: startLandscape ? 'landscape' : 'portrait' });
  registerFontsInDoc(doc);

  if (mode === 'month' || mode === 'both') {
    renderMonth(doc, bundle, theme, { cap });
  }
  if (mode === 'both') {
    doc.addPage('letter', 'portrait');
  }
  if (mode === 'detail' || mode === 'both') {
    const detailStart = doc.getNumberOfPages();
    renderDetail(doc, bundle, theme, ctx);
    numberDetailPages(doc, theme, detailStart);
  }
  return doc;
}

function numberDetailPages(doc: jsPDF, theme: Theme, start: number): void {
  const total = doc.getNumberOfPages();
  const count = total - start + 1;
  for (let p = start; p <= total; p++) {
    doc.setPage(p);
    setText(doc, theme.overflowColor);
    setPdfFont(doc, theme.calendar.headerFont, false);
    doc.setFontSize(9);
    doc.text(`Page ${p - start + 1} of ${count}`, LETTER_PORTRAIT.PAGE_W / 2, LETTER_PORTRAIT.PAGE_H - LETTER_PORTRAIT.MARGIN + 6, {
      align: 'center',
    });
  }
}
