// Month-view renderer: a Letter-landscape calendar grid drawn with vector jsPDF.
// Only month-visible items are drawn (classifyDay decides), so a cell can never
// overflow. Fillers (sayings/verses) fill the grid's free space and/or footer.

import type { jsPDF } from 'jspdf';
import type { CalendarBundle, Day, Theme } from '../model/types';
import { MONTH_NAMES, WEEKDAY_ABBR } from '../model/types';
import { computeWeeks, largestBlankRun, weekdayOrder } from '../calendar/grid';
import { classifyDay, type FitContext } from '../calendar/fit';
import { wrapLines } from '../calendar/measure';
import { CELL, monthGeometry } from './geometry';
import { setPdfFont } from '../data/fonts';
import { ellipsize, setDraw, setFill, setText } from './util';
import { holidayNamesFor } from './holidayNames';

export interface MonthRenderOpts {
  cap: number;
}

/** True if an item is a verse or saying (force-mode-eligible). */
function isVerseOrSaying(type: string): boolean {
  return type === 'bibleVerse' || type === 'saying';
}

export function renderMonth(doc: jsPDF, bundle: CalendarBundle, theme: Theme, opts: MonthRenderOpts): void {
  const grid = computeWeeks(bundle.year, bundle.month, bundle.weekStartsOn);
  const footerFiller = bundle.fillers.find((f) => f.slot === 'footer');
  const gridFiller = bundle.fillers.find((f) => f.slot === 'grid');
  const geo = monthGeometry(grid.weeks, !!footerFiller);
  const ctx: FitContext = { geo, theme, cap: opts.cap };

  // Page background.
  setFill(doc, theme.calendar.backgroundColor);
  doc.rect(0, 0, geo.pageW, geo.pageH, 'F');

  // Title band.
  setText(doc, theme.calendar.titleColor);
  setPdfFont(doc, theme.calendar.titleFont, true);
  doc.setFontSize(30);
  doc.text(`${MONTH_NAMES[bundle.month - 1]} ${bundle.year}`, geo.pageW / 2, geo.titleBand.y + 36, { align: 'center' });

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
    const holidayNames = holidayNamesFor(day);
    let cursorY = y + CELL.PAD + CELL.DATE_LINE_H;

    // Holiday lines.
    if (holidayNames.length) {
      setText(doc, theme.calendar.holidayColor);
      setPdfFont(doc, theme.calendar.holidayFont, false);
      doc.setFontSize(CELL.HOLIDAY_FONT);
      for (const name of holidayNames) {
        doc.text(ellipsize(doc, name, geo.colW - 2 * CELL.PAD), x + CELL.PAD, cursorY + CELL.HOLIDAY_FONT);
        cursorY += CELL.HOLIDAY_LINE_H;
      }
    }

    if (!day || day.items.length === 0) continue;

    const verseMode = bundle.verseMode ?? 'separate';

    // In separate mode, verse/saying items live on the dedicated verse page —
    // exclude them from the month grid so the main calendar stays uncluttered.
    const gridDay: Day =
      verseMode === 'separate'
        ? { ...day, items: day.items.filter((it) => !isVerseOrSaying(it.type)) }
        : day;

    const { monthItems, forceItems, detailOnly } = classifyDay(gridDay, ctx, holidayNames.length, verseMode);
    const forceIds = new Set(forceItems.map((i) => i.id));
    const suppressDots = verseMode === 'force' && forceItems.length > 0;

    // Force-mode verse/saying block (shrink-to-fit, italic for verses) at the top.
    if (verseMode === 'force' && forceItems.length > 0) {
      const cellContentW = geo.colW - 2 * CELL.PAD;
      const forceBlockH = Math.min(forceItems.length * CELL.CHIP_LINE_H * 3, geo.cellContentH * 0.5);
      const perItemH = forceBlockH / forceItems.length;
      for (const item of forceItems) {
        const style = theme.itemStyles[item.type];
        const italic = item.type === 'bibleVerse';
        const full = item.reference ? `${item.text}  — ${item.reference}` : item.text;
        drawShrinkText(doc, style.color, style.font, full, x + CELL.PAD, cursorY, cellContentW, perItemH, italic);
        cursorY += perItemH;
      }
    }

    // Item chips (non-force items).
    for (const item of monthItems) {
      if (forceIds.has(item.id)) continue; // already drawn in the force block
      const style = theme.itemStyles[item.type];
      const lines = wrapLines(item.text, style.font, CELL.CHIP_FONT, geo.cellContentW).slice(0, CELL.CHIP_MAX_LINES);
      // colored type swatch (suppressed in force mode for a cleaner look)
      if (!suppressDots) {
        setFill(doc, style.color);
        doc.circle(x + CELL.PAD + 1.8, cursorY + CELL.CHIP_FONT - 2.4, 1.7, 'F');
      }
      // chip text
      setText(doc, style.color);
      setPdfFont(doc, style.font, false);
      doc.setFontSize(CELL.CHIP_FONT);
      const textX = suppressDots ? x + CELL.PAD : x + CELL.PAD + CELL.BULLET_W;
      let ly = cursorY + CELL.CHIP_FONT - 1;
      for (const line of lines) {
        doc.text(line, textX, ly);
        ly += CELL.CHIP_LINE_H;
      }
      cursorY += lines.length * CELL.CHIP_LINE_H + CELL.CHIP_GAP;
    }

    // "+N more" overflow indicator.
    if (detailOnly.length > 0) {
      setText(doc, theme.overflowColor);
      setPdfFont(doc, theme.calendar.headerFont, false);
      doc.setFontSize(CELL.MORE_FONT);
      doc.text(`+${detailOnly.length} more (detail)`, x + CELL.PAD, cursorY + CELL.MORE_FONT - 1);
    }
  }

  // Grid free-space filler (saying / verse) in the largest blank run.
  if (gridFiller) {
    const run = largestBlankRun(grid);
    if (run && run.count >= 1) {
      const startR = Math.floor(run.start / 7);
      const startC = run.start % 7;
      // Only fill within a single row's contiguous run to keep the rectangle clean.
      const sameRowCount = Math.min(run.count, 7 - startC);
      const fx = geo.gridX + startC * geo.colW + 6;
      const fy = geo.gridY + startR * geo.rowH + 4;
      const fw = sameRowCount * geo.colW - 12;
      const fh = geo.rowH - 8;
      drawFiller(doc, theme, gridFiller.entry.text, gridFiller.entry.reference, fx, fy, fw, fh);
    }
  }

  // Footer band filler.
  if (footerFiller && geo.footerBand) {
    drawFiller(
      doc,
      theme,
      footerFiller.entry.text,
      footerFiller.entry.reference,
      geo.footerBand.x + 12,
      geo.footerBand.y + 2,
      geo.footerBand.w - 24,
      geo.footerBand.h - 4,
    );
  }
}

/** Shrink-to-fit a saying/verse into a rectangle, centered. */
function drawFiller(
  doc: jsPDF,
  theme: Theme,
  text: string,
  reference: string | undefined,
  x: number,
  y: number,
  w: number,
  h: number,
): void {
  setText(doc, theme.calendar.fillerColor);
  setPdfFont(doc, theme.calendar.fillerFont, false);
  const full = reference ? `${text}  — ${reference}` : text;
  let size = 13;
  let lines: string[] = [];
  for (; size >= 6; size--) {
    doc.setFontSize(size);
    lines = doc.splitTextToSize(full, w) as string[];
    if (lines.length * size * 1.2 <= h) break;
  }
  doc.setFontSize(size);
  const totalH = lines.length * size * 1.2;
  let ly = y + (h - totalH) / 2 + size;
  for (const line of lines) {
    doc.text(line, x + w / 2, ly, { align: 'center' });
    ly += size * 1.2;
  }
}

/**
 * Shrink-to-fit text into a left-aligned rectangle, top-anchored. Used for the
 * force-mode verse/saying block inside a day cell. Embedded fonts ship only
 * normal/bold faces, so the `italic` flag is a visual cue in the preview only —
 * here we render normal weight (kept in the signature for API symmetry).
 * Exported for reuse by the verse calendar page.
 */
export function drawShrinkText(
  doc: jsPDF,
  color: string,
  font: string,
  text: string,
  x: number,
  y: number,
  w: number,
  h: number,
  _italic = false,
  maxSize = 8,
  minSize = 5,
): void {
  setText(doc, color);
  setPdfFont(doc, font, false);
  let size = maxSize;
  let lines: string[] = [];
  for (; size >= minSize; size--) {
    doc.setFontSize(size);
    lines = doc.splitTextToSize(text, w) as string[];
    if (lines.length * size * 1.15 <= h) break;
  }
  doc.setFontSize(size);
  let ly = y + size;
  for (const line of lines) {
    if (ly > y + h) break; // clip to the reserved rectangle
    doc.text(line, x, ly);
    ly += size * 1.15;
  }
}

/** Shrink-to-fit, centered (exported wrapper for the verse calendar page). */
export function drawFillerPublic(
  doc: jsPDF,
  theme: Theme,
  text: string,
  reference: string | undefined,
  x: number,
  y: number,
  w: number,
  h: number,
): void {
  drawFiller(doc, theme, text, reference, x, y, w, h);
}
