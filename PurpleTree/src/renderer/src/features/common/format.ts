/** Human-readable byte size, e.g. 1536 -> "1.5 KB". */
export function formatBytes(n: number): string {
  if (!Number.isFinite(n) || n < 0) return '—';
  if (n < 1024) return `${n} B`;
  const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
  let v = n / 1024;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return `${v < 10 ? v.toFixed(1) : Math.round(v)} ${units[i]}`;
}

/** Locale date from ms epoch (empty for 0/unknown). */
export function formatDate(ms: number): string {
  if (!ms) return '';
  try {
    return new Date(ms).toLocaleDateString(undefined, {
      year: 'numeric',
      month: 'short',
      day: 'numeric'
    });
  } catch {
    return '';
  }
}

export function formatCount(n: number): string {
  return n.toLocaleString();
}

/** Elapsed duration from ms, e.g. 75200 -> "1:15". */
export function formatDuration(ms: number): string {
  const s = Math.max(0, Math.floor(ms / 1000));
  const m = Math.floor(s / 60);
  const rem = s % 60;
  return `${m}:${String(rem).padStart(2, '0')}`;
}

/** Compact rate, e.g. 18342 -> "18.3k". */
export function formatRate(perSec: number): string {
  if (!Number.isFinite(perSec) || perSec <= 0) return '0';
  if (perSec >= 1000) return `${(perSec / 1000).toFixed(1)}k`;
  return String(Math.round(perSec));
}

/** Stable-ish color per depth for treemap tiles (purple family). */
export function depthColor(depth: number): string {
  const palette = ['#7c3aed', '#8b5cf6', '#a78bfa', '#c4b5fd', '#ddd6fe', '#ede9fe'];
  return palette[Math.min(depth, palette.length - 1)];
}

export function riskColor(level: 'low' | 'medium' | 'high'): string {
  return level === 'low' ? '#16a34a' : level === 'medium' ? '#d97706' : '#dc2626';
}

/** Basename of an absolute path (handles / and \\). */
export function basename(p: string): string {
  const parts = p.split(/[\\/]/).filter(Boolean);
  return parts.length ? parts[parts.length - 1] : p;
}

/**
 * Returns an rgba() background color for a size-heat row.
 * fraction: 0–1 (item size / max size in the list).
 * hex: 6-digit hex color string like '#7c3aed'.
 */
export function heatBg(fraction: number, hex: string): string {
  if (fraction <= 0 || !/^#[0-9a-fA-F]{6}$/.test(hex)) return '';
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  // Power curve so mid-sized items are still visible; cap alpha at 0.38.
  const alpha = Math.pow(fraction, 0.7) * 0.38;
  return `rgba(${r},${g},${b},${alpha.toFixed(3)})`;
}
