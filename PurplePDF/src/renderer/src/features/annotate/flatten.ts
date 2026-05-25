/**
 * @file flatten.ts — canonical pipeline that converts the renderer's
 * in-memory annotation + page-op stack into bytes on save.
 *
 * Known limitation (1.0.0): annotations are keyed by **original** 0-based
 * page index (`Annot.pageIndex`). When a page is duplicated, both the
 * source slot and the duplicate slot point at the same source idx, so
 * annotations added against a duplicate slot will also appear on the
 * source on save. Likewise, `PageOp.move`/`PageOp.rotate` identify by
 * source idx so dragging a *duplicate* in the thumbnail rail may move
 * the original. Tracked for the 1.1.0 "slot-id refactor" in
 * docs/ROADMAP.md.
 */
import { PDFDocument, PDFName, PDFString, rgb, StandardFonts, degrees } from 'pdf-lib';
import type { Annot } from './types';
import { hexToRgb01 } from './types';
import type { FormValues } from '../forms/types';

export interface PageOp {
  kind: 'delete' | 'rotate' | 'insert-blank' | 'duplicate' | 'move' | 'crop';
  page: number; // 0-based source index
  /** For 'rotate': degrees clockwise to add (90/180/270). */
  degrees?: number;
  /** For 'move': absolute target insertion index in the current ordering (0..N). */
  to?: number;
  /** For 'crop': new crop box in PDF point units, page-relative (origin bottom-left). */
  crop?: { x: number; y: number; width: number; height: number };
}

export interface DocumentProperties {
  title?: string;
  author?: string;
  subject?: string;
  keywords?: string[];
  language?: string;
}

export interface BuildOptions {
  /** When true, clear standard document metadata fields. */
  stripMetadata?: boolean;
  /** When provided, write these properties into the document info dictionary. */
  properties?: DocumentProperties;
}

export async function buildModifiedPdf(
  original: ArrayBuffer,
  annotsByPage: Map<number, Annot[]>,
  pageOps: PageOp[],
  formValues?: FormValues,
  options?: BuildOptions
): Promise<Uint8Array> {
  const doc = await PDFDocument.load(original, { updateMetadata: false });
  const font = await doc.embedFont(StandardFonts.Helvetica);
  const fontBold = await doc.embedFont(StandardFonts.HelveticaBold);
  const fontOblique = await doc.embedFont(StandardFonts.HelveticaOblique);
  const fontBoldOblique = await doc.embedFont(StandardFonts.HelveticaBoldOblique);

  // Cache PNG/JPEG embeds per byte-array reference so multi-page images
  // (signatures and inserted images) reuse one image XObject.
  const pngCache = new Map<Uint8Array, import('pdf-lib').PDFImage>();
  const jpgCache = new Map<Uint8Array, import('pdf-lib').PDFImage>();
  const embedSignaturePng = async (
    bytes: Uint8Array
  ): Promise<import('pdf-lib').PDFImage> => {
    const cached = pngCache.get(bytes);
    if (cached) return cached;
    const img = await doc.embedPng(bytes);
    pngCache.set(bytes, img);
    return img;
  };
  const embedImageBytes = async (
    bytes: Uint8Array,
    mime: 'image/png' | 'image/jpeg'
  ): Promise<import('pdf-lib').PDFImage> => {
    if (mime === 'image/jpeg') {
      const cached = jpgCache.get(bytes);
      if (cached) return cached;
      const img = await doc.embedJpg(bytes);
      jpgCache.set(bytes, img);
      return img;
    }
    return await embedSignaturePng(bytes);
  };

  // 0) Apply form values to AcroForm fields (best-effort; skips unknown fields).
  if (formValues && Object.keys(formValues).length > 0) {
    try {
      const form = doc.getForm();
      const fields = form.getFields();
      const byName = new Map<string, ReturnType<typeof form.getFields>[number]>();
      for (const f of fields) byName.set(f.getName(), f);
      for (const [name, value] of Object.entries(formValues)) {
        const field = byName.get(name);
        if (!field) continue;
        const ctor = field.constructor.name;
        try {
          if (ctor === 'PDFTextField') {
            (field as unknown as { setText: (v: string) => void }).setText(
              typeof value === 'string' ? value : ''
            );
          } else if (ctor === 'PDFCheckBox') {
            if (value === true || value === 'true' || value === 'Yes') {
              (field as unknown as { check: () => void }).check();
            } else {
              (field as unknown as { uncheck: () => void }).uncheck();
            }
          } else if (ctor === 'PDFRadioGroup') {
            if (typeof value === 'string' && value)
              (field as unknown as { select: (v: string) => void }).select(value);
          } else if (ctor === 'PDFDropdown' || ctor === 'PDFOptionList') {
            if (typeof value === 'string' && value)
              (field as unknown as { select: (v: string) => void }).select(value);
          }
        } catch {
          // Skip fields that fail to set (e.g. value not in allowed list).
        }
      }
    } catch {
      // No AcroForm in this PDF — silently ignore.
    }
  }

  // 1) Flatten annotations onto each page using ORIGINAL page indices
  //    (before page ops shift things around).
  const pages = doc.getPages();
  for (const [pageIndex, annots] of annotsByPage.entries()) {
    if (pageIndex < 0 || pageIndex >= pages.length) continue;
    const page = pages[pageIndex];
    for (const a of annots) {
      if (a.kind === 'signature') {
        try {
          const img = await embedSignaturePng(a.pngBytes);
          page.drawImage(img, { x: a.x, y: a.y, width: a.w, height: a.h });
        } catch {
          // Bad PNG; skip rather than abort the whole save.
        }
      } else if (a.kind === 'image') {
        try {
          const img = await embedImageBytes(a.bytes, a.mime);
          page.drawImage(img, { x: a.x, y: a.y, width: a.w, height: a.h });
          if (a.subtext && a.subtext.trim()) {
            drawImageCaption(page, a, a.subtext, fontOblique);
          }
        } catch {
          // Bad image bytes; skip rather than abort the whole save.
        }
      } else {
        drawAnnotation(page, a, font, fontBold, fontOblique, fontBoldOblique);
      }
    }
  }

  // 2) Apply page ops while tracking index shifts.
  const indexMap = new Map<number, number>();
  for (let i = 0; i < pages.length; i++) indexMap.set(i, i);

  for (const op of pageOps) {
    const current = indexMap.get(op.page);
    if (current === undefined || current < 0) continue;
    if (op.kind === 'rotate') {
      const p = doc.getPage(current);
      const cur = p.getRotation().angle;
      p.setRotation(degrees((cur + (op.degrees ?? 90)) % 360));
    } else if (op.kind === 'delete') {
      doc.removePage(current);
      indexMap.set(op.page, -1);
      for (const [k, v] of indexMap) if (v > current) indexMap.set(k, v - 1);
    } else if (op.kind === 'insert-blank') {
      const p = doc.getPage(current);
      const { width, height } = p.getSize();
      doc.insertPage(current + 1, [width, height]);
      for (const [k, v] of indexMap) if (v > current) indexMap.set(k, v + 1);
    } else if (op.kind === 'duplicate') {
      const [copied] = await doc.copyPages(doc, [current]);
      doc.insertPage(current + 1, copied);
      for (const [k, v] of indexMap) if (v > current) indexMap.set(k, v + 1);
    } else if (op.kind === 'move') {
      const target = op.to ?? current;
      if (target === current || target === current + 1) {
        // Drop where it already is — no-op.
        continue;
      }
      const [copied] = await doc.copyPages(doc, [current]);
      doc.insertPage(target, copied);
      // Insert shifts pages with index >= target up by 1.
      for (const [k, v] of indexMap) if (v >= target) indexMap.set(k, v + 1);
      // Where is the original now?
      const removeIdx = current >= target ? current + 1 : current;
      doc.removePage(removeIdx);
      // Compute the final landing index of the moved page (the inserted copy):
      const landed = current >= target ? target : target - 1;
      for (const [k, v] of indexMap) {
        if (v === removeIdx) indexMap.set(k, landed);
        else if (v > removeIdx) indexMap.set(k, v - 1);
      }
    } else if (op.kind === 'crop' && op.crop) {
      const p = doc.getPage(current);
      p.setCropBox(op.crop.x, op.crop.y, op.crop.width, op.crop.height);
    }
  }

  // 3) Optional metadata strip — clears standard document info fields.
  if (options?.stripMetadata) {
    try {
      doc.setTitle('');
      doc.setAuthor('');
      doc.setSubject('');
      doc.setKeywords([]);
      doc.setProducer('');
      doc.setCreator('');
      const epoch = new Date(0);
      doc.setCreationDate(epoch);
      doc.setModificationDate(epoch);
    } catch {
      // Some PDFs throw on certain setters; best-effort.
    }
  }

  // 4) Optional explicit metadata write. Includes language via the catalog
  //    /Lang entry (used by screen readers for pronunciation).
  if (options?.properties) {
    try {
      const p = options.properties;
      if (p.title !== undefined) doc.setTitle(p.title);
      if (p.author !== undefined) doc.setAuthor(p.author);
      if (p.subject !== undefined) doc.setSubject(p.subject);
      if (p.keywords !== undefined) doc.setKeywords(p.keywords);
      if (p.language !== undefined && p.language) {
        try {
          (doc as unknown as { setLanguage: (l: string) => void }).setLanguage(p.language);
        } catch {
          // Older pdf-lib lacks setLanguage; fall back to direct catalog write.
          const cat = (doc as unknown as {
            catalog: { set: (key: unknown, value: unknown) => void };
          }).catalog;
          cat.set(PDFName.of('Lang'), PDFString.of(p.language));
        }
      }
    } catch {
      // best-effort
    }
  }

  return doc.save();
}

// pdf-lib's PDFPage typing is fine — we just don't need the full surface.
type Page = import('pdf-lib').PDFPage;
type Font = import('pdf-lib').PDFFont;

function drawAnnotation(
  page: Page,
  a: Annot,
  font: Font,
  fontBold: Font,
  fontOblique: Font,
  fontBoldOblique: Font
): void {
  const c = hexToRgb01(a.color);
  const colorRGB = rgb(c.r, c.g, c.b);

  if (a.kind === 'highlight') {
    const op = Math.max(0.2, Math.min(0.8, 0.2 + ((a.strokeWidth ?? 2) / 16) * 0.6));
    for (const r of a.rects) {
      page.drawRectangle({
        x: r.x,
        y: r.y,
        width: r.w,
        height: r.h,
        color: colorRGB,
        opacity: op
      });
    }
    return;
  }
  if (a.kind === 'underline') {
    const t = a.strokeWidth ?? 1.2;
    for (const r of a.rects) {
      page.drawLine({
        start: { x: r.x, y: r.y },
        end: { x: r.x + r.w, y: r.y },
        thickness: t,
        color: colorRGB
      });
    }
    return;
  }
  if (a.kind === 'strikethrough') {
    const t = a.strokeWidth ?? 1.2;
    for (const r of a.rects) {
      const y = r.y + r.h / 2;
      page.drawLine({
        start: { x: r.x, y },
        end: { x: r.x + r.w, y },
        thickness: t,
        color: colorRGB
      });
    }
    return;
  }
  if (a.kind === 'note') {
    const size = 14;
    page.drawRectangle({
      x: a.x,
      y: a.y,
      width: size,
      height: size,
      color: colorRGB,
      opacity: 0.9,
      borderColor: rgb(0, 0, 0),
      borderWidth: 0.5
    });
    if (a.text) {
      page.drawText(a.text, {
        x: a.x + size + 4,
        y: a.y + 2,
        size: 9,
        font,
        color: rgb(0, 0, 0),
        maxWidth: 200
      });
    }
    return;
  }
  if (a.kind === 'freehand') {
    if (a.points.length < 2) return;
    let d = `M ${a.points[0].x} ${a.points[0].y}`;
    for (let i = 1; i < a.points.length; i++) {
      d += ` L ${a.points[i].x} ${a.points[i].y}`;
    }
    page.drawSvgPath(d, {
      borderColor: colorRGB,
      borderWidth: a.width
    });
    return;
  }
  if (a.kind === 'rect') {
    page.drawRectangle({
      x: a.x,
      y: a.y,
      width: a.w,
      height: a.h,
      borderColor: colorRGB,
      borderWidth: a.strokeWidth,
      opacity: 0,
      borderOpacity: 1
    });
    return;
  }
  if (a.kind === 'textbox') {
    if (!a.text) return;
    page.drawText(a.text, {
      x: a.x + 2,
      y: a.y + a.h - a.fontSize - 2,
      size: a.fontSize,
      font,
      color: colorRGB,
      maxWidth: a.w - 4,
      lineHeight: a.fontSize * 1.2
    });
    return;
  }
  if (a.kind === 'redact') {
    // Fully opaque black rectangle covering the underlying area. Note:
    // this is a VISUAL blackout — the original content stream is not stripped.
    page.drawRectangle({
      x: a.x,
      y: a.y,
      width: a.w,
      height: a.h,
      color: rgb(0, 0, 0),
      opacity: 1
    });
    return;
  }
  if (a.kind === 'stamp') {
    const bc = hexToRgb01(a.borderColor);
    const borderRGB = rgb(bc.r, bc.g, bc.b);
    if (a.style === 'mark') {
      // Single glyph (✓ / ✗): center it inside the bounding box, no border.
      const size = Math.min(a.w, a.h) * 0.9;
      const tw = fontBold.widthOfTextAtSize(a.label, size);
      const th = fontBold.heightAtSize(size);
      page.drawText(a.label, {
        x: a.x + (a.w - tw) / 2,
        y: a.y + (a.h - th) / 2 + th * 0.15,
        size,
        font: fontBold,
        color: borderRGB
      });
      return;
    }
    // Rect-style stamp: tinted fill + single border + italic bold label,
    // optional italic subtitle line ("By Robert Olen at 6:36 pm, May 21, 2026").
    page.drawRectangle({
      x: a.x,
      y: a.y,
      width: a.w,
      height: a.h,
      color: borderRGB,
      opacity: 0.14,
      borderColor: borderRGB,
      borderWidth: 1.25,
      borderOpacity: 1
    });
    const padX = 10;
    const hasSub = !!(a.subtext && a.subtext.trim());
    // Fit the label within (w - 2*padX) at a reasonable size.
    const targetLabelW = Math.max(10, a.w - padX * 2);
    let labelSize = hasSub ? Math.min(a.h * 0.40, 22) : Math.min(a.h * 0.55, 26);
    while (labelSize > 6 && fontBoldOblique.widthOfTextAtSize(a.label, labelSize) > targetLabelW) {
      labelSize -= 1;
    }
    const labelH = fontBoldOblique.heightAtSize(labelSize);
    // PDF Y axis is up: position label near the top of the box (or vertically centered when no subtext).
    const labelY = hasSub
      ? a.y + a.h - labelH - a.h * 0.12
      : a.y + (a.h - labelH) / 2 + labelH * 0.18;
    page.drawText(a.label, {
      x: a.x + padX,
      y: labelY,
      size: labelSize,
      font: fontBoldOblique,
      color: borderRGB
    });
    if (hasSub) {
      const subSize = Math.max(6, Math.min(a.h * 0.22, 13));
      // Auto-shrink subtext to fit width.
      let sSize = subSize;
      const sub = a.subtext!;
      while (sSize > 5 && fontOblique.widthOfTextAtSize(sub, sSize) > targetLabelW) {
        sSize -= 0.5;
      }
      page.drawText(sub, {
        x: a.x + padX,
        y: a.y + a.h * 0.16,
        size: sSize,
        font: fontOblique,
        color: borderRGB
      });
    }
    return;
  }
  // 'signature' and 'image' are handled separately in the caller because
  // they require async embedPng/embedJpg.
}

/** Draw the frozen caption band along an image annotation's bottom edge —
 *  white italic text on a translucent dark strip, mirroring the on-screen
 *  overlay in AnnotationLayer. The caption auto-shrinks to fit the width. */
function drawImageCaption(page: Page, a: { x: number; y: number; w: number; h: number }, sub: string, fontOblique: Font): void {
  const bandH = Math.max(10, Math.min(a.h * 0.18, 18));
  const padX = 6;
  const maxW = Math.max(8, a.w - padX * 2);
  let size = bandH * 0.66;
  while (size > 5 && fontOblique.widthOfTextAtSize(sub, size) > maxW) {
    size -= 0.5;
  }
  // Translucent backing strip flush with the image's bottom edge.
  page.drawRectangle({
    x: a.x,
    y: a.y,
    width: a.w,
    height: bandH,
    color: rgb(0, 0, 0),
    opacity: 0.55,
    borderWidth: 0
  });
  const textW = fontOblique.widthOfTextAtSize(sub, size);
  const textH = fontOblique.heightAtSize(size);
  page.drawText(sub, {
    x: a.x + Math.max(padX, (a.w - textW) / 2),
    y: a.y + (bandH - textH) / 2 + textH * 0.18,
    size,
    font: fontOblique,
    color: rgb(1, 1, 1)
  });
}
