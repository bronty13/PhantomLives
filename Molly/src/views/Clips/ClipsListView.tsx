import { useMemo, useState } from 'react';
import type { Persona } from '../../state/personas';
import { listClips, type Clip } from '../../data/clips';
import { listPersonas, type Persona as PersonaRow } from '../../data/personas';
import { listClipTagsInRange, listContentTags, type ContentTag } from '../../data/contentTags';
import { ReadonlyTagPill } from '../Bundles/components/ContentTagPicker';
import { ClipDetail } from '../Calendar/ClipDetail';
import { MasterClipperImport } from '../Import/MasterClipperImport';
import { useAsyncRefresh } from '../../lib/useAsyncRefresh';

interface Props {
  active: Persona;
}

type SortKey = 'go_live' | 'title' | 'status' | 'persona';
type SortDir = 'asc' | 'desc';

export function ClipsListView({ active }: Props) {
  const [clips, setClips] = useState<Clip[]>([]);
  const [personas, setPersonas] = useState<PersonaRow[]>([]);
  const [contentTags, setContentTags] = useState<ContentTag[]>([]);
  const [tagsByClipId, setTagsByClipId] = useState<Map<string, number[]>>(new Map());
  const [search, setSearch] = useState('');
  const [useRegex, setUseRegex] = useState(false);
  const [selected, setSelected] = useState<string | null>(null);
  const [showImport, setShowImport] = useState(false);
  const [sortKey, setSortKey] = useState<SortKey>('go_live');
  // Default direction matches each key's natural reading:
  //   go_live → newest first  (desc)
  //   title / status / persona → alphabetical (asc)
  const [sortDir, setSortDir] = useState<SortDir>('desc');
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [status, setStatus] = useState('');

  // Filtering is client-side now: search + status + regex toggle apply
  // to the in-memory clips array. Persona scoping stays server-side.
  const { loading, refresh } = useAsyncRefresh(async (alive) => {
    // Wide date window (last 5 years → next 5 years) so every clip with a
    // go_live_date ends up in the tag map. Clips with no go_live aren't
    // returned by list_clip_tags_in_range, but they're rare in practice.
    const today = new Date();
    const wideFrom = `${today.getFullYear() - 5}-01-01`;
    const wideTo = `${today.getFullYear() + 5}-12-31`;
    const [c, p, tagDefs, tagRows] = await Promise.all([
      listClips({ personaCode: active.code, limit: 500 }),
      listPersonas(),
      listContentTags(),
      listClipTagsInRange(wideFrom, wideTo, active.code === 'ALL' ? null : active.code),
    ]);
    if (!alive()) return;
    setClips(c);
    setPersonas(p);
    setContentTags(tagDefs);
    const m = new Map<string, number[]>();
    for (const r of tagRows) {
      const arr = m.get(r.clipId) ?? [];
      arr.push(r.tagId);
      m.set(r.clipId, arr);
    }
    setTagsByClipId(m);
  }, [active.code]);

  const tagDefById = useMemo(() => new Map(contentTags.map((t) => [t.id, t])), [contentTags]);

  const personaByCode = useMemo(() => new Map(personas.map((p) => [p.code, p])), [personas]);

  // Distinct non-empty status values for the filter dropdown.
  const statusOptions = useMemo(() => {
    const s = new Set<string>();
    for (const c of clips) if (c.status) s.add(c.status);
    return [...s].sort((a, b) => a.localeCompare(b));
  }, [clips]);

  // Build a matcher for the current search + regex toggle. Pass-through
  // (no filter) on invalid regex; surface the error inline.
  const q = search.trim();
  let matcher: ((s: string) => boolean) | null = null;
  let regexError: string | null = null;
  if (q) {
    if (useRegex) {
      try {
        const re = new RegExp(q, 'i');
        matcher = (s) => re.test(s);
      } catch (e) {
        regexError = String(e).replace(/^SyntaxError:\s*/, '');
      }
    } else {
      const lower = q.toLowerCase();
      matcher = (s) => s.toLowerCase().includes(lower);
    }
  }

  const filtered = useMemo(() => {
    return clips.filter((c) => {
      if (statusFilter && c.status !== statusFilter) return false;
      if (!matcher) return true;
      return matcher(c.id) || matcher(c.title) || matcher(c.status);
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clips, statusFilter, q, useRegex]);

  const sorted = useMemo(() => {
    const copy = [...filtered];
    const mult = sortDir === 'asc' ? 1 : -1;
    copy.sort((a, b) => {
      switch (sortKey) {
        case 'title':   return mult * a.title.localeCompare(b.title);
        case 'status':  return mult * a.status.localeCompare(b.status);
        case 'persona': return mult * (a.personaCode ?? '').localeCompare(b.personaCode ?? '');
        case 'go_live':
        default:        return mult * (a.goLiveDate ?? '').localeCompare(b.goLiveDate ?? '');
      }
    });
    return copy;
  }, [filtered, sortKey, sortDir]);

  return (
    <div className="p-8 max-w-6xl space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h2 className="display-font text-2xl font-bold persona-accent">Clips</h2>
          <p className="opacity-70 text-sm">
            {active.code === 'ALL' ? 'All clips across personas.' : `${active.name} clips.`} · {clips.length} loaded
          </p>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <input
            className="pretty-input w-72"
            placeholder={useRegex ? 'Regex pattern (case-insensitive)…' : 'Search by ID, title, status…'}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <label className="flex items-center gap-1 text-xs select-none whitespace-nowrap">
            <input
              type="checkbox"
              checked={useRegex}
              onChange={(e) => setUseRegex(e.target.checked)}
            />
            regex
          </label>
          {q && !regexError && (
            <div className="text-xs opacity-60 whitespace-nowrap">{sorted.length} of {clips.length}</div>
          )}
          {(q || statusFilter) && (
            <button type="button" className="pretty-button secondary" onClick={() => { setSearch(''); setStatusFilter(''); }}>
              Clear
            </button>
          )}
          <button type="button" className="pretty-button secondary" onClick={() => setShowImport((v) => !v)}>
            {showImport ? 'Close importer' : '📂 Import CSV'}
          </button>
        </div>
      </div>
      {regexError && (
        <div className="text-xs" style={{ color: '#B45309' }}>Invalid regex: {regexError}</div>
      )}

      {showImport && (
        <MasterClipperImport
          personas={personas}
          onDone={async () => { await refresh(); }}
        />
      )}

      <div className="pretty-card">
        <div className="flex items-center justify-between mb-2 flex-wrap gap-2">
          <div className="flex items-center gap-2">
            <span className="text-xs uppercase tracking-wider opacity-60">Sort by</span>
            <div className="flex gap-1">
              {(['go_live', 'title', 'status', 'persona'] as const).map((k) => (
                <button
                  key={k}
                  type="button"
                  onClick={() => {
                    if (sortKey === k) {
                      // Same key clicked twice → flip direction.
                      setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'));
                    } else {
                      setSortKey(k);
                      // Natural default for each key (date desc, text asc).
                      setSortDir(k === 'go_live' ? 'desc' : 'asc');
                    }
                  }}
                  className="px-2.5 py-1 rounded-full text-xs font-semibold"
                  style={{
                    background: sortKey === k ? 'rgb(var(--persona-accent))' : 'rgba(255,255,255,0.55)',
                    color: sortKey === k ? 'white' : 'rgb(var(--persona-text))',
                    border: '1px solid rgb(var(--persona-primary) / 0.45)',
                  }}
                  title={sortKey === k ? 'Click again to flip direction' : `Sort by ${k.replace('_', ' ')}`}
                >
                  {k.replace('_', ' ')}{sortKey === k && (sortDir === 'asc' ? ' ↑' : ' ↓')}
                </button>
              ))}
            </div>
          </div>

          <div className="flex items-center gap-2">
            <span className="text-xs uppercase tracking-wider opacity-60">Status</span>
            <select
              className="pretty-input"
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value)}
              disabled={statusOptions.length === 0}
            >
              <option value="">(all)</option>
              {statusOptions.map((s) => (
                <option key={s} value={s}>{s}</option>
              ))}
            </select>
          </div>
        </div>

        {loading && <div className="text-sm opacity-60 italic">Loading clips…</div>}
        {!loading && clips.length === 0 && (
          <div className="text-sm opacity-70 italic">No clips yet. Click <strong>Import CSV</strong> to bring in a MasterClipper export.</div>
        )}
        {!loading && clips.length > 0 && sorted.length === 0 && (
          <div className="text-sm opacity-70 italic">No clips match the current filter.</div>
        )}

        <div className="divide-y divide-black/5">
          {sorted.map((c) => {
            const p = c.personaCode ? personaByCode.get(c.personaCode) : null;
            const tagIds = tagsByClipId.get(c.id) ?? [];
            return (
              <button
                key={c.id}
                type="button"
                onClick={() => setSelected(c.id)}
                className="w-full text-left grid grid-cols-12 gap-2 items-center py-2 hover:bg-white/60 rounded-lg px-2"
              >
                <div className="col-span-2 font-mono text-xs opacity-70">{c.id}</div>
                <div className="col-span-1">
                  {p && (
                    <span className="px-1.5 py-0.5 rounded-md text-[11px] font-semibold" style={{ background: p.primaryColor, color: p.textColor }}>
                      {p.code}
                    </span>
                  )}
                </div>
                <div className="col-span-5 min-w-0">
                  <div className="truncate font-semibold">{c.title || '(untitled)'}</div>
                  {tagIds.length > 0 && (
                    <div className="flex flex-wrap gap-1 mt-1">
                      {tagIds
                        .map((tid) => tagDefById.get(tid))
                        .filter((t): t is ContentTag => !!t)
                        .map((t) => <ReadonlyTagPill key={t.id} tag={t} />)}
                    </div>
                  )}
                </div>
                <div className="col-span-2 text-xs opacity-70">{c.status}</div>
                <div className="col-span-2 text-xs font-mono opacity-70 text-right">{c.goLiveDate ?? '—'}</div>
              </button>
            );
          })}
        </div>
      </div>

      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}

      {selected && (
        <ClipDetail
          clipId={selected}
          personas={personas}
          onClose={async () => {
            setSelected(null);
            try { await refresh(); } catch (e) { setStatus(String(e)); }
          }}
        />
      )}
    </div>
  );
}
