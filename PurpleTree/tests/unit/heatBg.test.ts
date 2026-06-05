import { describe, it, expect } from 'vitest';
import { heatBg } from '../../src/renderer/src/features/common/format';

describe('heatBg', () => {
  it('returns empty string for non-positive fractions', () => {
    expect(heatBg(0, '#7c3aed')).toBe('');
    expect(heatBg(-0.5, '#7c3aed')).toBe('');
  });

  it('returns empty string for invalid hex colors', () => {
    expect(heatBg(1, '#7c3ae')).toBe('');
    expect(heatBg(1, '7c3aed')).toBe('');
    expect(heatBg(1, 'purple')).toBe('');
    expect(heatBg(1, '#zzzzzz')).toBe('');
  });

  it('parses the hex into rgb channels', () => {
    // #7c3aed -> 124, 58, 237
    expect(heatBg(1, '#7c3aed')).toBe('rgba(124,58,237,0.380)');
  });

  it('caps alpha at 0.38 for the largest item (fraction = 1)', () => {
    expect(heatBg(1, '#2563eb')).toBe('rgba(37,99,235,0.380)');
  });

  it('applies a 0.7 power curve so mid-sized items stay visible', () => {
    // 0.5^0.7 * 0.38 ≈ 0.234 — noticeably more than a linear 0.19
    expect(heatBg(0.5, '#000000')).toBe('rgba(0,0,0,0.234)');
  });

  it('accepts uppercase hex', () => {
    expect(heatBg(1, '#FF0000')).toBe('rgba(255,0,0,0.380)');
  });
});
