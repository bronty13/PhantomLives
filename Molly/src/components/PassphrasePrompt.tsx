import { useEffect, useRef, useState } from 'react';

interface Props {
  title?: string;
  description?: string;
  confirmLabel?: string;
  /** When true, prompt asks for confirmation (init / change / import flow). */
  requireConfirm?: boolean;
  /** Show a second "Old passphrase" field (change-passphrase flow). */
  requireOld?: boolean;
  /** Minimum length for the new passphrase. Default 10. */
  minLength?: number;
  onSubmit: (passphrase: string, oldPassphrase?: string) => Promise<void>;
  onCancel: () => void;
}

/** Reusable passphrase modal. Single source of truth for init,
 * change-passphrase, unlock, and import flows. */
export function PassphrasePrompt({
  title = 'Enter passphrase',
  description,
  confirmLabel = 'Continue',
  requireConfirm = false,
  requireOld = false,
  minLength = 10,
  onSubmit,
  onCancel,
}: Props) {
  const [oldP, setOldP] = useState('');
  const [p, setP] = useState('');
  const [pConfirm, setPConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const firstRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => { firstRef.current?.focus(); }, []);

  const validationError = (() => {
    if (requireOld && oldP.length === 0) return null;
    if (p.length < minLength) return `Passphrase must be at least ${minLength} characters.`;
    if (requireConfirm && pConfirm !== p) return "Passphrases don't match.";
    return null;
  })();

  async function submit(e?: React.FormEvent) {
    e?.preventDefault();
    if (busy) return;
    setError(null);
    if (p.length < minLength) {
      setError(`Passphrase must be at least ${minLength} characters.`);
      return;
    }
    if (requireConfirm && pConfirm !== p) {
      setError("Passphrases don't match.");
      return;
    }
    setBusy(true);
    try {
      await onSubmit(p, requireOld ? oldP : undefined);
    } catch (e: any) {
      const msg = e && typeof e === 'object' && 'message' in e
        ? String((e as { message: string }).message)
        : String(e);
      setError(msg);
      setBusy(false);
      return;
    }
    setBusy(false);
  }

  return (
    <div className="fixed inset-0 z-50 bg-black/40 backdrop-blur-sm flex items-center justify-center p-4">
      <form onSubmit={submit} className="bg-white rounded-2xl shadow-2xl w-full max-w-md p-6 space-y-4">
        <header>
          <h2 className="display-font text-xl font-semibold persona-accent">{title}</h2>
          {description && <p className="text-sm opacity-70 mt-1">{description}</p>}
        </header>

        {requireOld && (
          <div className="space-y-1">
            <label className="text-xs font-semibold opacity-75" htmlFor="old-passphrase">Current passphrase</label>
            <input
              id="old-passphrase"
              ref={firstRef}
              type="password"
              className="pretty-input w-full font-mono"
              value={oldP}
              onChange={(e) => setOldP(e.target.value)}
              autoComplete="current-password"
            />
          </div>
        )}

        <div className="space-y-1">
          <label className="text-xs font-semibold opacity-75" htmlFor="passphrase">
            {requireOld ? 'New passphrase' : 'Passphrase'}
          </label>
          <input
            id="passphrase"
            ref={requireOld ? undefined : firstRef}
            type="password"
            className="pretty-input w-full font-mono"
            value={p}
            onChange={(e) => setP(e.target.value)}
            autoComplete={requireConfirm ? 'new-password' : 'current-password'}
          />
        </div>

        {requireConfirm && (
          <div className="space-y-1">
            <label className="text-xs font-semibold opacity-75" htmlFor="passphrase-confirm">Confirm</label>
            <input
              id="passphrase-confirm"
              type="password"
              className="pretty-input w-full font-mono"
              value={pConfirm}
              onChange={(e) => setPConfirm(e.target.value)}
              autoComplete="new-password"
            />
          </div>
        )}

        {validationError && !error && (
          <div className="text-xs opacity-70">{validationError}</div>
        )}
        {error && (
          <div className="text-sm text-red-700 bg-red-50 border border-red-200 rounded-xl px-3 py-2">{error}</div>
        )}

        <div className="flex justify-end gap-2 pt-2 border-t border-black/5">
          <button type="button" onClick={onCancel} disabled={busy} className="pretty-button secondary">Cancel</button>
          <button type="submit" disabled={busy || validationError != null} className="pretty-button">
            {busy ? 'Working…' : confirmLabel}
          </button>
        </div>
      </form>
    </div>
  );
}
