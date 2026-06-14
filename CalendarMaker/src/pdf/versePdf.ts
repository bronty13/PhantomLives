// Verse/saying calendar renderer: a second Letter-landscape grid page that shows
// ONLY the verse and saying items for each day, rendered with shrink-to-fit text.
// Used in "separate" verse mode so scripture/quotes get their own clean calendar
// alongside the main events calendar.

import type { jsPDF } from 'jspdf';
import type { CalendarBundle, Item, Theme } from '../model/types';
import { MONTH_NAMES, WEEKDAY_ABBR } from '../model/types';
import { computeWeeks, weekdayOrder } from '../calendar/grid';
import { CELL, monthGeometry } from './geometry';
import { setPdfFont } from '../data/fonts';
import { setDraw, setFill, setText } from './util';
import { drawShrinkText } from './monthPdf';

/** True if the bundle has any verse/saying items across its days. */
export function hasVerseOrSayingItems(bundle: CalendarBundle): boolean {
  for (const day of Object.values(bundle.days)) {
    if (day.items.some((it) => it.type === 'bibleVerse' || it.type === 'saying')) return true;
  }
  return false;
}

/** Render the verse/saying companion calendar page (assumes a fresh page is active). */
export function renderVerseCalendar(doc: jsPDF, bundle: CalendarBundle, theme: Theme): void {
  const grid = computeWeeks(bundle.year, bundle.month, bundle.weekStartsOn);
  const geo = monthGeometry(grid.weeks, false);

  // Page background.
  setFill(doc, theme.calendar.backgroundColor);
  doc.rect(0, 0, geo.pageW, geo.pageH, 'F');

  // Title band.
  setText(doc, theme.calendar.titleColor);
  setPdfFont(doc, theme.calendar.titleFont, true);
  doc.setFontSize(30);
  doc.text(`${MONTH_NAMES[bundle.month - 1]} ${bundle.year} — Scripture & Sayings`, geo.pageW / 2, geo.titleBand.y + 36, {
    align: 'center',
  });

  // Weekday header row.
  const order = weekdayOrder(bundle.weekStartsOn);
  setFill(doc, theme.calendar.headerBackground);
  doc.rect(geo.weekdayHeader.x, geo.weekdayHeader.y, geo.weekdayHeader.w, geo.weekdayHeader.h, 'F');
  setText(doc, theme.calendar.headerColor);
  setPdfFont(doc, theme.calendar.headerFont, true);
  doc.setFontSize(11);
  for (let c = 0; c < 7; c++) {
    const cx = geo.gridX + c * geo.colW + geo.colW / 2;
    doc.text(WEEKDAY_ABBR[order[c]], cx, geo.weekdayHeader.y + geo.weekdayHeader.h / 2 + 4, { align: 'center' });
  }

  // Grid cells.
  setDraw(doc, theme.calendar.gridLineColor);
  doc.setLineWidth(0.75);
  for (let i = 0; i < grid.cells.length; i++) {
    const r = Math.floor(i / 7);
    const c = i % 7;
    const x = geo.gridX + c * geo.colW;
    const y = geo.gridY + r * geo.rowH;
    doc.rect(x, y, geo.colW, geo.rowH);

    const cell = grid.cells[i];
    if (!cell.inMonth || cell.date == null) continue;

    // Day number.
    setText(doc, theme.calendar.dayNumberColor);
    setPdfFont(doc, theme.calendar.titleFont, true);
    doc.setFontSize(11);
    doc.text(String(cell.day), x + CELL.PAD, y + CELL.PAD + 9);

    const day = bundle.days[cell.date];
    if (!day) continue;

    const verseItems: Item[] = day.items
      .filter((it) => it.type === 'bibleVerse' || it.type === 'saying')
      .sort((a, b) => a.order - b.order);
    if (verseItems.length === 0) continue;

    // Each item gets an equal slice of the cell's content area, shrink-to-fit.
    const contentX = x + CELL.PAD;
    const contentY = y + CELL.PAD + CELL.DATE_LINE_H;
    const contentW = geo.colW - 2 * CELL.PAD;
    const contentH = geo.cellContentH;
    const perItemH = contentH / verseItems.length;

    let cursorY = contentY;
    for (const item of verseItems) {
      const style = theme.itemStyles[item.type];
      const italic = item.type === 'bibleVerse';
      const full = item.reference ? `${item.text}  — ${item.reference}` : item.text;
      // A larger max font here than the in-cell force block: this page is dedicated.
      drawShrinkText(doc, style.color, style.font, full, contentX, cursorY, contentW, perItemH, italic, 10, 5);
      cursorY += perItemH;
    }
  }
}
