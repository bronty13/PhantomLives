/**
 * Cadence engine — no cron, ever. The wizard speaks human ("every
 * Mon + Thu", "10 days before next month") and serializes to one of
 * the Cadence variants below. `nextOccurrencesAfter` walks forward
 * deterministically to materialize occurrences.
 *
 * Semantic mirror of PurpleTracker's `Cadence` model
 * (`PurpleTracker/Sources/PurpleTracker/Models/Cadence.swift`).
 */

export type Weekday = 0 | 1 | 2 | 3 | 4 | 5 | 6; // 0 = Sun, 6 = Sat

export type Cadence =
  | { kind: 'daily' }
  /** Fires on each listed weekday. `everyN` lets you do biweekly (N=2). */
  | { kind: 'weekly'; days: Weekday[]; everyN?: number; anchor?: string }
  /** Fires on the Nth day of every month. Clamps to end-of-month for short months. */
  | { kind: 'monthly_dom'; day: number }
  /** Fires on (1st of next month - daysBefore). E.g. 10 days before next month starts. */
  | { kind: 'monthly_days_before_next'; daysBefore: number }
  /** Fires on (last day of month + daysAfter). E.g. 3 days after month end. */
  | { kind: 'monthly_days_after_eom'; daysAfter: number }
  /** Fires every N days, starting from `anchor` (ISO date YYYY-MM-DD). */
  | { kind: 'every_n_days'; n: number; anchor: string };

export const WEEKDAY_LABELS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

// ---------- date helpers (UTC-safe, work in YYYY-MM-DD strings) -------------

export function isoDate(d: Date): string {
  const y = d.getFullYear().toString().padStart(4, '0');
  const m = (d.getMonth() + 1).toString().padStart(2, '0');
  const day = d.getDate().toString().padStart(2, '0');
  return `${y}-${m}-${day}`;
}

export function parseIso(s: string): Date {
  // Local-time anchored midnight. Avoids the off-by-one bug from
  // `new Date('YYYY-MM-DD')` (which parses as UTC).
  const [y, m, d] = s.split('-').map(Number);
  return new Date(y, (m ?? 1) - 1, d ?? 1);
}

export function addDays(d: Date, n: number): Date {
  const out = new Date(d);
  out.setDate(out.getDate() + n);
  return out;
}

export function startOfMonth(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), 1);
}

export function endOfMonth(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth() + 1, 0); // day 0 of next month = last day of this month
}

export function startOfNextMonth(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth() + 1, 1);
}

export function daysInMonth(d: Date): number {
  return endOfMonth(d).getDate();
}

// ---------- core: next occurrences ----------------------------------------

/**
 * Return the next `count` occurrences strictly AFTER `from` (or on/after
 * `from` when `inclusive=true`). Returns ISO date strings (YYYY-MM-DD).
 */
export function nextOccurrencesAfter(
  cadence: Cadence,
  from: Date,
  count: number,
  inclusive = false,
): string[] {
  const out: string[] = [];
  const startDate = inclusive ? from : addDays(from, 1);
  // Hard cap on the look-ahead to defend against pathological cadences.
  const maxLookAheadDays = 365 * 5;

  switch (cadence.kind) {
    case 'daily': {
      let d = startDate;
      for (let i = 0; i < count; i++) {
        out.push(isoDate(d));
        d = addDays(d, 1);
      }
      return out;
    }

    case 'weekly': {
      const days = [...new Set(cadence.days)].sort();
      if (days.length === 0) return [];
      const everyN = Math.max(1, cadence.everyN ?? 1);

      // Anchor week: count weeks from anchor (or 1970-01-04 = Sunday) so
      // biweekly is consistent across runs.
      const anchor = cadence.anchor ? parseIso(cadence.anchor) : new Date(1970, 0, 4);
      const anchorStartOfWeek = addDays(anchor, -anchor.getDay()); // back to Sunday

      let d = startDate;
      for (let i = 0; i < maxLookAheadDays && out.length < count; i++) {
        const weekday = d.getDay() as Weekday;
        if (days.includes(weekday)) {
          const weeksSinceAnchor = Math.floor(
            (addDays(d, -d.getDay()).getTime() - anchorStartOfWeek.getTime()) / (7 * 86_400_000),
          );
          if (weeksSinceAnchor % everyN === 0) {
            out.push(isoDate(d));
          }
        }
        d = addDays(d, 1);
      }
      return out;
    }

    case 'monthly_dom': {
      const target = clamp(cadence.day, 1, 31);
      let cursor = startOfMonth(startDate);
      // If we are mid-month and the target day this month is still ahead, use it; else move to next month.
      while (out.length < count) {
        const dim = daysInMonth(cursor);
        const dayThisMonth = Math.min(target, dim);
        const candidate = new Date(cursor.getFullYear(), cursor.getMonth(), dayThisMonth);
        if (candidate >= startDate) {
          out.push(isoDate(candidate));
        }
        cursor = startOfNextMonth(cursor);
        if (cursor.getFullYear() - startDate.getFullYear() > 5) break;
      }
      return out;
    }

    case 'monthly_days_before_next': {
      const offset = Math.max(0, cadence.daysBefore);
      let cursor = startOfMonth(startDate);
      while (out.length < count) {
        const next1 = startOfNextMonth(cursor);
        const candidate = addDays(next1, -offset);
        if (candidate >= startDate) {
          out.push(isoDate(candidate));
        }
        cursor = startOfNextMonth(cursor);
        if (cursor.getFullYear() - startDate.getFullYear() > 5) break;
      }
      return out;
    }

    case 'monthly_days_after_eom': {
      const offset = Math.max(0, cadence.daysAfter);
      let cursor = startOfMonth(startDate);
      while (out.length < count) {
        const eom = endOfMonth(cursor);
        const candidate = addDays(eom, offset);
        if (candidate >= startDate) {
          out.push(isoDate(candidate));
        }
        cursor = startOfNextMonth(cursor);
        if (cursor.getFullYear() - startDate.getFullYear() > 5) break;
      }
      return out;
    }

    case 'every_n_days': {
      const n = Math.max(1, cadence.n);
      const anchor = parseIso(cadence.anchor);
      // Find the first multiple of n on or after startDate.
      const deltaDays = Math.ceil((startDate.getTime() - anchor.getTime()) / 86_400_000);
      const skip = Math.max(0, Math.ceil(deltaDays / n));
      let d = addDays(anchor, skip * n);
      for (let i = 0; i < count; i++) {
        out.push(isoDate(d));
        d = addDays(d, n);
      }
      return out;
    }
  }
}

function clamp(n: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, n));
}

// ---------- describe (human-readable) ------------------------------------

export function describeCadence(c: Cadence): string {
  switch (c.kind) {
    case 'daily': return 'Every day';
    case 'weekly': {
      const days = [...new Set(c.days)].sort();
      const labels = days.map((d) => WEEKDAY_LABELS[d]).join(' + ');
      const everyN = c.everyN ?? 1;
      if (everyN === 1) return `Weekly · ${labels || '(no days)'}`;
      if (everyN === 2) return `Biweekly · ${labels || '(no days)'}`;
      return `Every ${everyN} weeks · ${labels || '(no days)'}`;
    }
    case 'monthly_dom': {
      const day = c.day;
      const suffix = (day === 1 || day === 21 || day === 31) ? 'st'
                   : (day === 2 || day === 22) ? 'nd'
                   : (day === 3 || day === 23) ? 'rd'
                   : 'th';
      return `Monthly · ${day}${suffix} of each month`;
    }
    case 'monthly_days_before_next':
      return c.daysBefore === 0
        ? 'Monthly · on the 1st of the next month'
        : `Monthly · ${c.daysBefore} day${c.daysBefore === 1 ? '' : 's'} before next month starts`;
    case 'monthly_days_after_eom':
      return c.daysAfter === 0
        ? 'Monthly · on the last day of the month'
        : `Monthly · ${c.daysAfter} day${c.daysAfter === 1 ? '' : 's'} after the month ends`;
    case 'every_n_days':
      return c.n === 1 ? 'Every day' : `Every ${c.n} days (anchored ${c.anchor})`;
  }
}

// ---------- sane defaults / validation ------------------------------------

export function defaultCadence(): Cadence {
  return { kind: 'weekly', days: [1] }; // Monday
}

export function isCadenceValid(c: Cadence): boolean {
  switch (c.kind) {
    case 'daily': return true;
    case 'weekly': return c.days.length > 0;
    case 'monthly_dom': return c.day >= 1 && c.day <= 31;
    case 'monthly_days_before_next': return c.daysBefore >= 0 && c.daysBefore <= 28;
    case 'monthly_days_after_eom':   return c.daysAfter  >= 0 && c.daysAfter  <= 28;
    case 'every_n_days': return c.n >= 1 && !!c.anchor;
  }
}
