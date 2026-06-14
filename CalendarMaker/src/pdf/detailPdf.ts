// Detail-view renderer: a Letter-portrait, date-ordered list across multiple
// pages, with a repeated header and page numbers. Shows ALL items; items demoted
// off the month grid are marked with a vector "⊘" (circle-with-slash) in the
// theme's overflow color.

import type { jsPDF } from 'jspdf';
import type { CalendarBundle, ItemType, Theme } from '../model/types';
import { ITEM_TYPE_LABELS, MONTH_NAMES } from '../model/types';
import type { FitContext } from '../calendar/fit';
import { buildDetailSections } from '../calendar/detail';
import { LETTER_PORTRAIT } from './geometry';
import { setPdfFont } from '../data/fonts';
import { setDraw, setFill, setText } from './util';
import { holidayNamesFor } from './holidayNames';

export function renderDetail(doc: jsPDF, bundle: CalendarBundle, theme: Theme, ctx: FitContext): void {
  const L = LETTER_PORTRAIT;
  const contentW = L.PAGE_W - 2 * L.MARGIN;
  const contentBottom = L.PAGE_H - L.MARGIN - L.FOOTER_H;
  const sections = buildDetailSections(bundle, ctx, (date) => holidayNamesFor(bundle.days[date]));

  const drawBg = () => {
    setFill(doc, theme.calendar.backgroundColor);
    doc.rect(0, 0, L.PAGE_W, L.PAGE_H, 'F');
  };
  const drawHeader = () => {
    setFill(doc, theme.calendar.headerBackground);
    doc.rect(0, 0, L.PAGE_W, L.MARGIN + L.HEADER_H - 10, 'F');
    setText(doc, theme.calendar.headerColor);
    setPdfFont(doc, theme.calendar.titleFont, true);
    doc.setFontSize(18);
    doc.text(`${MONTH_NAMES[bundle.month - 1]} ${bundle.year}`, L.MARGIN, L.MARGIN + 14);
    setPdfFont(doc, theme.calendar.headerFont, false);
    doc.setFontSize(11);
    doc.text('Details', L.PAGE_W - L.MARGIN, L.MARGIN + 14, { align: 'right' });
  };

  drawBg();
  drawHeader();
  let y = L.MARGIN + L.HEADER_H + 8;

  const pageBreak = () => {
    doc.addPage('letter', 'portrait');
    drawBg();
    drawHeader();
    y = L.MARGIN + L.HEADER_H + 8;
  };

  if (sections.length === 0) {
    setText(doc, theme.overflowColor);
    setPdfFont(doc, theme.calendar.fillerFont, false);
    doc.setFontSize(12);
    doc.text('No holidays or events this month.', L.MARGIN, y + 12);
  }

  for (const sec of sections) {
    // Keep the heading with at least its first line on the same page.
    if (y + 30 > contentBottom) pageBreak();

    // Date heading.
    setText(doc, theme.calendar.titleColor);
    setPdfFont(doc, theme.calendar.titleFont, true);
    doc.setFontSize(13);
    doc.text(`${sec.weekdayName}, ${MONTH_NAMES[bundle.month - 1]} ${sec.dayNum}`, L.MARGIN, y);
    y += 5;
    setDraw(doc, theme.calendar.gridLineColor);
    doc.setLineWidth(0.5);
    doc.line(L.MARGIN, y, L.MARGIN + contentW, y);
    y += 12;

    // Holiday lines.
    for (const name of sec.holidayNames) {
      if (y > contentBottom) pageBreak();
      setText(doc, theme.calendar.holidayColor);
      setPdfFont(doc, theme.calendar.holidayFont, true);
      doc.setFontSize(10);
      doc.text(`Holiday: ${name}`, L.MARGIN + 8, y);
      y += 14;
    }

    // Items.
    for (const { item, detailOnly } of sec.lines) {
      const style = theme.itemStyles[item.type];
      setPdfFont(doc, style.font, false);
      doc.setFontSize(10.5);
      const label = `${ITEM_TYPE_LABELS[item.type as ItemType]}: `;
      const indent = L.MARGIN + 8 + 10;
      // Verses/sayings carry a reference (e.g. "John 3:16") — append it inline.
      const body = item.reference ? `${item.text}  — ${item.reference}` : item.text;
      const lines = doc.splitTextToSize(label + body, contentW - 8 - 10) as string[];

      for (let li = 0; li < lines.length; li++) {
        if (y > contentBottom) pageBreak();
        if (li === 0) {
          if (detailOnly) {
            drawNoSymbol(doc, L.MARGIN + 8 + 3.2, y - 3, 3.2, theme.overflowColor);
          } else {
            setFill(doc, style.color);
            doc.circle(L.MARGIN + 8 + 3.2, y - 3, 1.9, 'F');
          }
        }
        setText(doc, detailOnly ? theme.overflowColor : style.color);
        doc.text(lines[li], indent, y);
        y += 14;
      }
    }
    y += 8;
  }
}

/** Vector circle-with-slash marker (font-independent). */
function drawNoSymbol(doc: jsPDF, cx: number, cy: number, r: number, color: string): void {
  setDraw(doc, color);
  doc.setLineWidth(0.9);
  doc.circle(cx, cy, r);
  const d = r * 0.72;
  doc.line(cx - d, cy + d, cx + d, cy - d);
}
