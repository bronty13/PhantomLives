import { useEffect, useRef, useState } from 'react';

interface Props {
  title: string;
  description?: string;
  initialValue?: string;
  placeholder?: string;
  confirmLabel?: string;
  /** When set, accept the typed value only if it passes; show the
   *  returned string as an inline error if not. Return null to accept. */
  validate?: (v: string) => string | null;
  onSubmit: (value: string) => void | Promise<void>;
  onCancel: () => void;
}

/** Tauri-safe replacement for window.prompt. Renders an in-app modal
 *  with a single text input. window.prompt() is silently disabled by
 *  Tauri 2's WebView in many configurations, so we never use it. */
export function NamePromptModal({
  title, description, initialValue = '', placeholder, confirmLabel = 'Save',
  validate, onSubmit, onCancel,
}: Props) {
  const [value, setValue] = useState(initialValue);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const inputRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    inputRef.current?.focus();
    inputRef.current?.select();
  }, []);

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onCancel();
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onCancel]);

  async function submit() {
    const trimmed = value.trim();
    if (validate) {
      const err = validate(trimmed);
      if (err) { setError(err); return; }
    } else if (trimmed.length === 0) {
      setError('Please enter something.');
      return;
    }
    setBusy(true); setError(null);
    try { await onSubmit(trimmed); }
    catch (e) { setError(String((e as { message?: string })?.message ?? e)); }
    finally { setBusy(false); }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 backdrop-blur-sm"
      onClick={onCancel}
    >
      <div
        className="rounded-3xl bg-white shadow-2xl border border-black/10 p-5 w-[420px] max-w-[90vw]"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between mb-3">
          <h3 className="display-font text-lg font-semibold persona-accent">{title}</h3>
          <button type="button" onClick={onCancel} className="opacity-50 hover:opacity-100 text-xl leading-none">×</button>
        </div>
        {description && <p className="text-xs opacity-70 mb-3">{description}</p>}
        <input
          ref={inputRef}
          type="text"
          value={value}
          onChange={(e) => { setValue(e.target.value); if (error) setError(null); }}
          onKeyDown={(e) => {
            if (e.key === 'Enter') { e.preventDefault(); submit(); }
          }}
          placeholder={placeholder}
          className="pretty-input w-full"
          disabled={busy}
        />
        {error && (
          <div className="text-xs text-red-700 bg-red-50 border border-red-200 rounded-xl px-3 py-2 mt-2">{error}</div>
        )}
        <div className="flex justify-end gap-2 mt-4">
          <button type="button" onClick={onCancel} disabled={busy} className="pretty-button secondary">
            Cancel
          </button>
          <button type="button" onClick={submit} disabled={busy} className="pretty-button">
            {busy ? 'Saving…' : confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
