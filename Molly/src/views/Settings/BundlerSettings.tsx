import { useCallback, useEffect, useState } from 'react';
import { open as openDialog } from '@tauri-apps/plugin-dialog';
import {
  addProhibitedWord,
  autoPurgeOldBundles,
  type BundlerSettings as BundlerSettingsDto,
  getBundlerSettings,
  listProhibitedWords,
  removeProhibitedWord,
  revealBundlesDir,
  setBundlerSettings,
} from '../../data/bundles';

export function BundlerSettings() {
  const [settings, setSettings] = useState<BundlerSettingsDto | null>(null);
  const [words, setWords] = useState<string[]>([]);
  const [newWord, setNewWord] = useState('');
  const [status, setStatus] = useState<string>('');
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(async () => {
    setSettings(await getBundlerSettings());
    setWords(await listProhibitedWords());
  }, []);

  useEffect(() => { refresh(); }, [refresh]);

  if (!settings) return <div className="pretty-card">Loading bundler settings…</div>;

  async function save(patch: Partial<BundlerSettingsDto>) {
    if (!settings) return;
    const next = { ...settings, ...patch };
    setSettings(next);
    try { await setBundlerSettings(next); } catch (e) { setStatus(`Save failed: ${String(e)}`); }
  }

  async function pickDir() {
    const picked = await openDialog({ directory: true, multiple: false, title: 'Pick bundle output folder' });
    if (typeof picked === 'string') await save({ bundlePath: picked });
  }

  async function addWord() {
    const w = newWord.trim();
    if (!w) return;
    setBusy(true); setStatus('');
    try { await addProhibitedWord(w); setNewWord(''); await refresh(); }
    catch (e) { setStatus(String(e)); }
    finally { setBusy(false); }
  }

  async function removeWord(w: string) {
    setBusy(true); setStatus('');
    try { await removeProhibitedWord(w); await refresh(); }
    catch (e) { setStatus(String(e)); }
    finally { setBusy(false); }
  }

  async function runPurge() {
    setBusy(true); setStatus('Purging…');
    try {
      const r = await autoPurgeOldBundles();
      setStatus(`Considered ${r.considered} · purged ${r.purged} · missing files ${r.skippedMissing} · ${r.lastRunAt}`);
      await refresh();
    } catch (e) {
      setStatus(`Purge failed: ${String(e)}`);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-4">
      <section className="pretty-card space-y-3">
        <h3 className="font-semibold">Output folder</h3>
        <div className="flex gap-2">
          <input
            type="text"
            className="pretty-input flex-1"
            placeholder="~/Downloads/Molly bundles/"
            value={settings.bundlePath ?? ''}
            onChange={(e) => save({ bundlePath: e.target.value || null })}
          />
          <button type="button" onClick={pickDir} className="pretty-button secondary">Choose…</button>
          <button type="button" onClick={() => save({ bundlePath: null })} className="pretty-button secondary">Default</button>
          <button type="button" onClick={() => revealBundlesDir()} className="pretty-button secondary">Reveal</button>
        </div>
        <div className="text-xs opacity-60 font-mono break-all">
          {settings.bundlePath || '~/Downloads/Molly bundles/'}
        </div>
      </section>

      <section className="pretty-card space-y-3">
        <h3 className="font-semibold">Retention</h3>
        <div className="grid grid-cols-2 gap-3 items-center">
          <label className="text-sm">Warn about drafts older than</label>
          <div className="flex items-center gap-2">
            <input
              type="number"
              min={0}
              max={365}
              className="pretty-input w-24"
              value={settings.warnThresholdDays}
              onChange={(e) => save({ warnThresholdDays: Math.max(0, Math.min(365, parseInt(e.target.value || '0', 10))) })}
            />
            <span className="text-xs opacity-70">days (0 disables)</span>
          </div>
          <label className="text-sm">Auto-purge published older than</label>
          <div className="flex items-center gap-2">
            <input
              type="number"
              min={0}
              max={365}
              className="pretty-input w-24"
              value={settings.purgeThresholdDays}
              onChange={(e) => save({ purgeThresholdDays: Math.max(0, Math.min(365, parseInt(e.target.value || '0', 10))) })}
            />
            <span className="text-xs opacity-70">days (0 disables)</span>
          </div>
          <label className="text-sm">Auto-purge enabled</label>
          <input
            type="checkbox"
            checked={settings.autoPurgeEnabled}
            onChange={(e) => save({ autoPurgeEnabled: e.target.checked })}
            className="w-5 h-5"
          />
        </div>
        <div className="flex gap-2 pt-2 border-t border-black/5">
          <button type="button" onClick={runPurge} disabled={busy} className="pretty-button">
            🧹 Run purge now
          </button>
          {settings.lastPurgeAt && (
            <span className="text-xs opacity-60 self-center">Last run: {settings.lastPurgeAt}</span>
          )}
        </div>
        {status && (
          <div className="text-xs bg-black/5 rounded-xl px-3 py-2 font-mono">{status}</div>
        )}
      </section>

      <section className="pretty-card space-y-3">
        <h3 className="font-semibold">Prohibited words (Content description)</h3>
        <p className="text-xs opacity-70">
          The description validator flags any of these substrings (case-insensitive). Defaults seeded on install.
        </p>
        <div className="flex flex-wrap gap-1.5">
          {words.map((w) => (
            <span key={w} className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs bg-red-100 text-red-800">
              {w}
              <button
                type="button"
                onClick={() => removeWord(w)}
                disabled={busy}
                className="w-4 h-4 rounded-full bg-white/40 hover:bg-white/60 transition flex items-center justify-center"
                aria-label={`Remove ${w}`}
              >
                ×
              </button>
            </span>
          ))}
          {words.length === 0 && <span className="text-xs opacity-60 italic">List is empty.</span>}
        </div>
        <div className="flex gap-2">
          <input
            type="text"
            className="pretty-input flex-1"
            placeholder="Add a word…"
            value={newWord}
            onChange={(e) => setNewWord(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') addWord(); }}
            disabled={busy}
          />
          <button type="button" onClick={addWord} className="pretty-button" disabled={busy || !newWord.trim()}>Add</button>
        </div>
      </section>
    </div>
  );
}
