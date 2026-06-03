import { useEffect, useMemo, useState } from 'react';
import type { NodeRow, FileFilter } from '../../../../shared/types';
import { formatBytes, formatDate, basename } from '../common/format';
import DeleteConfirm from '../delete/DeleteConfirm';

const api = window.purpleTree;

const SIZE_OPTS = [
  { label: 'Any size', mb: 0 },
  { label: '≥ 10 MB', mb: 10 },
  { label: '≥ 50 MB', mb: 50 },
  { label: '≥ 100 MB', mb: 100 },
  { label: '≥ 500 MB', mb: 500 },
  { label: '≥ 1 GB', mb: 1024 }
];
const AGE_OPTS = [
  { label: 'Any age', days: 0 },
  { label: 'Not opened in 3 months', days: 90 },
  { label: 'Not opened in 6 months', days: 180 },
  { label: 'Not opened in 1 year', days: 365 },
  { label: 'Not opened in 2 years', days: 730 }
];

interface Props {
  scanId: string;
  allowPermanent: boolean;
}

export default function LargeOldFilesView({ scanId, allowPermanent }: Props): JSX.Element {
  const [minMb, setMinMb] = useState(50);
  const [ageDays, setAgeDays] = useState(0);
  const [rows, setRows] = useState<NodeRow[]>([]);
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [confirm, setConfirm] = useState<string[] | null>(null);

  const filter: FileFilter = useMemo(
    () => ({ minBytes: minMb * 1024 * 1024, notAccessedDays: ageDays, extensions: [] }),
    [minMb, ageDays]
  );

  const reload = useMemo(
    () => () => {
      void api.getTopFiles(scanId, 500, filter).then((r) => {
        setRows(r);
        setSelected(new Set());
      });
    },
    [scanId, filter]
  );

  useEffect(() => reload(), [reload]);

  const toggle = (id: number): void =>
    setSelected((s) => {
      const n = new Set(s);
      n.has(id) ? n.delete(id) : n.add(id);
      return n;
    });

  const selectedPaths = rows.filter((r) => selected.has(r.id)).map((r) => r.path);

  return (
    <div className="view largeold-view">
      <div className="view-head">
        <h2>Large &amp; Old Files</h2>
        <select value={minMb} onChange={(e) => setMinMb(Number(e.target.value))}>
          {SIZE_OPTS.map((o) => (
            <option key={o.mb} value={o.mb}>
              {o.label}
            </option>
          ))}
        </select>
        <select value={ageDays} onChange={(e) => setAgeDays(Number(e.target.value))}>
          {AGE_OPTS.map((o) => (
            <option key={o.days} value={o.days}>
              {o.label}
            </option>
          ))}
        </select>
        <div className="spacer" />
        {selected.size > 0 && (
          <button className="btn-primary" onClick={() => setConfirm(selectedPaths)}>
            Delete {selected.size}…
          </button>
        )}
      </div>
      <div className="lo-list">
        {rows.map((r) => (
          <div
            key={r.id}
            className={`lo-row${selected.has(r.id) ? ' selected' : ''}`}
            onDoubleClick={() => void api.reveal(r.path)}
          >
            <input
              type="checkbox"
              checked={selected.has(r.id)}
              onChange={() => toggle(r.id)}
              onClick={(e) => e.stopPropagation()}
            />
            <span className="lo-size">{formatBytes(r.aggSize)}</span>
            <span className="lo-name" title={r.path}>
              {basename(r.path)}
            </span>
            <span className="lo-date">opened {formatDate(r.atimeMs) || '—'}</span>
            <span className="lo-dir" title={r.path}>
              {r.path}
            </span>
          </div>
        ))}
        {rows.length === 0 && <p className="muted">No files match these filters.</p>}
      </div>
      {confirm && (
        <DeleteConfirm
          paths={confirm}
          allowPermanent={allowPermanent}
          onClose={() => setConfirm(null)}
          onDone={() => {
            setConfirm(null);
            reload();
          }}
        />
      )}
    </div>
  );
}
