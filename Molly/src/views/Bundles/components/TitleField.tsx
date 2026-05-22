import { useEffect, useState } from 'react';
import { validateTitle } from '../../../lib/bundleValidation';

interface Props {
  value: string;
  onCommit: (s: string) => void;          // fires on blur
  disabled?: boolean;
}

/** Bundle title input. Live-validates; shows inline error after first blur. */
export function TitleField({ value, onCommit, disabled }: Props) {
  const [draft, setDraft] = useState(value);
  const [touched, setTouched] = useState(false);
  useEffect(() => { setDraft(value); }, [value]);

  const issues = validateTitle(draft);
  const errorMessage = touched && issues.length > 0 ? issues[0].message : '';

  return (
    <div className="space-y-1">
      <label htmlFor="bundle-title" className="text-xs font-semibold opacity-75">Title</label>
      <input
        id="bundle-title"
        type="text"
        className="pretty-input w-full"
        placeholder="e.g. Spring Picnic Bundle"
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={() => { setTouched(true); if (draft !== value) onCommit(draft); }}
        disabled={disabled}
      />
      {errorMessage && (
        <div className="text-xs text-red-700">{errorMessage}</div>
      )}
    </div>
  );
}
