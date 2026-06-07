// Page + grid geometry in PDF points (1pt = 1/72"). These constants are shared by
// the on-screen preview and the jsPDF renderer so the preview is truly WYSIWYG.

export const LETTER_LANDSCAPE = {
  PAGE_W: 792,
  PAGE_H: 612,
  MARGIN: 36,
  TITLE_BAND_H: 54,
  WEEKDAY_HEADER_H: 22,
  FOOTER_BAND_H: 30,
};

export const LETTER_PORTRAIT = {
  PAGE_W: 612,
  PAGE_H: 792,
  MARGIN: 48,
  HEADER_H: 46,
  FOOTER_H: 28,
};

// Month-cell typography (fixed sizes — theme controls font family + color, not
// size, for grid chips; this keeps the fit calculation deterministic and prevents
// any single item from blowing out a cell).
export const CELL = {
  PAD: 4,
  DATE_LINE_H: 13,
  HOLIDAY_FONT: 7,
  HOLIDAY_LINE_H: 9,
  CHIP_FONT: 7.5,
  CHIP_LINE_H: 9,
  CHIP_GAP: 1.5,
  CHIP_MAX_LINES: 2, // a chip wrapping beyond this is detail-only
  BULLET_W: 6, // colored type swatch + gap before chip text
  MORE_FONT: 6.5,
  MORE_LINE_H: 8,
};

export interface MonthGeometry {
  pageW: number;
  pageH: number;
  margin: number;
  titleBand: { x: number; y: number; w: number; h: number };
  weekdayHeader: { x: number; y: number; w: number; h: number };
  footerBand: { x: number; y: number; w: number; h: number } | null;
  gridX: number;
  gridY: number;
  gridW: number;
  gridH: number;
  colW: number;
  rowH: number;
  weeks: number;
  /** Vertical space inside a cell available for chips (below the date row). */
  cellContentH: number;
  /** Horizontal space for chip text (inside padding, after the bullet). */
  cellContentW: number;
}

export function monthGeometry(weeks: number, hasFooter: boolean): MonthGeometry {
  const L = LETTER_LANDSCAPE;
  const footerH = hasFooter ? L.FOOTER_BAND_H : 0;
  const gridX = L.MARGIN;
  const gridY = L.MARGIN + L.TITLE_BAND_H + L.WEEKDAY_HEADER_H;
  const gridW = L.PAGE_W - 2 * L.MARGIN;
  const gridH = L.PAGE_H - gridY - L.MARGIN - footerH;
  const colW = gridW / 7;
  const rowH = gridH / weeks;
  return {
    pageW: L.PAGE_W,
    pageH: L.PAGE_H,
    margin: L.MARGIN,
    titleBand: { x: L.MARGIN, y: L.MARGIN, w: gridW, h: L.TITLE_BAND_H },
    weekdayHeader: { x: gridX, y: L.MARGIN + L.TITLE_BAND_H, w: gridW, h: L.WEEKDAY_HEADER_H },
    footerBand: hasFooter ? { x: L.MARGIN, y: L.PAGE_H - L.MARGIN - footerH, w: gridW, h: footerH } : null,
    gridX,
    gridY,
    gridW,
    gridH,
    colW,
    rowH,
    weeks,
    cellContentH: rowH - 2 * CELL.PAD - CELL.DATE_LINE_H,
    cellContentW: colW - 2 * CELL.PAD - CELL.BULLET_W,
  };
}
