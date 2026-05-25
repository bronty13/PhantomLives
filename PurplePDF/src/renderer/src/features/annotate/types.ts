// All annotation coordinates are stored in PDF page space
// (origin bottom-left, y up, points). Renderer converts to viewport
// space on render via pdfjs viewport helpers.

export type AnnotKind =
  | 'highlight'
  | 'underline'
  | 'strikethrough'
  | 'note'
  | 'freehand'
  | 'rect'
  | 'textbox'
  | 'signature'
  | 'redact'
  | 'stamp'
  | 'image';

export interface PdfRect {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface PdfPoint {
  x: number;
  y: number;
}

interface BaseAnnot {
  id: string;
  page: number; // 0-based
  color: string;
}

export interface TextMarkupAnnot extends BaseAnnot {
  kind: 'highlight' | 'underline' | 'strikethrough';
  rects: PdfRect[];
  /** Line thickness (for underline/strikethrough) or opacity multiplier
   * (for highlight). Optional for backward compat. */
  strokeWidth?: number;
}

export interface NoteAnnot extends BaseAnnot {
  kind: 'note';
  x: number;
  y: number;
  text: string;
}

export interface FreehandAnnot extends BaseAnnot {
  kind: 'freehand';
  points: PdfPoint[];
  width: number;
}

export interface RectAnnot extends BaseAnnot {
  kind: 'rect';
  x: number;
  y: number;
  w: number;
  h: number;
  strokeWidth: number;
}

export interface TextBoxAnnot extends BaseAnnot {
  kind: 'textbox';
  x: number;
  y: number;
  w: number;
  h: number;
  text: string;
  fontSize: number;
}

export interface SignatureAnnot extends BaseAnnot {
  kind: 'signature';
  x: number;
  y: number;
  w: number;
  h: number;
  /** PNG bytes of the rendered signature (transparent background). */
  pngBytes: Uint8Array;
}

export interface RedactAnnot extends BaseAnnot {
  kind: 'redact';
  x: number;
  y: number;
  w: number;
  h: number;
}

/** A business-style rubber stamp (e.g. APPROVED / DENIED / ✓ / ✗) placed
 *  on the page. The label/subtext is rasterized to a bordered box at
 *  flatten time. */
export interface StampAnnot extends BaseAnnot {
  kind: 'stamp';
  x: number;
  y: number;
  w: number;
  h: number;
  /** Big label text, e.g. "APPROVED". */
  label: string;
  /** Optional second line (typically a frozen date/time). */
  subtext?: string;
  /** "rect" = bordered box with label; "mark" = single glyph (✓ / ✗). */
  style: 'rect' | 'mark';
  /** Border + text color (CSS hex). */
  borderColor: string;
}

/** A raster image inserted on the page. PNG or JPEG bytes are stored
 *  here verbatim and embedded into the saved PDF at flatten time. */
export interface ImageAnnot extends BaseAnnot {
  kind: 'image';
  x: number;
  y: number;
  w: number;
  h: number;
  /** Encoded image bytes. */
  bytes: Uint8Array;
  /** MIME type ('image/png' or 'image/jpeg'). */
  mime: 'image/png' | 'image/jpeg';
  /** Intrinsic pixel dimensions of the source image (for aspect-lock resize). */
  naturalWidth: number;
  naturalHeight: number;
  /** Optional alt text for accessibility tagging. */
  alt?: string;
  /** Optional caption frozen at placement (e.g. "By Robert Olen at 6:36 pm,
   *  May 21, 2026"), rendered as an overlay band along the image's bottom
   *  edge. Driven by a custom image stamp's `defaultIncludeSubtitle`. */
  subtext?: string;
}

export type Annot =
  | TextMarkupAnnot
  | NoteAnnot
  | FreehandAnnot
  | RectAnnot
  | TextBoxAnnot
  | SignatureAnnot
  | RedactAnnot
  | StampAnnot
  | ImageAnnot;

export type Tool =
  | 'select'
  | 'highlight'
  | 'underline'
  | 'strikethrough'
  | 'note'
  | 'freehand'
  | 'rect'
  | 'textbox'
  | 'signature'
  | 'redact'
  | 'stamp'
  | 'image'
  | 'crop';

export const DEFAULT_COLORS: Record<Tool, string> = {
  select: '#A78BFA',
  highlight: '#FACC15',
  underline: '#F472B6',
  strikethrough: '#F87171',
  note: '#FBBF24',
  freehand: '#A78BFA',
  rect: '#A78BFA',
  textbox: '#FFFFFF',
  signature: '#1f1a2e',
  redact: '#000000',
  stamp: '#16A34A',
  image: '#A78BFA',
  crop: '#A78BFA'
};

export const DEFAULT_SIZES: Record<Tool, number> = {
  select: 2,
  highlight: 8,
  underline: 2,
  strikethrough: 2,
  note: 2,
  freehand: 2,
  rect: 2,
  textbox: 4,
  signature: 2,
  redact: 2,
  stamp: 2,
  image: 2,
  crop: 2
};

export const SIZE_STEPS = [1, 2, 4, 8, 16] as const;

export function newId(): string {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 9)}`;
}

export function hexToRgb01(hex: string): { r: number; g: number; b: number } {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex);
  if (!m) return { r: 0, g: 0, b: 0 };
  const n = parseInt(m[1], 16);
  return {
    r: ((n >> 16) & 0xff) / 255,
    g: ((n >> 8) & 0xff) / 255,
    b: (n & 0xff) / 255
  };
}
