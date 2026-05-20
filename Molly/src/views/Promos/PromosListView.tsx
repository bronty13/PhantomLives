import { useMemo, useState } from 'react';
import { openUrl } from '@tauri-apps/plugin-opener';
import type { Persona } from '../../state/personas';
import {
  deletePromo,
  listPromos,
  type SocialPromo,
} from '../../data/socialPromos';
import { listPlatforms, type SocialPlatform } from '../../data/socialPlatforms';
import { listPersonas, type Persona as PersonaRow } from '../../data/personas';
import { ConfirmButton } from '../../components/ConfirmButton';
import { PromoEditor } from './PromoEditor';
import { MONTH_NAMES, todayParts } from '../../lib/money';
import { useAsyncRefresh } from '../../lib/useAsyncRefresh';

interface Props {
  active: Persona;
}

function fmtPostedAt(iso: string): string {
  // Render YYYY-MM-DDTHH:MM as "May 20, 2026 · 7:30 PM"
  if (!iso) return '';
  const d = new Date(iso.includes('T') ? iso : iso + 'T00:00:00');
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
}

export function PromosListView({ active }: Props) {
  const t = todayParts();
  const [year, setYear] = useState<number>(t.year);
  const [month, setMonth] = useState<number | 'all'>('all');
  const [platformFilter, setPlatformFilter] = useState<number | 'all'>('all');
  const [search, setSearch] = useState('');

  const [rows, setRows] = useState<SocialPromo[]>([]);
  const [platforms, setPlatforms] = useState<SocialPlatform[]>([]);
  const [personas, setPersonas] = useState<PersonaRow[]>([]);
  const [editing, setEditing] = useState<SocialPromo | 'new' | null>(null);
  const [status, setStatus] = useState<string>('');

  const { loading, refresh } = useAsyncRefresh(async (alive) => {
    const filter: Parameters<typeof listPromos>[0] = {
      personaCode: active.code,
      search,
      year,
    };
    if (month !== 'all') filter.month = month;
    if (platformFilter !== 'all') filter.platformId = platformFilter;
    const [r, p, pe] = await Promise.all([listPromos(filter), listPlatforms(), listPersonas()]);
    if (!alive()) return;
    setRows(r);
    setPlatforms(p);
    setPersonas(pe);
  }, [active.code, year, month, platformFilter]);

  const platformsById = useMemo(() => new Map(platforms.map((p) => [p.id, p])), [platforms]);
  const personaByCode = useMemo(() => new Map(personas.map((p) => [p.code, p])), [personas]);

  async function remove(promo: SocialPromo) {
    try {
      await deletePromo(promo.id);
      setStatus('Deleted.');
      await refresh();
    } catch (e) {
      setStatus(`Couldn't delete: ${String(e)}`);
    }
  }

  async function open(url: string) {
    if (!url) return;
    try { await openUrl(url); } catch (e) { setStatus(String(e)); }
  }

  if (editing) {
    return (
      <PromoEditor
        initial={editing === 'new' ? null : editing}
        active={active}
        platforms={platforms}
        personas={personas}
        onClose={async () => {
          setEditing(null);
          try { await refresh(); } catch (e) { setStatus(String(e)); }
        }}
      />
    );
  }

  const yearOptions: number[] = [];
  for (let y = t.year + 1; y >= 2024; y--) yearOptions.push(y);

  return (
    <div className="p-8 max-w-5xl space-y-4">
      <div className="flex items-end justify-between gap-3">
        <div>
          <h2 className="display-font text-2xl font-bold persona-accent">Promos</h2>
          <p className="opacity-70 text-sm">
            Reddit, X, Instagram, anywhere you post a tease. {active.code !== 'ALL' && <>Filtered to <strong>{active.name}</strong>.</>}
          </p>
        </div>
        <div className="flex items-end gap-2 flex-wrap justify-end">
          <select className="pretty-input" value={String(platformFilter)} onChange={(e) => setPlatformFilter(e.target.value === 'all' ? 'all' : Number(e.target.value))}>
            <option value="all">All platforms</option>
            {platforms.map((p) => <option key={p.id} value={p.id}>{p.icon} {p.name}</option>)}
          </select>
          <select className="pretty-input" value={year} onChange={(e) => setYear(Number(e.target.value))}>
            {yearOptions.map((y) => <option key={y} value={y}>{y}</option>)}
          </select>
          <select className="pretty-input" value={String(month)} onChange={(e) => setMonth(e.target.value === 'all' ? 'all' : Number(e.target.value))}>
            <option value="all">All months</option>
            {MONTH_NAMES.map((m, i) => <option key={m} value={i + 1}>{m}</option>)}
          </select>
          <input
            className="pretty-input w-56"
            placeholder="Search title / handle…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') refresh(); }}
            onBlur={() => refresh()}
          />
          <button type="button" className="pretty-button" onClick={() => setEditing('new')}>✨ New promo</button>
        </div>
      </div>

      <div className="pretty-card">
        {loading && <div className="text-sm opacity-60 italic">Loading promos…</div>}
        {!loading && rows.length === 0 && (
          <div className="text-sm opacity-70 italic">No promos here yet. Click <strong>New promo</strong>.</div>
        )}
        <div className="divide-y divide-black/5">
          {rows.map((p) => {
            const plat = platformsById.get(p.platformId);
            const persona = p.personaCode ? personaByCode.get(p.personaCode) : null;
            return (
              <div key={p.id} className="grid grid-cols-12 gap-2 items-center py-2 text-sm">
                <div className="col-span-2">
                  <span
                    className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-[11px] font-semibold"
                    style={{ background: plat?.color ?? '#A16D9C', color: 'white' }}
                  >
                    <span>{plat?.icon ?? '📣'}</span>
                    <span>{plat?.name ?? '(deleted)'}</span>
                  </span>
                </div>
                <div className="col-span-1">
                  {persona ? (
                    <span className="px-1.5 py-0.5 rounded-md text-[11px] font-semibold" style={{ background: persona.primaryColor, color: persona.textColor }}>{persona.code}</span>
                  ) : <span className="text-[11px] opacity-50">—</span>}
                </div>
                <div className="col-span-4 min-w-0">
                  <div className="font-semibold truncate" title={p.title || p.handle || p.url}>
                    {p.title || p.handle || '(no title)'}
                  </div>
                  {p.handle && <div className="font-mono text-[11px] opacity-60 truncate">{p.handle}</div>}
                </div>
                <div className="col-span-3 text-xs opacity-70">{fmtPostedAt(p.postedAt)}</div>
                <div className="col-span-2 flex justify-end gap-1">
                  {p.url && <button type="button" className="pretty-button secondary" onClick={() => open(p.url)}>Open</button>}
                  <button type="button" className="pretty-button secondary" onClick={() => setEditing(p)}>Edit</button>
                  <ConfirmButton label="✕" confirmLabel="✕?" onConfirm={() => remove(p)} />
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}
