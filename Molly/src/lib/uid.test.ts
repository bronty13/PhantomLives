import { describe, expect, it } from 'vitest';
import { formatDateKey } from './uid';

describe('formatDateKey', () => {
  it('formats with zero-padded month + day', () => {
    expect(formatDateKey(new Date(2026, 0, 5))).toBe('2026-01-05');
    expect(formatDateKey(new Date(2026, 4, 21))).toBe('2026-05-21');
    expect(formatDateKey(new Date(2026, 11, 31))).toBe('2026-12-31');
  });

  // The four-digit year pad covers the contract pinned in uid.ts.
  // Use setFullYear(1) — JS's Date(year, …) constructor adds 1900 for
  // year args in [0, 99], so we can't pass `1` directly.
  it('zero-pads the year to four digits', () => {
    const d = new Date(2026, 0, 1);
    d.setFullYear(1);
    expect(formatDateKey(d)).toBe('0001-01-01');
  });

  // Matches MasterClipper's IDGeneratorService format so cross-tool IDs
  // line up visually.
  it('output matches MasterClipper YYYY-MM-DD shape', () => {
    const out = formatDateKey(new Date(2026, 4, 21));
    expect(out).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });
});
