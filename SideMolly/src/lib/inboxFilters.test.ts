import { describe, expect, it } from 'vitest';
import {
  applyInboxFilters, isCompleted, DEFAULT_INBOX_FILTERS, type InboxFilters,
} from './inboxFilters';
import type { BundleSummary } from '../data/bundles';

function bundle(over: Partial<BundleSummary>): BundleSummary {
  return {
    uid: '2026-06-01-0001',
    bundleType: 'content',
    personaCode: 'CoC',
    title: 'A clip',
    originalTitle: 'A clip',
    titleOverride: '',
    ingestedAt: '2026-06-01T12:00:00',
    verifyStatus: 'verified',
    bundleState: 'new',
    completedAt: null,
    fileCount: 3,
    sourceZipPath: '/x.zip',
    ...over,
  };
}

const f = (over: Partial<InboxFilters>): InboxFilters => ({ ...DEFAULT_INBOX_FILTERS, ...over });

describe('isCompleted', () => {
  it('treats null and empty as active, a timestamp as complete', () => {
    expect(isCompleted(bundle({ completedAt: null }))).toBe(false);
    expect(isCompleted(bundle({ completedAt: '' }))).toBe(false);
    expect(isCompleted(bundle({ completedAt: '2026-06-02T10:00:00' }))).toBe(true);
  });
});

describe('applyInboxFilters — status', () => {
  const active = bundle({ uid: 'a', completedAt: null });
  const done = bundle({ uid: 'b', completedAt: '2026-06-02T10:00:00' });
  const rows = [active, done];

  it('active (default) hides completed', () => {
    expect(applyInboxFilters(rows, f({ status: 'active' })).map((b) => b.uid)).toEqual(['a']);
  });
  it('completed shows only completed', () => {
    expect(applyInboxFilters(rows, f({ status: 'completed' })).map((b) => b.uid)).toEqual(['b']);
  });
  it('all shows everything', () => {
    expect(applyInboxFilters(rows, f({ status: 'all' })).map((b) => b.uid).sort()).toEqual(['a', 'b']);
  });
});

describe('applyInboxFilters — type & persona', () => {
  const rows = [
    bundle({ uid: 'c1', bundleType: 'content', personaCode: 'CoC' }),
    bundle({ uid: 'y1', bundleType: 'youtube', personaCode: 'PoA' }),
    bundle({ uid: 'np', bundleType: 'custom', personaCode: null }),
  ];
  it('filters by bundle type', () => {
    expect(applyInboxFilters(rows, f({ status: 'all', type: 'youtube' })).map((b) => b.uid)).toEqual(['y1']);
  });
  it('filters by persona', () => {
    expect(applyInboxFilters(rows, f({ status: 'all', persona: 'CoC' })).map((b) => b.uid)).toEqual(['c1']);
  });
  it('null persona never matches a specific persona filter', () => {
    expect(applyInboxFilters(rows, f({ status: 'all', persona: 'PoA' })).map((b) => b.uid)).toEqual(['y1']);
  });
});

describe('applyInboxFilters — search', () => {
  const rows = [
    bundle({ uid: '2026-06-01-0001', title: 'Beach day' }),
    bundle({ uid: '2026-06-02-0009', title: 'Studio shoot' }),
  ];
  it('matches title case-insensitively', () => {
    expect(applyInboxFilters(rows, f({ status: 'all', search: 'STUDIO' })).map((b) => b.uid)).toEqual(['2026-06-02-0009']);
  });
  it('matches uid substring', () => {
    expect(applyInboxFilters(rows, f({ status: 'all', search: '0009' })).map((b) => b.uid)).toEqual(['2026-06-02-0009']);
  });
});

describe('applyInboxFilters — date range', () => {
  const rows = [
    bundle({ uid: 'm05', ingestedAt: '2026-05-20T08:00:00' }),
    bundle({ uid: 'm06', ingestedAt: '2026-06-01T08:00:00' }),
    bundle({ uid: 'm07', ingestedAt: '2026-06-10T08:00:00' }),
  ];
  it('honors an inclusive from/to window', () => {
    const out = applyInboxFilters(rows, f({ status: 'all', dateFrom: '2026-06-01', dateTo: '2026-06-01' }));
    expect(out.map((b) => b.uid)).toEqual(['m06']);
  });
  it('open-ended from', () => {
    const out = applyInboxFilters(rows, f({ status: 'all', dateFrom: '2026-06-01' }));
    expect(out.map((b) => b.uid).sort()).toEqual(['m06', 'm07']);
  });
});

describe('applyInboxFilters — sort', () => {
  const rows = [
    bundle({ uid: 'old', ingestedAt: '2026-05-01T08:00:00' }),
    bundle({ uid: 'new', ingestedAt: '2026-06-01T08:00:00' }),
  ];
  it('newest first by default', () => {
    expect(applyInboxFilters(rows, f({ status: 'all', sort: 'newest' })).map((b) => b.uid)).toEqual(['new', 'old']);
  });
  it('oldest first when asked', () => {
    expect(applyInboxFilters(rows, f({ status: 'all', sort: 'oldest' })).map((b) => b.uid)).toEqual(['old', 'new']);
  });
  it('does not mutate the input array', () => {
    const input = [...rows];
    applyInboxFilters(input, f({ status: 'all', sort: 'oldest' }));
    expect(input.map((b) => b.uid)).toEqual(['old', 'new']);
  });
});
