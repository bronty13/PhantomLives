import { useEffect, useMemo, useState } from 'react';
import type { NodeRow, FileFilter, DeleteResult } from '../../../../shared/types';
import { formatBytes, formatDate, basename, heatBg } from '../common/format';
import { useColumnResize } from '../common/useColumnResize';
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
  heatmapColor: string;
}

interface Tip { text: string; x: number; y: number }

export default function LargeOldFilesView({ scanId, allowPermanent, heatmapColor }: Props): JSX.Element {
  const [minMb, setMinMb] = useState(50);
  const [ageDays, setAgeDays] = useState(0);
  const [rows, setRows] = useState<NodeRow[]>([]);
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [confirm, setConfirm] = useState<string[] | null>(null);
  const [tip, setTip] = useState<Tip | null>(null);
  const { width: nameWidth, onMouseDown: nameResizeDown } = useColumnResize(220);

  const showTip = (e: React.MouseEvent, text: string): void =>
    setTip({ text, x: e.clientX, y: e.clientY });
  const moveTip = (e: React.MouseEvent): void =>
    setTip((t) => (t ? { ...t, x: e.clientX, y: e.clientY } : null));
  const hideTip = (): void => setTip(null);

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
      <div className="lo-head">
        <span className="lo-head-chk" />
        <span className="lo-size">Size</span>
        <div className="lo-name lo-name-hd" style={{ flex: `0 0 ${nameWidth}px` }}>
          <span>Name</span>
          <div className="col-resize-handle" onMouseDown={nameResizeDown} />
        </div>
        <span className="lo-date">Last opened</span>
        <span className="lo-dir">Path</span>
      </div>
      <div className="lo-list">
        {rows.map((r) => {
          const maxSize = rows[0]?.aggSize ?? 0;
          const bg = heatBg(maxSize > 0 ? r.aggSize / maxSize : 0, heatmapColor);
          return (
          <div
            key={r.id}
            className={`lo-row${selected.has(r.id) ? ' selected' : ''}`}
            style={bg ? { backgroundColor: bg } : undefined}
            onDoubleClick={() => void api.reveal(r.path)}
          >
            <input
              type="checkbox"
              checked={selected.has(r.id)}
              onChange={() => toggle(r.id)}
              onClick={(e) => e.stopPropagation()}
            />
            <span className="lo-size">{formatBytes(r.aggSize)}</span>
            <span
              className="lo-name"
              style={{ flex: `0 0 ${nameWidth}px` }}
              onMouseEnter={(e) => showTip(e, `${basename(r.path)}\n${r.path}`)}
              onMouseMove={moveTip}
              onMouseLeave={hideTip}
            >
              {basename(r.path)}
            </span>
            <span className="lo-date">opened {formatDate(r.atimeMs) || '—'}</span>
            <span
              className="lo-dir"
              onMouseEnter={(e) => showTip(e, r.path)}
              onMouseMove={moveTip}
              onMouseLeave={hideTip}
            >
              {r.path}
            </span>
          </div>
          );
        })}
        {rows.length === 0 && <p className="muted">No files match these filters.</p>}
      </div>
      {tip && (
        <div className="path-tooltip" style={{ left: tip.x + 14, top: tip.y + 18 }}>
          {tip.text.split('\n').map((line, i) => (
            <div key={i} className={i === 0 ? 'tip-name' : 'tip-path'}>{line}</div>
          ))}
        </div>
      )}
      {confirm && (
        <DeleteConfirm
          paths={confirm}
          allowPermanent={allowPermanent}
          onClose={() => setConfirm(null)}
          onDone={(result: DeleteResult) => {
            setConfirm(null);
            const removed = new Set(result.removed);
            setRows((prev) => prev.filter((r) => !removed.has(r.path)));
            setSelected(new Set());
          }}
        />
      )}
    </div>
  );
}

