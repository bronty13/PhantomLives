// Pure rotation-derivation rule for the subreddit tracker.
//
// A subreddit's "rotation" badge (Ready / Tomorrow / Resting) used to be a
// frozen flag: marking a sub posted flipped it to `wait` ("Resting") and
// nothing ever moved it back, so a sub Sallie posted to was stuck on
// "Resting" forever. This module derives the badge from how long ago she
// last posted, so it naturally walks Resting → Tomorrow → Ready as the days
// pass.
//
// Two modes (stored in app_settings, see state/redditRotation.ts):
//   • 'auto'   — derive from last_posted_at + a configurable rest window.
//   • 'manual' — keep the stored flag; Sallie resets each sub by hand.
//
// `restDays` = the number of whole days a sub rests after a post before it's
// Ready again. It becomes Ready on day `restDays`, shows "Tomorrow" the day
// before that, and "Resting" any earlier. So:
//   restDays 2 → posted today = Resting, yesterday = Tomorrow, 2+ days = Ready
//   restDays 1 → posted today = Tomorrow (ready tomorrow), 1+ days = Ready
//   restDays 0 → always Ready (no rest)

import type { Rotation } from '../data/reddit';

export type RotationMode = 'auto' | 'manual';

export const ROTATION_MODE_DEFAULT: RotationMode = 'auto';
export const REST_DAYS_DEFAULT = 2;
export const REST_DAYS_MIN = 0;
export const REST_DAYS_MAX = 30;

/** Whole days between two YYYY-MM-DD strings (b − a), timezone-safe. */
export function daysBetween(a: string, b: string): number {
  const pa = parseIsoDate(a);
  const pb = parseIsoDate(b);
  if (pa == null || pb == null) return 0;
  return Math.round((pb - pa) / 86_400_000);
}

function parseIsoDate(iso: string): number | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!m) return null;
  return Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
}

export function clampRestDays(n: number): number {
  if (!Number.isFinite(n)) return REST_DAYS_DEFAULT;
  return Math.min(REST_DAYS_MAX, Math.max(REST_DAYS_MIN, Math.round(n)));
}

/**
 * The rotation badge to actually show for a sub.
 *
 * In 'manual' mode the stored flag wins untouched. In 'auto' mode the flag is
 * ignored and the badge is computed from `lastPostedAt` relative to `today`.
 */
export function effectiveRotation(opts: {
  mode: RotationMode;
  restDays: number;
  stored: Rotation;
  lastPostedAt: string | null;
  today: string;
}): Rotation {
  const { mode, stored, lastPostedAt, today } = opts;
  if (mode === 'manual') return stored;

  // Auto mode.
  if (!lastPostedAt) return 'fresh'; // never posted → always Ready
  const rest = clampRestDays(opts.restDays);
  if (rest <= 0) return 'fresh';

  const elapsed = Math.max(0, daysBetween(lastPostedAt, today));
  if (elapsed >= rest) return 'fresh';       // rested long enough → Ready
  if (elapsed >= rest - 1) return 'soon';     // ready tomorrow → Tomorrow
  return 'wait';                              // still Resting
}
