import { MONTH_NAMES } from '../../model/types';

/** Easy month dropdown + year stepper. Any past/future month is allowed. */
export function MonthYearPicker({ year, month, onChange }: { year: number; month: number; onChange: (year: number, month: number) => void }) {
  return (
    <div className="row" style={{ gap: 10 }}>
      <select value={month} onChange={(e) => onChange(year, parseInt(e.target.value, 10))} style={{ flex: 1 }}>
        {MONTH_NAMES.map((m, i) => (
          <option key={i} value={i + 1}>{m}</option>
        ))}
      </select>
      <div className="row" style={{ gap: 4 }}>
        <button onClick={() => onChange(year - 1, month)} aria-label="Previous year">−</button>
        <input
          type="number"
          value={year}
          onChange={(e) => onChange(parseInt(e.target.value || '0', 10) || year, month)}
          style={{ width: 92, textAlign: 'center' }}
        />
        <button onClick={() => onChange(year + 1, month)} aria-label="Next year">+</button>
      </div>
    </div>
  );
}

/** Default month = current month + 1 (rolling Dec→Jan). */
export function defaultYearMonth(now = new Date()): { year: number; month: number } {
  let month = now.getMonth() + 2; // getMonth() is 0-based; +1 for 1-based, +1 for "next month"
  let year = now.getFullYear();
  if (month > 12) {
    month -= 12;
    year += 1;
  }
  return { year, month };
}
