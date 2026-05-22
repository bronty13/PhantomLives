import { useState } from 'react';
import { open } from '@tauri-apps/plugin-dialog';
import { convertFileSrc } from '@tauri-apps/api/core';
import type { BundleFileInfo, FileKind } from '../../../data/bundles';
import { reorderBeforeTarget } from '../../../lib/reorderHelpers';

interface Props {
  files: BundleFileInfo[];
  /** Picker dialog title shown to Sallie. */
  pickTitle: string;
  /** Accepted kinds — Content/Custom use ['video','image']; Audio is the description input, not here. */
  allowedKinds: FileKind[];
  busy: boolean;
  onPick: (srcPaths: string[]) => Promise<void>;
  onRemove: (fileId: number) => Promise<void>;
  onReorder: (orderedIds: number[]) => Promise<void>;
  fieldId?: string;
  /** Filter to a subset (e.g. one FanSite day). If absent, shows all. */
  filterDayId?: number | null;
}

function fmtBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  if (n < 1024 * 1024 * 1024) return `${(n / 1024 / 1024).toFixed(1)} MB`;
  return `${(n / 1024 / 1024 / 1024).toFixed(2)} GB`;
}

function kindIcon(k: FileKind): string {
  if (k === 'video') return '🎬';
  if (k === 'image') return '🖼️';
  return '🎙️';
}

/** Drag-reorderable list of files (videos/images). Sallie clicks "+ Add files"
 * to pick one or many via Tauri dialog; each is saved through Rust which
 * copies the bytes into app data, hashes them, and assigns the next position. */
export function OrderedFileList({
  files, pickTitle, allowedKinds, busy, onPick, onRemove, onReorder, fieldId = 'bundle-files',
  filterDayId,
}: Props) {
  const [draggingId, setDraggingId] = useState<number | null>(null);
  const [dropTargetId, setDropTargetId] = useState<number | null>(null);

  const list = filterDayId !== undefined
    ? files.filter((f) => f.fansiteDayId === filterDayId)
    : files;

  async function pickAndUpload() {
    if (busy) return;
    const filters: { name: string; extensions: string[] }[] = [];
    if (allowedKinds.includes('video')) {
      filters.push({ name: 'Video', extensions: ['mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi'] });
    }
    if (allowedKinds.includes('image')) {
      filters.push({ name: 'Image', extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'tiff'] });
    }
    if (allowedKinds.includes('audio')) {
      filters.push({ name: 'Audio', extensions: ['mp3', 'm4a', 'wav', 'aac', 'flac', 'ogg'] });
    }
    const picked = await open({ multiple: true, directory: false, title: pickTitle, filters });
    if (!picked) return;
    const arr = Array.isArray(picked) ? picked : [picked];
    if (arr.length === 0) return;
    await onPick(arr as string[]);
  }

  return (
    <div className="space-y-2" id={fieldId} tabIndex={-1}>
      <div className="flex items-center justify-between">
        <label className="text-xs font-semibold opacity-75">Files (order matters — drag to reorder)</label>
        <button
          type="button"
          onClick={pickAndUpload}
          disabled={busy}
          className="pretty-button"
        >
          {busy ? 'Saving…' : '＋ Add files'}
        </button>
      </div>

      {list.length === 0 ? (
        <div className="text-xs opacity-60 italic">No files yet — click <strong>＋ Add files</strong> to pick from Finder.</div>
      ) : (
        <ul className="space-y-1.5">
          {list.map((f, idx) => {
            const isDragging = draggingId === f.id;
            const isDropTarget = dropTargetId === f.id && draggingId !== null && draggingId !== f.id;
            const thumbnail = f.kind === 'image'
              ? convertFileSrc(`${f.relpath}`) // best-effort; uses tauri's asset protocol
              : null;
            return (
              <li
                key={f.id}
                draggable
                onDragStart={(e) => {
                  setDraggingId(f.id);
                  e.dataTransfer.effectAllowed = 'move';
                  e.dataTransfer.setData('text/plain', String(f.id));
                }}
                onDragOver={(e) => {
                  if (draggingId !== null && draggingId !== f.id) {
                    e.preventDefault();
                    e.dataTransfer.dropEffect = 'move';
                    if (dropTargetId !== f.id) setDropTargetId(f.id);
                  }
                }}
                onDragLeave={() => { if (dropTargetId === f.id) setDropTargetId(null); }}
                onDrop={async (e) => {
                  e.preventDefault();
                  if (draggingId !== null) {
                    const nextIds = reorderBeforeTarget(list, (it) => it.id, draggingId, f.id).map((it) => it.id);
                    await onReorder(nextIds);
                  }
                  setDraggingId(null);
                  setDropTargetId(null);
                }}
                onDragEnd={() => { setDraggingId(null); setDropTargetId(null); }}
                className="flex items-center gap-3 px-3 py-2 rounded-xl bg-white/70 border transition"
                style={{
                  borderColor: isDropTarget ? 'rgb(var(--persona-accent))' : 'rgb(var(--persona-primary) / 0.25)',
                  outline: isDropTarget ? '2px solid rgb(var(--persona-accent))' : 'none',
                  opacity: isDragging ? 0.5 : 1,
                  cursor: isDragging ? 'grabbing' : 'grab',
                  userSelect: 'none',
                }}
              >
                <span aria-hidden className="opacity-50 font-mono text-xs">⋮⋮</span>
                <span className="font-mono text-xs opacity-70 w-6 text-right">{idx + 1}.</span>
                {thumbnail ? (
                  <img src={thumbnail} alt="" className="w-10 h-10 object-cover rounded" />
                ) : (
                  <span className="w-10 h-10 flex items-center justify-center text-2xl rounded bg-black/5">
                    {kindIcon(f.kind)}
                  </span>
                )}
                <div className="flex-1 min-w-0">
                  <div className="text-sm font-medium truncate" title={f.originalName}>{f.originalName}</div>
                  <div className="text-xs opacity-60 font-mono">
                    {f.kind} · {fmtBytes(f.sizeBytes)} · {f.sha256.slice(0, 8)}…
                  </div>
                </div>
                <button
                  type="button"
                  onClick={(e) => { e.stopPropagation(); onRemove(f.id); }}
                  className="pretty-button danger text-xs"
                  title={`Remove ${f.originalName}`}
                  draggable={false}
                >
                  Remove
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
