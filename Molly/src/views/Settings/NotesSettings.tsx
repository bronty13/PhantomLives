import { useCallback, useEffect, useState } from 'react';
import { ColorPicker } from '../../components/ColorPicker';
import {
  type NoteTag,
  createNoteTag, deleteNoteTag, listNoteTags, updateNoteTag,
} from '../../data/notes';

/** Settings → 📝 Notes pane. v1 focuses on tag CRUD; per-note style
 *  defaults (font + paper colour) come in commit 7 of the Phase 13
 *  trilogy and add a separate section beneath. */
export function NotesSettings() {
  const [tags, setTags] = useState<NoteTag[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [newName, setNewName] = useState('');
  const [newColor, setNewColor] = useState('#f9a8d4');
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(async () => {
    try { setTags(await listNoteTags()); }
    catch (e) { setError(String((e as { message?: string })?.message ?? e)); }
  }, []);

  useEffect(() => { refresh(); }, [refresh]);

  async function addTag() {
    if (!newName.trim()) return;
    setBusy(true); setError(null);
    try {
      await createNoteTag(newName.trim(), newColor);
      setNewName(''); setNewColor('#f9a8d4');
      await refresh();
    } catch (e) {
      setError(String((e as { message?: string })?.message ?? e));
    } finally { setBusy(false); }
  }

  return (
    <div className="space-y-4">
      <section className="pretty-card space-y-3">
        <h3 className="font-semibold">🏷 Tags</h3>
        <p className="text-xs opacity-70">
          Tags label notes for filtering. The six built-ins (with the little ✨) can be renamed and
          recoloured but not deleted — that keeps your existing tag links from going dangling. Your
          own custom tags can be freely deleted (notes lose the link, the note itself stays).
        </p>
        {error && (
          <div className="text-xs text-red-700 bg-red-50 border border-red-200 rounded-xl px-3 py-2">{error}</div>
        )}
        <div className="space-y-2">
          {tags.map((tag) => (
            <TagRow key={tag.id} tag={tag} onChanged={refresh} onError={setError} />
          ))}
        </div>

        <div className="pt-3 border-t border-black/5 space-y-2">
          <h4 className="text-sm font-semibold">＋ Add a new tag</h4>
          <div className="flex flex-wrap items-end gap-3">
            <label className="flex flex-col gap-1">
              <span className="text-xs uppercase tracking-wider opacity-60">Name</span>
              <input
                type="text"
                value={newName}
                onChange={(e) => setNewName(e.target.value)}
                placeholder="e.g. customs, taxes"
                className="pretty-input w-44"
                onKeyDown={(e) => { if (e.key === 'Enter') addTag(); }}
              />
            </label>
            <ColorPicker label="Color" value={newColor} onChange={setNewColor} />
            <button
              type="button"
              onClick={addTag}
              disabled={busy || !newName.trim()}
              className="pretty-button"
            >
              {busy ? 'Saving…' : 'Add tag'}
            </button>
          </div>
        </div>
      </section>
    </div>
  );
}

function TagRow({ tag, onChanged, onError }: {
  tag: NoteTag; onChanged: () => Promise<void>; onError: (s: string | null) => void;
}) {
  const [name, setName] = useState(tag.name);
  const [color, setColor] = useState(tag.color);
  const [busy, setBusy] = useState(false);

  async function save() {
    if (name.trim() === tag.name && color === tag.color) return;
    setBusy(true); onError(null);
    try { await updateNoteTag(tag.id, name.trim(), color); await onChanged(); }
    catch (e) { onError(String((e as { message?: string })?.message ?? e)); }
    finally { setBusy(false); }
  }
  async function doDelete() {
    if (!window.confirm(`Delete tag "${tag.name}"? Notes will lose the link but stay intact.`)) return;
    onError(null);
    try { await deleteNoteTag(tag.id); await onChanged(); }
    catch (e) { onError(String((e as { message?: string })?.message ?? e)); }
  }

  return (
    <div className="flex items-center gap-3 flex-wrap">
      <span
        className="text-xs font-semibold px-2.5 py-1 rounded-full"
        style={{ background: color, color: pickReadableTextColor(color) }}
      >
        #{tag.name}{tag.isBuiltin ? ' ✨' : ''}
      </span>
      <input
        type="text"
        value={name}
        onChange={(e) => setName(e.target.value)}
        onBlur={save}
        onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur(); }}
        className="pretty-input w-40 text-sm"
      />
      <ColorPicker value={color} onChange={(c) => { setColor(c); }} />
      <button
        type="button"
        onClick={save}
        disabled={busy || (name.trim() === tag.name && color === tag.color)}
        className="pretty-button secondary text-xs"
      >
        Save
      </button>
      {!tag.isBuiltin && (
        <button type="button" onClick={doDelete} className="pretty-button danger text-xs">
          Delete
        </button>
      )}
    </div>
  );
}

/** Cheap WCAG-ish contrast picker: dark text on light bg, white on dark. */
function pickReadableTextColor(hex: string): string {
  const m = hex.match(/^#?([\da-f]{2})([\da-f]{2})([\da-f]{2})$/i);
  if (!m) return 'black';
  const r = parseInt(m[1], 16), g = parseInt(m[2], 16), b = parseInt(m[3], 16);
  const luma = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  return luma > 0.6 ? '#3a1431' : 'white';
}
