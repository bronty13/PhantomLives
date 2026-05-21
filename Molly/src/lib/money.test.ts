import { describe, expect, it } from 'vitest';
import { fmtMoney, parseMoney } from './money';

describe('parseMoney', () => {
  it('parses plain integers', () => {
    expect(parseMoney('42')).toBe(42);
  });

  it('parses decimals', () => {
    expect(parseMoney('20.03')).toBe(20.03);
    expect(parseMoney('0.5')).toBe(0.5);
    expect(parseMoney('1234.56')).toBe(1234.56);
  });

  it('strips $ and commas', () => {
    expect(parseMoney('$1,234.56')).toBe(1234.56);
    expect(parseMoney('$5')).toBe(5);
    expect(parseMoney('1,000,000.00')).toBe(1_000_000);
  });

  it('strips internal whitespace', () => {
    expect(parseMoney(' $5.50 ')).toBe(5.5);
    expect(parseMoney('1 234.56')).toBe(1234.56);
  });

  it('returns 0 for unparseable or empty', () => {
    expect(parseMoney('')).toBe(0);
    expect(parseMoney('abc')).toBe(0);
    expect(parseMoney('$')).toBe(0);
  });

  it('handles trailing decimal point (mid-typing)', () => {
    // Crucial for the MoneyInput pattern — we need parseMoney("5.") = 5
    // so the on-change handler doesn't corrupt the buffer mid-typing.
    expect(parseMoney('5.')).toBe(5);
    expect(parseMoney('.5')).toBe(0.5);
  });
});

describe('fmtMoney', () => {
  it('formats with two decimals by default', () => {
    expect(fmtMoney(5)).toBe('$5.00');
    expect(fmtMoney(1234.56)).toBe('$1,234.56');
    expect(fmtMoney(0)).toBe('$0.00');
  });

  it('renders negatives with a leading -', () => {
    expect(fmtMoney(-12.5)).toBe('-$12.50');
  });

  it('honors the decimals option', () => {
    expect(fmtMoney(5, { decimals: 0 })).toBe('$5');
    expect(fmtMoney(5.123, { decimals: 3 })).toBe('$5.123');
  });

  it('round-trips with parseMoney for typical values', () => {
    for (const v of [0, 5, 20.03, 1234.56, -42.5]) {
      expect(parseMoney(fmtMoney(v))).toBeCloseTo(v, 2);
    }
  });
});
