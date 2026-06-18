// Convert between the discrete NiteFlirt <font size> ladder (1..7) and CSS pt
// values, snapping arbitrary inbound sizes to the nearest rung. Used on import
// (round-trip from `style="font-size:..."`) and to surface the snap to the user.

import { NF_SIZES, SIZE_PT, DEFAULT_SIZE, type NFSize } from './model';

/** Clamp any number to a valid NFSize (1..7). */
export function clampSize(n: number): NFSize {
  if (!Number.isFinite(n)) return DEFAULT_SIZE;
  const r = Math.round(n);
  if (r < 1) return 1;
  if (r > 7) return 7;
  return r as NFSize;
}

/** Parse a CSS font-size string/number into a pt number. Handles `"18pt"`,
 *  `"14px"` (px→pt at 0.75), and bare numbers (treated as pt). Returns null if
 *  it can't be parsed. */
export function cssFontSizeToPt(value: string | number): number | null {
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  const m = value.trim().match(/^(-?\d*\.?\d+)\s*(pt|px|em|rem|%)?$/i);
  if (!m) return null;
  const num = parseFloat(m[1]);
  if (!Number.isFinite(num)) return null;
  const unit = (m[2] || 'pt').toLowerCase();
  switch (unit) {
    case 'pt':
      return num;
    case 'px':
      return num * 0.75; // 96px = 72pt
    case 'em':
    case 'rem':
      return num * 12; // assume 12pt base
    case '%':
      return (num / 100) * 12;
    default:
      return num;
  }
}

/** Snap a pt value to the nearest NiteFlirt size rung. */
export function ptToSize(pt: number): NFSize {
  let best: NFSize = DEFAULT_SIZE;
  let bestDist = Infinity;
  for (const s of NF_SIZES) {
    const d = Math.abs(SIZE_PT[s] - pt);
    if (d < bestDist) {
      bestDist = d;
      best = s;
    }
  }
  return best;
}

/** Convenience: a CSS font-size value (`"18.5pt"`) → nearest rung, or null. */
export function cssFontSizeToNFSize(value: string | number): NFSize | null {
  const pt = cssFontSizeToPt(value);
  return pt == null ? null : ptToSize(pt);
}
