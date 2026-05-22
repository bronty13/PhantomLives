import { useEffect, useState } from 'react';

interface Props {
  value: string;
  onCommit: (s: string) => void;          // fires on blur
  label?: string;
  placeholder?: string;
  rows?: number;
  fieldId?: string;
  disabled?: boolean;
}

/** Plain textarea for free-form notes (optional in spec). Used by every
 * bundle type for "Special Instructions" and also reused by FanDayModal
 * for the per-day short message in PR2. */
export function SpecialInstructionsField({
  value, onCommit, label = 'Special instructions', placeholder = "Anything Robert should know? (optional)",
  rows = 3, fieldId = 'bundle-special-instructions', disabled,
}: Props) {
  const [draft, setDraft] = useState(value);
  useEffect(() => { setDraft(value); }, [value]);
  return (
    <div className="space-y-1">
      <label htmlFor={fieldId} className="text-xs font-semibold opacity-75">{label}</label>
      <textarea
        id={fieldId}
        className="pretty-input w-full"
        rows={rows}
        value={draft}
        placeholder={placeholder}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={() => { if (draft !== value) onCommit(draft); }}
        disabled={disabled}
      />
    </div>
  );
}
