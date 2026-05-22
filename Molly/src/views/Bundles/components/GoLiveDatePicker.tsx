import { useMemo } from 'react';
import { validateGoLiveDate } from '../../../lib/bundleValidation';

interface Props {
  value: string | null;
  onChange: (s: string | null) => void;
  disabled?: boolean;
  /** Optional default to suggest if the field is empty (e.g. tomorrow). */
  defaultValue?: string;
}

function todayIso(d: Date = new Date()): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${dd}`;
}

/** Date picker that hard-blocks past dates at the input level + surfaces
 * the "are you allowing enough time for editing?" warning under the input. */
export function GoLiveDatePicker({ value, onChange, disabled, defaultValue }: Props) {
  const today = new Date();
  const min = todayIso(today);
  const issues = useMemo(() => validateGoLiveDate(value, today), [value]);
  const issue = issues[0];

  return (
    <div className="space-y-1">
      <label htmlFor="bundle-go-live" className="text-xs font-semibold opacity-75">Go-live date</label>
      <input
        id="bundle-go-live"
        type="date"
        className="pretty-input w-full"
        min={min}
        value={value ?? ''}
        onChange={(e) => onChange(e.target.value || null)}
        disabled={disabled}
      />
      {issue && (
        <div className={`text-xs ${issue.severity === 'warn' ? 'text-amber-700' : 'text-red-700'}`}>
          {issue.message}
        </div>
      )}
      {!value && defaultValue && (
        <button
          type="button"
          onClick={() => onChange(defaultValue)}
          className="text-xs opacity-70 underline"
          disabled={disabled}
        >
          Use {defaultValue}
        </button>
      )}
    </div>
  );
}
