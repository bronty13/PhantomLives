import { useEffect, useState } from 'react';
import { db } from '../data/db';

// Monthly adhoc-income goals. Each month's target is one row in
// `app_settings` keyed `goals.adhocMonthly.<MM>` (zero-padded) with
// the value stored as an integer cents string. The cents convention
// matches the rest of the money-handling code (customer_sales,
// products); the public API on this module trades in dollars (number).
//
// No migration: rows are created lazily on first save. Sites that
// haven't customized a month see the hard-coded default — flipping a
// default in code therefore propagates automatically to anyone who
// has never touched that month, and never overrides a user who has.

export type MonthNumber = 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12;

export type MonthlyGoals = Record<MonthNumber, number>;

export const DEFAULT_GOALS: MonthlyGoals = {
  1: 1000, 2: 1000, 3: 1000, 4: 1000, 5: 1000, 6: 1000,
  7: 1000, 8: 1000, 9: 1000, 10: 1000, 11: 2000, 12: 2000,
};

export const ALL_MONTHS: readonly MonthNumber[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

function keyFor(month: MonthNumber): string {
  return `goals.adhocMonthly.${String(month).padStart(2, '0')}`;
}

export async function loadMonthlyGoals(): Promise<MonthlyGoals> {
  const out: MonthlyGoals = { ...DEFAULT_GOALS };
  try {
    const conn = await db();
    const rows = await conn.select<{ key: string; value: string }[]>(
      "SELECT key, value FROM app_settings WHERE key LIKE 'goals.adhocMonthly.%'",
    );
    for (const r of rows) {
      const m = r.key.match(/^goals\.adhocMonthly\.(\d{2})$/);
      if (!m) continue;
      const month = parseInt(m[1], 10);
      if (!ALL_MONTHS.includes(month as MonthNumber)) continue;
      const cents = parseInt(r.value, 10);
      if (Number.isFinite(cents) && cents >= 0) {
        out[month as MonthNumber] = cents / 100;
      }
    }
  } catch {
    // first-run / DB not ready yet — fall through to defaults
  }
  return out;
}

export async function saveMonthlyGoal(month: MonthNumber, dollars: number): Promise<void> {
  const cents = Math.max(0, Math.round(dollars * 100));
  const conn = await db();
  await conn.execute(
    'INSERT INTO app_settings (key, value) VALUES ($1, $2) ON CONFLICT(key) DO UPDATE SET value = $2',
    [keyFor(month), String(cents)],
  );
}

export async function resetMonthlyGoalsToDefaults(): Promise<void> {
  for (const m of ALL_MONTHS) {
    await saveMonthlyGoal(m, DEFAULT_GOALS[m]);
  }
}

/**
 * Hook for the monthly-goals map. `loaded` lets callers wait one tick
 * before rendering goal-aware UI so the GoalProgress card doesn't
 * briefly show defaults before the saved values arrive.
 */
export function useMonthlyGoals() {
  const [goals, setGoalsState] = useState<MonthlyGoals>(DEFAULT_GOALS);
  const [loaded, setLoaded] = useState<boolean>(false);

  useEffect(() => {
    let alive = true;
    loadMonthlyGoals().then((g) => {
      if (!alive) return;
      setGoalsState(g);
      setLoaded(true);
    });
    return () => { alive = false; };
  }, []);

  async function setGoal(month: MonthNumber, dollars: number) {
    setGoalsState((cur) => ({ ...cur, [month]: dollars }));
    try {
      await saveMonthlyGoal(month, dollars);
    } catch (e) {
      console.warn('Could not persist monthly goal', e);
    }
  }

  async function resetAll() {
    setGoalsState(DEFAULT_GOALS);
    try {
      await resetMonthlyGoalsToDefaults();
    } catch (e) {
      console.warn('Could not reset monthly goals', e);
    }
  }

  return { goals, setGoal, resetAll, loaded };
}
