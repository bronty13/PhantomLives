// Pure filter/sort logic for the Inbox toolbar. Kept out of the React view
// so it can be unit-tested without rendering. The Inbox loads every bundle
// once (small personal dataset) and narrows client-side through this.
import type { BundleSummary } from '../data/bundles';

export type StatusFilter = 'active' | 'completed' | 'all';
export type SortOrder = 'newest' | 'oldest';

export interface InboxFilters {
  status: StatusFilter;
  /** Bundle type, or 'all'. */
  type: string;
  /** Persona code (e.g. 'CoC'), or 'all'. */
  persona: string;
  /** Free text matched against title + uid (case-insensitive). */
  search: string;
  /** Inclusive `YYYY-MM-DD` lower bound on ingested date, or '' for none. */
  dateFrom: string;
  /** Inclusive `YYYY-MM-DD` upper bound on ingested date, or '' for none. */
  dateTo: string;
  sort: SortOrder;
}

export const DEFAULT_INBOX_FILTERS: InboxFilters = {
  status: 'active',
  type: 'all',
  persona: 'all',
  search: '',
  dateFrom: '',
  dateTo: '',
  sort: 'newest',
};

/** A bundle is "complete" iff it carries a completion timestamp. */
export function isCompleted(b: BundleSummary): boolean {
  return b.completedAt != null && b.completedAt !== '';
}

/** Date portion (`YYYY-MM-DD`) of an ISO-ish `ingestedAt` for range compares. */
function ingestedDay(b: BundleSummary): string {
  return b.ingestedAt.slice(0, 10);
}

/** Apply status/type/persona/search/date filters then sort by ingested date.
 *  Pure — returns a new array, never mutates the input. */
export function applyInboxFilters(
  rows: BundleSummary[],
  f: InboxFilters,
): BundleSummary[] {
  const needle = f.search.trim().toLowerCase();

  const filtered = rows.filter((b) => {
    if (f.status === 'active' && isCompleted(b)) return false;
    if (f.status === 'completed' && !isCompleted(b)) return false;

    if (f.type !== 'all' && b.bundleType !== f.type) return false;
    if (f.persona !== 'all' && (b.personaCode ?? '') !== f.persona) return false;

    if (needle) {
      const hay = `${b.title}\n${b.uid}`.toLowerCase();
      if (!hay.includes(needle)) return false;
    }

    if (f.dateFrom || f.dateTo) {
      const day = ingestedDay(b);
      if (f.dateFrom && day < f.dateFrom) return false;
      if (f.dateTo && day > f.dateTo) return false;
    }

    return true;
  });

  // ISO-ish timestamps sort correctly as plain strings.
  filtered.sort((a, b) =>
    f.sort === 'newest'
      ? b.ingestedAt.localeCompare(a.ingestedAt)
      : a.ingestedAt.localeCompare(b.ingestedAt),
  );

  return filtered;
}
