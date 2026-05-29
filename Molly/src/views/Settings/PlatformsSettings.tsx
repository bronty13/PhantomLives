import { useState } from 'react';
import {
  createPlatform,
  deletePlatform,
  listPlatforms,
  updatePlatform,
  type SocialPlatform,
} from '../../data/socialPlatforms';
import { ColorPicker } from '../../components/ColorPicker';
import { ConfirmButton } from '../../components/ConfirmButton';
import { useAsyncRefresh } from '../../lib/useAsyncRefresh';

const EMPTY = (): Omit<SocialPlatform, 'id'> => ({
  name: '',
  shortCode: '',
  icon: '📣',
  color: '#A16D9C',
  sortOrder: 100,
  archived: false,
  dailyGoal: 1,
});

export function PlatformsSettings() {
  const [rows, setRows] = useState<SocialPlatform[]>([]);
  const [draft, setDraft] = useState<(Omit<SocialPlatform, 'id'> & { id?: number }) | null>(null);
  const [status, setStatus] = useState('');

  const { refresh } = useAsyncRefresh(async (alive) => {
    const list = await listPlatforms();
    if (!alive()) return;
    setRows(list);
  }, []);

  async function save() {
    if (!draft) return;
    try {
      if (draft.id) {
        await updatePlatform({ ...draft, id: draft.id });
        setStatus(`Saved ${draft.name}.`);
      } else {
        await createPlatform(draft);
        setStatus(`Added ${draft.name}.`);
      }
      setDraft(null);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't save: ${String(e)}`);
    }
  }

  async function remove(p: SocialPlatform) {
    try {
      await deletePlatform(p.id);
      setStatus(`Removed ${p.name}.`);
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
            <h3 className="display-font text-xl font-semibold persona-accent">Social platforms</h3>
            <p className="text-sm opacity-70">Reddit, X, Instagram, etc. Used to tag promos.</p>
          </div>
          <button type="button" className="pretty-button" onClick={() => setDraft(EMPTY())}>✨ Add platform</button>
        </div>

        {draft && (
          <div className="mb-3 p-3 rounded-xl bg-white border border-black/5 grid grid-cols-12 gap-3">
            <label className="flex flex-col gap-1 col-span-4">
              <span className="text-xs uppercase tracking-wider opacity-60">Name</span>
              <input className="pretty-input" value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} />
            </label>
            <label className="flex flex-col gap-1 col-span-2">
              <span className="text-xs uppercase tracking-wider opacity-60">Short</span>
              <input className="pretty-input" value={draft.shortCode} onChange={(e) => setDraft({ ...draft, shortCode: e.target.value })} />
            </label>
            <label className="flex flex-col gap-1 col-span-2">
              <span className="text-xs uppercase tracking-wider opacity-60">Icon (emoji)</span>
              <input className="pretty-input text-center" value={draft.icon} onChange={(e) => setDraft({ ...draft, icon: e.target.value })} maxLength={4} />
            </label>
            <label className="flex flex-col gap-1 col-span-2">
              <span className="text-xs uppercase tracking-wider opacity-60">Sort</span>
              <input type="number" className="pretty-input" value={draft.sortOrder} onChange={(e) => setDraft({ ...draft, sortOrder: Number(e.target.value) || 0 })} />
            </label>
            <div className="col-span-12">
              <ColorPicker label="Color" value={draft.color} onChange={(v) => setDraft({ ...draft, color: v })} />
            </div>
            <div className="col-span-12 flex justify-end gap-2">
              <button type="button" className="pretty-button secondary" onClick={() => setDraft(null)}>Cancel</button>
              <button type="button" className="pretty-button" onClick={save} disabled={!draft.name.trim()}>Save</button>
            </div>
          </div>
        )}

        <div className="space-y-2">
          {rows.map((p) => {
            const isEditing = draft && draft.id === p.id;
            return (
              <div key={p.id} className="p-3 rounded-xl border border-black/5" style={{ background: 'rgb(var(--persona-tint))' }}>
                <div className="flex items-center justify-between gap-3">
                  <div className="flex items-center gap-3">
                    <span className="text-lg">{p.icon}</span>
                    <span className="w-3 h-3 rounded-full" style={{ background: p.color, border: '1px solid rgba(0,0,0,0.1)' }} />
                    <span className="font-semibold">{p.name}</span>
                    <span className="font-mono text-xs opacity-60">[{p.shortCode}]</span>
                  </div>
                  <div className="flex gap-2">
                    <button type="button" className="pretty-button secondary" onClick={() => setDraft(isEditing ? null : { ...p })}>
                      {isEditing ? 'Cancel' : 'Edit'}
                    </button>
                    <ConfirmButton label="Delete" confirmLabel="Confirm?" onConfirm={() => remove(p)} />
                  </div>
                </div>
              </div>
            );
          })}
          {rows.length === 0 && !draft && (
            <div className="text-sm opacity-70 italic">Nothing here yet — click <strong>Add platform</strong>.</div>
          )}
        </div>
      </div>
      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}
