import { useState } from 'react';
import { interests, products, type TaxonomyItem } from '../../data/taxonomy';
import { ColorPicker } from '../../components/ColorPicker';
import { ConfirmButton } from '../../components/ConfirmButton';
import { useAsyncRefresh } from '../../lib/useAsyncRefresh';

interface Props {
  kind: 'products' | 'interests';
}

const TITLE: Record<Props['kind'], { title: string; blurb: string; addLabel: string }> = {
  products: {
    title: 'Products',
    blurb: 'What customers buy from you. Used to tag customers and (in later phases) link sales reports.',
    addLabel: '✨ Add product',
  },
  interests: {
    title: 'Interests',
    blurb: 'What customers like. Used to tag customers and (in later phases) filter content suggestions.',
    addLabel: '✨ Add interest',
  },
};

export function TaxonomySettings({ kind }: Props) {
  const api = kind === 'products' ? products : interests;
  const meta = TITLE[kind];
  const [items, setItems] = useState<TaxonomyItem[]>([]);
  const [draft, setDraft] = useState<{ name: string; color: string; sortOrder: number } | null>(null);
  const [editing, setEditing] = useState<TaxonomyItem | null>(null);
  const [status, setStatus] = useState<string>('');

  const { refresh } = useAsyncRefresh(async (alive) => {
    const items = await api.list();
    if (!alive()) return;
    setItems(items);
  }, [kind]);

  async function saveDraft() {
    if (!draft) return;
    try {
      await api.create(draft.name.trim(), draft.color, draft.sortOrder);
      setStatus(`Added ${draft.name}.`);
      setDraft(null);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't add: ${String(e)}`);
    }
  }

  async function saveEdit() {
    if (!editing) return;
    try {
      await api.update(editing);
      setStatus(`Saved ${editing.name}.`);
      setEditing(null);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't save: ${String(e)}`);
    }
  }

  async function remove(item: TaxonomyItem) {
    try {
      await api.remove(item.id);
      setStatus(`Removed ${item.name}.`);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't delete: ${String(e)}`);
    }
  }

  return (
    <div className="space-y-3">
      <div className="pretty-card">
        <div className="flex items-center justify-between mb-3">
          <div>
            <h3 className="display-font text-xl font-semibold persona-accent">{meta.title}</h3>
            <p className="text-sm opacity-70">{meta.blurb}</p>
          </div>
          <button
            type="button"
            className="pretty-button"
            onClick={() => setDraft({ name: '', color: '#FFB6C1', sortOrder: (items.at(-1)?.sortOrder ?? 0) + 10 })}
          >
            {meta.addLabel}
          </button>
        </div>

        {draft && (
          <div className="mb-3 p-3 rounded-xl bg-white border border-black/5 grid grid-cols-3 gap-3">
            <label className="flex flex-col gap-1">
              <span className="text-xs uppercase tracking-wider opacity-60">Name</span>
              <input className="pretty-input" value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} />
            </label>
            <label className="flex flex-col gap-1">
              <span className="text-xs uppercase tracking-wider opacity-60">Sort order</span>
              <input type="number" className="pretty-input" value={draft.sortOrder} onChange={(e) => setDraft({ ...draft, sortOrder: Number(e.target.value) || 0 })} />
            </label>
            <ColorPicker label="Color" value={draft.color} onChange={(v) => setDraft({ ...draft, color: v })} />
            <div className="col-span-3 flex justify-end gap-2">
              <button type="button" className="pretty-button secondary" onClick={() => setDraft(null)}>Cancel</button>
              <button type="button" className="pretty-button" onClick={saveDraft} disabled={!draft.name.trim()}>Save</button>
            </div>
          </div>
        )}

        <div className="space-y-2">
          {items.map((item) => {
            const isEditing = editing?.id === item.id;
            return (
              <div key={item.id} className="p-3 rounded-xl border border-black/5" style={{ background: 'rgb(var(--persona-tint))' }}>
                <div className="flex items-center justify-between gap-3">
                  <div className="flex items-center gap-3">
                    <span className="w-3 h-3 rounded-full" style={{ background: item.color, border: '1px solid rgba(0,0,0,0.1)' }} />
                    <span className="font-semibold">{item.name}</span>
                    <span className="text-xs opacity-50">sort {item.sortOrder}</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <button type="button" className="pretty-button secondary" onClick={() => setEditing(isEditing ? null : { ...item })}>
                      {isEditing ? 'Cancel' : 'Edit'}
                    </button>
                    <ConfirmButton label="Delete" confirmLabel="Confirm?" onConfirm={() => remove(item)} />
                  </div>
                </div>
                {isEditing && editing && (
                  <div className="mt-3 grid grid-cols-3 gap-3 p-3 rounded-xl bg-white border border-black/5">
                    <label className="flex flex-col gap-1">
                      <span className="text-xs uppercase tracking-wider opacity-60">Name</span>
                      <input className="pretty-input" value={editing.name} onChange={(e) => setEditing({ ...editing, name: e.target.value })} />
                    </label>
                    <label className="flex flex-col gap-1">
                      <span className="text-xs uppercase tracking-wider opacity-60">Sort order</span>
                      <input type="number" className="pretty-input" value={editing.sortOrder} onChange={(e) => setEditing({ ...editing, sortOrder: Number(e.target.value) || 0 })} />
                    </label>
                    <ColorPicker label="Color" value={editing.color} onChange={(v) => setEditing({ ...editing, color: v })} />
                    <div className="col-span-3 flex justify-end gap-2">
                      <button type="button" className="pretty-button secondary" onClick={() => setEditing(null)}>Cancel</button>
                      <button type="button" className="pretty-button" onClick={saveEdit}>Save</button>
                    </div>
                  </div>
                )}
              </div>
            );
          })}
          {items.length === 0 && (
            <div className="text-sm opacity-70 italic">Nothing here yet — click <strong>{meta.addLabel}</strong>.</div>
          )}
        </div>
      </div>
      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}
