import { useState } from 'react';
import { interests, kinks, products, type TaxonomyItem } from '../../data/taxonomy';
import { ColorPicker } from '../../components/ColorPicker';
import { ConfirmButton } from '../../components/ConfirmButton';
import { useAsyncRefresh } from '../../lib/useAsyncRefresh';

interface Props {
  kind: 'products' | 'interests' | 'kinks';
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
  kinks: {
    title: 'Kinks',
    blurb: 'What customers are into. Order matters — sort_order controls how chips appear in the customer editor.',
    addLabel: '✨ Add kink',
  },
};

export function TaxonomySettings({ kind }: Props) {
  const api = kind === 'products' ? products : kind === 'interests' ? interests : kinks;
  const meta = TITLE[kind];
  const [items, setItems] = useState<TaxonomyItem[]>([]);
  const [draft, setDraft] = useState<{ name: string; color: string; sortOrder: number } | null>(null);
  const [editing, setEditing] = useState<TaxonomyItem | null>(null);
  const [status, setStatus] = useState<string>('');
  const [filter, setFilter] = useState<string>('');

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

  const q = filter.trim().toLowerCase();
  const filteredItems = q
    ? items.filter((i) =>
        i.name.toLowerCase().includes(q) ||
        (i.description ?? '').toLowerCase().includes(q)
      )
    : items;

  return (
    <div className="space-y-3">
      <div className="pretty-card">
        <div className="flex items-center justify-between mb-3 gap-3">
          <div className="min-w-0">
            <h3 className="display-font text-xl font-semibold persona-accent">{meta.title}</h3>
            <p className="text-sm opacity-70">{meta.blurb}</p>
          </div>
          <button
            type="button"
            className="pretty-button shrink-0"
            onClick={() => setDraft({ name: '', color: '#FFB6C1', sortOrder: (items.at(-1)?.sortOrder ?? 0) + 10 })}
          >
            {meta.addLabel}
          </button>
        </div>

        <div className="mb-3 flex items-center gap-2">
          <input
            type="text"
            className="pretty-input flex-1"
            placeholder={`Filter ${meta.title.toLowerCase()}…`}
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
          />
          <div className="text-xs opacity-60 whitespace-nowrap">
            {q ? `${filteredItems.length} of ${items.length}` : `${items.length} total`}
          </div>
          {q && (
            <button
              type="button"
              className="pretty-button secondary"
              onClick={() => setFilter('')}
            >
              Clear
            </button>
          )}
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
          {filteredItems.map((item) => {
            const isEditing = editing?.id === item.id;
            return (
              <div key={item.id} className="p-3 rounded-xl border border-black/5" style={{ background: 'rgb(var(--persona-tint))' }}>
                <div className="flex items-center justify-between gap-3">
                  <div className="flex items-center gap-3 min-w-0 flex-1">
                    <span className="w-3 h-3 rounded-full shrink-0" style={{ background: item.color, border: '1px solid rgba(0,0,0,0.1)' }} />
                    <div className="min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="font-semibold truncate">{item.name}</span>
                        <span className="text-xs opacity-50 shrink-0">sort {item.sortOrder}</span>
                        {kind === 'products' && (item.priceCents ?? 0) > 0 && (
                          <span className="text-xs font-medium shrink-0" style={{ color: 'rgb(var(--persona-accent))' }}>
                            · ${((item.priceCents ?? 0) / 100).toFixed(2)} / {item.unit || 'item'}
                          </span>
                        )}
                      </div>
                      {item.description && (
                        <div className="text-xs opacity-70 truncate">{item.description}</div>
                      )}
                    </div>
                  </div>
                  <div className="flex items-center gap-2 shrink-0">
                    <button type="button" className="pretty-button secondary" onClick={() => setEditing(isEditing ? null : { ...item })}>
                      {isEditing ? 'Cancel' : 'Edit'}
                    </button>
                    <ConfirmButton label="Delete" confirmLabel="Confirm?" onConfirm={() => remove(item)} />
                  </div>
                </div>
                {isEditing && editing && (
                  <div
                    key={editing.id}
                    className="mt-3 grid grid-cols-3 gap-3 p-3 rounded-xl bg-white border border-black/5"
                  >
                    <label className="flex flex-col gap-1">
                      <span className="text-xs uppercase tracking-wider opacity-60">Name</span>
                      <input className="pretty-input" value={editing.name} onChange={(e) => setEditing({ ...editing, name: e.target.value })} />
                    </label>
                    <label className="flex flex-col gap-1">
                      <span className="text-xs uppercase tracking-wider opacity-60">Sort order</span>
                      <input type="number" className="pretty-input" value={editing.sortOrder} onChange={(e) => setEditing({ ...editing, sortOrder: Number(e.target.value) || 0 })} />
                    </label>
                    <ColorPicker label="Color" value={editing.color} onChange={(v) => setEditing({ ...editing, color: v })} />
                    {kind === 'products' && (
                      <>
                        <label className="flex flex-col gap-1">
                          <span className="text-xs uppercase tracking-wider opacity-60">Price (USD)</span>
                          {/*
                            Uncontrolled (defaultValue, not value) so React doesn't reformat
                            the buffer to .toFixed(2) on every keystroke — that's what made
                            "$20.03" impossible to type before. The `key={editing.id}` on the
                            parent grid ensures defaults pick up the right row when the user
                            switches between rows. onBlur normalizes whatever was typed back
                            to 2-decimal form.
                          */}
                          <input
                            type="text"
                            inputMode="decimal"
                            className="pretty-input"
                            placeholder="0.00"
                            defaultValue={((editing.priceCents ?? 0) / 100).toFixed(2)}
                            onChange={(e) => {
                              // Strip everything except digits + one decimal point,
                              // tolerate partial typing like "20." or ".03".
                              const cleaned = e.target.value.replace(/[^\d.]/g, '');
                              const dollars = parseFloat(cleaned);
                              const cents = isFinite(dollars) ? Math.round(dollars * 100) : 0;
                              setEditing({ ...editing, priceCents: Math.max(0, cents) });
                            }}
                            onBlur={(e) => {
                              const dollars = parseFloat(e.target.value.replace(/[^\d.]/g, '')) || 0;
                              e.target.value = dollars.toFixed(2);
                            }}
                          />
                        </label>
                        <label className="flex flex-col gap-1">
                          <span className="text-xs uppercase tracking-wider opacity-60">Unit</span>
                          <input
                            className="pretty-input"
                            list="product-units"
                            placeholder="minute, hour, session, item…"
                            value={editing.unit ?? ''}
                            onChange={(e) => setEditing({ ...editing, unit: e.target.value })}
                          />
                          <datalist id="product-units">
                            <option value="minute" />
                            <option value="hour" />
                            <option value="session" />
                            <option value="item" />
                            <option value="set" />
                          </datalist>
                        </label>
                        <div /> {/* fill grid */}
                      </>
                    )}
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
          {items.length > 0 && filteredItems.length === 0 && (
            <div className="text-sm opacity-70 italic">No matches for "{filter}".</div>
          )}
        </div>
      </div>
      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}
