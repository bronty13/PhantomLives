import { useEffect, useState } from 'react';
import { totalsForPeriod } from '../../data/income';
import { fmtMoney, MONTH_NAMES, todayParts } from '../../lib/money';
import { useMonthlyGoals, type MonthNumber } from '../../state/incomeGoals';

interface Props {
  /** Year selected on the Adhoc Income view. */
  year: number;
  /** Month selected on the Adhoc Income view (1–12, or 'all' for whole year). */
  month: number | 'all';
  /** Re-fetch ticker — bump after every income save in the parent so the
   *  progress bar re-reads the DB without us needing our own listener. */
  refreshKey?: number;
}

/**
 * Pretty goal-progress card on the Adhoc Income tab. Renders only for
 * the **current calendar month** view — past months are static history
 * (tax-prep mode) and a goal-vs-actual ribbon would be noise.
 *
 * Pulls the current adhoc total via `totalsForPeriod(...).adhocTotal`,
 * which already sums adhoc + customer_sales for the chosen month.
 */
export function GoalProgress({ year, month, refreshKey = 0 }: Props) {
  const { goals, loaded } = useMonthlyGoals();
  const [actual, setActual] = useState<number>(0);
  const today = todayParts();

  // Only render for the current calendar month — past months don't get
  // a goal bar (we're not going to make Sallie feel bad about June
  // 2024). 'all'-year view also hides.
  const isCurrentMonth = year === today.year && month === today.month;
  const goalDollars = isCurrentMonth ? goals[month as MonthNumber] : 0;

  useEffect(() => {
    let alive = true;
    if (!isCurrentMonth) {
      setActual(0);
      return;
    }
    totalsForPeriod({ year, month: month as number })
      .then((t) => {
        if (alive) setActual(t.adhocTotal);
      })
      .catch(() => {
        if (alive) setActual(0);
      });
    return () => { alive = false; };
  }, [year, month, refreshKey, isCurrentMonth]);

  if (!isCurrentMonth || !loaded) return null;

  const percent = goalDollars > 0 ? (actual / goalDollars) * 100 : 0;
  const fillPct = Math.min(100, Math.max(0, percent));
  const over = actual > goalDollars ? actual - goalDollars : 0;
  const daysLeft = daysLeftInMonth(today.year, today.month, today.day);

  return (
    <div
      className="pretty-card"
      style={{
        background:
          'linear-gradient(135deg, rgb(var(--persona-secondary) / 0.7), rgb(var(--persona-tint)))',
        border: '1px solid rgb(var(--persona-primary) / 0.45)',
      }}
    >
      <div className="flex items-baseline justify-between gap-4 flex-wrap">
        <div className="min-w-0">
          <div className="text-xs uppercase tracking-wider opacity-60">
            {MONTH_NAMES[today.month - 1]} goal
          </div>
          <div className="flex items-baseline gap-2 mt-0.5">
            <span
              className="persona-accent font-bold"
              style={{
                fontFamily: 'Caveat, "Paper Daisy", cursive',
                fontSize: '2.6rem',
                lineHeight: 1,
              }}
            >
              {fmtMoney(actual)}
            </span>
            <span className="text-sm opacity-70">of {fmtMoney(goalDollars)}</span>
          </div>
        </div>
        <div className="text-right text-xs opacity-70 leading-tight">
          <div className="display-font font-semibold persona-accent text-base">
            {Math.round(percent)}%
          </div>
          {goalDollars > 0 && (
            <div>{daysLeft === 0 ? 'last day of month!' : `${daysLeft} day${daysLeft === 1 ? '' : 's'} left`}</div>
          )}
        </div>
      </div>

      <div
        className="mt-3 relative h-5 rounded-full overflow-hidden"
        style={{ background: 'rgb(var(--persona-primary) / 0.18)' }}
      >
        <div
          className="absolute top-0 left-0 h-full rounded-full"
          style={{
            width: `${fillPct}%`,
            background:
              'linear-gradient(90deg, rgb(var(--persona-accent)), rgb(var(--persona-primary)))',
            transition: 'width 480ms cubic-bezier(0.16, 1.0, 0.3, 1)',
            boxShadow: '0 0 12px rgb(var(--persona-accent) / 0.55)',
          }}
        />
        {/* Milestone markers — light up once passed */}
        {[25, 50, 75, 100].map((m) => (
          <span
            key={m}
            className="absolute top-1/2 text-[11px] leading-none"
            style={{
              left: `${m}%`,
              transform: 'translate(-50%, -50%)',
              opacity: percent >= m ? 1 : 0.4,
              filter: percent >= m ? 'drop-shadow(0 0 3px white)' : 'none',
              transition: 'opacity 280ms ease, filter 280ms ease',
              userSelect: 'none',
            }}
            aria-hidden
          >
            {m === 25 ? '🌸' : m === 50 ? '🌷' : m === 75 ? '🌟' : '🎉'}
          </span>
        ))}
      </div>

      {over > 0 && (
        <div
          className="inline-flex items-center gap-1 mt-2 px-2.5 py-0.5 rounded-full text-xs font-semibold"
          style={{
            background: 'rgb(var(--persona-accent))',
            color: 'white',
            boxShadow: '0 4px 10px -4px rgb(var(--persona-accent) / 0.55)',
          }}
        >
          🚀 +{fmtMoney(over)} over goal!
        </div>
      )}
    </div>
  );
}

function daysLeftInMonth(year: number, month: number, day: number): number {
  // Days remaining including today's room to add more income. month
  // is 1-indexed; new Date(year, month, 0) gives the last day of the
  // requested 1-indexed month.
  const lastDay = new Date(year, month, 0).getDate();
  return Math.max(0, lastDay - day);
}
