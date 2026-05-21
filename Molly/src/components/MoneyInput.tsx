import { useEffect, useRef, useState } from 'react';

interface Props {
  value: number;
  onChange: (n: number) => void;
  className?: string;
  placeholder?: string;
  /** Render an empty string when the underlying value is 0 (true)
   *  or "0.00" (false). Default: true — feels right for free-form
   *  amount fields, less surprising than a pre-filled zero. */
  blankWhenZero?: boolean;
}

/**
 * Controlled-value, uncontrolled-display money input.
 *
 * The classic "<input value={String(num)} onChange={parseMoney}>" pattern
 * has a fatal flaw for decimals: typing "5." parses to 5, re-renders as
 * "5", strips the trailing dot, and the user can never type cents. We
 * fix this by keeping a *string buffer* as the source of truth for the
 * input display, while still emitting the canonical numeric value to
 * the parent on every change. A ref tracks the value we just emitted so
 * parent re-renders triggered by our own onChange don't clobber the
 * buffer; only an external value change (e.g. switching rows) re-inits
 * the display.
 *
 * Used everywhere previously calling parseMoney directly in onChange:
 * Adhoc income, Expenses (amount + exclusionAmount), Recurring
 * expenses, Site income wizard.
 */
export function MoneyInput({ value, onChange, className, placeholder, blankWhenZero = true }: Props) {
  const initial = blankWhenZero && value === 0 ? '' : value.toFixed(2);
  const [text, setText] = useState<string>(initial);
  const lastEmitted = useRef<number>(value);

  // Re-initialize the buffer when the value changes from outside
  // (caller switched rows / canceled). When the caller is just echoing
  // our own emitted value back, lastEmitted will match and we leave the
  // buffer alone so the user's in-flight typing isn't reformatted.
  useEffect(() => {
    if (value !== lastEmitted.current) {
      setText(blankWhenZero && value === 0 ? '' : value.toFixed(2));
      lastEmitted.current = value;
    }
  }, [value, blankWhenZero]);

  function emit(parsed: number) {
    lastEmitted.current = parsed;
    onChange(parsed);
  }

  function handleChange(raw: string) {
    setText(raw);
    // Strip currency symbols / commas / whitespace; tolerate partials
    // like "5.", ".5", "" — they all parse to a useful number (or 0 for "").
    const cleaned = raw.replace(/[$,\s]/g, '');
    const n = parseFloat(cleaned);
    emit(Number.isFinite(n) ? n : 0);
  }

  function handleBlur() {
    const cleaned = text.replace(/[$,\s]/g, '');
    if (cleaned === '' || cleaned === '.') {
      setText(blankWhenZero ? '' : '0.00');
      emit(0);
      return;
    }
    const n = parseFloat(cleaned);
    if (Number.isFinite(n)) {
      setText(n.toFixed(2));
      emit(n);
    }
  }

  return (
    <input
      type="text"
      inputMode="decimal"
      className={className}
      value={text}
      placeholder={placeholder ?? '0.00'}
      onChange={(e) => handleChange(e.target.value)}
      onBlur={handleBlur}
    />
  );
}
