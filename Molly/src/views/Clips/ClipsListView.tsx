import { useEffect, useMemo, useState } from 'react';
import type { Persona } from '../../state/personas';
import { listClips, type Clip } from '../../data/clips';
import { listPersonas, type Persona as PersonaRow } from '../../data/personas';
import { ClipDetail } from '../Calendar/ClipDetail';
import { MasterClipperImport } from '../Import/MasterClipperImport';

interface Props {
  active: Persona;
}

type SortKey = 'go_live' | 'title' | 'status' | 'persona';

export function ClipsListView({ active }: Props) {
  const [clips, setClips] = useState<Clip[]>([]);
  const [personas, setPersonas] = useState<PersonaRow[]>([]);
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<string | null>(null);
  const [showImport, setShowImport] = useState(false);
  const [sortKey, setSortKey] = useState<SortKey>('go_live');
  const [status, setStatus] = useState('');

  async function refresh() {
    const [c, p] = await Promise.all([
      listClips({ personaCode: active.code, search, limit: 500 }),
      listPersonas(),
    ]);
    setClips(c);
    setPersonas(p);
  }

  useEffect(() => {
    refresh().catch((e) => setStatus(String(e)));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [active.code]);

  const personaByCode = useMemo(() => new Map(personas.map((p) => [p.code, p])), [personas]);

  const sorted = useMemo(() => {
    const copy = [...clips];
    copy.sort((a, b) => {
      switch (sortKey) {
        case 'title':   return a.title.localeCompare(b.title);
        case 'status':  return a.status.localeCompare(b.status);
        case 'persona': return (a.personaCode ?? '').localeCompare(b.personaCode ?? '');
        case 'go_live':
        default:        return (b.goLiveDate ?? '').localeCompare(a.goLiveDate ?? '');
      }
    });
    return copy;
  }, [clips, sortKey]);

  return (
    <div className="p-8 max-w-6xl space-y-4">
      <div className="flex items-end justify-between gap-3">
        <div>
          <h2 className="display-font text-2xl font-bold persona-accent">Clips</h2>
          <p className="opacity-70 text-sm">
            {active.code === 'ALL' ? 'All clips across personas.' : `${active.name} clips.`} · {clips.length} loaded
          </p>
        </div>
        <div className="flex items-center gap-2">
          <input
            className="pretty-input w-72"
            placeholder="Search ID / title / keywords…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') refresh(); }}
            onBlur={refresh}
          />
          <button type="button" className="pretty-button secondary" onClick={() => setShowImport((v) => !v)}>
            {showImport ? 'Close importer' : '📂 Import CSV'}
          </button>
        </div>
      </div>

      {showImport && (
        <MasterClipperImport
          personas={personas}
          onDone={async () => { await refresh(); }}
        />
      )}

      <div className="pretty-card">
        <div className="flex items-center justify-between mb-2">
          <div className="text-xs uppercase tracking-wider opacity-60">Sort by</div>
          <div className="flex gap-1">
            {(['go_live', 'title', 'status', 'persona'] as const).map((k) => (
              <button
                key={k}
                type="button"
                onClick={() => setSortKey(k)}
                className="px-2.5 py-1 rounded-full text-xs font-semibold"
                style={{
                  background: sortKey === k ? 'rgb(var(--persona-accent))' : 'rgba(255,255,255,0.55)',
                  color: sortKey === k ? 'white' : 'rgb(var(--persona-text))',
                  border: '1px solid rgb(var(--persona-primary) / 0.45)',
                }}
              >
                {k.replace('_', ' ')}
              </button>
            ))}
          </div>
        </div>

        {sorted.length === 0 && (
          <div className="text-sm opacity-70 italic">No clips yet. Click <strong>Import CSV</strong> to bring in a MasterClipper export.</div>
        )}

        <div className="divide-y divide-black/5">
          {sorted.map((c) => {
            const p = c.personaCode ? personaByCode.get(c.personaCode) : null;
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
                <div className="col-span-5 truncate font-semibold">{c.title || '(untitled)'}</div>
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
            await refresh();
          }}
        />
      )}
    </div>
  );
}
