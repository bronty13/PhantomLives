import { describe, it, expect } from 'vitest';
import {
  hasBlockingIssues,
  validateCategories,
  validateContentDescription,
  validateContentFiles,
  validateGoLiveDate,
  validatePersona,
  validateTitle,
} from './bundleValidation';
import type { BundleCategory, BundleFileInfo } from '../data/bundles';

describe('validateTitle', () => {
  it.each(['', '   ', 'none', 'NONE', 'Blank', 'CUSTOM', 'hello', 'x'])(
    'rejects %p',
    (s) => {
      expect(validateTitle(s).length).toBeGreaterThan(0);
    },
  );
  it.each(['hello world', 'Sallie Saturday Special', '  two words  '])(
    'accepts %p',
    (s) => {
      expect(validateTitle(s)).toEqual([]);
    },
  );
});

describe('validatePersona', () => {
  it('flags empty / null', () => {
    expect(validatePersona(null).length).toBe(1);
    expect(validatePersona('').length).toBe(1);
  });
  it('accepts a code', () => {
    expect(validatePersona('CoC')).toEqual([]);
  });
});

describe('validateGoLiveDate', () => {
  const today = new Date(2026, 4, 22); // May 22, 2026

  it('requires a value', () => {
    expect(validateGoLiveDate(null, today)[0].severity).toBe('error');
  });
  it('rejects past dates', () => {
    expect(validateGoLiveDate('2026-05-21', today)[0].severity).toBe('error');
  });
  it('warns today', () => {
    expect(validateGoLiveDate('2026-05-22', today)[0].severity).toBe('warn');
  });
  it('warns within 5 days', () => {
    expect(validateGoLiveDate('2026-05-25', today)[0].severity).toBe('warn');
    expect(validateGoLiveDate('2026-05-27', today)[0].severity).toBe('warn');
  });
  it('passes beyond 5 days', () => {
    expect(validateGoLiveDate('2026-05-28', today)).toEqual([]);
    expect(validateGoLiveDate('2026-06-01', today)).toEqual([]);
  });
  it('rejects malformed input', () => {
    expect(validateGoLiveDate('nope', today)[0].severity).toBe('error');
    expect(validateGoLiveDate('2026-02-30', today)[0].severity).toBe('error');
  });
});

describe('validateContentDescription', () => {
  it('requires text OR audio', () => {
    expect(validateContentDescription('', null, []).some((i) => i.severity === 'error')).toBe(true);
  });
  it('rejects both at once', () => {
    expect(validateContentDescription('hi', 'rel', []).some((i) => i.severity === 'error')).toBe(true);
  });
  it('passes with just text', () => {
    expect(validateContentDescription('hi', null, [])).toEqual([]);
  });
  it('passes with just audio', () => {
    expect(validateContentDescription('', 'rel', [])).toEqual([]);
  });
  it('flags prohibited words case-insensitively', () => {
    const issues = validateContentDescription('I love my Mommy', null, ['mommy']);
    expect(issues.some((i) => i.message.includes('mommy'))).toBe(true);
  });
  it('matches prohibited as substring inside longer word', () => {
    const issues = validateContentDescription('he has addictions', null, ['addiction']);
    expect(issues.some((i) => i.message.includes('addiction'))).toBe(true);
  });
  it('skips empty entries in the prohibited list', () => {
    expect(validateContentDescription('hi there', null, ['', '   '])).toEqual([]);
  });
});

describe('validateCategories', () => {
  const mk = (n: number): BundleCategory[] =>
    Array.from({ length: n }, (_, i) => ({ name: `CAT${i}`, position: i + 1 }));

  it.each([0, 1, 2])('fails with %d', (n) => {
    expect(validateCategories(mk(n)).length).toBe(1);
  });
  it.each([3, 4, 10])('passes with %d', (n) => {
    expect(validateCategories(mk(n))).toEqual([]);
  });
});

describe('validateContentFiles', () => {
  const mk = (kind: 'video' | 'image' | 'audio'): BundleFileInfo => ({
    id: 1,
    bundleUid: 'x',
    fansiteDayId: null,
    position: 1,
    relpath: 'r',
    originalName: 'n',
    kind,
    sizeBytes: 1,
    sha256: '',
  });
  it('rejects no media', () => {
    expect(validateContentFiles([]).length).toBe(1);
    // audio-only counts as no media (audio is for description, not files).
    expect(validateContentFiles([mk('audio')]).length).toBe(1);
  });
  it('accepts video or image', () => {
    expect(validateContentFiles([mk('image')])).toEqual([]);
    expect(validateContentFiles([mk('video')])).toEqual([]);
  });
});

describe('hasBlockingIssues', () => {
  it('returns true on any error', () => {
    expect(
      hasBlockingIssues([
        { fieldPath: 'a', message: '', severity: 'warn', jumpToFieldId: '' },
        { fieldPath: 'b', message: '', severity: 'error', jumpToFieldId: '' },
      ]),
    ).toBe(true);
  });
  it('returns false when only warnings', () => {
    expect(
      hasBlockingIssues([
        { fieldPath: 'a', message: '', severity: 'warn', jumpToFieldId: '' },
      ]),
    ).toBe(false);
  });
});
