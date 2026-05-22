import { useCallback, useEffect, useState } from 'react';
import {
  type SiteCredential,
  clearCredentialPassword,
  createSiteCredential,
  deleteSiteCredential,
  listSiteCredentials,
  revealCredentialPassword,
  setCredentialPassword,
  setCredentialPrimary,
  updateCredentialLabel,
  updateCredentialUsername,
} from '../../data/siteCredentials';
import { useKeystore } from '../../state/keystoreContext';

interface Props {
  siteId: number;
}

/**
 * The Credentials section inside the site editor. Lists all of a site's
 * credentials with inline edit (label, username, password), set-primary
 * radio, delete button, + Add credential. Password operations are gated
 * by keystore unlock state — when locked, the password fields show a
 * helpful banner instead of an input.
 */
export function SiteCredentialsEditor({ siteId }: Props) {
  const { status: keystoreStatus } = useKeystore();
  const [creds, setCreds] = useState<SiteCredential[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [addLabel, setAddLabel] = useState('');
  const [busyId, setBusyId] = useState<number | 'new' | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      const rows = await listSiteCredentials(siteId);
      setCreds(rows);
    } catch (e) {
      setError(String((e as { message?: string })?.message ?? e));
    } finally {
      setLoading(false);
    }
  }, [siteId]);

  useEffect(() => { refresh(); }, [refresh]);

  async function withBusy<T>(id: number | 'new', fn: () => Promise<T>): Promise<T | null> {
    setBusyId(id);
    setError(null);
    try { return await fn(); }
    catch (e) {
      setError(String((e as { message?: string })?.message ?? e));
      return null;
    } finally {
      setBusyId(null);
    }
  }

  async function doAdd() {
    const label = addLabel.trim() || 'new login';
    const ok = await withBusy('new', async () => {
      await createSiteCredential(siteId, label);
      await refresh();
    });
    if (ok !== null) setAddLabel('');
  }

  return (
    <div className="col-span-2 mt-2 p-3 rounded-xl bg-pink-50/40 border border-pink-200 space-y-3">
      <div className="flex items-baseline justify-between">
        <h4 className="font-semibold text-sm">Credentials</h4>
        <span className="text-xs opacity-60">{creds.length} login{creds.length === 1 ? '' : 's'}</span>
      </div>

      {keystoreStatus && !keystoreStatus.initialized && (
        <div className="text-xs bg-amber-50 border border-amber-200 rounded-xl px-3 py-2">
          Set up the keystore in <strong>Settings → 🔐 Security</strong> first to store passwords.
        </div>
      )}

      {error && (
        <div className="text-xs text-red-700 bg-red-50 border border-red-200 rounded-xl px-3 py-2">{error}</div>
      )}

      {loading && <div className="text-xs opacity-60 italic">Loading credentials…</div>}

      <ul className="space-y-2">
        {creds.map((c) => (
          <CredentialRow
            key={c.id}
            cred={c}
            canDelete={creds.length > 1}
            busy={busyId === c.id}
            onChange={refresh}
            onError={setError}
            setBusy={(b) => setBusyId(b ? c.id : null)}
          />
        ))}
      </ul>

      <div className="flex items-center gap-2 pt-2 border-t border-pink-200">
        <input
          type="text"
          placeholder="Label for new login (e.g. 'CoC store', 'backup')"
          value={addLabel}
          onChange={(e) => setAddLabel(e.target.value)}
          className="pretty-input flex-1 text-sm"
          disabled={busyId === 'new'}
        />
        <button
          type="button"
          onClick={doAdd}
          disabled={busyId === 'new'}
          className="pretty-button text-sm"
        >
          ＋ Add credential
        </button>
      </div>
    </div>
  );
}

function CredentialRow({
  cred, canDelete, busy, onChange, onError, setBusy,
}: {
  cred: SiteCredential;
  canDelete: boolean;
  busy: boolean;
  onChange: () => Promise<void>;
  onError: (msg: string) => void;
  setBusy: (b: boolean) => void;
}) {
  const { status: keystoreStatus } = useKeystore();
  const [label, setLabel] = useState(cred.label);
  const [username, setUsername] = useState(cred.username);
  const [passwordDraft, setPasswordDraft] = useState('');
  const [showPlain, setShowPlain] = useState(false);
  const [revealed, setRevealed] = useState<string | null>(null);

  useEffect(() => setLabel(cred.label), [cred.label]);
  useEffect(() => setUsername(cred.username), [cred.username]);

  const locked = !keystoreStatus?.unlocked;

  async function commitLabel() {
    if (label === cred.label) return;
    setBusy(true);
    try { await updateCredentialLabel(cred.id, label); await onChange(); }
    catch (e) { onError(String((e as { message?: string })?.message ?? e)); }
    finally { setBusy(false); }
  }
  async function commitUsername() {
    if (username === cred.username) return;
    setBusy(true);
    try { await updateCredentialUsername(cred.id, username); await onChange(); }
    catch (e) { onError(String((e as { message?: string })?.message ?? e)); }
    finally { setBusy(false); }
  }
  async function commitPassword() {
    if (passwordDraft.length === 0) return;
    setBusy(true);
    try {
      await setCredentialPassword(cred.id, passwordDraft);
      setPasswordDraft('');
      await onChange();
    } catch (e) {
      onError(String((e as { message?: string })?.message ?? e));
    } finally { setBusy(false); }
  }
  async function doReveal() {
    if (locked) return;
    setBusy(true);
    try {
      const plain = await revealCredentialPassword(cred.id);
      setRevealed(plain);
      window.setTimeout(() => setRevealed(null), 10_000);
    } catch (e) {
      onError(String((e as { message?: string })?.message ?? e));
    } finally { setBusy(false); }
  }
  async function doClear() {
    if (!confirm(`Remove the stored password for "${cred.label}"?`)) return;
    setBusy(true);
    try { await clearCredentialPassword(cred.id); await onChange(); }
    catch (e) { onError(String((e as { message?: string })?.message ?? e)); }
    finally { setBusy(false); }
  }
  async function doSetPrimary() {
    if (cred.isPrimary) return;
    setBusy(true);
    try { await setCredentialPrimary(cred.id); await onChange(); }
    catch (e) { onError(String((e as { message?: string })?.message ?? e)); }
    finally { setBusy(false); }
  }
  async function doDelete() {
    if (!canDelete) return;
    if (!confirm(`Delete the "${cred.label}" credential? Its password is also removed.`)) return;
    setBusy(true);
    try { await deleteSiteCredential(cred.id); await onChange(); }
    catch (e) { onError(String((e as { message?: string })?.message ?? e)); }
    finally { setBusy(false); }
  }

  return (
    <li className="p-3 rounded-xl bg-white border border-pink-200 space-y-2">
      <div className="flex items-center gap-2">
        <input
          type="radio"
          name={`primary-${cred.siteId}`}
          checked={cred.isPrimary}
          onChange={doSetPrimary}
          title="Set as primary (this credential's username mirrors to sites.username)"
          className="w-4 h-4"
          disabled={busy}
        />
        <input
          type="text"
          value={label}
          onChange={(e) => setLabel(e.target.value)}
          onBlur={commitLabel}
          placeholder="Label"
          className="pretty-input flex-1 text-sm font-semibold"
          disabled={busy}
        />
        {cred.isPrimary && <span className="text-[10px] font-mono opacity-60">primary</span>}
        <button
          type="button"
          onClick={doDelete}
          disabled={!canDelete || busy}
          className="pretty-button danger text-xs"
          title={canDelete ? 'Delete this credential' : 'Cannot delete the last credential'}
        >
          🗑
        </button>
      </div>
      <div className="flex items-center gap-2">
        <label className="text-xs opacity-60 w-16">Username</label>
        <input
          type="text"
          value={username}
          onChange={(e) => setUsername(e.target.value)}
          onBlur={commitUsername}
          placeholder="(empty)"
          className="pretty-input flex-1 text-sm font-mono"
          disabled={busy}
        />
      </div>
      <div className="flex items-center gap-2">
        <label className="text-xs opacity-60 w-16">Password</label>
        {locked ? (
          <div className="flex-1 text-xs opacity-70 bg-pink-50 border border-pink-200 rounded-xl px-3 py-1.5">
            🔒 Keystore is locked — unlock in <strong>Settings → 🔐 Security</strong> to {cred.hasPassword ? 'view or change' : 'set a'} password.
          </div>
        ) : cred.hasPassword && revealed != null ? (
          <input
            type="text"
            readOnly
            value={revealed}
            className="pretty-input flex-1 text-sm font-mono"
            onFocus={(e) => e.currentTarget.select()}
          />
        ) : (
          <input
            type={showPlain ? 'text' : 'password'}
            value={passwordDraft}
            onChange={(e) => setPasswordDraft(e.target.value)}
            onBlur={commitPassword}
            placeholder={cred.hasPassword ? '●●●●●●●● (set; type to replace)' : '(no password set)'}
            className="pretty-input flex-1 text-sm font-mono"
            disabled={busy}
          />
        )}
        {!locked && (
          <>
            {cred.hasPassword && (
              <button type="button" onClick={doReveal} disabled={busy} className="pretty-button secondary text-xs" title="Reveal for 10s">
                {revealed != null ? '🙈' : '👁'}
              </button>
            )}
            <button type="button" onClick={() => setShowPlain((v) => !v)} className="pretty-button secondary text-xs" title="Show typed characters">
              {showPlain ? 'Hide' : 'Show'}
            </button>
            {cred.hasPassword && (
              <button type="button" onClick={doClear} disabled={busy} className="pretty-button danger text-xs" title="Clear stored password">
                Clear
              </button>
            )}
          </>
        )}
      </div>
      {cred.hasPassword && cred.passwordUpdatedAt && (
        <div className="text-[10px] opacity-50 font-mono">
          Password set {cred.passwordUpdatedAt}
        </div>
      )}
    </li>
  );
}
