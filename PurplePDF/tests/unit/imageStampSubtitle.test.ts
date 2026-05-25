// Regression guard for the custom-image-stamp subtitle (defaultIncludeSubtitle).
// An ImageAnnot carrying `subtext` must flatten without error and draw the
// caption overlay band — exercising flatten.ts's drawImageCaption path. Also
// pins the caption-content contract (buildStampSubtext) used at placement.
import { describe, expect, it } from 'vitest';
import { PDFDocument } from 'pdf-lib';
import { buildModifiedPdf } from '../../src/renderer/src/features/annotate/flatten';
import { buildStampSubtext, formatStampDateTime } from '../../src/renderer/src/features/annotate/userInfo';
import type { Annot, ImageAnnot } from '../../src/renderer/src/features/annotate/types';

// Minimal 1x1 white PNG (same fixture used by images-to-pdf.test.ts).
const ONE_PX_PNG_B64 =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP8//8/AwAI/AL+ESLnRgAAAABJRU5ErkJggg==';

function pngBytes(): Uint8Array {
  const bin = atob(ONE_PX_PNG_B64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function blankPdf(): Promise<ArrayBuffer> {
  const doc = await PDFDocument.create();
  doc.addPage([300, 300]);
  const bytes = await doc.save();
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
}

function imageAnnot(subtext?: string): ImageAnnot {
  return {
    id: 'img-1',
    page: 0,
    color: '#000000',
    kind: 'image',
    x: 50,
    y: 50,
    w: 120,
    h: 80,
    bytes: pngBytes(),
    mime: 'image/png',
    naturalWidth: 1,
    naturalHeight: 1,
    subtext
  };
}

describe('image stamp subtitle (defaultIncludeSubtitle)', () => {
  it('flattens an image annotation WITH a caption into a valid PDF', async () => {
    const original = await blankPdf();
    const annots = new Map<number, Annot[]>([[0, [imageAnnot('By Robert Olen at 6:36 pm, May 21, 2026')]]]);
    const out = await buildModifiedPdf(original, annots, []);
    const loaded = await PDFDocument.load(out);
    expect(loaded.getPageCount()).toBe(1);
  });

  it('the caption adds drawing operators (with-caption output is larger)', async () => {
    const original = await blankPdf();
    const withCaption = await buildModifiedPdf(
      original,
      new Map<number, Annot[]>([[0, [imageAnnot('By Robert Olen at 6:36 pm, May 21, 2026')]]]),
      []
    );
    const withoutCaption = await buildModifiedPdf(
      original,
      new Map<number, Annot[]>([[0, [imageAnnot(undefined)]]]),
      []
    );
    // The caption draws a filled rectangle + a text run, so its content
    // stream must be strictly larger than the bare-image case.
    expect(withCaption.byteLength).toBeGreaterThan(withoutCaption.byteLength);
  });

  it('buildStampSubtext composes the user+date caption placed on image stamps', () => {
    // Image stamps always request both halves (single boolean toggle).
    const date = new Date('2026-05-21T18:36:00');
    const dateOnly = buildStampSubtext({ includeUser: false, includeDate: true, date });
    expect(dateOnly).toBe(formatStampDateTime(date));
    expect(dateOnly).toContain('2026');
    // No user (no IPC priming in tests) and no date → empty, so the band is suppressed.
    expect(buildStampSubtext({ includeUser: false, includeDate: false })).toBe('');
  });
});
