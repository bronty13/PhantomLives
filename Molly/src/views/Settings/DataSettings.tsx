import { useState } from 'react';
import { invoke } from '@tauri-apps/api/core';

interface ExportResult {
  path: string;
  sizeBytes: number;
  fileCount: number;
}

const IS_DEV = import.meta.env.VITE_MOLLY_DEV === '1';

function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 / 1024).toFixed(2)} MB`;
}

export function DataSettings() {
  const [result, setResult] = useState<ExportResult | null>(null);
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState<string>('');

  async function runExport() {
    setBusy(true);
    setStatus('');
    try {
      const r = await invoke<ExportResult>('export_full_data');
      setResult(r);
      setStatus(`Exported ${r.fileCount} file${r.fileCount === 1 ? '' : 's'} (${formatBytes(r.sizeBytes)}).`);
    } catch (e) {
      setStatus(`Export failed: ${String(e)}`);
    } finally {
      setBusy(false);
    }
  }

  async function revealDir() {
    try {
      await invoke('reveal_export_dir');
    } catch (e) {
      setStatus(String(e));
    }
  }

  async function revealFile(path: string) {
    try {
      await invoke('reveal_path', { path });
    } catch (e) {
      setStatus(String(e));
    }
  }

  async function importPicked() {
    setBusy(true);
    setStatus('');
    try {
      const { open } = await import('@tauri-apps/plugin-dialog');
      const picked = await open({ multiple: false, directory: false, title: 'Pick a Molly-export-*.zip', filters: [{ name: 'Molly export', extensions: ['zip'] }] });
      if (!picked || typeof picked !== 'string') return;
      const safety: string = await invoke('import_full_export', { path: picked });
      setStatus(`Imported. A pre-import safety archive was saved at ${safety}. Quit and relaunch Molly to load the new data cleanly.`);
    } catch (e) {
      setStatus(`Import failed: ${String(e)}`);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-3">
      <div className="pretty-card">
        <h3 className="display-font text-xl font-semibold persona-accent mb-1">Data export</h3>
        <p className="text-sm opacity-70 mb-3">
          Bundle everything Molly knows (database + receipts + settings + a small manifest) into one zip
          file so Robert can take a look. Re-running just makes a new file; old ones are untouched.
        </p>
        <div className="flex flex-wrap gap-2 items-center">
          <button type="button" className="pretty-button" onClick={runExport} disabled={busy}>
            📦 Export everything
          </button>
          <button type="button" className="pretty-button secondary" onClick={revealDir} disabled={busy}>
            🗂  Reveal export folder
          </button>
        </div>

        <div className="mt-3 text-xs opacity-70">
          Default location: <span className="font-mono">~/Downloads/Molly export/</span> (Mac) ·{' '}
          <span className="font-mono">%USERPROFILE%\Downloads\Molly export\</span> (Windows). Auto-created on demand.
        </div>

        {result && (
          <div className="mt-3 p-3 rounded-xl border border-black/5" style={{ background: 'rgb(var(--persona-tint))' }}>
            <div className="text-xs uppercase tracking-wider opacity-60 mb-1">Last export</div>
            <div className="font-mono text-xs truncate" title={result.path}>{result.path}</div>
            <div className="text-xs opacity-70 mt-0.5">{result.fileCount} files · {formatBytes(result.sizeBytes)}</div>
            <div className="mt-2 flex gap-2">
              <button type="button" className="pretty-button secondary" onClick={() => revealFile(result.path)} disabled={busy}>
                Reveal in Finder
              </button>
            </div>
            <div className="mt-3 text-xs">
              <strong>Sending to Robert?</strong> Drop this .zip into our Slack DM. He'll import it on his dev machine and look at how Molly's being used.
            </div>
          </div>
        )}
      </div>

      {IS_DEV && (
        <div className="pretty-card border-amber-300 border" style={{ background: '#fffbeb' }}>
          <h4 className="display-font text-base font-semibold mb-1">🛠 Dev import (VITE_MOLLY_DEV=1)</h4>
          <p className="text-xs opacity-70 mb-2">
            Replace the live Molly database + attachments with the contents of a user-exported zip. A pre-import
            safety archive is written first so this is reversible. Restart the app after importing.
          </p>
          <button type="button" className="pretty-button" onClick={importPicked} disabled={busy}>
            📥 Import a Molly-export-*.zip…
          </button>
        </div>
      )}

      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}
