// Text measurement via a singleton headless jsPDF using the SAME embedded fonts
// the export will use. This is what lets the editor's live overflow check and the
// PDF renderer agree exactly on whether an item fits a cell.

import { jsPDF } from 'jspdf';
import type { FontKey } from '../model/types';
import { cssFamily, registerFontsInDoc } from '../data/fonts';

let measureDoc: jsPDF | null = null;

export function getMeasureDoc(): jsPDF {
  if (!measureDoc) {
    measureDoc = new jsPDF({ unit: 'pt', format: 'letter', orientation: 'landscape' });
    registerFontsInDoc(measureDoc);
  }
  return measureDoc;
}

/** Wrap `text` to `maxWidth` (points) at the given font/size; returns the lines. */
export function wrapLines(text: string, fontKey: FontKey, sizePt: number, maxWidth: number, bold = false): string[] {
  const doc = getMeasureDoc();
  doc.setFont(cssFamily(fontKey), bold ? 'bold' : 'normal');
  doc.setFontSize(sizePt);
  const t = (text ?? '').trim();
  if (!t) return [];
  return doc.splitTextToSize(t, Math.max(1, maxWidth)) as string[];
}

/** Width of a single string at a font/size, in points. */
export function textWidth(text: string, fontKey: FontKey, sizePt: number, bold = false): number {
  const doc = getMeasureDoc();
  doc.setFont(cssFamily(fontKey), bold ? 'bold' : 'normal');
  doc.setFontSize(sizePt);
  return doc.getTextWidth(text ?? '');
}
