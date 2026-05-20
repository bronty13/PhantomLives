import { useEffect, useState } from 'react';
import type { Persona } from '../../state/personas';
import { clipCounts, countByPersona, detectReuse, recentImports, type ClipCounts, type ClipImportLog, type PersonaCount, type ReuseGroup } from '../../data/clips';
import { listPersonas, type Persona as PersonaRow } from '../../data/personas';
import { listOverdue, listToday, describeDueDate, type Occurrence } from '../../data/occurrences';
import { SayingsBanner } from '../../components/SayingsBanner';

interface Props {
  active: Persona;
  onGoTo: (view: 'reminders') => void;
}

export function HomeDashboard({ active, onGoTo }: Props) {
  const [counts, setCounts] = useState<ClipCounts | null>(null);
  const [byPersona, setByPersona] = useState<PersonaCount[]>([]);
  const [reuse, setReuse] = useState<ReuseGroup[]>([]);
  const [imports, setImports] = useState<ClipImportLog[]>([]);
  const [personas, setPersonas] = useState<PersonaRow[]>([]);
  const [today, setToday] = useState<Occurrence[]>([]);
  const [overdue, setOverdue] = useState<Occurrence[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    const opts = active.code === 'ALL' ? undefined : { personaCode: active.code };
    Promise.all([
      clipCounts(active.code === 'ALL' ? undefined : active.code),
      countByPersona(),
      detectReuse(),
      recentImports(5),
      listPersonas(),
      listToday(opts),
      listOverdue(opts),
    ])
      .then(([c, bp, r, im, p, t, o]) => {
        if (!alive) return;
        setCounts(c);
        setByPersona(bp);
        setReuse(r);
        setImports(im);
        setPersonas(p);
        setToday(t);
        setOverdue(o);
      })
      .catch((e) => setError(String(e)));
    return () => {
      alive = false;
    };
  }, [active.code]);

  const personaByCode = new Map(personas.map((p) => [p.code, p]));
  const totalForBars = byPersona.reduce((acc, x) => acc + x.count, 0) || 1;

  return (
    <div className="p-8 space-y-4 max-w-5xl">
      <SayingsBanner variant="hero" rerollKey={active.code} />

      <div className="pretty-card">
        <div className="text-xs uppercase tracking-wider opacity-60">welcome back</div>
        <h2 className="display-font text-3xl font-bold persona-accent mt-1">Hi, I'm Molly 💕</h2>
        <p className="opacity-80 mt-2">
          {active.code === 'ALL'
            ? 'Cross-persona dashboard. Pick a persona to filter.'
            : `Dashboard filtered to ${active.name}. Pick ★ All to see everything.`}
        </p>
      </div>

      {(overdue.length > 0 || today.length > 0) && (
        <div className="pretty-card">
          <div className="flex items-center justify-between mb-2">
            <h3 className="display-font text-lg font-semibold persona-accent">
              {overdue.length > 0 ? `⏰ ${overdue.length} overdue, ${today.length} today` : `💖 ${today.length} due today`}
            </h3>
            <button type="button" className="pretty-button secondary" onClick={() => onGoTo('reminders')}>Open Reminders →</button>
          </div>
          <div className="space-y-1.5">
            {[...overdue.slice(0, 4), ...today.slice(0, Math.max(0, 4 - Math.min(overdue.length, 4)))].map((o) => {
              const p = o.personaCode ? personaByCode.get(o.personaCode) : null;
              const isOverdue = overdue.some((x) => x.id === o.id);
              return (
                <div
                  key={o.id}
                  className="flex items-center gap-2 text-sm p-2 rounded-lg"
                  style={{
                    background: isOverdue ? 'rgba(254, 226, 226, 0.4)' : 'rgb(var(--persona-tint))',
                    border: `1px solid ${isOverdue ? '#fca5a5' : 'rgb(var(--persona-primary) / 0.35)'}`,
                  }}
                >
                  {p ? (
                    <span className="px-1.5 py-0.5 rounded-md text-[11px] font-semibold" style={{ background: p.primaryColor, color: p.textColor }}>
                      {p.code}
                    </span>
                  ) : (
                    <span className="px-1.5 py-0.5 rounded-md text-[11px] font-semibold bg-black/10">ALL</span>
                  )}
                  <span className="font-semibold flex-1 truncate">{o.scheduleName}</span>
                  <span className="text-xs opacity-70">{describeDueDate(o.dueAt)}</span>
                </div>
              );
            })}
          </div>
        </div>
      )}

      <div className="grid grid-cols-3 gap-3">
        <Stat title="This month" value={counts?.mtd ?? 0} sub={`vs ${counts?.priorMtd ?? 0} last month`} />
        <Stat title="Year to date" value={counts?.ytd ?? 0} sub="clip releases" />
        <Stat title="All time" value={counts?.total ?? 0} sub="clips on file" />
      </div>

      <div className="pretty-card">
        <h3 className="display-font text-lg font-semibold persona-accent mb-3">Clips per persona</h3>
        {byPersona.length === 0 && <div className="text-sm opacity-70 italic">No clips imported yet.</div>}
        <div className="space-y-2">
          {byPersona.map((row) => {
            const p = row.personaCode ? personaByCode.get(row.personaCode) : null;
            const pct = (row.count / totalForBars) * 100;
            return (
              <div key={row.personaCode ?? '(none)'} className="flex items-center gap-3">
                <div className="w-28 flex items-center gap-2">
                  {p ? (
                    <>
                      <span className="px-1.5 py-0.5 rounded-md text-[11px] font-semibold" style={{ background: p.primaryColor, color: p.textColor }}>{p.code}</span>
                      <span className="text-xs">{p.name}</span>
                    </>
                  ) : <span className="text-xs italic opacity-60">(unassigned)</span>}
                </div>
                <div className="flex-1 h-3 rounded-full bg-black/5 overflow-hidden">
                  <div
                    className="h-full rounded-full"
                    style={{ width: `${pct}%`, background: p?.primaryColor ?? '#A16D9C' }}
                  />
                </div>
                <div className="w-12 text-right text-sm font-mono">{row.count}</div>
              </div>
            );
          })}
        </div>
      </div>

      <div className="pretty-card">
        <h3 className="display-font text-lg font-semibold persona-accent mb-2">Reuse detection</h3>
        <p className="text-xs opacity-60 mb-3">
          Possible duplicate posts: same external ID, or same title posted within ~2 weeks.
        </p>
        {reuse.length === 0 && <div className="text-sm opacity-70 italic">Looking good — nothing flagged.</div>}
        <div className="space-y-2">
          {reuse.slice(0, 8).map((g) => (
            <div key={`${g.reason}-${g.key}`} className="p-2 rounded-xl border border-amber-200 bg-amber-50/60">
              <div className="text-xs uppercase tracking-wider opacity-60">
                {g.reason === 'external_id' ? 'Same external ID' : 'Same title (within 14 days)'}
              </div>
              <div className="font-semibold text-sm">{g.key}</div>
              <div className="text-xs opacity-80 mt-1 space-y-0.5">
                {g.clips.map((c) => {
                  const p = c.personaCode ? personaByCode.get(c.personaCode) : null;
                  return (
                    <div key={c.id} className="flex items-center gap-2">
                      <span className="font-mono">{c.id}</span>
                      {p && <span className="px-1.5 py-0 rounded text-[10px]" style={{ background: p.primaryColor, color: p.textColor }}>{p.code}</span>}
                      <span className="opacity-80">{c.goLiveDate ?? '—'}</span>
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      </div>

      <div className="pretty-card">
        <h3 className="display-font text-lg font-semibold persona-accent mb-2">Recent imports</h3>
        {imports.length === 0 && <div className="text-sm opacity-70 italic">No imports yet. Head to <strong>Clips → Import</strong>.</div>}
        <div className="space-y-1.5">
          {imports.map((im) => (
            <div key={im.id} className="flex items-center justify-between text-sm p-2 rounded-xl border border-black/5">
              <div>
                <div className="font-mono text-xs opacity-60">{im.importedAt}</div>
                <div>{im.sourceFile || '(file)'}</div>
              </div>
              <div className="text-xs text-right">
                <span className="font-semibold">{im.rowsInserted}</span> added · <span className="font-semibold">{im.rowsUpdated}</span> updated
                {im.rowsSkipped > 0 && <> · <span className="text-red-700">{im.rowsSkipped} skipped</span></>}
              </div>
            </div>
          ))}
        </div>
      </div>

      {error && <div className="pretty-card text-sm text-red-700"><strong>Error:</strong> {error}</div>}
    </div>
  );
}

function Stat({ title, value, sub }: { title: string; value: number; sub: string }) {
  return (
    <div className="pretty-card">
      <div className="text-xs uppercase tracking-wider opacity-60">{title}</div>
      <div className="display-font text-3xl font-bold persona-accent mt-1">{value}</div>
      <div className="text-xs opacity-70 mt-1">{sub}</div>
    </div>
  );
}
