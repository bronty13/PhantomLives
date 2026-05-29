import { describe, it, expect } from 'vitest';
import {
  daysInMonth,
  hasBlockingIssues,
  validateCategories,
  validateContentDescription,
  validateContentFiles,
  validateCustomDelivery,
  validateFanSiteCompletion,
  validateGoLiveDate,
  validatePersona,
  validateTitle,
} from './bundleValidation';
import type { Bundle, BundleCategory, BundleFanDay, BundleFileInfo } from '../data/bundles';

function mkBundle(overrides: Partial<Bundle> = {}): Bundle {
  const base: Bundle = {
    summary: {
      uid: 'x', bundleType: 'custom', personaCode: 'CoC',
      state: 'draft', title: 'Hello World', contentDate: '2026-05-22',
      goLiveDate: '2026-06-15', publishedAt: null, bundlePath: null,
      bundleSizeBytes: null, createdAt: '2026-05-22', updatedAt: '2026-05-22',
      agingFlag: 'fresh', fileCount: 0, tagIds: [],
      completedAt: null, deleteAfter: null,
    },
    specialInstructions: '',
    descriptionMode: null,
    descriptionText: '',
    descriptionAudioRelpath: null,
    descriptionAudioAbsolutePath: null,
    descriptionAudioOriginalName: null,
    deliveryKind: null,
    deliverySiteId: null,
    deliveryUrl: null,
    deliveryRecipient: '',
    priceCents: null,
    handledInPlatform: false,
    fansiteYear: null,
    fansiteMonth: null,
    outerSha256: null,
    innerSha256: null,
    files: [],
    categories: [],
    fanDays: [],
  };
  return { ...base, ...overrides };
}

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
    absolutePath: 'r',
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

describe('daysInMonth', () => {
  it('handles 28/29/30/31', () => {
    expect(daysInMonth(2026, 1)).toBe(31);
    expect(daysInMonth(2026, 2)).toBe(28);
    expect(daysInMonth(2024, 2)).toBe(29); // leap
    expect(daysInMonth(2026, 4)).toBe(30);
    expect(daysInMonth(2026, 12)).toBe(31);
  });
  it('returns 0 on bad month', () => {
    expect(daysInMonth(2026, 0)).toBe(0);
    expect(daysInMonth(2026, 13)).toBe(0);
  });
});

describe('validateCustomDelivery', () => {
  const recipientFilled = (b: Bundle) => { b.deliveryRecipient = 'alice'; return b; };

  it('errors when deliveryKind is unset', () => {
    const b = recipientFilled(mkBundle({ handledInPlatform: true }));
    const issues = validateCustomDelivery(b);
    expect(issues.some((i) => i.fieldPath === 'delivery')).toBe(true);
  });
  it('errors when site kind has no siteId', () => {
    const b = recipientFilled(mkBundle({
      handledInPlatform: true, deliveryKind: 'site',
    }));
    const issues = validateCustomDelivery(b);
    expect(issues.some((i) => i.fieldPath === 'delivery')).toBe(true);
  });
  it('passes with site + siteId', () => {
    const b = recipientFilled(mkBundle({
      handledInPlatform: true, deliverySiteId: 1, deliveryKind: 'site',
    }));
    expect(validateCustomDelivery(b)).toEqual([]);
  });
  it('passes with URL kind and no URL — Robert fills it in on return', () => {
    const b = recipientFilled(mkBundle({
      handledInPlatform: true, deliveryKind: 'url',
    }));
    expect(validateCustomDelivery(b)).toEqual([]);
  });
  it('requires recipient', () => {
    const b = mkBundle({
      handledInPlatform: true, deliverySiteId: 1, deliveryKind: 'site',
      deliveryRecipient: '   ',
    });
    expect(validateCustomDelivery(b).some((i) => i.fieldPath === 'delivery.recipient')).toBe(true);
  });
  it('price required unless handled in platform', () => {
    const noPrice = recipientFilled(mkBundle({ deliverySiteId: 1, deliveryKind: 'site' }));
    expect(validateCustomDelivery(noPrice).some((i) => i.fieldPath === 'price')).toBe(true);
    const withPrice = recipientFilled(mkBundle({
      deliverySiteId: 1, deliveryKind: 'site', priceCents: 2500,
    }));
    expect(validateCustomDelivery(withPrice).some((i) => i.fieldPath === 'price')).toBe(false);
    const handled = recipientFilled(mkBundle({
      deliverySiteId: 1, deliveryKind: 'site', handledInPlatform: true,
    }));
    expect(validateCustomDelivery(handled).some((i) => i.fieldPath === 'price')).toBe(false);
    const negative = recipientFilled(mkBundle({
      deliverySiteId: 1, deliveryKind: 'site', priceCents: -1,
    }));
    expect(validateCustomDelivery(negative).some((i) => i.fieldPath === 'price')).toBe(true);
  });
});

describe('validateFanSiteCompletion', () => {
  function mkDay(day: number, message: string, fileCount: number): BundleFanDay {
    return { id: day, dayOfMonth: day, message, fileCount, tagIds: [] };
  }

  it('requires year + month first', () => {
    const issues = validateFanSiteCompletion(mkBundle());
    expect(issues.some((i) => i.fieldPath === 'fansiteMonth')).toBe(true);
  });
  it('rejects out-of-range month', () => {
    const issues = validateFanSiteCompletion(mkBundle({
      fansiteYear: 2026, fansiteMonth: 13,
    }));
    expect(issues.some((i) => i.fieldPath === 'fansiteMonth')).toBe(true);
  });
  it('lists every missing day', () => {
    // Feb 2026 = 28 days, fill 25
    const fanDays: BundleFanDay[] = [];
    for (let d = 1; d <= 25; d++) fanDays.push(mkDay(d, 'post', 1));
    const issues = validateFanSiteCompletion(mkBundle({
      fansiteYear: 2026, fansiteMonth: 2, fanDays,
    }));
    const missing = issues.filter((i) => i.fieldPath.startsWith('fanDay.'));
    expect(missing.length).toBe(3);
  });
  it('differentiates missing message vs missing file', () => {
    const fanDays = [
      mkDay(5, '', 1),       // missing message
      mkDay(6, 'post', 0),    // missing file
    ];
    // Fill the rest of Jan (31 days)
    for (let d = 1; d <= 31; d++) {
      if (d === 5 || d === 6) continue;
      fanDays.push(mkDay(d, 'p', 1));
    }
    const issues = validateFanSiteCompletion(mkBundle({
      fansiteYear: 2026, fansiteMonth: 1, fanDays,
    }));
    const d5 = issues.find((i) => i.fieldPath === 'fanDay.05')!;
    const d6 = issues.find((i) => i.fieldPath === 'fanDay.06')!;
    expect(d5.message).toContain('message');
    expect(d6.message).toContain('file');
  });
  it('passes when every day is complete', () => {
    const fanDays: BundleFanDay[] = [];
    for (let d = 1; d <= 30; d++) fanDays.push(mkDay(d, 'post', 1));
    expect(validateFanSiteCompletion(mkBundle({
      fansiteYear: 2026, fansiteMonth: 6, fanDays,
    }))).toEqual([]);
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
