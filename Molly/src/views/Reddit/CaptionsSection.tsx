import { useEffect, useMemo, useState } from 'react';
import type { Persona } from '../../state/personas';
import {
  createCaption,
  deleteCaption,
  listCaptions,
  updateCaption,
  type Caption,
  type CaptionInput,
} from '../../data/reddit';
import { listContentTags, type ContentTag } from '../../data/contentTags';

interface Props {
  active: Persona;
}

export function CaptionsSection({ active }: Props) {
  const [caps, setCaps] = useState<Caption[]>([]);
  const [tags, setTags] = useState<ContentTag[]>([]);
  const [draftText, setDraftText] = useState('');
  const [draftTagId, setDraftTagId] = useState<number | ''>('');
  const [editing, setEditing] = useState<{ id: number; text: string; tagId: number | '' } | null>(null);
  const [copiedId, setCopiedId] = useState<number | null>(null);
  const [filterTag, setFilterTag] = useState<number | ''>('');
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState('');

  const personaCode = active.code === 'ALL' ? null : active.code;

  async function refresh() {
    try {
      const [c, t] = await Promise.all([listCaptions(personaCode), listContentTags()]);
      setCaps(c);
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
    return caps.filter((c) => {
      if (filterTag !== '' && c.tagId !== filterTag) return false;
      if (q && !c.text.toLowerCase().includes(q)) return false;
      return true;
    });
  }, [caps, filterTag, search]);

  async function add() {
    const text = draftText.trim();
    if (!text) return;
    try {
      const input: CaptionInput = {
        personaCode,
        text,
        tagId: draftTagId === '' ? null : draftTagId,
      };
      await createCaption(input);
      setDraftText('');
      setDraftTagId('');
      await refresh();
    } catch (e) {
      setStatus(String(e));
    }
  }

  async function saveEdit() {
    if (!editing) return;
    try {
      await updateCaption(editing.id, {
        personaCode,
        text: editing.text,
        tagId: editing.tagId === '' ? null : editing.tagId,
      });
      setEditing(null);
      await refresh();
    } catch (e) {
      setStatus(String(e));
    }
  }

  async function remove(c: Caption) {
    if (!confirm('Delete this caption?')) return;
    try { await deleteCaption(c.id); await refresh(); }
    catch (e) { setStatus(String(e)); }
  }

  async function copy(c: Caption) {
    try {
      await navigator.clipboard.writeText(c.text);
      setCopiedId(c.id);
      setTimeout(() => setCopiedId((prev) => prev === c.id ? null : prev), 1500);
    } catch (e) {
      setStatus(`Couldn't copy: ${String(e)}`);
    }
  }

  return (
    <div className="space-y-3">
      <div className="pretty-card">
        <h3 className="display-font text-xl font-semibold persona-accent mb-1">💬 Captions</h3>
        <p className="text-xs opacity-60 mb-3">
          A casual stash. Type a caption, hit + Save, then click any one to copy. Optional tag for filtering.
        </p>
        <div className="flex gap-2 flex-wrap mb-2">
          <textarea
            className="pretty-input flex-1 min-w-[200px]"
            rows={2}
            placeholder="Write a caption…"
            value={draftText}
            onChange={(e) => setDraftText(e.target.value)}
          />
          <div className="flex flex-col gap-2 min-w-[140px]">
            <select
              className="pretty-input"
              value={draftTagId}
              onChange={(e) => setDraftTagId(e.target.value === '' ? '' : Number(e.target.value))}
            >
              <option value="">No tag</option>
              {tags.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
            </select>
            <button type="button" className="pretty-button" onClick={add} disabled={!draftText.trim()}>
              ＋ Save
            </button>
          </div>
        </div>
      </div>

      <div className="flex gap-2 flex-wrap items-center">
        <input
          className="pretty-input flex-1 min-w-[150px]"
          placeholder="Search captions…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <select
          className="pretty-input"
          value={filterTag}
          onChange={(e) => setFilterTag(e.target.value === '' ? '' : Number(e.target.value))}
        >
          <option value="">All tags</option>
          {tags.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
        </select>
        <span className="text-xs opacity-60">{filtered.length} of {caps.length}</span>
      </div>

      {filtered.length === 0 ? (
        <div className="pretty-card text-sm opacity-60 italic">No captions yet — write one above.</div>
      ) : (
        <ul className="grid grid-cols-1 md:grid-cols-2 gap-2">
          {filtered.map((c) => {
            const tag = c.tagId ? tagById.get(c.tagId) : null;
            const isEdit = editing?.id === c.id;
            return (
              <li key={c.id} className="pretty-card flex flex-col gap-2">
                <div className="flex items-center gap-2">
                  {tag && (
                    <span
                      className="px-2 py-0.5 rounded-full text-[10px] font-semibold"
                      style={{ background: tag.color, color: idealTextColor(tag.color) }}
                    >
                      {tag.name}
                    </span>
                  )}
                  <span className="text-[10px] opacity-50 ml-auto">
                    {new Date(c.updatedAt + 'Z').toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}
                  </span>
                </div>
                {isEdit ? (
                  <>
                    <textarea
                      className="pretty-input w-full"
                      rows={3}
                      value={editing.text}
                      onChange={(e) => setEditing({ ...editing, text: e.target.value })}
                    />
                    <div className="flex gap-2">
                      <select
                        className="pretty-input flex-1"
                        value={editing.tagId}
                        onChange={(e) => setEditing({ ...editing, tagId: e.target.value === '' ? '' : Number(e.target.value) })}
                      >
                        <option value="">No tag</option>
                        {tags.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
                      </select>
                      <button type="button" className="pretty-button secondary text-xs" onClick={() => setEditing(null)}>Cancel</button>
                      <button type="button" className="pretty-button text-xs" onClick={saveEdit}>Save</button>
                    </div>
                  </>
                ) : (
                  <>
                    <div className="text-sm leading-relaxed">{c.text}</div>
                    <div className="flex gap-2 justify-end">
                      <button
                        type="button"
                        className="pretty-button secondary text-xs"
                        onClick={() => setEditing({ id: c.id, text: c.text, tagId: c.tagId ?? '' })}
                      >
                        Edit
                      </button>
                      <button
                        type="button"
                        className="pretty-button text-xs"
                        onClick={() => copy(c)}
                        style={copiedId === c.id ? { background: '#2ecc71' } : undefined}
                      >
                        {copiedId === c.id ? '✓ Copied!' : 'Copy'}
                      </button>
                      <button
                        type="button"
                        className="pretty-button danger text-xs"
                        onClick={() => remove(c)}
                      >
                        Delete
                      </button>
                    </div>
                  </>
                )}
              </li>
            );
          })}
        </ul>
      )}

      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
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
