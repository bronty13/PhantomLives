import { useEffect, useState } from 'react';
import { getVersion } from '@tauri-apps/api/app';
import { check, type Update } from '@tauri-apps/plugin-updater';
import { relaunch } from '@tauri-apps/plugin-process';

type State =
  | { kind: 'idle' }
  | { kind: 'checking' }
  | { kind: 'none'; checkedAt: string }
  | { kind: 'available'; update: Update; checkedAt: string }
  | { kind: 'downloading'; downloaded: number; total: number | null }
  | { kind: 'installed' }
  | { kind: 'error'; message: string };

function fmtBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 / 1024).toFixed(2)} MB`;
}

export function UpdatesSettings() {
  const [version, setVersion] = useState<string>('—');
  const [state, setState] = useState<State>({ kind: 'idle' });

  useEffect(() => {
    getVersion().then(setVersion).catch(() => setVersion('—'));
  }, []);

  async function runCheck() {
    setState({ kind: 'checking' });
    try {
      const update = await check();
      const checkedAt = new Date().toLocaleString();
      if (!update) {
        setState({ kind: 'none', checkedAt });
      } else {
        setState({ kind: 'available', update, checkedAt });
      }
    } catch (e) {
      setState({ kind: 'error', message: String(e) });
    }
  }

  async function downloadAndInstall(update: Update) {
    let downloaded = 0;
    let total: number | null = null;
    setState({ kind: 'downloading', downloaded, total });
    try {
      await update.downloadAndInstall((event) => {
        switch (event.event) {
          case 'Started':
            total = typeof event.data?.contentLength === 'number' ? event.data.contentLength : null;
            setState({ kind: 'downloading', downloaded, total });
            break;
          case 'Progress':
            downloaded += event.data?.chunkLength ?? 0;
            setState({ kind: 'downloading', downloaded, total });
            break;
          case 'Finished':
            setState({ kind: 'installed' });
            break;
        }
      });
      // Relaunch into the new bundle. Catch and surface any error.
      try {
        await relaunch();
      } catch (e) {
        console.warn('relaunch failed', e);
      }
    } catch (e) {
      setState({ kind: 'error', message: String(e) });
    }
  }

  return (
    <div className="space-y-3">
      <div className="pretty-card">
        <h3 className="display-font text-xl font-semibold persona-accent mb-1">Updates</h3>
        <p className="text-sm opacity-70 mb-3">
          Molly checks for updates on launch. You can also check manually here. Downloads happen in the
          background; click <strong>Install &amp; relaunch</strong> when one's ready.
        </p>

        <div className="grid grid-cols-2 gap-3 mb-3">
          <div className="p-3 rounded-xl persona-tint border border-black/5">
            <div className="text-xs uppercase tracking-wider opacity-60">Current version</div>
            <div className="display-font text-xl font-bold persona-accent mt-0.5">{version}</div>
          </div>
          <div className="p-3 rounded-xl persona-tint border border-black/5">
            <div className="text-xs uppercase tracking-wider opacity-60">Last checked</div>
            <div className="text-sm mt-0.5">
              {state.kind === 'checking' && 'Checking…'}
              {(state.kind === 'none' || state.kind === 'available') && state.checkedAt}
              {state.kind === 'idle' && '(not yet)'}
              {state.kind === 'downloading' && 'downloading…'}
              {state.kind === 'installed' && 'just now ✓'}
              {state.kind === 'error' && state.message.slice(0, 80)}
            </div>
          </div>
        </div>

        <div className="flex flex-wrap gap-2">
          <button type="button" className="pretty-button" onClick={runCheck} disabled={state.kind === 'checking' || state.kind === 'downloading'}>
            🔍 Check for updates
          </button>
          {state.kind === 'available' && (
            <button type="button" className="pretty-button" onClick={() => downloadAndInstall(state.update)}>
              ⬇️ Download v{state.update.version}
            </button>
          )}
        </div>

        {state.kind === 'none' && (
          <div className="mt-3 text-sm opacity-80">You're on the newest version. ✨</div>
        )}
        {state.kind === 'available' && (
          <div className="mt-3 text-sm">
            <strong>Update available:</strong> v{state.update.version}
            {state.update.body && (
              <div className="text-xs opacity-70 mt-1 whitespace-pre-line">{state.update.body}</div>
            )}
          </div>
        )}
        {state.kind === 'downloading' && (
          <div className="mt-3">
            <div className="text-sm mb-1">
              Downloading… {fmtBytes(state.downloaded)}{state.total ? ` / ${fmtBytes(state.total)}` : ''}
            </div>
            <div className="h-2 rounded-full bg-black/5 overflow-hidden">
              <div
                className="h-full transition-all"
                style={{
                  width: state.total ? `${(state.downloaded / state.total) * 100}%` : '40%',
                  background: 'rgb(var(--persona-accent))',
                }}
              />
            </div>
          </div>
        )}
        {state.kind === 'installed' && (
          <div className="mt-3 text-sm">Installed. Molly will relaunch in a moment. ✨</div>
        )}
        {state.kind === 'error' && (
          <div className="mt-3 text-sm text-red-700">
            <strong>Couldn't check:</strong> {state.message}
            <div className="text-xs opacity-70 mt-1">
              This usually means the release feed hasn't been set up yet for this version. You can grab the latest
              installer manually from the <a href="https://github.com/bronty13/PhantomLives/releases" target="_blank" rel="noreferrer" className="underline">GitHub Releases page</a>.
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
