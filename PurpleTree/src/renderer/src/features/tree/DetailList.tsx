import { useEffect, useMemo, useState } from 'react';
import type { NodeRow, SortKey, SortSpec } from '../../../../shared/types';
import { formatBytes, formatDate, formatCount } from '../common/format';
import DeleteConfirm from '../delete/DeleteConfirm';

const api = window.purpleTree;
const PAGE = 1000;

interface Props {
  scanId: string;
  focusId: number;
  allowPermanent: boolean;
  onDrill: (id: number) => void;
}

export default function DetailList({ scanId, focusId, allowPermanent, onDrill }: Props): JSX.Element {
  const [rows, setRows] = useState<NodeRow[]>([]);
  const [sort, setSort] = useState<SortSpec>({ key: 'size', dir: 'desc' });
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
        <button className="col-name" onClick={() => toggleSort('name')}>
          Name{arrow('name')}
        </button>
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
          const pct = rows.length && rows[0].aggSize > 0 ? (r.aggSize / rows[0].aggSize) * 100 : 0;
          return (
            <div
              key={r.id}
              className={`detail-row${selected.has(r.id) ? ' selected' : ''}`}
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
              <span className="col-name" title={r.path}>
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
