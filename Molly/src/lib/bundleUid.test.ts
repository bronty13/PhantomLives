import { describe, it, expect } from 'vitest';
import { formatBundleUid, parseBundleUid, todayIso } from './bundleUid';

describe('bundleUid', () => {
  it('formats with 4-digit zero-padded counter', () => {
    expect(formatBundleUid('2026-05-22', 1)).toBe('2026-05-22-0001');
    expect(formatBundleUid('2026-05-22', 42)).toBe('2026-05-22-0042');
    expect(formatBundleUid('2026-05-22', 9999)).toBe('2026-05-22-9999');
  });

  it('rejects out-of-range counters', () => {
    expect(() => formatBundleUid('2026-05-22', 0)).toThrow();
    expect(() => formatBundleUid('2026-05-22', 10000)).toThrow();
    expect(() => formatBundleUid('2026-05-22', -1)).toThrow();
  });

  it('parses well-formed UIDs', () => {
    expect(parseBundleUid('2026-05-22-0001')).toEqual({ date: '2026-05-22', counter: 1 });
    expect(parseBundleUid('2026-12-31-9999')).toEqual({ date: '2026-12-31', counter: 9999 });
  });

  it('rejects malformed UIDs', () => {
    expect(parseBundleUid('')).toBeNull();
    expect(parseBundleUid('2026-5-22-0001')).toBeNull(); // month must be 2 digits
    expect(parseBundleUid('2026-05-22-1')).toBeNull(); // counter must be 4 digits
    expect(parseBundleUid('garbage')).toBeNull();
  });

  it('todayIso formats Date in YYYY-MM-DD shape', () => {
    expect(todayIso(new Date(2026, 4, 22))).toBe('2026-05-22'); // month is 0-indexed in JS
    expect(todayIso(new Date(2026, 0, 1))).toBe('2026-01-01');
    expect(todayIso(new Date(2026, 11, 31))).toBe('2026-12-31');
  });
});
