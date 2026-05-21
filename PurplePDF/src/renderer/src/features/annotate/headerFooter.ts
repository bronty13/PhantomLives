import { PDFDocument, StandardFonts, rgb } from 'pdf-lib';
import { embedUnicodeFont } from '../text/unicodeFont';

export interface StampOptions {
  header?: string;
  footer?: string;
  bates?: { prefix: string; start: number; digits: number };
  fontSize?: number;
  margin?: number;
}

/**
 * Stamp header text (top center), footer text (bottom center), and optional
 * Bates numbers (bottom right) on every page of `bytes`. Supports tokens in
 * header/footer strings: {page} {total} {date} {bates}.
 */
export async function applyHeaderFooter(
  bytes: Uint8Array,
  opts: StampOptions
): Promise<Uint8Array> {
  const doc = await PDFDocument.load(bytes);
  const fallback = await doc.embedFont(StandardFonts.Helvetica);
  const font = await embedUnicodeFont(doc, { fallback });
  const pages = doc.getPages();
  const total = pages.length;
  const size = opts.fontSize ?? 10;
  const margin = opts.margin ?? 24;
  const today = new Date().toLocaleDateString();
  const digits = opts.bates?.digits ?? 6;
  for (let i = 0; i < total; i++) {
    const page = pages[i];
    const { width, height } = page.getSize();
    const bates = opts.bates
      ? `${opts.bates.prefix}${String(opts.bates.start + i).padStart(digits, '0')}`
      : '';
    const expand = (s: string): string =>
      s
        .replaceAll('{page}', String(i + 1))
        .replaceAll('{total}', String(total))
        .replaceAll('{date}', today)
        .replaceAll('{bates}', bates);
    if (opts.header) {
      const text = expand(opts.header);
      const tw = font.widthOfTextAtSize(text, size);
      page.drawText(text, {
        x: (width - tw) / 2,
        y: height - margin,
        size,
        font,
        color: rgb(0, 0, 0)
      });
    }
    if (opts.footer) {
      const text = expand(opts.footer);
      const tw = font.widthOfTextAtSize(text, size);
      page.drawText(text, {
        x: (width - tw) / 2,
        y: margin - size,
        size,
        font,
        color: rgb(0, 0, 0)
      });
    }
    if (opts.bates) {
      const tw = font.widthOfTextAtSize(bates, size);
      page.drawText(bates, {
        x: width - margin - tw,
        y: margin - size,
        size,
        font,
        color: rgb(0, 0, 0)
      });
    }
  }
  return await doc.save();
}
