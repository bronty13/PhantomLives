/**
 * @file stamps.ts — built-in business stamp presets.
 *
 * Each preset describes how the Stamp tool should construct a new
 * {@link StampAnnot}. Sizes are in PDF points; colors are CSS hex.
 */

export interface StampPreset {
  id: string;
  label: string;
  /** "rect" = full bordered box with label (e.g. APPROVED); "mark" =
   *  single large glyph with no border (e.g. ✓ / ✗). */
  style: 'rect' | 'mark';
  /** Border + text color. */
  color: string;
  /** Default size (PDF points). */
  width: number;
  height: number;
}

export const STAMP_PRESETS: StampPreset[] = [
  { id: 'approved',     label: 'APPROVED',     style: 'rect', color: '#16A34A', width: 200, height: 60 },
  { id: 'denied',       label: 'DENIED',       style: 'rect', color: '#DC2626', width: 200, height: 60 },
  { id: 'reviewed',     label: 'REVIEWED',     style: 'rect', color: '#2563EB', width: 200, height: 60 },
  { id: 'revised',      label: 'REVISED',      style: 'rect', color: '#1E3A8A', width: 200, height: 60 },
  { id: 'received',     label: 'RECEIVED',     style: 'rect', color: '#2563EB', width: 200, height: 60 },
  { id: 'draft',        label: 'DRAFT',        style: 'rect', color: '#6B7280', width: 200, height: 60 },
  { id: 'final',        label: 'FINAL',        style: 'rect', color: '#7C3AED', width: 200, height: 60 },
  { id: 'confidential', label: 'CONFIDENTIAL', style: 'rect', color: '#DC2626', width: 210, height: 60 },
  { id: 'void',         label: 'VOID',         style: 'rect', color: '#DC2626', width: 160, height: 60 },
  { id: 'check',        label: '✓',            style: 'mark', color: '#16A34A', width: 36,  height: 36 },
  { id: 'x',            label: '✗',            style: 'mark', color: '#DC2626', width: 36,  height: 36 }
];

/** Returns a short, locale-aware "M/D/YYYY h:mm AM" stamp date string. */
export function formatStampDate(d: Date = new Date()): string {
  const date = d.toLocaleDateString(undefined, { year: 'numeric', month: 'numeric', day: 'numeric' });
  const time = d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
  return `${date} ${time}`;
}
