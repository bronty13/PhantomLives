// Tiny pure colour helpers. Branch colours are hex; we derive light pastel
// fills (mix toward white) for topic boxes and pick a readable text colour,
// without depending on CSS color-mix (keeps it predictable across WebKit
// versions and unit-testable).

export type RGB = [number, number, number];

/** Parse `#rgb` / `#rrggbb` to an [r,g,b] triple (0–255). Falls back to brand. */
export function parseHex(hex: string): RGB {
  let h = hex.trim().replace(/^#/, '');
  if (h.length === 3) h = h.split('').map((c) => c + c).join('');
  if (h.length !== 6 || /[^0-9a-fA-F]/.test(h)) return [147, 97, 219];
  return [
    parseInt(h.slice(0, 2), 16),
    parseInt(h.slice(2, 4), 16),
    parseInt(h.slice(4, 6), 16),
  ];
}

function toHex([r, g, b]: RGB): string {
  const c = (n: number) => Math.max(0, Math.min(255, Math.round(n))).toString(16).padStart(2, '0');
  return `#${c(r)}${c(g)}${c(b)}`;
}

/** Mix `hex` toward `target` by `t` (0 = hex, 1 = target). */
export function mix(hex: string, target: string, t: number): string {
  const a = parseHex(hex);
  const b = parseHex(target);
  return toHex([
    a[0] + (b[0] - a[0]) * t,
    a[1] + (b[1] - a[1]) * t,
    a[2] + (b[2] - a[2]) * t,
  ]);
}

/** rgba() string from a hex + alpha (0–1). */
export function withAlpha(hex: string, alpha: number): string {
  const [r, g, b] = parseHex(hex);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

/** Relative luminance (0–1) per WCAG, used to pick readable text. */
export function luminance(hex: string): number {
  const lin = parseHex(hex).map((v) => {
    const s = v / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.4126 * lin[2];
}

/** Dark or light text colour that reads on the given background. */
export function readableText(bgHex: string): string {
  return luminance(bgHex) > 0.55 ? '#2a2140' : '#ffffff';
}
