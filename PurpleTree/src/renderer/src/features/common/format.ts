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
