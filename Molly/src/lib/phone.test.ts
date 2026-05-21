import { describe, expect, it } from 'vitest';
import { formatUSPhone, isValidUSPhone, usPhoneDigits } from './phone';

describe('usPhoneDigits', () => {
  it('strips non-digits', () => {
    expect(usPhoneDigits('(555) 123-4567')).toBe('5551234567');
    expect(usPhoneDigits('555.123.4567')).toBe('5551234567');
    expect(usPhoneDigits('+1 555 123 4567')).toBe('5551234567');
  });

  it('drops a leading 1 when there are 10+ remaining digits', () => {
    expect(usPhoneDigits('15551234567')).toBe('5551234567');
    expect(usPhoneDigits('1-555-123-4567')).toBe('5551234567');
  });

  it('does not strip leading 1 when the number is already exactly 10 digits', () => {
    // The leading-1 strip only fires when length > 10 AND starts with 1.
    expect(usPhoneDigits('1555123456')).toBe('1555123456');
  });

  it('handles empty / short input', () => {
    expect(usPhoneDigits('')).toBe('');
    expect(usPhoneDigits('555')).toBe('555');
  });
});

describe('formatUSPhone', () => {
  it('returns empty for empty', () => {
    expect(formatUSPhone('')).toBe('');
  });

  it('formats partial inputs progressively', () => {
    expect(formatUSPhone('5')).toBe('(5');
    expect(formatUSPhone('555')).toBe('(555');
    expect(formatUSPhone('5551')).toBe('(555) 1');
    expect(formatUSPhone('555123')).toBe('(555) 123');
    expect(formatUSPhone('5551234')).toBe('(555) 123-4');
  });

  it('formats a complete 10-digit number canonically', () => {
    expect(formatUSPhone('5551234567')).toBe('(555) 123-4567');
  });

  it('accepts already-formatted inputs idempotently', () => {
    expect(formatUSPhone('(555) 123-4567')).toBe('(555) 123-4567');
  });

  it('accepts +1 country-code prefix', () => {
    expect(formatUSPhone('+1 555 123 4567')).toBe('(555) 123-4567');
    expect(formatUSPhone('15551234567')).toBe('(555) 123-4567');
  });

  it('treats beyond-10 digits as an extension', () => {
    expect(formatUSPhone('555123456789')).toBe('(555) 123-4567 x89');
  });
});

describe('isValidUSPhone', () => {
  it('is valid only when the digit-only form is exactly 10', () => {
    expect(isValidUSPhone('5551234567')).toBe(true);
    expect(isValidUSPhone('(555) 123-4567')).toBe(true);
    expect(isValidUSPhone('+1 555 123 4567')).toBe(true);
    expect(isValidUSPhone('1-555-123-4567')).toBe(true);
  });

  it('is invalid for short numbers', () => {
    expect(isValidUSPhone('')).toBe(false);
    expect(isValidUSPhone('555')).toBe(false);
    expect(isValidUSPhone('555-123-456')).toBe(false);
  });

  it('is valid for 11 digits starting with 1 (the leading-1 strip applies)', () => {
    expect(isValidUSPhone('15551234567')).toBe(true);
  });

  it('is invalid for 11 digits NOT starting with 1', () => {
    expect(isValidUSPhone('25551234567')).toBe(false);
  });
});
