/**
 * @file userInfo.ts — module-level cache of the OS username plus a
 * pretty "display name" used in stamp subtitles ("By {displayName} at …").
 *
 * The renderer asks the main process for `os.userInfo().username` once via
 * the `ping` IPC, then caches the result for the lifetime of the window.
 */

let cachedRawUser: string | null = null;
let cachedDisplayUser: string | null = null;
let pendingPing: Promise<void> | null = null;

/** Best-effort title-case from a login id ("robert.olen" → "Robert Olen"). */
function prettify(raw: string): string {
  const cleaned = raw.replace(/[._-]+/g, ' ').trim();
  if (!cleaned) return '';
  return cleaned
    .split(/\s+/)
    .map((w) => (w.length <= 2 ? w.toUpperCase() : w[0].toUpperCase() + w.slice(1).toLowerCase()))
    .join(' ');
}

/** Kick off a one-time ping; idempotent. */
export function primeStampUser(): Promise<void> {
  if (pendingPing) return pendingPing;
  const api = (window as unknown as { purplePDF?: { ping?: () => Promise<{ osUser?: string }> } })
    .purplePDF;
  if (!api?.ping) {
    cachedRawUser = '';
    cachedDisplayUser = '';
    pendingPing = Promise.resolve();
    return pendingPing;
  }
  pendingPing = api
    .ping()
    .then((r) => {
      cachedRawUser = (r?.osUser ?? '').trim();
      cachedDisplayUser = cachedRawUser ? prettify(cachedRawUser) : '';
    })
    .catch(() => {
      cachedRawUser = '';
      cachedDisplayUser = '';
    });
  return pendingPing;
}

/** Returns raw login id (e.g. "jdoe"); empty string if unknown. */
export function getStampUserRaw(): string {
  return cachedRawUser ?? '';
}

/** Returns "Robert Olen" style display name; falls back to raw id. */
export function getStampUserDisplay(): string {
  if (cachedDisplayUser) return cachedDisplayUser;
  return cachedRawUser ?? '';
}

/** "6:36 pm, May 21, 2026" — matches Acrobat-style dynamic stamps. */
export function formatStampDateTime(d: Date = new Date()): string {
  const time = d
    .toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit', hour12: true })
    .toLowerCase()
    .replace(/\s+/g, ' ');
  const date = d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
  return `${time}, ${date}`;
}

/**
 * Build the subtitle line shown under a stamp label.
 * - includeUser + includeDate → "By Robert Olen at 6:36 pm, May 21, 2026"
 * - !includeUser + includeDate → "6:36 pm, May 21, 2026"
 * - includeUser + !includeDate → "By Robert Olen"
 * - neither                    → ""
 */
export function buildStampSubtext(opts: {
  includeUser: boolean;
  includeDate: boolean;
  date?: Date;
}): string {
  const u = opts.includeUser ? getStampUserDisplay() : '';
  const t = opts.includeDate ? formatStampDateTime(opts.date) : '';
  if (u && t) return `By ${u} at ${t}`;
  if (u) return `By ${u}`;
  if (t) return t;
  return '';
}
