import { describe, expect, it } from 'vitest';
import {
  addDays,
  endOfMonth,
  isoDate,
  nextOccurrencesAfter,
  parseIso,
  startOfMonth,
  startOfNextMonth,
} from './cadence';

describe('date helpers', () => {
  it('isoDate formats local-time Y-M-D with zero-padding', () => {
    expect(isoDate(new Date(2026, 0, 5))).toBe('2026-01-05');
    expect(isoDate(new Date(2026, 11, 31))).toBe('2026-12-31');
  });

  it('parseIso round-trips with isoDate', () => {
    const s = '2026-05-21';
    expect(isoDate(parseIso(s))).toBe(s);
  });

  it('addDays handles negative + wrap-around', () => {
    expect(isoDate(addDays(parseIso('2026-05-01'), -1))).toBe('2026-04-30');
    expect(isoDate(addDays(parseIso('2026-01-01'), -1))).toBe('2025-12-31');
  });

  it('startOfMonth / endOfMonth pin the bounds', () => {
    const mid = parseIso('2026-02-15');
    expect(isoDate(startOfMonth(mid))).toBe('2026-02-01');
    expect(isoDate(endOfMonth(mid))).toBe('2026-02-28'); // 2026 is not a leap year
  });

  it('endOfMonth handles February in a leap year', () => {
    expect(isoDate(endOfMonth(parseIso('2024-02-10')))).toBe('2024-02-29');
  });

  it('startOfNextMonth crosses year boundary', () => {
    expect(isoDate(startOfNextMonth(parseIso('2026-12-15')))).toBe('2027-01-01');
  });
});

describe('nextOccurrencesAfter — daily', () => {
  it('emits consecutive days starting the day after `from` by default', () => {
    const dates = nextOccurrencesAfter({ kind: 'daily' }, parseIso('2026-05-21'), 3);
    expect(dates).toEqual(['2026-05-22', '2026-05-23', '2026-05-24']);
  });

  it('honors `inclusive` to include the start date itself', () => {
    const dates = nextOccurrencesAfter({ kind: 'daily' }, parseIso('2026-05-21'), 3, true);
    expect(dates).toEqual(['2026-05-21', '2026-05-22', '2026-05-23']);
  });
});

describe('nextOccurrencesAfter — weekly', () => {
  // 2026-05-21 is a Thursday (4). 2026-05-25 is Mon (1), 2026-05-28 Thu (4).
  it('emits the listed weekdays after the start date', () => {
    const dates = nextOccurrencesAfter(
      { kind: 'weekly', days: [1, 4] }, // Mon + Thu
      parseIso('2026-05-21'),
      4,
    );
    expect(dates).toEqual(['2026-05-25', '2026-05-28', '2026-06-01', '2026-06-04']);
  });

  it('returns [] when no days are listed', () => {
    expect(
      nextOccurrencesAfter({ kind: 'weekly', days: [] }, parseIso('2026-05-21'), 3),
    ).toEqual([]);
  });

  it('biweekly (everyN=2) skips alternating weeks consistently from anchor', () => {
    const dates = nextOccurrencesAfter(
      { kind: 'weekly', days: [1], everyN: 2, anchor: '2026-05-04' }, // every other Monday
      parseIso('2026-05-04'),
      3,
      true, // include the anchor itself
    );
    // Anchor week 0 → Mon May 4; week 1 skipped; week 2 → May 18; week 4 → June 1.
    expect(dates).toEqual(['2026-05-04', '2026-05-18', '2026-06-01']);
  });
});

describe('nextOccurrencesAfter — monthly_dom', () => {
  it('fires on the same day-of-month each month', () => {
    const dates = nextOccurrencesAfter(
      { kind: 'monthly_dom', day: 15 },
      parseIso('2026-05-01'),
      3,
    );
    expect(dates).toEqual(['2026-05-15', '2026-06-15', '2026-07-15']);
  });

  it('clamps to end-of-month for short months', () => {
    const dates = nextOccurrencesAfter(
      { kind: 'monthly_dom', day: 31 },
      parseIso('2026-01-01'),
      4,
    );
    // Jan 31, Feb 28 (clamped), Mar 31, Apr 30 (clamped).
    expect(dates).toEqual(['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30']);
  });

  it('skips the current month if its target day has already passed', () => {
    const dates = nextOccurrencesAfter(
      { kind: 'monthly_dom', day: 10 },
      parseIso('2026-05-21'),
      2,
    );
    expect(dates).toEqual(['2026-06-10', '2026-07-10']);
  });
});

describe('nextOccurrencesAfter — monthly_days_before_next', () => {
  it('fires N days before the next month starts', () => {
    // 10 days before June 1 = May 22; 10 days before July 1 = June 21.
    const dates = nextOccurrencesAfter(
      { kind: 'monthly_days_before_next', daysBefore: 10 },
      parseIso('2026-05-01'),
      2,
    );
    expect(dates).toEqual(['2026-05-22', '2026-06-21']);
  });
});

describe('nextOccurrencesAfter — monthly_days_after_eom', () => {
  it('fires N days after end-of-month', () => {
    // EoM May = May 31; +3 = June 3. EoM June = June 30; +3 = July 3.
    const dates = nextOccurrencesAfter(
      { kind: 'monthly_days_after_eom', daysAfter: 3 },
      parseIso('2026-05-01'),
      2,
    );
    expect(dates).toEqual(['2026-06-03', '2026-07-03']);
  });
});

describe('nextOccurrencesAfter — every_n_days', () => {
  it('emits dates spaced n days apart starting from the first multiple after `from`', () => {
    const dates = nextOccurrencesAfter(
      { kind: 'every_n_days', n: 7, anchor: '2026-05-04' },
      parseIso('2026-05-21'),
      3,
    );
    // Anchor May 4 + 7*3 = May 25 (first multiple >= May 22 which is from+1).
    expect(dates).toEqual(['2026-05-25', '2026-06-01', '2026-06-08']);
  });
});
