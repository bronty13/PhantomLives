/**
 * @file tags.ts — select/multi-select tag palette (indexed by option.color).
 */

export interface TagColor {
  bg: string;
  fg: string;
  bgDark: string;
  fgDark: string;
}

export const TAG_COLORS: TagColor[] = [
  { bg: '#ece7f8', fg: '#4f3da0', bgDark: '#352c52', fgDark: '#c8bbf2' },
  { bg: '#f3e6d8', fg: '#8a5a2a', bgDark: '#4a3823', fgDark: '#e3bb8c' },
  { bg: '#e2ecdd', fg: '#3f6437', bgDark: '#2d4028', fgDark: '#b1d3a5' },
  { bg: '#ddeaf0', fg: '#2e6076', bgDark: '#243c47', fgDark: '#9fcbdd' },
  { bg: '#f6e0e3', fg: '#94404f', bgDark: '#4b2b30', fgDark: '#e8a8b2' },
  { bg: '#f0e4f0', fg: '#7d4382', bgDark: '#442b46', fgDark: '#d9aade' },
  { bg: '#f4ecd4', fg: '#7d6520', bgDark: '#46401f', fgDark: '#dcc878' },
  { bg: '#e8e6e1', fg: '#5b554b', bgDark: '#3b3933', fgDark: '#c2bcb0' }
];

export function tagColor(index: number, dark: boolean): { background: string; color: string } {
  const c = TAG_COLORS[((index % TAG_COLORS.length) + TAG_COLORS.length) % TAG_COLORS.length];
  return dark ? { background: c.bgDark, color: c.fgDark } : { background: c.bg, color: c.fg };
}
