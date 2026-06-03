import { useState } from 'react';
import type { DeleteResult } from '../../../../shared/types';

const api = window.purpleTree;

interface Props {
  paths: string[];
  allowPermanent: boolean;
  onClose: () => void;
  /** Called after a successful (full or partial) deletion. */
  onDone: (result: DeleteResult) => void;
}

export default function DeleteConfirm({ paths, allowPermanent, onClose, onDone }: Props): JSX.Element {
  const [busy, setBusy] = useState(false);
  const [permanentArmed, setPermanentArmed] = useState(false);
  const [result, setResult] = useState<DeleteResult | null>(null);

  const run = async (permanent: boolean): Promise<void> => {
    setBusy(true);
    const r = permanent ? await api.permanentDelete(paths) : await api.trash(paths);
    setBusy(false);
    setResult(r);
    onDone(r);
  };

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h2>Delete {paths.length} item{paths.length === 1 ? '' : 's'}?</h2>
        {!result && (
          <>
            <div className="path-list">
              {paths.slice(0, 12).map((p) => (
                <div key={p} className="path-row" title={p}>
                  {p}
                </div>
              ))}
              {paths.length > 12 && <div className="path-row muted">…and {paths.length - 12} more</div>}
            </div>
            <p className="muted">
              Moving to the {navigator.platform.startsWith('Win') ? 'Recycle Bin' : 'Trash'} is
              recoverable.
            </p>
            {allowPermanent && (
              <label className="danger-check">
                <input
                  type="checkbox"
                  checked={permanentArmed}
                  onChange={(e) => setPermanentArmed(e.target.checked)}
                />
                I understand permanent deletion cannot be undone
              </label>
            )}
            <div className="modal-actions">
              <button onClick={onClose} disabled={busy}>
                Cancel
              </button>
              {allowPermanent && (
                <button
                  className="btn-danger"
                  disabled={busy || !permanentArmed}
                  onClick={() => void run(true)}
                >
                  Delete Permanently
                </button>
              )}
              <button className="btn-primary" disabled={busy} onClick={() => void run(false)}>
                {busy ? 'Working…' : 'Move to Trash'}
              </button>
            </div>
          </>
        )}
        {result && (
          <>
            <p>
              Removed <strong>{result.removed.length}</strong>
              {result.failed.length > 0 && (
                <>
                  {' '}
                  · <strong className="err">{result.failed.length} blocked/failed</strong>
                </>
              )}
              .
            </p>
            {result.failed.length > 0 && (
              <div className="path-list">
                {result.failed.slice(0, 10).map((f) => (
                  <div key={f.path} className="path-row err" title={f.reason}>
                    {f.path} — {f.reason}
                  </div>
                ))}
              </div>
            )}
            <div className="modal-actions">
              <button className="btn-primary" onClick={onClose}>
                Done
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
