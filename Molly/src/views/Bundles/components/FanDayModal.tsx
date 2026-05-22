import { useEffect, useState } from 'react';
import {
  type Bundle,
  type BundleFanDay,
  type BundleFileInfo,
  createFanDay,
  deleteBundleFile,
  deleteFanDay,
  reorderBundleFiles,
  saveBundleFile,
  updateFanDayMessage,
} from '../../../data/bundles';
import { OrderedFileList } from './OrderedFileList';

interface Props {
  bundleUid: string;
  dayOfMonth: number;
  bundle: Bundle;
  onClose: () => void;
  onChanged: () => Promise<void>;   // refresh parent (recompute completion %, etc)
}

/** Per-day editor for a FanSite bundle. Opens as a slide-in panel from
 * the right; on first save creates the bundle_fan_days row if needed. */
export function FanDayModal({ bundleUid, dayOfMonth, bundle, onClose, onChanged }: Props) {
  const existing: BundleFanDay | undefined = bundle.fanDays.find((d) => d.dayOfMonth === dayOfMonth);
  const [fanDayId, setFanDayId] = useState<number | null>(existing?.id ?? null);
  const [message, setMessage] = useState<string>(existing?.message ?? '');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // If the row doesn't exist yet, create it on mount so file uploads
  // have an fansite_day_id to attach to.
  useEffect(() => {
    if (fanDayId != null) return;
    let alive = true;
    createFanDay(bundleUid, dayOfMonth)
      .then(async (row) => {
        if (!alive) return;
        setFanDayId(row.id);
        await onChanged();
      })
      .catch((e) => alive && setError(String(e)));
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [bundleUid, dayOfMonth]);

  // Re-derive files belonging to this day from the parent bundle.
  const files: BundleFileInfo[] = bundle.files.filter((f) => f.fansiteDayId === fanDayId);

  async function withBusy<T>(fn: () => Promise<T>): Promise<T | null> {
    setBusy(true); setError(null);
    try { return await fn(); }
    catch (e) { setError(String(e)); return null; }
    finally { setBusy(false); }
  }

  async function commitMessage() {
    if (fanDayId == null) return;
    if (message === (existing?.message ?? '')) return;
    await withBusy(async () => {
      await updateFanDayMessage(fanDayId, message);
      await onChanged();
    });
  }

  async function onPickFiles(srcPaths: string[]) {
    if (fanDayId == null) return;
    await withBusy(async () => {
      for (const src of srcPaths) {
        const kind: 'video' | 'image' = guessKind(src);
        await saveBundleFile(bundleUid, src, kind, fanDayId);
      }
      await onChanged();
    });
  }
  async function onRemoveFile(id: number) {
    await withBusy(async () => { await deleteBundleFile(id); await onChanged(); });
  }
  async function onReorder(orderedIds: number[]) {
    await withBusy(async () => { await reorderBundleFiles(bundleUid, orderedIds); await onChanged(); });
  }
  async function onDeleteDay() {
    if (fanDayId == null) { onClose(); return; }
    if (!confirm(`Delete everything for day ${dayOfMonth}? Files for this day are removed too.`)) return;
    await withBusy(async () => { await deleteFanDay(fanDayId); await onChanged(); });
    onClose();
  }

  return (
    <div className="fixed inset-0 z-40 bg-black/40 backdrop-blur-sm flex items-stretch justify-end">
      <div className="bg-white w-full max-w-xl h-full overflow-y-auto shadow-2xl flex flex-col">
        <header className="p-6 border-b border-black/5 flex items-center justify-between sticky top-0 bg-white z-10">
          <div>
            <h2 className="display-font text-xl font-semibold">Day {String(dayOfMonth).padStart(2, '0')}</h2>
            <p className="text-xs opacity-60">Short message + files for this day's post.</p>
          </div>
          <button type="button" onClick={onClose} className="pretty-button secondary">Done</button>
        </header>

        <div className="p-6 space-y-5 flex-1">
          {error && (
            <div className="text-sm text-red-700 bg-red-50 border border-red-200 rounded-xl px-3 py-2">{error}</div>
          )}
          <div className="space-y-1">
            <label htmlFor={`bundle-fan-day-${dayOfMonth}-message`} className="text-xs font-semibold opacity-75">Short message</label>
            <textarea
              id={`bundle-fan-day-${dayOfMonth}-message`}
              className="pretty-input w-full"
              rows={3}
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              onBlur={commitMessage}
              placeholder="Caption / tease for the post…"
              disabled={busy}
            />
          </div>

          <OrderedFileList
            files={files}
            pickTitle={`Pick files for day ${dayOfMonth}`}
            allowedKinds={['video', 'image']}
            busy={busy}
            onPick={onPickFiles}
            onRemove={onRemoveFile}
            onReorder={onReorder}
          />

          <div className="pt-3 border-t border-black/5">
            <button type="button" onClick={onDeleteDay} className="pretty-button danger text-xs" disabled={busy}>
              🗑 Delete day {dayOfMonth} (files + message)
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function guessKind(path: string): 'video' | 'image' {
  const ext = (path.split('.').pop() ?? '').toLowerCase();
  return ['mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi'].includes(ext) ? 'video' : 'image';
}
