import { useEffect, useState } from 'react';
import { open } from '@tauri-apps/plugin-dialog';
import { getWatchSettings, revealWatchDir, scanWatchDirNow, setWatchDir,
         type WatchSettings as WatchSettingsT, type ScanResult } from '../../data/bundles';

export function WatchSettings() {
  const [settings, setSettings] = useState<WatchSettingsT | null>(null);
  const [status, setStatus] = useState<string>('');
  const [busy, setBusy] = useState(false);
  const [lastScan, setLastScan] = useState<ScanResult | null>(null);

  const refresh = async () => {
    try {
      setSettings(await getWatchSettings());
    } catch (e) {
      setStatus(`Failed to load: ${e}`);
    }
  };

  useEffect(() => { refresh(); }, []);

  const pickFolder = async () => {
    try {
      const picked = await open({ directory: true, multiple: false });
      if (typeof picked === 'string') {
        const next = await setWatchDir(picked);
        setSettings(next);
        setStatus(`Watched folder set to ${picked}`);
      }
    } catch (e) {
      setStatus(`Pick failed: ${e}`);
    }
  };

  const useDefault = async () => {
    try {
      const next = await setWatchDir(null);
      setSettings(next);
      setStatus('Reverted to default watched folder.');
    } catch (e) {
      setStatus(`Reset failed: ${e}`);
    }
  };

  const reveal = async () => {
    try { await revealWatchDir(); }
    catch (e) { setStatus(`Reveal failed: ${e}`); }
  };

  const scanNow = async () => {
    setBusy(true);
    setStatus('Scanning…');
    try {
      const r = await scanWatchDirNow();
      setLastScan(r);
      setStatus(
        `Scan complete: ${r.considered} considered · ${r.ingested} ingested · ${r.skipped} skipped` +
        (r.failed > 0 ? ` · ⚠ ${r.failed} failed` : ''),
      );
    } catch (e) {
      setStatus(`Scan failed: ${e}`);
    } finally {
      setBusy(false);
    }
  };

  if (!settings) return <div className="sm-card">Loading…</div>;

  return (
    <div className="flex flex-col gap-4">
      <div className="sm-card">
        <div className="font-semibold mb-2">Watched folder</div>
        <div className="text-xs mb-2" style={{ color: 'rgb(var(--surface-muted))' }}>
          Bundles dropped into this folder by Molly are auto-ingested. Drag-and-drop onto the
          window still works regardless of this setting.
        </div>
        <div className="font-mono text-xs sm-card mt-2" style={{ background: 'rgb(var(--surface-base))' }}>
          {settings.resolvedPath}
        </div>
        <div className="text-xs mt-1" style={{ color: 'rgb(var(--surface-muted))' }}>
          {settings.usingDefault ? '(using default ~/Downloads/Molly bundles/)' : '(custom path)'}
        </div>
        <div className="flex gap-2 mt-3 flex-wrap">
          <button type="button" className="sm-button" onClick={pickFolder} disabled={busy}>
            📂 Choose folder…
          </button>
          {!settings.usingDefault && (
            <button type="button" className="sm-button secondary" onClick={useDefault} disabled={busy}>
              ↺ Use default
            </button>
          )}
          <button type="button" className="sm-button secondary" onClick={reveal} disabled={busy}>
            📁 Reveal
          </button>
          <button type="button" className="sm-button" onClick={scanNow} disabled={busy}>
            {busy ? '⏳ Scanning…' : '🔄 Scan now'}
          </button>
        </div>
      </div>

      {lastScan && (
        <div className="sm-card">
          <div className="font-semibold mb-2">Last scan</div>
          <div className="font-mono text-xs">{lastScan.scannedPath}</div>
          <div className="text-sm mt-1">
            {lastScan.considered} considered · {lastScan.ingested} ingested ·{' '}
            {lastScan.skipped} skipped
            {lastScan.failed > 0 && <span style={{ color: '#c4252e' }}> · {lastScan.failed} failed</span>}
          </div>
          {lastScan.errors.length > 0 && (
            <details className="mt-2 text-xs">
              <summary style={{ color: '#c4252e', cursor: 'pointer' }}>
                {lastScan.errors.length} error{lastScan.errors.length === 1 ? '' : 's'}
              </summary>
              <ul className="mt-1 font-mono">
                {lastScan.errors.map((e, i) => <li key={i}>· {e}</li>)}
              </ul>
            </details>
          )}
        </div>
      )}

      {status && (
        <div className="text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>
          {status}
        </div>
      )}
    </div>
  );
}
