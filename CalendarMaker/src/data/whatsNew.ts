// Friendly, large-print release notes shown in the in-app "What's New" popup.
// Keep entries short and plain-language (the primary reader has low vision) — this
// is NOT the technical CHANGELOG. Add a new entry at the TOP each release.

import { compareVersions } from '../update/version';

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
      'New “Help” button at the top opens a full, plain-language guide to everything.',
      'You can make the guide’s text bigger or smaller with the A+ and A− buttons.',
    ],
  },
  {
    version: '0.3.5',
    date: 'June 14, 2026',
    highlights: [
      'CalendarMaker now lives at a web link you can bookmark — just open it any time.',
      'When a new version is ready, a green bar appears at the top: tap “Update now”.',
      'After each update, this “What’s New” note tells you what changed.',
    ],
  },
  {
    version: '0.3.4',
    date: 'June 14, 2026',
    highlights: [
      'Bible verses and sayings now appear on the day the moment you pick them — no extra step.',
      'New choice for how verses print: inside each day (the new default) or on their own page. Change it any time in Settings.',
      'Morning Affirmations are now built in — find them in the Saying list.',
      'Easier verse finder: type a reference like “John 3:16”, or tap Book → Chapter → Verse.',
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
