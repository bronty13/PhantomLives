// Friendly release notes shown in the creator's in-app "What's New" popup after an
// update. This is NOT the technical CHANGELOG — keep entries short and plain.
// Add a new entry at the TOP each release, and keep its `version` equal to
// APP_VERSION / package.json.

import { compareVersions } from '../../shared/version';

export interface ReleaseNote {
  version: string;
  date: string; // human-friendly, e.g. "June 14, 2026"
  highlights: string[];
}

export const WHATS_NEW: ReleaseNote[] = [
  {
    version: '0.4.0',
    date: 'June 14, 2026',
    highlights: [
      'Quizzer now lives at a web link you can bookmark — open it any time, on any device.',
      'When a newer version is published, a bar appears at the top: click “Update now” to get it.',
      'Your quizzes, wheels, and branding stay put across updates (they live in this browser).',
      'After each update, this “What’s New” note tells you what changed.',
    ],
  },
];

/**
 * Release notes the user hasn't seen yet (strictly newer than `lastSeen`), newest
 * first. A first run (no `lastSeen` recorded) returns nothing — there's no update
 * to announce to a brand-new install; the caller just records the current version.
 */
export function unseenNotes(lastSeen: string | null): ReleaseNote[] {
  if (!lastSeen) return [];
  return [...WHATS_NEW]
    .filter((n) => compareVersions(n.version, lastSeen) > 0)
    .sort((a, b) => compareVersions(b.version, a.version));
}
