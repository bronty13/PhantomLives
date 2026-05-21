import { PDFDocument, StandardFonts, degrees, rgb } from 'pdf-lib';
import { embedUnicodeFont } from '../text/unicodeFont';

/**
 * Stamp a diagonal, semi-transparent watermark on every page of `bytes` and
 * return the new PDF bytes. Color and angle are fixed; font size scales to
 * the page so a single line spans most of the diagonal.
 */
export async function applyWatermark(bytes: Uint8Array, text: string): Promise<Uint8Array> {
  const doc = await PDFDocument.load(bytes);
  const fallback = await doc.embedFont(StandardFonts.HelveticaBold);
  const font = await embedUnicodeFont(doc, { bold: true, fallback });
  const pages = doc.getPages();
  for (const page of pages) {
    const { width, height } = page.getSize();
    // Pick a font size so the text width fills ~85% of the diagonal.
    const diag = Math.sqrt(width * width + height * height);
    const target = diag * 0.85;
    let fontSize = 96;
    let textW = font.widthOfTextAtSize(text, fontSize);
    if (textW > 0) {
      fontSize = Math.max(24, Math.min(240, fontSize * (target / textW)));
      textW = font.widthOfTextAtSize(text, fontSize);
    }
    const textH = font.heightAtSize(fontSize);
    // 45° rotated centered on the page.
    const angle = Math.atan2(height, width);
    const deg = (angle * 180) / Math.PI;
    const cx = width / 2;
    const cy = height / 2;
    const cos = Math.cos(angle);
    const sin = Math.sin(angle);
    const x = cx - (textW / 2) * cos + (textH / 2) * sin;
    const y = cy - (textW / 2) * sin - (textH / 2) * cos;
    page.drawText(text, {
      x,
      y,
      size: fontSize,
      font,
      color: rgb(0.6, 0.6, 0.6),
      opacity: 0.25,
      rotate: degrees(deg)
    });
  }
  return await doc.save();
}
