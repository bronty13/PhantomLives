// Tiny pure helpers for showing file sizes and how much the Squish tool saved.
// Decimal units (1000-based) to match what Finder, Explorer, and Slack report.

/** Human-friendly file size, e.g. `4.2 GB`, `880 MB`, `500 B`. */
export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes < 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let v = bytes;
  let i = 0;
  while (v >= 1000 && i < units.length - 1) {
    v /= 1000;
    i++;
  }
  // Whole numbers for bytes and for big values (≥100); one decimal otherwise.
  const digits = i === 0 || v >= 100 ? 0 : 1;
  return `${v.toFixed(digits)} ${units[i]}`;
}

/** How much smaller the output is than the input, as a 0–100 whole percent.
 * Clamped at 0 so a (rare) bigger output never shows a negative "savings". */
export function savingsPercent(inputBytes: number, outputBytes: number): number {
  if (inputBytes <= 0 || outputBytes < 0) return 0;
  return Math.max(0, Math.round((1 - outputBytes / inputBytes) * 100));
}
