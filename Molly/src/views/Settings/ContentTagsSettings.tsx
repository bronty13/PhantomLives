import { useState } from 'react';
import {
  createContentTag,
  deleteContentTag,
  listContentTags,
  updateContentTag,
  type ContentTag,
} from '../../data/contentTags';
import { ColorPicker } from '../../components/ColorPicker';
import { useAsyncRefresh } from '../../lib/useAsyncRefresh';
import { ReadonlyTagPill } from '../Bundles/components/ContentTagPicker';

const CUTE_SWATCHES = [
  '#FCA5A5', // soft coral
  '#FBA17C', // peach
  '#FDA4AF', // rose
  '#F9A8D4', // bubble-gum pink
  '#F472B6', // hot pink
  '#DDD6FE', // lilac
  '#C4B5FD', // lavender
  '#A5B4FC', // periwinkle
  '#BAE6FD', // sky
  '#A7F3D0', // mint
  '#86EFAC', // spring green
  '#FCD34D', // butter
];

export function ContentTagsSettings() {
  const [tags, setTags] = useState<ContentTag[]>([]);
  const [editing, setEditing] = useState<{ id: number | 'new'; name: string; color: string } | null>(null);
  const [status, setStatus] = useState<string>('');
  const [busy, setBusy] = useState(false);

  const { refresh } = useAsyncRefresh(async (alive) => {
    const list = await listContentTags();
    if (!alive()) return;
    setTags(list);
  }, []);

  async function save() {
    if (!editing) return;
    const name = editing.name.trim();
    if (!name) return;
    setBusy(true);
    try {
      if (editing.id === 'new') {
        await createContentTag(name, editing.color);
        setStatus(`Added ${name}.`);
      } else {
        await updateContentTag(editing.id, name, editing.color);
        setStatus(`Saved ${name}.`);
      }
      setEditing(null);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't save: ${String(e)}`);
    } finally {
      setBusy(false);
    }
  }

  async function remove(t: ContentTag) {
    if (!confirm(`Delete tag "${t.name}"? It will be removed from every bundle that uses it.`)) return;
    setBusy(true);
    try {
      await deleteContentTag(t.id);
      setStatus(`Removed ${t.name}.`);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't delete: ${String(e)}`);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-3">
      <div className="pretty-card">
        <div className="flex items-start justify-between mb-2">
          <div>
            <h3 className="display-font text-xl font-semibold persona-accent">🏷️ Content tags</h3>
            <p className="text-sm opacity-70 mt-1">
              Reusable, color-coded tags for every Content / Custom / Fan-Site bundle. Built-ins can be
              renamed and recoloured but not deleted — your custom tags can be deleted any time.
            </p>
          </div>
          <button
            type="button"
            className="pretty-button"
            onClick={() => setEditing({ id: 'new', name: '', color: CUTE_SWATCHES[3] })}
            disabled={busy}
          >
            ＋ New tag
          </button>
        </div>

        {tags.length === 0 && (
          <div className="text-sm opacity-60 italic">No tags yet. Click <strong>＋ New tag</strong> to add one.</div>
        )}

        {tags.length > 0 && (
          <ul className="space-y-1.5">
            {tags.map((t) => (
              <li
                key={t.id}
                className="flex items-center gap-3 px-3 py-2 rounded-xl border"
                style={{
                  borderColor: 'rgb(var(--persona-primary) / 0.25)',
                  background: 'rgb(var(--persona-tint))',
                }}
              >
                <ReadonlyTagPill tag={t} />
                <div className="flex-1 min-w-0">
                  <div className="text-sm font-medium truncate">{t.name}</div>
                  <div className="text-xs opacity-60 font-mono">
                    {t.color}{t.isBuiltin ? ' · built-in' : ''}
                  </div>
                </div>
                <button
                  type="button"
                  className="pretty-button secondary text-xs"
                  onClick={() => setEditing({ id: t.id, name: t.name, color: t.color })}
                  disabled={busy}
                >
                  Edit
                </button>
                {!t.isBuiltin && (
                  <button
                    type="button"
                    className="pretty-button danger text-xs"
                    onClick={() => remove(t)}
                    disabled={busy}
                  >
                    Delete
                  </button>
                )}
              </li>
            ))}
          </ul>
        )}
      </div>

      {editing && (
        <div className="pretty-card space-y-3">
          <h4 className="display-font text-lg font-semibold persona-accent">
            {editing.id === 'new' ? 'New tag' : `Edit: ${editing.name || 'Tag'}`}
          </h4>
          <div className="grid grid-cols-2 gap-3">
            <label className="flex flex-col gap-1">
              <span className="text-xs uppercase tracking-wider opacity-60">Name</span>
              <input
                className="pretty-input"
                autoFocus
                value={editing.name}
                onChange={(e) => setEditing({ ...editing, name: e.target.value })}
                placeholder="e.g. stockings"
              />
            </label>
            <ColorPicker
              label="Color"
              value={editing.color}
              swatches={CUTE_SWATCHES}
              onChange={(v) => setEditing({ ...editing, color: v })}
            />
            <div className="col-span-2 flex items-center gap-2">
              <span className="text-xs uppercase tracking-wider opacity-60">Preview</span>
              <ReadonlyTagPill
                tag={{
                  id: 0,
                  name: editing.name || 'preview',
                  color: editing.color,
                  sortOrder: 0,
                  isBuiltin: false,
                }}
              />
            </div>
          </div>
          <div className="flex justify-end gap-2">
            <button type="button" className="pretty-button secondary" onClick={() => setEditing(null)} disabled={busy}>Cancel</button>
            <button type="button" className="pretty-button" onClick={save} disabled={busy || !editing.name.trim()}>
              {editing.id === 'new' ? '＋ Add tag' : 'Save'}
            </button>
          </div>
        </div>
      )}

      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}
