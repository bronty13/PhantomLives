// Smoke-test the image-to-PDF conversion end-to-end. Uses pdf-lib directly
// (no Electron) to mirror what src/main/convert.ts does for JPG/PNG inputs.
import { describe, expect, it } from 'vitest';
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { PDFDocument } from 'pdf-lib';

// Minimal 1x1 PNG (8-bit RGBA, single white pixel) — produced with
// `python -c "from PIL import Image; Image.new('RGBA',(1,1),(255,255,255,255)).save('p.png')"`
// and base64-encoded.
const ONE_PX_PNG_B64 =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP8//8/AwAI/AL+ESLnRgAAAABJRU5ErkJggg==';

describe('imagesToPdf (P4)', () => {
  it('produces a valid PDF from a PNG image', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'purplepdf-test-'));
    try {
      const pngPath = join(dir, 'pixel.png');
      const outPath = join(dir, 'out.pdf');
      await writeFile(pngPath, Buffer.from(ONE_PX_PNG_B64, 'base64'));

      // Inline equivalent of imagesToPdf for the PNG-only path.
      const doc = await PDFDocument.create();
      const bytes = await readFile(pngPath);
      const img = await doc.embedPng(bytes);
      const page = doc.addPage([img.width, img.height]);
      page.drawImage(img, { x: 0, y: 0, width: img.width, height: img.height });
      await writeFile(outPath, await doc.save());

      // Re-load to verify it's a valid PDF and has one page sized like the image.
      const loaded = await PDFDocument.load(await readFile(outPath));
      expect(loaded.getPageCount()).toBe(1);
      const p = loaded.getPage(0);
      expect(Math.round(p.getWidth())).toBe(1);
      expect(Math.round(p.getHeight())).toBe(1);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});
