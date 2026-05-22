import { useCallback, useEffect, useState } from 'react';
import { open as openDialog } from '@tauri-apps/plugin-dialog';
import { openUrl } from '@tauri-apps/plugin-opener';
import {
  type AtwHealthCheck,
  type AtwSettings as AtwSettingsType,
  atwHealthCheck,
  atwRunNow,
  getAtwSettings,
  setAtwSettings,
} from '../../data/atwSettings';
import {
  type InstallResult,
  type SetupState,
  ensureAtwBotFiles,
  installAtwBotDeps,
} from '../../data/atwSetup';
import { upsertAtwJob } from '../../data/backgroundJobs';
import { useKeystore } from '../../state/keystoreContext';
import { PassphrasePrompt } from '../../components/PassphrasePrompt';

/** Settings → 🌀 ATW Repost pane. */
export function AtwSettingsPane() {
  const { status: keystoreStatus, unlock } = useKeystore();
  const [settings, setSettings] = useState<AtwSettingsType | null>(null);
  const [health, setHealth] = useState<AtwHealthCheck | null>(null);
  const [setup, setSetup] = useState<SetupState | null>(null);
  const [passwordDraft, setPasswordDraft] = useState('');
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const [installResult, setInstallResult] = useState<InstallResult | null>(null);
  const [showUnlock, setShowUnlock] = useState(false);

  const refresh = useCallback(async () => {
    try {
      // Ensure bundled files are copied to app data BEFORE the health
      // check, so the "repost.js present" row reflects the auto-managed
      // state on first load rather than reporting a missing install.
      const setupNow = await ensureAtwBotFiles();
      const [s, h] = await Promise.all([getAtwSettings(), atwHealthCheck()]);
      setSetup(setupNow);
      setSettings(s);
      setHealth(h);
    } catch (e) {
      setStatus(`Couldn't load ATW settings: ${String((e as { message?: string })?.message ?? e)}`);
    }
  }, []);

  useEffect(() => { refresh(); }, [refresh]);

  if (!settings || !health || !setup) {
    return <div className="pretty-card">Loading ATW settings…</div>;
  }

  async function save(patch: Partial<AtwSettingsType>, passwordOverride?: string | null) {
    if (!settings) return;
    setBusy(true);
    setStatus(null);
    try {
      const next = await setAtwSettings({
        email: patch.email ?? settings.email,
        password: passwordOverride === undefined ? null : passwordOverride,
        botDir: patch.botDir !== undefined ? patch.botDir : settings.botDir,
        browserExecutablePath: patch.browserExecutablePath !== undefined
          ? patch.browserExecutablePath
          : settings.browserExecutablePath,
        cadenceSeconds: patch.cadenceSeconds ?? settings.cadenceSeconds,
        repostDays: patch.repostDays ?? settings.repostDays,
        scheduleStartHour: patch.scheduleStartHour ?? settings.scheduleStartHour,
        scheduleEndHour: patch.scheduleEndHour ?? settings.scheduleEndHour,
        utcOffset: patch.utcOffset ?? settings.utcOffset,
        delayMs: patch.delayMs ?? settings.delayMs,
        headless: patch.headless ?? settings.headless,
      });
      setSettings(next);
      await upsertAtwJob(next.cadenceSeconds);
      await refresh();
    } catch (e) {
      setStatus(`Save failed: ${String((e as { message?: string })?.message ?? e)}`);
    } finally {
      setBusy(false);
    }
  }

  async function savePassword() {
    if (passwordDraft.length === 0) return;
    await save({}, passwordDraft);
    setPasswordDraft('');
    setStatus('Password saved (encrypted).');
  }

  async function clearPassword() {
    if (!confirm('Remove the stored ATW password?')) return;
    await save({}, '');
    setStatus('Password cleared.');
  }

  async function pickBrowserPath() {
    const picked = await openDialog({ directory: false, multiple: false, title: 'Pick Chromium / Brave / Edge binary' });
    if (typeof picked === 'string') await save({ browserExecutablePath: picked });
  }
  async function clearBrowserPath() { await save({ browserExecutablePath: null }); }

  async function installDeps() {
    setBusy(true);
    setInstallResult(null);
    setStatus('Installing bot dependencies (npm install)… this can take a minute on first run.');
    try {
      const result = await installAtwBotDeps();
      setInstallResult(result);
      setStatus(result.status === 'success' ? `✓ ${result.summary}` : `✗ ${result.summary}`);
      await refresh();
    } catch (e) {
      setStatus(`Install failed: ${String((e as { message?: string })?.message ?? e)}`);
    } finally {
      setBusy(false);
    }
  }

  async function pickOverrideBotDir() {
    const picked = await openDialog({ directory: true, multiple: false, title: 'Pick an atw-repost-bot directory (advanced)' });
    if (typeof picked === 'string') await save({ botDir: picked });
  }
  async function clearOverrideBotDir() { await save({ botDir: null }); }

  async function runNow() {
    if (!keystoreStatus?.unlocked) {
      setStatus('Unlock the keystore first.');
      setShowUnlock(true);
      return;
    }
    setBusy(true);
    setStatus('Running ATW bot now (this can take several minutes)…');
    try {
      const outcome = await atwRunNow();
      setStatus(`${outcome.status === 'success' ? '✓' : '✗'} ${outcome.summary}`);
      await refresh();
    } catch (e) {
      setStatus(`Run failed: ${String((e as { message?: string })?.message ?? e)}`);
    } finally {
      setBusy(false);
    }
  }

  async function doUnlock(passphrase: string) {
    await unlock(passphrase);
    setShowUnlock(false);
    setStatus('Keystore unlocked.');
  }

  const locked = !keystoreStatus?.unlocked;

  return (
    <div className="space-y-4">
      {/* Inline unlock — no nav-away required */}
      {keystoreStatus?.initialized && locked && (
        <section className="pretty-card border-pink-300 bg-pink-50 flex items-center gap-3">
          <span className="text-lg">🔒</span>
          <span className="flex-1 text-sm">
            Keystore is <strong>locked</strong> — needed to set, change, or use the ATW password.
          </span>
          <button type="button" onClick={() => setShowUnlock(true)} className="pretty-button">
            Unlock now
          </button>
        </section>
      )}

      {/* Health check — actionable rows */}
      <section className="pretty-card space-y-3">
        <h3 className="font-semibold">🩺 Health check</h3>
        <HealthRow ok={health.nodeFound} label="Node.js installed">
          {health.nodeFound ? (
            <span className="font-mono">{health.nodePath}</span>
          ) : (
            <>
              <span>Not found on PATH. Molly needs Node.js 18 or later.</span>
              <button type="button" onClick={() => openUrl('https://nodejs.org/')} className="pretty-button secondary text-xs ml-2">
                Open nodejs.org
              </button>
            </>
          )}
        </HealthRow>
        <HealthRow ok={health.chromeFound} label="Chromium-based browser found">
          {health.chromeFound ? (
            <span className="font-mono">{health.chromePath}</span>
          ) : (
            <div className="space-y-1">
              <div>
                Not found at standard locations. Install any Chromium-based browser
                (Chromium, Brave, or Edge) OR set an override below.
              </div>
              <div className="flex gap-2 flex-wrap">
                <button type="button" onClick={() => openUrl('https://github.com/ungoogled-software/ungoogled-chromium-macos/releases')} className="pretty-button secondary text-xs">
                  Get ungoogled-chromium (recommended)
                </button>
                <button type="button" onClick={() => openUrl('https://brave.com/download/')} className="pretty-button secondary text-xs">
                  Get Brave
                </button>
              </div>
            </div>
          )}
        </HealthRow>
        <HealthRow ok={setup.filesCopied} label="Bot installed">
          {setup.filesCopied ? (
            <span className="font-mono">{setup.botDir}</span>
          ) : (
            <div className="space-y-1">
              <div>
                Files missing at <span className="font-mono opacity-60">{setup.botDir}</span>. Clicking
                "Install bot dependencies" below will copy the bundled bot files here automatically.
              </div>
              {settings.botDir && (
                <button
                  type="button"
                  onClick={async () => { await save({ botDir: null }); setStatus('Bot directory reset to default (auto-managed).'); }}
                  disabled={busy}
                  className="pretty-button secondary text-xs"
                >
                  ↩️ Reset to default location (recommended)
                </button>
              )}
            </div>
          )}
        </HealthRow>
        <HealthRow ok={setup.nodeModulesPresent} label="Bot dependencies installed">
          {setup.nodeModulesPresent
            ? 'Up to date'
            : 'Click "Install bot dependencies" below to run npm install.'}
        </HealthRow>
        {(!setup.nodeModulesPresent || setup.needsNpmInstall) && health.nodeFound && (
          <div className="space-y-2">
            <button
              type="button"
              onClick={installDeps}
              disabled={busy}
              className="pretty-button"
            >
              {busy ? '⏳ Installing… (this can take 30-60s)' : '⬇ Install bot dependencies (npm install)'}
            </button>
            {busy && (
              <div className="text-xs bg-amber-50 border border-amber-200 rounded-xl px-3 py-2 font-mono">
                Running <code>npm install</code> in <span className="opacity-60">{setup.botDir}</span>… you can leave this tab open.
              </div>
            )}
            {!busy && status && (status.startsWith('✓') || status.startsWith('✗') || status.startsWith('Install')) && (
              <div className={`text-xs rounded-xl px-3 py-2 font-mono ${status.startsWith('✗') || status.startsWith('Install failed') ? 'bg-rose-50 border border-rose-200' : 'bg-emerald-50 border border-emerald-200'}`}>
                {status}
              </div>
            )}
          </div>
        )}
        {installResult && (
          <details className="text-xs" open={installResult.status === 'failed'}>
            <summary className="opacity-60 cursor-pointer">npm install log (last lines)</summary>
            <pre className="mt-2 bg-black/5 rounded-xl p-2 max-h-48 overflow-auto whitespace-pre-wrap font-mono text-[10px]">
              {installResult.logExcerpt || '(no output captured)'}
            </pre>
          </details>
        )}
      </section>

      {/* Credentials */}
      <section className="pretty-card space-y-3">
        <h3 className="font-semibold">🔑 Credentials</h3>
        {keystoreStatus && !keystoreStatus.initialized && (
          <div className="text-xs bg-amber-50 border border-amber-200 rounded-xl px-3 py-2">
            Set up the keystore in <strong>Settings → 🔐 Security</strong> first to encrypt your ATW password.
          </div>
        )}
        <label className="block space-y-1">
          <span className="text-xs font-semibold opacity-75">ATW email</span>
          <input
            type="email"
            className="pretty-input w-full"
            defaultValue={settings.email}
            onBlur={(e) => { if (e.target.value !== settings.email) save({ email: e.target.value }); }}
            disabled={busy}
          />
        </label>
        <label className="block space-y-1">
          <span className="text-xs font-semibold opacity-75">
            ATW password {settings.hasPassword && <span className="opacity-60">(encrypted; type to replace)</span>}
          </span>
          <div className="flex gap-2">
            <input
              type="password"
              className="pretty-input flex-1 font-mono"
              placeholder={settings.hasPassword ? '●●●●●●●●' : 'enter to set'}
              value={passwordDraft}
              onChange={(e) => setPasswordDraft(e.target.value)}
              disabled={busy || locked || !keystoreStatus?.initialized}
            />
            <button
              type="button"
              onClick={savePassword}
              disabled={busy || locked || passwordDraft.length === 0}
              className="pretty-button"
            >
              {settings.hasPassword ? 'Replace' : 'Set'}
            </button>
            {settings.hasPassword && (
              <button
                type="button"
                onClick={clearPassword}
                disabled={busy || locked}
                className="pretty-button danger"
              >
                Clear
              </button>
            )}
          </div>
          {locked && keystoreStatus?.initialized && (
            <div className="text-xs opacity-60 italic">
              🔒 Keystore locked — use the Unlock button at the top of this page.
            </div>
          )}
        </label>
      </section>

      {/* Schedule */}
      <section className="pretty-card space-y-3">
        <h3 className="font-semibold">⏱ Schedule + behavior</h3>
        <div className="grid grid-cols-2 gap-3 items-center">
          <label className="text-sm">Run every</label>
          <select
            className="pretty-input"
            value={settings.cadenceSeconds}
            onChange={(e) => save({ cadenceSeconds: Number(e.target.value) })}
            disabled={busy}
          >
            <option value={3600}>1 hour</option>
            <option value={2 * 3600}>2 hours</option>
            <option value={4 * 3600}>4 hours (default)</option>
            <option value={6 * 3600}>6 hours</option>
            <option value={12 * 3600}>12 hours</option>
            <option value={24 * 3600}>24 hours</option>
          </select>
          <label className="text-sm">Spread reposts across</label>
          <select
            className="pretty-input"
            value={settings.repostDays}
            onChange={(e) => save({ repostDays: Number(e.target.value) })}
            disabled={busy}
          >
            {[1, 2, 3, 4, 5, 6, 7].map((d) => (
              <option key={d} value={d}>{d} day{d === 1 ? '' : 's'}</option>
            ))}
          </select>
          <label className="text-sm">Waking-hour window (local)</label>
          <div className="flex items-center gap-2 text-sm">
            <input
              type="number" min={0} max={23}
              className="pretty-input w-16"
              value={settings.scheduleStartHour}
              onChange={(e) => save({ scheduleStartHour: Math.max(0, Math.min(23, Number(e.target.value) || 0)) })}
              disabled={busy}
            />
            <span>to</span>
            <input
              type="number" min={1} max={24}
              className="pretty-input w-16"
              value={settings.scheduleEndHour}
              onChange={(e) => save({ scheduleEndHour: Math.max(1, Math.min(24, Number(e.target.value) || 0)) })}
              disabled={busy}
            />
          </div>
          <label className="text-sm">UTC offset</label>
          <input
            type="number" min={-12} max={14}
            className="pretty-input w-16"
            value={settings.utcOffset}
            onChange={(e) => save({ utcOffset: Number(e.target.value) || 0 })}
            disabled={busy}
          />
          <label className="text-sm">Delay between submissions</label>
          <div className="flex items-center gap-1 text-sm">
            <input
              type="number" min={1000} max={60000} step={500}
              className="pretty-input w-24"
              value={settings.delayMs}
              onChange={(e) => save({ delayMs: Math.max(1000, Math.min(60000, Number(e.target.value) || 4000)) })}
              disabled={busy}
            />
            <span className="opacity-60">ms</span>
          </div>
          <label className="text-sm">Run headless</label>
          <input
            type="checkbox"
            checked={settings.headless}
            onChange={(e) => save({ headless: e.target.checked })}
            className="w-5 h-5"
            disabled={busy}
          />
        </div>
      </section>

      {/* Run now */}
      <section className="pretty-card space-y-3">
        <h3 className="font-semibold">▶️ Run now</h3>
        <p className="text-xs opacity-70">
          Run the ATW bot once on demand. Uses the credentials + settings above. The bot takes several
          minutes per cycle depending on how many listings need reposting. Status appears below
          when it finishes; run history is also visible in the <strong>🌀 Jobs</strong> sidebar entry.
        </p>
        <button type="button" onClick={runNow} disabled={busy} className="pretty-button">
          🌀 Run ATW Repost now
        </button>
        {status && (
          <div className="text-sm bg-black/5 rounded-xl px-3 py-2 font-mono whitespace-pre-wrap">{status}</div>
        )}
      </section>

      {/* Advanced */}
      <details className="pretty-card">
        <summary className="font-semibold cursor-pointer">⚙️ Advanced</summary>
        <div className="space-y-4 mt-3">
          <div className="space-y-2">
            <h4 className="text-sm font-semibold">Override browser binary</h4>
            <p className="text-xs opacity-70">
              Use this only if your Chromium-based browser (Chromium, Brave, Edge) is installed in a
              non-standard location and the auto-discover above failed.
            </p>
            <div className="flex items-center gap-2">
              <input
                type="text"
                className="pretty-input flex-1 font-mono text-xs"
                placeholder="(auto-discovered)"
                value={settings.browserExecutablePath ?? ''}
                readOnly
              />
              <button type="button" onClick={pickBrowserPath} disabled={busy} className="pretty-button secondary text-xs">
                Choose…
              </button>
              {settings.browserExecutablePath && (
                <button type="button" onClick={clearBrowserPath} disabled={busy} className="pretty-button secondary text-xs">
                  Clear
                </button>
              )}
            </div>
          </div>
          <div className="space-y-2">
            <h4 className="text-sm font-semibold">Override bot directory</h4>
            <p className="text-xs opacity-70">
              By default Molly auto-manages a copy of the bot at <code className="font-mono text-[10px]">{setup.botDir}</code>.
              Set this only if you want Molly to invoke a different <code className="font-mono text-[10px]">atw-repost-bot</code> install (e.g. an older
              custom version you're maintaining yourself).
            </p>
            <div className="flex items-center gap-2">
              <input
                type="text"
                className="pretty-input flex-1 font-mono text-xs"
                placeholder="(use auto-managed bot)"
                value={settings.botDir ?? ''}
                readOnly
              />
              <button type="button" onClick={pickOverrideBotDir} disabled={busy} className="pretty-button secondary text-xs">
                Choose…
              </button>
              {settings.botDir && (
                <button type="button" onClick={clearOverrideBotDir} disabled={busy} className="pretty-button secondary text-xs">
                  Reset to auto
                </button>
              )}
            </div>
          </div>
        </div>
      </details>

      {showUnlock && (
        <PassphrasePrompt
          title="Unlock keystore"
          description="Enter your passphrase to use the ATW password."
          confirmLabel="Unlock"
          onSubmit={doUnlock}
          onCancel={() => setShowUnlock(false)}
        />
      )}
    </div>
  );
}

function HealthRow({ ok, label, children }: { ok: boolean; label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-baseline gap-2 text-sm">
      <span className="text-base" aria-hidden>{ok ? '✓' : '✗'}</span>
      <span className="font-semibold w-44">{label}</span>
      <span className={`flex-1 text-xs ${ok ? 'opacity-70' : 'text-amber-800'}`}>{children}</span>
    </div>
  );
}
