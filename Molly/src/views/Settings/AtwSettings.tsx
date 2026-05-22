import { useCallback, useEffect, useState } from 'react';
import { open as openDialog } from '@tauri-apps/plugin-dialog';
import {
  type AtwHealthCheck,
  type AtwSettings as AtwSettingsType,
  atwHealthCheck,
  atwRunNow,
  getAtwSettings,
  setAtwSettings,
} from '../../data/atwSettings';
import { upsertAtwJob } from '../../data/backgroundJobs';
import { useKeystore } from '../../state/keystoreContext';

/** Settings → 🌀 ATW Repost pane. */
export function AtwSettingsPane() {
  const { status: keystoreStatus } = useKeystore();
  const [settings, setSettings] = useState<AtwSettingsType | null>(null);
  const [health, setHealth] = useState<AtwHealthCheck | null>(null);
  const [passwordDraft, setPasswordDraft] = useState('');
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      const [s, h] = await Promise.all([getAtwSettings(), atwHealthCheck()]);
      setSettings(s);
      setHealth(h);
    } catch (e) {
      setStatus(`Couldn't load ATW settings: ${String((e as { message?: string })?.message ?? e)}`);
    }
  }, []);

  useEffect(() => { refresh(); }, [refresh]);

  if (!settings || !health) {
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
      // Mirror cadence to the background_jobs row.
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

  async function pickBotDir() {
    const picked = await openDialog({ directory: true, multiple: false, title: 'Pick atw-repost-bot directory' });
    if (typeof picked === 'string') await save({ botDir: picked });
  }

  async function clearBotDir() { await save({ botDir: null }); }

  async function pickChromePath() {
    const picked = await openDialog({ directory: false, multiple: false, title: 'Pick Chrome / Chromium binary' });
    if (typeof picked === 'string') await save({ browserExecutablePath: picked });
  }
  async function clearChromePath() { await save({ browserExecutablePath: null }); }

  async function runNow() {
    if (!keystoreStatus?.unlocked) {
      setStatus('Unlock the keystore first (Settings → 🔐 Security).');
      return;
    }
    setBusy(true);
    setStatus('Running ATW bot now (this can take several minutes)…');
    try {
      const outcome = await atwRunNow();
      setStatus(`${outcome.status === 'success' ? '✓' : '✗'} ${outcome.summary}`);
    } catch (e) {
      setStatus(`Run failed: ${String((e as { message?: string })?.message ?? e)}`);
    } finally {
      setBusy(false);
    }
  }

  const locked = !keystoreStatus?.unlocked;

  return (
    <div className="space-y-4">
      <section className="pretty-card space-y-3">
        <h3 className="font-semibold">🩺 Health check</h3>
        <HealthRow ok={health.nodeFound} label="Node.js installed">
          {health.nodePath ?? 'Install Node 18+ from nodejs.org and restart Molly.'}
        </HealthRow>
        <HealthRow ok={health.chromeFound} label="Chrome / Chromium found">
          {health.chromePath ?? 'Install Google Chrome OR set Browser executable path below.'}
        </HealthRow>
        <HealthRow ok={health.botDirSet && health.botDirExists} label="Bot directory">
          {!health.botDirSet
            ? 'Not set — pick the folder that contains your atw-repost-bot/repost.js.'
            : !health.botDirExists
            ? `Set to ${settings.botDir} but the folder doesn't exist.`
            : `${settings.botDir}`}
        </HealthRow>
        <HealthRow ok={health.botDirHasRepostJs} label="repost.js present">
          {health.botDirHasRepostJs ? 'OK' : 'Bot directory is missing repost.js — wrong folder?'}
        </HealthRow>
        <HealthRow ok={health.botDirHasNodeModules} label="node_modules installed">
          {health.botDirHasNodeModules
            ? 'OK'
            : 'Run `npm install` inside the bot directory (Playwright + stealth plugin install on first run).'}
        </HealthRow>
      </section>

      <section className="pretty-card space-y-3">
        <h3 className="font-semibold">🔑 Credentials</h3>
        {keystoreStatus && !keystoreStatus.initialized && (
          <div className="text-xs bg-amber-50 border border-amber-200 rounded-xl px-3 py-2">
            Set up the keystore in <strong>Settings → 🔐 Security</strong> first.
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
            <div className="text-xs opacity-60 italic">🔒 Unlock keystore (Settings → 🔐 Security) to set or change the password.</div>
          )}
        </label>
      </section>

      <section className="pretty-card space-y-3">
        <h3 className="font-semibold">📂 Bot installation</h3>
        <p className="text-xs opacity-70">
          Molly orchestrates your existing <code className="font-mono">atw-repost-bot</code>; pick the
          folder that contains <code className="font-mono">repost.js</code>. v1 doesn't ship the bot
          itself; future versions will.
        </p>
        <div className="flex items-center gap-2">
          <input
            type="text"
            className="pretty-input flex-1 font-mono text-sm"
            placeholder="/path/to/atw-repost-bot"
            value={settings.botDir ?? ''}
            readOnly
          />
          <button type="button" onClick={pickBotDir} disabled={busy} className="pretty-button secondary">
            Choose…
          </button>
          {settings.botDir && (
            <button type="button" onClick={clearBotDir} disabled={busy} className="pretty-button secondary">
              Clear
            </button>
          )}
        </div>

        <details>
          <summary className="text-xs opacity-60 cursor-pointer">Advanced: override Chrome binary</summary>
          <div className="mt-2 flex items-center gap-2">
            <input
              type="text"
              className="pretty-input flex-1 font-mono text-xs"
              placeholder="(auto-discovered)"
              value={settings.browserExecutablePath ?? ''}
              readOnly
            />
            <button type="button" onClick={pickChromePath} disabled={busy} className="pretty-button secondary text-xs">
              Choose…
            </button>
            {settings.browserExecutablePath && (
              <button type="button" onClick={clearChromePath} disabled={busy} className="pretty-button secondary text-xs">
                Clear
              </button>
            )}
          </div>
        </details>
      </section>

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

      <section className="pretty-card space-y-3">
        <h3 className="font-semibold">▶️ Run now</h3>
        <p className="text-xs opacity-70">
          Run the ATW bot once on demand. Uses the credentials + settings above. The bot takes several
          minutes per cycle depending on how many listings need reposting. Status appears below
          when it finishes; run history is also visible in the <strong>🌀 Jobs</strong> sidebar entry.
        </p>
        <button type="button" onClick={runNow} disabled={busy || locked} className="pretty-button">
          🌀 Run ATW Repost now
        </button>
        {status && (
          <div className="text-sm bg-black/5 rounded-xl px-3 py-2 font-mono whitespace-pre-wrap">{status}</div>
        )}
      </section>
    </div>
  );
}

function HealthRow({ ok, label, children }: { ok: boolean; label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-baseline gap-2 text-sm">
      <span className="text-base" aria-hidden>{ok ? '✓' : '✗'}</span>
      <span className="font-semibold w-44">{label}</span>
      <span className={`flex-1 font-mono text-xs ${ok ? 'opacity-70' : 'text-amber-800'}`}>{children}</span>
    </div>
  );
}
