import { useEffect, useState } from 'react';
import type { SnapshotInfo, SnapshotDiff } from '../../../../shared/types';
import { formatBytes, formatCount, formatDate } from '../common/format';

const api = window.purpleTree;

function signed(n: number): string {
  return `${n >= 0 ? '+' : '−'}${formatBytes(Math.abs(n))}`;
}
function statusColor(s: string): string {
  return s === 'grew' || s === 'added' ? '#dc2626' : '#16a34a';
}

interface Props {
  /** Called after loading a snapshot into a live scan. */
  onLoaded: (scanId: string) => void;
}

export default function SnapshotsView({ onLoaded }: Props): JSX.Element {
  const [snaps, setSnaps] = useState<SnapshotInfo[]>([]);
  const [selected, setSelected] = useState<string[]>([]);
  const [diff, setDiff] = useState<SnapshotDiff | null>(null);
  const [busy, setBusy] = useState(false);
  const [filter, setFilter] = useState<'all' | 'files' | 'folders'>('all');

  const reload = (): void => {
    void api.snapshotList().then(setSnaps);
  };
  useEffect(() => reload(), []);

  const toggleSel = (id: string): void =>
    setSelected((sel) => {
      if (sel.includes(id)) return sel.filter((s) => s !== id);
      const next = [...sel, id];
      return next.slice(-2); // keep at most 2 (the two most recently ticked)
    });

  const compare = async (): Promise<void> => {
    if (selected.length !== 2) return;
    setBusy(true);
    const d = await api.snapshotDiff(selected[0], selected[1]);
    setBusy(false);
    setDiff(d);
  };

  const load = async (id: string): Promise<void> => {
    const r = await api.snapshotLoad(id);
    if (r) onLoaded(r.scanId);
  };

  const remove = async (id: string): Promise<void> => {
    await api.snapshotDelete(id);
    setSelected((s) => s.filter((x) => x !== id));
    if (diff && (diff.a.scanId === id || diff.b.scanId === id)) setDiff(null);
    reload();
  };

  return (
    <div className="view snapshots-view">
      <div className="view-head">
        <h2>Snapshots</h2>
        <div className="spacer" />
        <span className="muted">{selected.length}/2 selected to compare</span>
        <button className="btn-primary" disabled={selected.length !== 2 || busy} onClick={() => void compare()}>
          {busy ? 'Comparing…' : 'Compare'}
        </button>
      </div>
      <p className="muted">
        Use <strong>Save Snapshot</strong> in the top bar after a scan, then come back here to load an
        old scan or compare two over time. (Sizes use your current On-disk/Logical setting.)
      </p>

      <div className="snap-list">
        {snaps.length === 0 && <p className="muted">No snapshots yet.</p>}
        {snaps.map((s) => (
          <div key={s.scanId} className={`snap-row${selected.includes(s.scanId) ? ' selected' : ''}`}>
            <input type="checkbox" checked={selected.includes(s.scanId)} onChange={() => toggleSel(s.scanId)} />
            <span className="snap-main">
              <span className="snap-root" title={s.rootPath}>
                {s.rootPath}
              </span>
              <span className="snap-meta">
                {formatDate(s.createdMs)} · {formatBytes(s.totalBytes)} · {formatCount(s.totalFiles)} files
              </span>
            </span>
            <button onClick={() => void load(s.scanId)}>Open</button>
            <button className="btn-danger" onClick={() => void remove(s.scanId)}>
              Delete
            </button>
          </div>
        ))}
      </div>

      {diff && (
        <div className="diff-panel">
          <div className="diff-head">
            <strong>{formatDate(diff.a.createdMs)}</strong> → <strong>{formatDate(diff.b.createdMs)}</strong>{' '}
            · overall{' '}
            <strong style={{ color: statusColor(diff.totalDelta >= 0 ? 'grew' : 'shrank') }}>
              {signed(diff.totalDelta)}
            </strong>
            {diff.entries.length === 0 && <span className="muted"> · no changes detected</span>}
            <span className="diff-filter">
              {(['all', 'files', 'folders'] as const).map((f) => (
                <button key={f} className={filter === f ? 'active' : ''} onClick={() => setFilter(f)}>
                  {f === 'all' ? 'All' : f === 'files' ? 'Files' : 'Folders'}
                </button>
              ))}
            </span>
          </div>
          <div className="diff-rows">
            {diff.entries
              .filter((e) => filter === 'all' || (filter === 'files' ? !e.isDir : e.isDir))
              .map((e) => (
                <div key={e.path} className="diff-row" onDoubleClick={() => void api.reveal(e.path)}>
                  <span className="diff-badge" style={{ background: statusColor(e.status) }}>
                    {e.status}
                  </span>
                  <span className="diff-path" title={e.path}>
                    {e.isDir ? '📁' : '📄'} {e.path}
                  </span>
                  <span className="diff-sizes muted">
                    {formatBytes(e.sizeA)} → {formatBytes(e.sizeB)}
                  </span>
                  <span className="diff-delta" style={{ color: statusColor(e.status) }}>
                    {signed(e.delta)}
                  </span>
                </div>
              ))}
          </div>
        </div>
      )}
    </div>
  );
}
