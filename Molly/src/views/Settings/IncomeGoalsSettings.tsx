import { useState } from 'react';
import { MoneyInput } from '../../components/MoneyInput';
import { MONTH_NAMES, fmtMoney } from '../../lib/money';
import {
  ALL_MONTHS,
  DEFAULT_GOALS,
  useMonthlyGoals,
  type MonthNumber,
} from '../../state/incomeGoals';

export function IncomeGoalsSettings() {
  const { goals, setGoal, resetAll, loaded } = useMonthlyGoals();
  const [status, setStatus] = useState<string>('');

  async function onCommit(month: MonthNumber, dollars: number) {
    await setGoal(month, dollars);
    setStatus(`Saved ${MONTH_NAMES[month - 1]}.`);
  }

  async function onReset() {
    if (!confirm('Reset every month back to the defaults ($1000 Jan–Oct, $2000 Nov–Dec)?')) return;
    await resetAll();
    setStatus('All months reset to defaults.');
  }

  const annualTotal = ALL_MONTHS.reduce((acc, m) => acc + goals[m], 0);

  return (
    <div className="space-y-3">
      <div className="pretty-card">
        <h3 className="display-font text-xl font-semibold persona-accent mb-1">💎 Monthly income goals</h3>
        <p className="text-sm opacity-70 mb-4">
          Set Sallie's target for adhoc income each month — the
          progress bar on the Income tab fills toward this number, and
          crossing 25 / 50 / 75 / 100% triggers a milestone celebration.
          Defaults are $1,000 for Jan–Oct (steady months) and $2,000
          for Nov–Dec (holiday season).
        </p>

        <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
          {ALL_MONTHS.map((m) => (
            <label key={m} className="flex flex-col gap-1">
              <span className="text-xs uppercase tracking-wider opacity-60 flex justify-between">
                <span>{MONTH_NAMES[m - 1]}</span>
                {goals[m] !== DEFAULT_GOALS[m] && (
                  <span className="opacity-50 normal-case tracking-normal">
                    default {fmtMoney(DEFAULT_GOALS[m])}
                  </span>
                )}
              </span>
              <MoneyInput
                className="pretty-input font-mono"
                value={goals[m]}
                onChange={(dollars) => void onCommit(m, dollars)}
                blankWhenZero={false}
              />
            </label>
          ))}
        </div>

        <div className="flex items-center justify-between mt-4">
          <div className="text-xs opacity-70">
            Annual target:{' '}
            <span className="font-mono font-semibold persona-accent">{fmtMoney(annualTotal)}</span>
          </div>
          <button
            type="button"
            onClick={onReset}
            className="pretty-button secondary text-xs px-3 py-1"
            disabled={!loaded}
          >
            ↺ Reset to defaults
          </button>
        </div>

        {status && (
          <div className="text-xs opacity-70 mt-2 italic">{status}</div>
        )}
      </div>
    </div>
  );
}
