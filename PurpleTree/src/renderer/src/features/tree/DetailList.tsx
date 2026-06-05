import { useEffect, useMemo, useState } from 'react';
import type { NodeRow, SortKey, SortSpec } from '../../../../shared/types';
import { formatBytes, formatDate, formatCount, heatBg } from '../common/format';
import { useColumnResize } from '../common/useColumnResize';
import DeleteConfirm from '../delete/DeleteConfirm';

const api = window.purpleTree;
const PAGE = 1000;

interface Props {
  scanId: string;
  focusId: number;
  allowPermanent: boolean;
  heatmapColor: string;
  onDrill: (id: number) => void;
}

interface Tip { text: string; x: number; y: number }

export default function DetailList({ scanId, focusId, allowPermanent, heatmapColor, onDrill }: Props): JSX.Element {
  const [rows, setRows] = useState<NodeRow[]>([]);
  const [sort, setSort] = useState<SortSpec>({ key: 'size', dir: 'desc' });
  const [tip, setTip] = useState<Tip | null>(null);
  const { width: nameWidth, onMouseDown: nameResizeDown } = useColumnResize(260);

  const showTip = (e: React.MouseEvent, text: string): void =>
    setTip({ text, x: e.clientX, y: e.clientY });
  const moveTip = (e: React.MouseEvent): void =>
    setTip((t) => (t ? { ...t, x: e.clientX, y: e.clientY } : null));
  const hideTip = (): void => setTip(null);
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [confirm, setConfirm] = useState<string[] | null>(null);

  const reload = useMemo(
    () => () => {
      void api.getChildren(scanId, focusId, sort, PAGE, 0).then((r) => {
        setRows(r);
        setSelected(new Set());
      });
    },
    [scanId, focusId, sort]
  );

  useEffect(() => reload(), [reload]);

  const toggleSort = (key: SortKey): void =>
    setSort((s) => (s.key === key ? { key, dir: s.dir === 'asc' ? 'desc' : 'asc' } : { key, dir: 'desc' }));

  const arrow = (key: SortKey): string => (sort.key === key ? (sort.dir === 'asc' ? ' ▲' : ' ▼') : '');

  const toggleSel = (id: number): void =>
    setSelected((s) => {
      const n = new Set(s);
      n.has(id) ? n.delete(id) : n.add(id);
      return n;
    });

  const selectedPaths = rows.filter((r) => selected.has(r.id)).map((r) => r.path);

  return (
    <div className="detail-list">
      <div className="detail-actions">
        <span className="muted">{formatCount(rows.length)} items</span>
        <div className="spacer" />
        {selected.size > 0 && (
          <>
            <span className="muted">{selected.size} selected</span>
            <button onClick={() => setConfirm(selectedPaths)}>Delete…</button>
          </>
        )}
      </div>
      <div className="detail-head">
        <span className="col-sel" />
        <div className="col-name" style={{ flex: `0 0 ${nameWidth}px` }}>
          <button onClick={() => toggleSort('name')}>Name{arrow('name')}</button>
          <div className="col-resize-handle" onMouseDown={nameResizeDown} />
        </div>
        <button className="col-size" onClick={() => toggleSort('size')}>
          Size{arrow('size')}
        </button>
        <button className="col-count" onClick={() => toggleSort('count')}>
          Files{arrow('count')}
        </button>
        <button className="col-date" onClick={() => toggleSort('mtime')}>
          Modified{arrow('mtime')}
        </button>
      </div>
      <div className="detail-body">
        {rows.map((r) => {
          const maxSize = rows[0]?.aggSize ?? 0;
          const fraction = maxSize > 0 ? r.aggSize / maxSize : 0;
          const pct = fraction * 100;
          const bg = heatBg(fraction, heatmapColor);
          return (
            <div
              key={r.id}
              className={`detail-row${selected.has(r.id) ? ' selected' : ''}`}
              style={bg ? { backgroundColor: bg } : undefined}
              onDoubleClick={() => (r.isDir ? onDrill(r.id) : void api.reveal(r.path))}
            >
              <span className="col-sel">
                <input
                  type="checkbox"
                  checked={selected.has(r.id)}
                  onChange={() => toggleSel(r.id)}
                  onClick={(e) => e.stopPropagation()}
                />
              </span>
              <span
                className="col-name"
                style={{ flex: `0 0 ${nameWidth}px` }}
                onMouseEnter={(e) => showTip(e, `${r.name}\n${r.path}`)}
                onMouseMove={moveTip}
                onMouseLeave={hideTip}
              >
                <span className="bar" style={{ width: `${pct}%` }} />
                <span className="tree-icon">{r.isDir ? '📁' : '📄'}</span>
                {r.name}
                {r.permDenied && <span className="badge">no access</span>}
              </span>
              <span className="col-size">{formatBytes(r.aggSize)}</span>
              <span className="col-count">{r.isDir ? formatCount(r.fileCount) : ''}</span>
              <span className="col-date">{formatDate(r.mtimeMs)}</span>
            </div>
          );
        })}
        {rows.length === 0 && <div className="empty-row muted">This folder is empty.</div>}
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
          onDone={() => {
            setConfirm(null);
            reload();
          }}
        />
      )}
    </div>
  );
}
