import { useEffect, useState } from 'react';
import type { ResolvedCachePreset } from '../../../../shared/types';
import { formatBytes, formatCount, riskColor } from '../common/format';

const api = window.purpleTree;

export default function CacheCleanupView(): JSX.Element {
  const [presets, setPresets] = useState<ResolvedCachePreset[] | null>(null);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState<string>('');

  const scan = (): void => {
    setPresets(null);
    setSelected(new Set());
    void api.scanCachePresets().then(setPresets);
  };

  useEffect(() => scan(), []);

  const toggle = (id: string): void =>
    setSelected((s) => {
      const n = new Set(s);
      n.has(id) ? n.delete(id) : n.add(id);
      return n;
    });

  const chosen = (presets ?? []).filter((p) => selected.has(p.id));
  const reclaim = chosen.reduce((a, p) => a + p.totalBytes, 0);

  const clean = async (): Promise<void> => {
    if (chosen.length === 0) return;
    setBusy(true);
    setStatus('Cleaning…');
    let removed = 0;
    let failed = 0;
    for (const preset of chosen) {
      const r = await api.cleanCache(preset.paths);
      removed += r.removed.length;
      failed += r.failed.length;
    }
    setBusy(false);
    setStatus(`Moved ${formatCount(removed)} items to Trash${failed ? ` · ${failed} skipped` : ''}.`);
    scan();
  };

  return (
    <div className="view cache-view">
      <div className="view-head">
        <h2>Smart Cache Cleanup</h2>
        <div className="spacer" />
        {status && <span className="muted">{status}</span>}
        <button onClick={scan} disabled={busy}>
          Re-scan
        </button>
        <button className="btn-primary" disabled={busy || chosen.length === 0} onClick={() => void clean()}>
          Move {formatBytes(reclaim)} to Trash
        </button>
      </div>
      <p className="muted cache-note">
        Everything here goes to the Trash (recoverable), never permanently deleted. Quit the related
        apps first so caches aren&apos;t in use. Nothing is selected by default — you choose.
      </p>
      {!presets && <p className="muted">Measuring caches…</p>}
      <div className="cache-list">
        {presets?.map((p) => (
          <label key={p.id} className={`cache-row${selected.has(p.id) ? ' selected' : ''}`}>
            <input
              type="checkbox"
              checked={selected.has(p.id)}
              onChange={() => toggle(p.id)}
              disabled={p.totalBytes === 0}
            />
            <span className="cache-main">
              <span className="cache-label">
                {p.label}
                <span className="risk" style={{ background: riskColor(p.riskLevel) }}>
                  {p.riskLevel}
                </span>
              </span>
              <span className="cache-desc">{p.description}</span>
              {p.paths.length > 0 && (
                <span className="cache-paths" title={p.paths.join('\n')}>
                  {p.paths.join(', ')}
                </span>
              )}
            </span>
            <span className="cache-size">
              {formatBytes(p.totalBytes)}
              <span className="cache-count">{formatCount(p.fileCount)} files</span>
            </span>
          </label>
        ))}
        {presets && presets.length === 0 && (
          <p className="muted">No known cache locations found on this machine.</p>
        )}
      </div>
    </div>
  );
}
