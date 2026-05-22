import { useEffect, useState } from 'react';
import {
  type SiteCredential,
  listSiteCredentials,
  revealCredentialPassword,
} from '../../data/siteCredentials';
import { useKeystore } from '../../state/keystoreContext';

interface Props {
  siteId: number;
  /** Notify caller when status text should update (toast / banner). */
  onStatus: (msg: string) => void;
}

/**
 * Per-site-card credentials block. Loads the site's credentials on mount,
 * shows compact view for a single credential or a labeled list when
 * multiple. Renders Reveal / Copy password buttons gated by keystore
 * unlock state.
 */
export function SiteCredentialsBar({ siteId, onStatus }: Props) {
  const { status: keystoreStatus, lock } = useKeystore();
  const [creds, setCreds] = useState<SiteCredential[] | null>(null);
  const [revealedId, setRevealedId] = useState<number | null>(null);
  const [revealed, setRevealed] = useState<string>('');
  const [busyId, setBusyId] = useState<number | null>(null);

  // Suppress lint warning — `lock` not used here but consumed by other components.
  void lock;

  useEffect(() => {
    let alive = true;
    listSiteCredentials(siteId)
      .then((rows) => { if (alive) setCreds(rows); })
      .catch(() => { if (alive) setCreds([]); });
    return () => { alive = false; };
  }, [siteId]);

  // Auto-hide revealed plaintext after 10s.
  useEffect(() => {
    if (revealedId == null) return;
    const t = window.setTimeout(() => {
      setRevealedId(null);
      setRevealed('');
    }, 10_000);
    return () => window.clearTimeout(t);
  }, [revealedId]);

  if (creds == null) return null; // still loading; card renders without this block
  // Filter out any credential whose only purpose is the legacy bw-compat
  // "default" row when it has no password and no useful label difference
  // from sites.username — actually keep them all; the per-card layout
  // handles a single primary cred with `hasPassword=false` cleanly.
  if (creds.length === 0) return null;

  const anyWithPassword = creds.some((c) => c.hasPassword);
  if (!anyWithPassword) return null; // no passwords stored; show nothing extra

  const locked = !keystoreStatus?.unlocked;

  async function doReveal(c: SiteCredential) {
    if (locked) return;
    setBusyId(c.id);
    try {
      const plain = await revealCredentialPassword(c.id);
      setRevealedId(c.id);
      setRevealed(plain);
      onStatus(`Password for "${c.label}" revealed (auto-hides in 10s)`);
    } catch (e) {
      onStatus(`Couldn't reveal password: ${String((e as { message?: string })?.message ?? e)}`);
    } finally {
      setBusyId(null);
    }
  }

  async function doCopy(c: SiteCredential) {
    if (locked) return;
    setBusyId(c.id);
    try {
      const plain = await revealCredentialPassword(c.id);
      await navigator.clipboard.writeText(plain);
      onStatus(`Password copied (clipboard clears in 30s)`);
      window.setTimeout(() => {
        navigator.clipboard.writeText('').catch(() => {});
      }, 30_000);
    } catch (e) {
      onStatus(`Couldn't copy password: ${String((e as { message?: string })?.message ?? e)}`);
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div className="space-y-1 pt-1 border-t border-black/5">
      {creds
        .filter((c) => c.hasPassword)
        .map((c) => (
          <div key={c.id} className="flex items-center gap-2 text-xs">
            {creds.length > 1 && (
              <span className="opacity-60 font-mono min-w-[4rem] truncate" title={c.label}>{c.label}:</span>
            )}
            {locked ? (
              <span className="opacity-50 italic flex-1" title="Unlock keystore to view">🔒 password set</span>
            ) : revealedId === c.id ? (
              <span className="font-mono flex-1 truncate select-all" title="Auto-hides in 10s">{revealed}</span>
            ) : (
              <span className="opacity-50 italic flex-1">●●●●●●●●</span>
            )}
            <button
              type="button"
              onClick={() => (revealedId === c.id ? setRevealedId(null) : doReveal(c))}
              disabled={locked || busyId === c.id}
              className="pretty-button secondary text-[10px] py-0.5 px-1.5"
              title={revealedId === c.id ? 'Hide' : 'Reveal for 10s'}
            >
              {revealedId === c.id ? '🙈' : '👁'}
            </button>
            <button
              type="button"
              onClick={() => doCopy(c)}
              disabled={locked || busyId === c.id}
              className="pretty-button secondary text-[10px] py-0.5 px-1.5"
              title="Copy password to clipboard (clears in 30s)"
            >
              📋
            </button>
          </div>
        ))}
    </div>
  );
}
