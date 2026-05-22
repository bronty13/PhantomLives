import { useMemo, useState } from 'react';
import { MnemonicGrid } from '../../components/MnemonicGrid';
import { PassphrasePrompt } from '../../components/PassphrasePrompt';
import {
  changePassphrase,
  exportKeystoreMnemonic,
  importKeystoreFromMnemonic,
  initKeystore,
  wipeKeystore,
} from '../../data/keystore';
import { useKeystore } from '../../state/keystoreContext';

type Modal =
  | { kind: 'none' }
  | { kind: 'init' }
  | { kind: 'unlock' }
  | { kind: 'change' }
  | { kind: 'reveal' }
  | { kind: 'import' }
  | { kind: 'wipe' };

export function SecuritySettings() {
  const { status, refresh, unlock, lock } = useKeystore();
  const [modal, setModal] = useState<Modal>({ kind: 'none' });
  const [mnemonic, setMnemonic] = useState<string[] | null>(null);
  const [importCells, setImportCells] = useState<string[]>(() => Array(24).fill(''));
  const [wipeData, setWipeData] = useState(true);
  const [savedNotice, setSavedNotice] = useState<string | null>(null);

  // Live count of how many of the 24 cells are filled (used to enable
  // the Import button only when all 24 are present; live validation
  // against the BIP-39 wordlist happens server-side on submit).
  const filledCellCount = useMemo(
    () => importCells.filter((w) => w.trim().length > 0).length,
    [importCells],
  );

  if (!status) {
    return <div className="pretty-card">Loading keystore status…</div>;
  }

  async function doInit(passphrase: string) {
    await initKeystore(passphrase);
    await unlock(passphrase);
    setModal({ kind: 'none' });
    setSavedNotice('Keystore created and unlocked.');
  }
  async function doUnlock(passphrase: string) {
    await unlock(passphrase);
    setModal({ kind: 'none' });
  }
  async function doChange(newP: string, oldP?: string) {
    await changePassphrase(oldP ?? '', newP);
    await refresh();
    setModal({ kind: 'none' });
    setSavedNotice('Passphrase changed.');
  }
  async function doReveal() {
    const m = await exportKeystoreMnemonic();
    setMnemonic(m.words);
    setModal({ kind: 'reveal' });
  }
  async function doImport(newP: string) {
    const words = importCells
      .map((w) => w.replace(/^\s*\d+\s*[.)]\s*/, '').trim().toLowerCase())
      .filter((w) => w.length > 0);
    await importKeystoreFromMnemonic(words, newP);
    await refresh();
    setImportCells(Array(24).fill(''));
    setModal({ kind: 'none' });
    setSavedNotice('Keystore imported from mnemonic and unlocked.');
  }
  async function doWipe() {
    const ok = confirm(
      'Wipe the keystore?\n\n' +
      'This deletes your encryption keys forever. ' +
      (wipeData
        ? 'All encrypted data in Molly will also be wiped.'
        : 'Encrypted data will remain in the database but become unrecoverable.') +
      '\n\nThis cannot be undone.'
    );
    if (!ok) return;
    await wipeKeystore(wipeData);
    await refresh();
    setSavedNotice('Keystore wiped.');
  }

  return (
    <div className="space-y-4">
      {/* Status block */}
      <section className="pretty-card space-y-3">
        <h3 className="font-semibold">Status</h3>
        <div className="text-sm">
          {!status.initialized && <span>🔓 Keystore not set up yet — create one below.</span>}
          {status.initialized && status.unlocked && (
            <span>
              ✨ <strong>Unlocked</strong>
              {status.unlockedSecs != null && (
                <span className="opacity-60"> since {fmtElapsed(status.unlockedSecs)} ago</span>
              )}
              {' '}— auto-locks after 8 hours of inactivity.
            </span>
          )}
          {status.initialized && !status.unlocked && (
            <span>🔒 <strong>Locked</strong> — unlock to use encrypted passwords.</span>
          )}
        </div>
        <div className="flex flex-wrap gap-2">
          {!status.initialized && (
            <button type="button" onClick={() => setModal({ kind: 'init' })} className="pretty-button">
              ✨ Create keystore
            </button>
          )}
          {status.initialized && !status.unlocked && (
            <button type="button" onClick={() => setModal({ kind: 'unlock' })} className="pretty-button">
              🔓 Unlock
            </button>
          )}
          {status.initialized && status.unlocked && (
            <>
              <button type="button" onClick={lock} className="pretty-button secondary">🔒 Lock now</button>
              <button type="button" onClick={() => setModal({ kind: 'change' })} className="pretty-button secondary">
                Change passphrase
              </button>
            </>
          )}
        </div>
        {savedNotice && (
          <div className="text-xs bg-emerald-50 border border-emerald-200 rounded-xl px-3 py-2">{savedNotice}</div>
        )}
      </section>

      {/* Backup mnemonic */}
      {status.initialized && status.unlocked && (
        <section className="pretty-card space-y-3">
          <h3 className="font-semibold">Backup recovery words</h3>
          <p className="text-xs opacity-70">
            Your 24 recovery words ARE your encryption key. Write them down on paper, store them in
            a safe place, or paste them into a private Slack DM with Robert so he can decrypt the same data.
            Anyone with these words can read everything Molly encrypts.
          </p>
          {!mnemonic ? (
            <button type="button" onClick={doReveal} className="pretty-button">
              🔑 Reveal recovery words
            </button>
          ) : (
            <MnemonicReveal words={mnemonic} onDismiss={() => setMnemonic(null)} />
          )}
        </section>
      )}

      {/* Import */}
      {status.initialized && (
        <section className="pretty-card space-y-3">
          <h3 className="font-semibold">Restore from recovery words</h3>
          <p className="text-xs opacity-70">
            Type or paste your 24 BIP-39 words below — one per cell. Press <strong>space</strong> or
            <strong> Enter</strong> after each word to jump to the next cell. You can also paste all
            24 at once into any cell, or use <strong>📋 Paste from clipboard</strong> to fill them in
            one go. Words are case-insensitive; pasted &ldquo;1. word&rdquo; numbered lists also work.
          </p>
          <MnemonicGrid value={importCells} onChange={setImportCells} />
          <div className="flex items-center justify-between text-xs">
            <span className="opacity-60">{filledCellCount}/24 filled</span>
            <button
              type="button"
              onClick={() => setModal({ kind: 'import' })}
              disabled={filledCellCount !== 24}
              className="pretty-button"
            >
              Import keystore from these words
            </button>
          </div>
          <div className="text-xs bg-amber-50 border border-amber-200 rounded-xl px-3 py-2 text-amber-900">
            ⚠️ Importing replaces your current keystore. Any encrypted data already in Molly will
            become unreadable unless this mnemonic matches what originally encrypted it.
          </div>
        </section>
      )}

      {/* Wipe */}
      {status.initialized && (
        <section className="pretty-card space-y-3 border-red-200">
          <h3 className="font-semibold text-red-800">Danger zone</h3>
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={wipeData}
              onChange={(e) => setWipeData(e.target.checked)}
              className="w-4 h-4"
            />
            Also wipe all encrypted data in Molly
          </label>
          <button type="button" onClick={doWipe} className="pretty-button danger">
            🗑 Wipe keystore
          </button>
        </section>
      )}

      {/* Modals */}
      {modal.kind === 'init' && (
        <PassphrasePrompt
          title="Create keystore"
          description="Pick a passphrase you'll remember. Sallie and Robert should pick the same one if they're sharing."
          requireConfirm
          confirmLabel="Create"
          onSubmit={(p) => doInit(p)}
          onCancel={() => setModal({ kind: 'none' })}
        />
      )}
      {modal.kind === 'unlock' && (
        <PassphrasePrompt
          title="Unlock keystore"
          confirmLabel="Unlock"
          onSubmit={(p) => doUnlock(p)}
          onCancel={() => setModal({ kind: 'none' })}
        />
      )}
      {modal.kind === 'change' && (
        <PassphrasePrompt
          title="Change passphrase"
          requireOld
          requireConfirm
          confirmLabel="Change"
          onSubmit={(newP, oldP) => doChange(newP, oldP)}
          onCancel={() => setModal({ kind: 'none' })}
        />
      )}
      {modal.kind === 'import' && (
        <PassphrasePrompt
          title="Pick a passphrase for the imported keystore"
          description="This passphrase will wrap the imported recovery words. It can be the same as before or new."
          requireConfirm
          confirmLabel="Import"
          onSubmit={(p) => doImport(p)}
          onCancel={() => setModal({ kind: 'none' })}
        />
      )}
    </div>
  );
}

function MnemonicReveal({ words, onDismiss }: { words: string[]; onDismiss: () => void }) {
  const [saved, setSaved] = useState(false);
  return (
    <div className="space-y-3">
      <div className="bg-amber-50 border border-amber-300 rounded-xl px-3 py-2 text-sm text-amber-900">
        ⚠️ These 24 words are your master key. Don't email them. Don't screenshot. Don't store in cloud notes.
      </div>
      {/* Same grid layout as the import side — identical visual rhythm. */}
      <MnemonicGrid value={words} onChange={() => {}} readOnly />
      <div className="flex flex-wrap items-center gap-2">
        <button type="button" onClick={() => navigator.clipboard.writeText(words.join(' '))} className="pretty-button secondary">
          📋 Copy all (one line)
        </button>
        <button
          type="button"
          onClick={() => navigator.clipboard.writeText(words.map((w, i) => `${i + 1}. ${w}`).join('\n'))}
          className="pretty-button secondary"
        >
          📝 Copy numbered list
        </button>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={saved} onChange={(e) => setSaved(e.target.checked)} className="w-4 h-4" />
          I've saved them somewhere safe
        </label>
        <button type="button" onClick={onDismiss} disabled={!saved} className="pretty-button ml-auto">
          Done
        </button>
      </div>
    </div>
  );
}

function fmtElapsed(secs: number): string {
  if (secs < 60) return `${secs}s`;
  if (secs < 3600) return `${Math.floor(secs / 60)}m`;
  return `${Math.floor(secs / 3600)}h ${Math.floor((secs % 3600) / 60)}m`;
}
