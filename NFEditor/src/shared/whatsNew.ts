// Plain-language release notes for the in-app "What's New" popup (NOT the technical
// CHANGELOG). Add a new entry at the TOP each release. Shown once per new version.

import { compareVersions } from './update/version';

export interface ReleaseNote {
  version: string;
  date: string; // human-friendly, e.g. "June 17, 2026"
  highlights: string[];
}

export const WHATS_NEW: ReleaseNote[] = [
  {
    version: '0.1.0',
    date: 'June 17, 2026',
    highlights: [
      'NFEditor is here — build NiteFlirt Profiles and Listings visually, no hand-coding.',
      'Compact or legacy-table output, a live three-up preview, and a running character count.',
      'Emoji are blocked automatically so a stray emoji can never truncate your live page.',
      'Paste an existing listing to import it, or start from a built-in template.',
    ],
  },
];

/** Release notes the user hasn't seen yet (strictly newer than `lastSeen`),
 *  newest first. A first run (no `lastSeen`) returns nothing — there's no update to
 *  announce; the caller just records the current version. */
export function unseenNotes(lastSeen: string | null): ReleaseNote[] {
  if (!lastSeen) return [];
  return [...WHATS_NEW]
    .filter((n) => compareVersions(n.version, lastSeen) > 0)
    .sort((a, b) => compareVersions(b.version, a.version));
}
