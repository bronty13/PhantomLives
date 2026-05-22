import { useEffect, useState } from 'react';
import type { Persona } from '../../state/personas';
import {
  c4sCounts,
  c4sLastImports,
  type C4SCounts,
  type C4SImportRow,
} from '../../data/c4sClips';
import type { PersonaCode } from '../../lib/c4sClassify';
import { StaleBanner } from './StaleBanner';
import { useC4SPrefs } from '../../state/c4sPrefs';

interface Props {
  active: Persona;
  onImport: () => void;
  onOpenGrid: () => void;
  refreshToken?: number;
}

const PERSONA_TINT: Record<string, { bg: string; fg: string; label: string }> = {
  CoC: { bg: '#FFC0CB', fg: '#5B2540', label: 'Curse Of Curves' },
  PoA: { bg: '#C8102E', fg: '#FFFFFF', label: 'Princess of Addiction' },
};

function fmtMoneyCents(c: number | null | undefined): string {
  if (c == null) return '—';
  return `$${(c / 100).toFixed(2)}`;
}

function oldestImportedAt(rows: C4SImportRow[], scope: PersonaCode | 'ALL'): string | null {
  if (rows.length === 0) return null;
  if (scope === 'CoC' || scope === 'PoA') {
    const r = rows.find((x) => x.personaCode === scope);
    return r?.importedAt ?? null;
  }
  // ★All: oldest of the two (worst-case freshness).
  let oldest: string | null = null;
  for (const r of rows) {
    if (oldest == null || r.importedAt < oldest) oldest = r.importedAt;
  }
  return oldest;
}

export function C4SDashboard({ active, onImport, onOpenGrid, refreshToken }: Props) {
  const [counts, setCounts] = useState<C4SCounts | null>(null);
  const [imports, setImports] = useState<C4SImportRow[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [prefs] = useC4SPrefs();

  useEffect(() => {
    let alive = true;
    const scope = active.code === 'CoC' || active.code === 'PoA' ? active.code : 'ALL';
    Promise.all([
      c4sCounts(scope === 'ALL' ? undefined : scope),
      c4sLastImports(),
    ])
      .then(([c, im]) => {
        if (!alive) return;
        setCounts(c);
        setImports(im);
      })
      .catch((e) => setError(String(e)));
    return () => {
      alive = false;
    };
  }, [active.code, refreshToken]);

  if (active.code === 'Sa') {
    return (
      <div className="space-y-4">
        <div className="pretty-card">
          <h2 className="display-font text-2xl font-bold persona-accent">🛍️ C4S Store</h2>
          <p className="opacity-70 text-sm mt-1">
            Sa (Sheer Attraction) doesn't have a Clips4Sale store — switch to <strong>CoC</strong> or <strong>PoA</strong> at the top to see clips.
          </p>
        </div>
      </div>
    );
  }

  const scope: PersonaCode | 'ALL' = active.code === 'CoC' || active.code === 'PoA' ? active.code : 'ALL';
  const importedAt = oldestImportedAt(imports, scope);
  const total = counts?.total ?? 0;
  const statusTotal = (counts?.byStatus ?? []).reduce((a, b) => a + b.count, 0) || 1;

  // Persona overlap callout (★All only): categories that appear in both stores.
  let overlapCount = 0;
  if (scope === 'ALL' && counts) {
    // Cheap approximation — full overlap detection needs both per-persona category sets;
    // skip for now and just show the global top categories below.
    overlapCount = 0;
  }
  void overlapCount;

  return (
    <div className="space-y-4">
      <StaleBanner importedAt={prefs.showStaleBanner ? importedAt : null} onImport={onImport} />

      <div className="flex items-center justify-between">
        <div>
          <h2 className="display-font text-2xl font-bold persona-accent">🛍️ C4S Store</h2>
          <p className="opacity-70 text-sm">
            {scope === 'ALL' ? 'All clips across CoC + PoA stores.' : `${PERSONA_TINT[scope].label} store.`}{' '}
            <button type="button" className="underline opacity-80" onClick={onOpenGrid}>open grid →</button>
          </p>
        </div>
      </div>

      <div className="grid grid-cols-3 gap-3">
        <Stat title="Total clips" value={total} sub={scope === 'ALL' ? 'across both stores' : 'in this store'} />
        <Stat
          title="Lifetime sales"
          value={counts?.salesTotal ?? 0}
          sub={`from ${counts?.clipsWithSales ?? 0} clip${(counts?.clipsWithSales ?? 0) === 1 ? '' : 's'} with data`}
        />
        <Stat
          title="Income (last 6mo)"
          value={fmtMoneyCents(counts?.income6moTotalCents ?? 0)}
          sub="C4S excl. % cut"
        />
      </div>

      {scope === 'ALL' && counts && counts.byPersona.length > 0 && (
        <div className="pretty-card">
          <h3 className="display-font text-lg font-semibold persona-accent mb-3">By store</h3>
          <div className="space-y-2">
            {counts.byPersona.map((row) => {
              const tint = PERSONA_TINT[row.personaCode];
              const pct = (row.count / total) * 100;
              return (
                <div key={row.personaCode} className="flex items-center gap-3">
                  <div className="w-28 flex items-center gap-2">
                    <span
                      className="px-1.5 py-0.5 rounded-md text-[11px] font-semibold"
                      style={{ background: tint?.bg ?? '#ddd', color: tint?.fg ?? '#222' }}
                    >
                      {row.personaCode}
                    </span>
                    <span className="text-xs">{tint?.label}</span>
                  </div>
                  <div className="flex-1 h-3 rounded-full bg-black/5 overflow-hidden">
                    <div
                      className="h-full rounded-full"
                      style={{ width: `${pct}%`, background: tint?.bg ?? '#A16D9C' }}
                    />
                  </div>
                  <div className="w-12 text-right text-sm font-mono">{row.count}</div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      <div className="pretty-card">
        <h3 className="display-font text-lg font-semibold persona-accent mb-3">Clips by status</h3>
        {(counts?.byStatus ?? []).length === 0 && (
          <div className="text-sm opacity-70 italic">No clips imported yet.</div>
        )}
        <div className="space-y-2">
          {(counts?.byStatus ?? []).map((row) => {
            const pct = (row.count / statusTotal) * 100;
            return (
              <div key={row.status} className="flex items-center gap-3">
                <div className="w-40 text-xs opacity-80 truncate" title={row.status}>{row.status || '(blank)'}</div>
                <div className="flex-1 h-3 rounded-full bg-black/5 overflow-hidden">
                  <div className="h-full rounded-full" style={{ width: `${pct}%`, background: 'rgb(var(--persona-accent))' }} />
                </div>
                <div className="w-12 text-right text-sm font-mono">{row.count}</div>
              </div>
            );
          })}
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div className="pretty-card">
          <h3 className="display-font text-lg font-semibold persona-accent mb-2">Top 10 categories</h3>
          {(counts?.topCategories ?? []).length === 0 ? (
            <div className="text-sm opacity-70 italic">Nothing to show yet.</div>
          ) : (
            <ol className="space-y-1 text-sm">
              {counts!.topCategories.map((c) => (
                <li key={c.name} className="flex items-center justify-between gap-2">
                  <span className="truncate" title={c.name}>{c.name}</span>
                  <span className="font-mono text-xs opacity-70">{c.count}</span>
                </li>
              ))}
            </ol>
          )}
        </div>
        <div className="pretty-card">
          <h3 className="display-font text-lg font-semibold persona-accent mb-2">Top 10 keywords</h3>
          {(counts?.topKeywords ?? []).length === 0 ? (
            <div className="text-sm opacity-70 italic">Nothing to show yet.</div>
          ) : (
            <div className="flex flex-wrap gap-1.5">
              {counts!.topKeywords.map((k) => (
                <span key={k.name} className="px-2 py-0.5 rounded-full text-[11px] bg-black/[0.06]" title={`${k.count}×`}>
                  {k.name} <span className="opacity-50 font-mono">·{k.count}</span>
                </span>
              ))}
            </div>
          )}
        </div>
      </div>

      <div className="pretty-card">
        <h3 className="display-font text-lg font-semibold persona-accent mb-2">Pricing</h3>
        {counts == null || counts.priceMinCents == null ? (
          <div className="text-sm opacity-70 italic">No pricing data yet.</div>
        ) : (
          <div className="grid grid-cols-3 gap-3 text-center">
            <PriceCard label="Min" value={fmtMoneyCents(counts.priceMinCents)} />
            <PriceCard label="Mean" value={fmtMoneyCents(counts.priceMeanCents)} />
            <PriceCard label="Max" value={fmtMoneyCents(counts.priceMaxCents)} />
          </div>
        )}
      </div>

      {error && <div className="pretty-card text-sm text-red-700"><strong>Error:</strong> {error}</div>}
    </div>
  );
}

function Stat({ title, value, sub }: { title: string; value: number | string; sub: string }) {
  return (
    <div className="pretty-card">
      <div className="text-xs uppercase tracking-wider opacity-60">{title}</div>
      <div className="display-font text-3xl font-bold persona-accent mt-1">{value}</div>
      <div className="text-xs opacity-70 mt-1">{sub}</div>
    </div>
  );
}

function PriceCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="p-3 rounded-2xl border border-black/5 bg-black/[0.02]">
      <div className="text-[11px] uppercase tracking-wider opacity-60">{label}</div>
      <div className="display-font text-xl font-bold persona-accent mt-1">{value}</div>
    </div>
  );
}
