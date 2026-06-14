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
import { renderVerseCalendar, hasVerseOrSayingItems } from './versePdf';
import { setText } from './util';

/** Where the separate verse/saying calendar page sits relative to the detail pages. */
export type VerseExportOrder = 'verse-before-detail' | 'verse-after-detail';

export interface ExportOptions {
  verseOrder?: VerseExportOrder;
}

export function buildCalendarPdf(
  bundle: CalendarBundle,
  theme: Theme,
  mode: ExportMode,
  cap: number,
  opts: ExportOptions = {},
): jsPDF {
  const grid = computeWeeks(bundle.year, bundle.month, bundle.weekStartsOn);
  const hasFooter = bundle.fillers.some((f) => f.slot === 'footer');
  const geo = monthGeometry(grid.weeks, hasFooter);
  const ctx: FitContext = { geo, theme, cap };

  const verseOrder = opts.verseOrder ?? 'verse-before-detail';
  // The dedicated verse calendar only appears in 'separate' mode (force mode
  // already plasters verses into the main grid) when the month is being shown.
  const showVerseCal =
    (bundle.verseMode ?? 'force') === 'separate' &&
    hasVerseOrSayingItems(bundle) &&
    (mode === 'month' || mode === 'both');

  const startLandscape = mode !== 'detail';
  const doc = new jsPDF({ unit: 'pt', format: 'letter', orientation: startLandscape ? 'landscape' : 'portrait' });
  registerFontsInDoc(doc);

  const addVerseCalPage = () => {
    doc.addPage('letter', 'landscape');
    renderVerseCalendar(doc, bundle, theme);
  };

  // Only used by 'both' — always starts a fresh portrait page for the detail list.
  const addDetailPages = () => {
    doc.addPage('letter', 'portrait');
    const detailStart = doc.getNumberOfPages();
    renderDetail(doc, bundle, theme, ctx);
    numberDetailPages(doc, theme, detailStart);
  };

  if (mode === 'month' || mode === 'both') {
    renderMonth(doc, bundle, theme, { cap });
  }

  if (mode === 'month') {
    if (showVerseCal) addVerseCalPage();
    return doc;
  }

  if (mode === 'detail') {
    renderDetail(doc, bundle, theme, ctx);
    numberDetailPages(doc, theme, 1);
    return doc;
  }

  // mode === 'both'
  if (showVerseCal && verseOrder === 'verse-before-detail') {
    addVerseCalPage();
    addDetailPages();
  } else if (showVerseCal && verseOrder === 'verse-after-detail') {
    addDetailPages();
    addVerseCalPage();
  } else {
    addDetailPages();
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
