// Phase 9 — bundle UID helpers.
//
// The authoritative UID generator lives in Rust (bundles.rs::next_uid_in_conn);
// when the frontend calls createBundle, the Rust side decides the next UID and
// returns it. This module exposes pure helpers used in tests + display.

/** YYYY-MM-DD in the local timezone — what bundle UIDs prefix on. */
export function todayIso(now: Date = new Date()): string {
  const yyyy = now.getFullYear();
  const mm = String(now.getMonth() + 1).padStart(2, '0');
  const dd = String(now.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
}

/** Construct a bundle UID with a 4-digit counter (1..9999). */
export function formatBundleUid(date: string, counter: number): string {
  if (counter < 1 || counter > 9999) {
    throw new Error(`counter out of range: ${counter}`);
  }
  return `${date}-${String(counter).padStart(4, '0')}`;
}

/** Parse a bundle UID string into (date, counter). Returns null on bad shape. */
export function parseBundleUid(uid: string): { date: string; counter: number } | null {
  const m = uid.match(/^(\d{4}-\d{2}-\d{2})-(\d{4})$/);
  if (!m) return null;
  return { date: m[1], counter: parseInt(m[2], 10) };
}
