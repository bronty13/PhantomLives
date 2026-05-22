import { useCallback, useEffect, useState } from 'react';
import { open as openDialog, save as saveDialog } from '@tauri-apps/plugin-dialog';
import { downloadDir } from '@tauri-apps/api/path';
import { ConfirmModal } from '../../components/ConfirmModal';
import {
  type NoteAttachment,
  deleteNoteAttachment, downloadNoteAttachment,
  listNoteAttachments, openNoteAttachment, saveNoteAttachment,
} from '../../data/notes';

interface Props {
  noteId: number;
  /** Bumps the parent's notes-list refresh so attachment count stays
   *  in sync after add/delete. */
  onChanged?: () => void;
}

export function AttachmentsBar({ noteId, onChanged }: Props) {
  const [items, setItems] = useState<NoteAttachment[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pendingDelete, setPendingDelete] = useState<NoteAttachment | null>(null);

  const refresh = useCallback(async () => {
    try { setItems(await listNoteAttachments(noteId)); }
    catch (e) { setError(String((e as { message?: string })?.message ?? e)); }
  }, [noteId]);

  useEffect(() => { refresh(); }, [refresh]);

  async function pickAndAttach() {
    setError(null);
    const picked = await openDialog({
      multiple: true,
      title: 'Attach file(s) to this note',
    });
    if (!picked) return;
    const paths = Array.isArray(picked) ? picked : [picked];
    setBusy(true);
    try {
      for (const p of paths) {
        if (typeof p === 'string') await saveNoteAttachment(noteId, p);
      }
      await refresh();
      onChanged?.();
    } catch (e) {
      setError(String((e as { message?: string })?.message ?? e));
    } finally {
      setBusy(false);
    }
  }

  async function doDownload(a: NoteAttachment) {
    setError(null);
    try {
      const defaultDir = await downloadDir();
      const dest = await saveDialog({
        title: 'Save attachment as…',
        defaultPath: `${defaultDir}/${a.originalName}`,
      });
      if (!dest) return;
      await downloadNoteAttachment(a.id, dest);
    } catch (e) {
      setError(String((e as { message?: string })?.message ?? e));
    }
  }

  async function doOpen(a: NoteAttachment) {
    setError(null);
    try { await openNoteAttachment(a.id); }
    catch (e) { setError(String((e as { message?: string })?.message ?? e)); }
  }

  async function confirmDelete() {
    if (!pendingDelete) return;
    const target = pendingDelete;
    setPendingDelete(null);
    setError(null);
    try {
      await deleteNoteAttachment(target.id);
      await refresh();
      onChanged?.();
    } catch (e) {
      setError(String((e as { message?: string })?.message ?? e));
    }
  }

  return (
    <div className="mt-4 mb-4">
      <div className="flex items-center justify-between mb-2">
        <h4 className="text-xs uppercase tracking-wider opacity-60 font-semibold">
          📎 Attachments {items.length > 0 && <span className="opacity-60">({items.length})</span>}
        </h4>
        <button
          type="button"
          onClick={pickAndAttach}
          disabled={busy}
          className="pretty-button secondary text-xs"
        >
          {busy ? 'Attaching…' : '＋ Attach file'}
        </button>
      </div>
      {error && (
        <div className="text-xs text-red-700 bg-red-50 border border-red-200 rounded-xl px-3 py-2 mb-2">{error}</div>
      )}
      {items.length === 0 ? (
        <div className="text-xs italic opacity-50">
          No attachments yet. Drop screenshots, PDFs, anything Sallie wants alongside this note.
        </div>
      ) : (
        <ul className="space-y-1">
          {items.map((a) => (
            <li key={a.id} className="flex items-center gap-2 text-xs bg-white/55 rounded-xl px-3 py-1.5 border border-black/5">
              <span className="text-base" title={a.mime}>{iconFor(a.mime, a.originalName)}</span>
              <span className="flex-1 truncate font-medium">{a.originalName}</span>
              <span className="opacity-50 font-mono text-[10px]">{fmtSize(a.sizeBytes)}</span>
              <button type="button" onClick={() => doOpen(a)} className="pretty-button secondary text-[11px] py-0.5 px-2" title="Open in the default app">
                Open
              </button>
              <button type="button" onClick={() => doDownload(a)} className="pretty-button secondary text-[11px] py-0.5 px-2" title="Save a copy somewhere else">
                Download
              </button>
              <button type="button" onClick={() => setPendingDelete(a)} className="pretty-button danger text-[11px] py-0.5 px-2" title="Remove this attachment">
                Delete
              </button>
            </li>
          ))}
        </ul>
      )}
      {pendingDelete && (
        <ConfirmModal
          title="Delete attachment?"
          message={`Delete "${pendingDelete.originalName}"?\n\nThe file in this note is removed; your original (wherever you attached it from) stays untouched.`}
          confirmLabel="Delete"
          danger
          onCancel={() => setPendingDelete(null)}
          onConfirm={confirmDelete}
        />
      )}
    </div>
  );
}

function fmtSize(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  if (n < 1024 * 1024 * 1024) return `${(n / (1024 * 1024)).toFixed(1)} MB`;
  return `${(n / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

function iconFor(mime: string, name: string): string {
  if (mime.startsWith('image/')) return '🖼️';
  if (mime.startsWith('video/')) return '🎬';
  if (mime.startsWith('audio/')) return '🎵';
  if (mime === 'application/pdf') return '📕';
  if (mime === 'application/zip') return '🗜️';
  if (mime.startsWith('text/')) return '📄';
  if (name.endsWith('.json')) return '🧾';
  return '📎';
}
