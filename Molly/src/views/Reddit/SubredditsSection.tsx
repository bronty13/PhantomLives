import { useEffect, useMemo, useState } from 'react';
import type { Persona } from '../../state/personas';
import {
  createSubreddit,
  deleteSubreddit,
  listSubreddits,
  markSubredditPosted,
  setSubredditStarred,
  setSubredditVerified,
  updateSubreddit,
  type Rotation,
  type Subreddit,
  type SubredditInput,
} from '../../data/reddit';
import { listContentTags, type ContentTag } from '../../data/contentTags';
import { todayIso } from '../../data/dailyTasks';

const ROT_LABEL: Record<Rotation, string> = { fresh: 'Ready', soon: 'Tomorrow', wait: 'Resting' };
const ROT_BG: Record<Rotation, string> = { fresh: '#eafbf1', soon: '#fef9e7', wait: '#fcebeb' };
const ROT_FG: Record<Rotation, string> = { fresh: '#1a7a45', soon: '#854F0B', wait: '#A32D2D' };

type SortKey = 'alpha' | 'category' | 'last_posted' | 'rotation';

interface Props {
  active: Persona;
}

export function SubredditsSection({ active }: Props) {
  const [subs, setSubs] = useState<Subreddit[]>([]);
  const [tags, setTags] = useState<ContentTag[]>([]);
  const [search, setSearch] = useState('');
  const [tagFilter, setTagFilter] = useState<number | ''>('');
  const [rotFilter, setRotFilter] = useState<Rotation | ''>('');
  const [sortKey, setSortKey] = useState<SortKey>('alpha');
  const [editing, setEditing] = useState<{ id: number | 'new'; input: SubredditInput } | null>(null);
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState('');

  const personaCode = active.code === 'ALL' ? null : active.code;

  async function refresh() {
    try {
      const [s, t] = await Promise.all([listSubreddits(personaCode), listContentTags()]);
      setSubs(s);
      setTags(t);
    } catch (e) {
      setStatus(String(e));
    }
  }

  useEffect(() => {
    refresh();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [active.code]);

  const tagById = useMemo(() => new Map(tags.map((t) => [t.id, t])), [tags]);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    let rows = subs.filter((s) => {
      if (q && !s.name.toLowerCase().includes(q) && !s.notes.toLowerCase().includes(q)) return false;
      if (tagFilter !== '' && s.tagId !== tagFilter) return false;
      if (rotFilter !== '' && s.rotation !== rotFilter) return false;
      return true;
    });
    const rotOrder: Record<Rotation, number> = { fresh: 0, soon: 1, wait: 2 };
    rows.sort((a, b) => {
      if (a.starred !== b.starred) return (b.starred ? 1 : 0) - (a.starred ? 1 : 0);
      switch (sortKey) {
        case 'alpha': return a.name.localeCompare(b.name);
        case 'category': {
          const ta = a.tagId ? tagById.get(a.tagId)?.name ?? '' : '';
          const tb = b.tagId ? tagById.get(b.tagId)?.name ?? '' : '';
          return ta.localeCompare(tb) || a.name.localeCompare(b.name);
        }
        case 'last_posted': {
          if (!a.lastPostedAt && !b.lastPostedAt) return 0;
          if (!a.lastPostedAt) return 1;
          if (!b.lastPostedAt) return -1;
          return b.lastPostedAt.localeCompare(a.lastPostedAt);
        }
        case 'rotation': return rotOrder[a.rotation] - rotOrder[b.rotation] || a.name.localeCompare(b.name);
      }
    });
    return rows;
  }, [subs, search, tagFilter, rotFilter, sortKey, tagById]);

  function emptyInput(): SubredditInput {
    return {
      personaCode: personaCode,
      name: '',
      tagId: null,
      verified: false,
      karmaReq: '50+',
      rotation: 'fresh',
      notes: '',
    };
  }

  async function save() {
    if (!editing) return;
    if (!editing.input.name.trim()) return;
    setBusy(true);
    try {
      if (editing.id === 'new') {
        await createSubreddit(editing.input);
        setStatus(`Added r/${editing.input.name.trim()}`);
      } else {
        await updateSubreddit(editing.id, editing.input);
        setStatus(`Saved r/${editing.input.name.trim()}`);
      }
      setEditing(null);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't save: ${String(e)}`);
    } finally {
      setBusy(false);
    }
  }

  async function toggleStar(s: Subreddit) {
    try { await setSubredditStarred(s.id, !s.starred); await refresh(); }
    catch (e) { setStatus(String(e)); }
  }
  async function toggleVerified(s: Subreddit) {
    try { await setSubredditVerified(s.id, !s.verified); await refresh(); }
    catch (e) { setStatus(String(e)); }
  }
  async function markPosted(s: Subreddit) {
    try { await markSubredditPosted(s.id, todayIso()); setStatus(`Marked r/${s.name} as posted today.`); await refresh(); }
    catch (e) { setStatus(String(e)); }
  }
  async function changeCategory(s: Subreddit, newTagId: number | null) {
    if ((newTagId ?? null) === (s.tagId ?? null)) return;
    // Optimistic — flip locally so the chip re-colors immediately, then save.
    setSubs((prev) => prev.map((r) => r.id === s.id ? { ...r, tagId: newTagId } : r));
    try {
      await updateSubreddit(s.id, {
        personaCode: s.personaCode,
        name: s.name,
        tagId: newTagId,
        verified: s.verified,
        karmaReq: s.karmaReq,
        rotation: s.rotation,
        notes: s.notes,
      });
      await refresh();
    } catch (e) {
      setStatus(`Couldn't save category: ${String(e)}`);
      await refresh();
    }
  }
  async function remove(s: Subreddit) {
    if (!confirm(`Remove r/${s.name}? Past posts to this sub will stay in the log under the snapshotted name.`)) return;
    try { await deleteSubreddit(s.id); setStatus(`Removed r/${s.name}.`); await refresh(); }
    catch (e) { setStatus(`Couldn't delete: ${String(e)}`); }
  }

  return (
    <div className="space-y-3">
      <div className="pretty-card">
        <div className="flex items-baseline justify-between mb-3 flex-wrap gap-2">
          <div>
            <h3 className="display-font text-xl font-semibold persona-accent">📌 Subreddit tracker</h3>
            <div className="text-xs opacity-60">
              {filtered.length} of {subs.length} subs
              {active.code !== 'ALL' && <> · {active.name}</>}
            </div>
          </div>
          <button
            type="button"
            className="pretty-button"
            onClick={() => setEditing({ id: 'new', input: emptyInput() })}
            disabled={busy}
          >
            ＋ Add sub
          </button>
        </div>

        <div className="flex flex-wrap gap-2 mb-3">
          <input
            className="pretty-input flex-1 min-w-[150px]"
            placeholder="Search name or notes…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <select className="pretty-input" value={tagFilter} onChange={(e) => setTagFilter(e.target.value === '' ? '' : Number(e.target.value))}>
            <option value="">All categories</option>
            {tags.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
          </select>
          <select className="pretty-input" value={rotFilter} onChange={(e) => setRotFilter(e.target.value as Rotation | '')}>
            <option value="">All rotation</option>
            <option value="fresh">Ready</option>
            <option value="soon">Tomorrow</option>
            <option value="wait">Resting</option>
          </select>
          <select className="pretty-input" value={sortKey} onChange={(e) => setSortKey(e.target.value as SortKey)}>
            <option value="alpha">⭐ Starred · A–Z</option>
            <option value="category">⭐ Starred · Category</option>
            <option value="last_posted">⭐ Starred · Last posted</option>
            <option value="rotation">⭐ Starred · Rotation</option>
          </select>
        </div>

        {filtered.length === 0 ? (
          <div className="text-sm opacity-60 italic">No subs match the current filters.</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-[10px] uppercase tracking-wider opacity-60">
                  <th className="text-left py-2 pr-2"></th>
                  <th className="text-left py-2 pr-2">Subreddit</th>
                  <th className="text-left py-2 pr-2">Category</th>
                  <th className="text-center py-2 pr-2">✓?</th>
                  <th className="text-left py-2 pr-2">Karma</th>
                  <th className="text-left py-2 pr-2">Rotation</th>
                  <th className="text-left py-2 pr-2">Last posted</th>
                  <th className="text-left py-2 pr-2">Notes</th>
                  <th className="text-right py-2 pr-2"></th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((s) => {
                  const tag = s.tagId ? tagById.get(s.tagId) : null;
                  return (
                    <tr key={s.id} className="border-t" style={{ borderColor: 'rgb(var(--persona-primary) / 0.15)' }}>
                      <td className="py-2 pr-2">
                        <button
                          type="button"
                          className="text-base"
                          style={{ color: s.starred ? '#F39C12' : 'rgba(0,0,0,0.2)' }}
                          onClick={() => toggleStar(s)}
                          title={s.starred ? 'Unstar' : 'Star'}
                        >
                          ★
                        </button>
                      </td>
                      <td className="py-2 pr-2 font-semibold">r/{s.name}</td>
                      <td className="py-2 pr-2">
                        <CategorySelect
                          value={s.tagId}
                          tags={tags}
                          onChange={(newTagId) => changeCategory(s, newTagId)}
                          tagColor={tag?.color}
                        />
                      </td>
                      <td className="py-2 pr-2 text-center">
                        <input
                          type="checkbox"
                          checked={s.verified}
                          onChange={() => toggleVerified(s)}
                        />
                      </td>
                      <td className="py-2 pr-2 text-xs opacity-70">{s.karmaReq}</td>
                      <td className="py-2 pr-2">
                        <span
                          className="px-2 py-0.5 rounded-full text-[11px] font-semibold"
                          style={{ background: ROT_BG[s.rotation], color: ROT_FG[s.rotation] }}
                        >
                          {ROT_LABEL[s.rotation]}
                        </span>
                      </td>
                      <td className="py-2 pr-2 text-xs opacity-70 font-mono">{s.lastPostedAt ?? '—'}</td>
                      <td className="py-2 pr-2 text-xs opacity-70 max-w-[140px] truncate" title={s.notes}>{s.notes}</td>
                      <td className="py-2 pr-2 text-right whitespace-nowrap">
                        <button
                          type="button"
                          className="text-base opacity-60 hover:opacity-100 px-1"
                          onClick={() => markPosted(s)}
                          title="Mark posted today"
                        >
                          ✓
                        </button>
                        <button
                          type="button"
                          className="text-xs opacity-60 hover:opacity-100 px-1"
                          onClick={() => setEditing({
                            id: s.id,
                            input: {
                              personaCode: s.personaCode,
                              name: s.name, tagId: s.tagId,
                              verified: s.verified, karmaReq: s.karmaReq,
                              rotation: s.rotation, notes: s.notes,
                            },
                          })}
                          title="Edit"
                        >
                          ✎
                        </button>
                        <button
                          type="button"
                          className="text-base opacity-50 hover:opacity-100 hover:text-red-600 px-1"
                          onClick={() => remove(s)}
                          title="Delete"
                        >
                          ✕
                        </button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {editing && (
        <SubEditor
          input={editing.input}
          isNew={editing.id === 'new'}
          tags={tags}
          busy={busy}
          onChange={(input) => setEditing({ ...editing, input })}
          onCancel={() => setEditing(null)}
          onSave={save}
        />
      )}

      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}

function SubEditor({
  input, isNew, tags, busy, onChange, onCancel, onSave,
}: {
  input: SubredditInput;
  isNew: boolean;
  tags: ContentTag[];
  busy: boolean;
  onChange: (input: SubredditInput) => void;
  onCancel: () => void;
  onSave: () => void;
}) {
  return (
    <div className="pretty-card space-y-3">
      <h4 className="display-font text-lg font-semibold persona-accent">
        {isNew ? 'New subreddit' : `Edit r/${input.name}`}
      </h4>
      <div className="grid grid-cols-2 gap-3">
        <label className="flex flex-col gap-1">
          <span className="text-xs uppercase tracking-wider opacity-60">Name (without r/)</span>
          <input
            className="pretty-input"
            value={input.name}
            onChange={(e) => onChange({ ...input, name: e.target.value })}
            autoFocus
          />
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-xs uppercase tracking-wider opacity-60">Category</span>
          <select
            className="pretty-input"
            value={input.tagId ?? ''}
            onChange={(e) => onChange({ ...input, tagId: e.target.value === '' ? null : Number(e.target.value) })}
          >
            <option value="">(none)</option>
            {tags.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
          </select>
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-xs uppercase tracking-wider opacity-60">Karma req</span>
          <input
            className="pretty-input"
            value={input.karmaReq}
            onChange={(e) => onChange({ ...input, karmaReq: e.target.value })}
            placeholder="e.g. 50+"
          />
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-xs uppercase tracking-wider opacity-60">Rotation</span>
          <select
            className="pretty-input"
            value={input.rotation}
            onChange={(e) => onChange({ ...input, rotation: e.target.value as Rotation })}
          >
            <option value="fresh">Ready to post</option>
            <option value="soon">Tomorrow</option>
            <option value="wait">Resting</option>
          </select>
        </label>
        <label className="flex items-center gap-2 text-sm col-span-2">
          <input
            type="checkbox"
            checked={input.verified}
            onChange={(e) => onChange({ ...input, verified: e.target.checked })}
          />
          Account verified for this sub
        </label>
        <label className="flex flex-col gap-1 col-span-2">
          <span className="text-xs uppercase tracking-wider opacity-60">Notes</span>
          <input
            className="pretty-input"
            value={input.notes}
            onChange={(e) => onChange({ ...input, notes: e.target.value })}
          />
        </label>
      </div>
      <div className="flex justify-end gap-2">
        <button type="button" className="pretty-button secondary" onClick={onCancel} disabled={busy}>Cancel</button>
        <button type="button" className="pretty-button" onClick={onSave} disabled={busy || !input.name.trim()}>
          {isNew ? '＋ Add sub' : 'Save'}
        </button>
      </div>
    </div>
  );
}

/** Inline-editable category cell. Renders as a pretty pill that's also a
 *  native <select> — click anywhere on it to pick a category. Color matches
 *  the chosen tag (or muted "—" placeholder when none). Native `<select>`
 *  was chosen over a custom dropdown for accessibility + zero-dependency
 *  keyboard support. */
function CategorySelect({
  value,
  tags,
  onChange,
  tagColor,
}: {
  value: number | null;
  tags: ContentTag[];
  onChange: (next: number | null) => void;
  tagColor?: string;
}) {
  const hasTag = value != null && !!tagColor;
  const bg = hasTag ? tagColor! : 'rgba(0,0,0,0.05)';
  const fg = hasTag ? idealTextColor(tagColor!) : 'rgba(0,0,0,0.5)';
  return (
    <select
      value={value ?? ''}
      onChange={(e) => onChange(e.target.value === '' ? null : Number(e.target.value))}
      onClick={(e) => e.stopPropagation()}
      className="appearance-none px-2 py-0.5 rounded-full text-[11px] font-semibold cursor-pointer focus:outline-none focus:ring-2 focus:ring-offset-1 transition"
      style={{
        background: bg,
        color: fg,
        border: `1px solid ${hasTag ? bg : 'rgba(0,0,0,0.15)'}`,
        // Tiny SVG caret so the chip still hints it's clickable. Color
        // adapts to the foreground so a dark chip gets a white caret.
        backgroundImage: `url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='8' height='5' viewBox='0 0 8 5'><path d='M0 0l4 5 4-5z' fill='${encodeURIComponent(fg)}'/></svg>")`,
        backgroundRepeat: 'no-repeat',
        backgroundPosition: 'right 6px center',
        paddingRight: 18,
      }}
      title="Click to change category"
    >
      <option value="">— no category —</option>
      {tags.map((t) => (
        <option key={t.id} value={t.id}>{t.name}</option>
      ))}
    </select>
  );
}

function idealTextColor(hex: string): string {
  const h = hex.replace('#', '');
  if (h.length !== 6) return '#1F2937';
  const r = parseInt(h.slice(0, 2), 16);
  const g = parseInt(h.slice(2, 4), 16);
  const b = parseInt(h.slice(4, 6), 16);
  const lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  return lum > 160 ? '#1F2937' : '#FFFFFF';
}
