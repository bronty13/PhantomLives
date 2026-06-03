import { useEffect, useState } from 'react';
import type { DuplicateSet, DuplicateProgress } from '../../../../shared/types';
import { formatBytes, basename } from '../common/format';
import DeleteConfirm from '../delete/DeleteConfirm';

const api = window.purpleTree;

interface Props {
  scanId: string;
  allowPermanent: boolean;
}

export default function DuplicatesView({ scanId, allowPermanent }: Props): JSX.Element {
  const [status, setStatus] = useState<'idle' | 'running' | 'done'>('idle');
  const [progress, setProgress] = useState<DuplicateProgress | null>(null);
  const [sets, setSets] = useState<DuplicateSet[]>([]);
  const [totalWasted, setTotalWasted] = useState(0);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [confirm, setConfirm] = useState<string[] | null>(null);

  useEffect(() => {
    const offP = api.onDupProgress((e) => {
      if (e.scanId === scanId) setProgress(e.progress);
    });
    const offD = api.onDupDone((e) => {
      if (e.scanId !== scanId) return;
      setStatus('done');
      setSets(e.result.sets);
      setTotalWasted(e.result.totalWasted);
      // Default: keep the first copy in each set, select the rest.
      const sel = new Set<string>();
      for (const s of e.result.sets) s.paths.slice(1).forEach((p) => sel.add(p));
      setSelected(sel);
    });
    return () => {
      offP();
      offD();
    };
  }, [scanId]);

  // Reset when the scan changes.
  useEffect(() => {
    setStatus('idle');
    setSets([]);
    setSelected(new Set());
    setProgress(null);
  }, [scanId]);

  const start = (): void => {
    setStatus('running');
    setSets([]);
    void api.findDuplicates(scanId);
  };

  const toggle = (p: string): void =>
    setSelected((s) => {
      const n = new Set(s);
      n.has(p) ? n.delete(p) : n.add(p);
      return n;
    });

  const selectedReclaim = sets
    .flatMap((s) => s.paths.filter((p) => selected.has(p)).map(() => s.size))
    .reduce((a, b) => a + b, 0);

  return (
    <div className="view dup-view">
      <div className="view-head">
        <h2>Duplicate Files</h2>
        {status === 'idle' && <button className="btn-primary" onClick={start}>Find Duplicates</button>}
        {status === 'running' && (
          <span className="muted">
            {progress
              ? `${progress.phase} — ${progress.filesHashed.toLocaleString()} files, ${formatBytes(
                  progress.bytesHashed
                )} hashed`
              : 'Starting…'}
          </span>
        )}
        {status === 'done' && (
          <span className="muted">
            {sets.length} sets · {formatBytes(totalWasted)} reclaimable · re-run{' '}
            <button onClick={start}>↻</button>
          </span>
        )}
      </div>

      {status === 'done' && sets.length === 0 && (
        <p className="muted">No duplicate files found. 🎉</p>
      )}

      {sets.length > 0 && (
        <>
          <div className="dup-toolbar">
            <span className="muted">
              {[...selected].length} selected · {formatBytes(selectedReclaim)} to reclaim
            </span>
            <div className="spacer" />
            <button
              className="btn-primary"
              disabled={selected.size === 0}
              onClick={() => setConfirm([...selected])}
            >
              Delete Selected…
            </button>
          </div>
          <div className="dup-sets">
            {sets.map((s) => (
              <div key={s.hash} className="dup-set">
                <div className="dup-set-head">
                  {s.paths.length} copies · {formatBytes(s.size)} each ·{' '}
                  <strong>{formatBytes(s.wastedBytes)} wasted</strong>
                </div>
                {s.paths.map((p, i) => (
                  <div key={p} className="dup-path">
                    <input type="checkbox" checked={selected.has(p)} onChange={() => toggle(p)} />
                    <span className="dup-keep">{i === 0 ? '(keep)' : ''}</span>
                    <span className="dup-name" title={p} onDoubleClick={() => void api.reveal(p)}>
                      {basename(p)}
                    </span>
                    <span className="dup-dir" title={p}>
                      {p}
                    </span>
                  </div>
                ))}
              </div>
            ))}
          </div>
        </>
      )}

      {confirm && (
        <DeleteConfirm
          paths={confirm}
          allowPermanent={allowPermanent}
          onClose={() => setConfirm(null)}
          onDone={(r) => {
            // Drop removed paths from the sets/selection.
            const removed = new Set(r.removed);
            setSets((prev) =>
              prev
                .map((s) => ({ ...s, paths: s.paths.filter((p) => !removed.has(p)) }))
                .filter((s) => s.paths.length > 1)
            );
            setSelected((prev) => new Set([...prev].filter((p) => !removed.has(p))));
            setConfirm(null);
          }}
        />
      )}
    </div>
  );
}
