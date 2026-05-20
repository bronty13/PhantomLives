import { useMemo, useState } from 'react';
import { listSiteIncome, upsertSiteIncome, type SiteIncome } from '../../data/income';
import { listSites, type Site } from '../../data/sites';
import { listPersonas, type Persona as PersonaRow } from '../../data/personas';
import { fmtMoney, MONTH_NAMES, parseMoney, todayParts } from '../../lib/money';
import { useAsyncRefresh } from '../../lib/useAsyncRefresh';

interface Props {
  onClose: () => void;
}

export function SiteIncomeWizard({ onClose }: Props) {
  const t = todayParts();
  const [year, setYear] = useState<number>(t.year);
  const [month, setMonth] = useState<number>(t.month === 1 ? 12 : t.month - 1);   // default to "last completed month"
  const [sites, setSites] = useState<Site[]>([]);
  const [personas, setPersonas] = useState<PersonaRow[]>([]);
  const [existing, setExisting] = useState<Map<number, SiteIncome>>(new Map());
  const [edits, setEdits] = useState<Map<number, { amount: number; note: string }>>(new Map());
  const [status, setStatus] = useState<string>('');

  const { loading, refresh } = useAsyncRefresh(async (alive) => {
    const [s, p, ex] = await Promise.all([listSites(), listPersonas(), listSiteIncome(year, month)]);
    if (!alive()) return;
    setSites(s);
    setPersonas(p);
    const exMap = new Map<number, SiteIncome>();
    for (const row of ex) exMap.set(row.siteId, row);
    setExisting(exMap);
    // seed edits from existing
    const editMap = new Map<number, { amount: number; note: string }>();
    for (const row of ex) editMap.set(row.siteId, { amount: row.amount, note: row.note });
    setEdits(editMap);
  }, [year, month]);

  const grouped = useMemo(() => {
    const m = new Map<string, Site[]>();
    for (const s of sites) {
      const list = m.get(s.personaCode) ?? [];
      list.push(s);
      m.set(s.personaCode, list);
    }
    return m;
  }, [sites]);

  const totalsByPersona = useMemo(() => {
    const m = new Map<string, number>();
    for (const [code, list] of grouped) {
      let t = 0;
      for (const s of list) t += (edits.get(s.id)?.amount ?? existing.get(s.id)?.amount ?? 0);
      m.set(code, t);
    }
    return m;
  }, [grouped, edits, existing]);

  const grandTotal = useMemo(() => {
    let t = 0;
    for (const v of totalsByPersona.values()) t += v;
    return t;
  }, [totalsByPersona]);

  function setAmount(siteId: number, v: number) {
    const next = new Map(edits);
    const prev = next.get(siteId) ?? { amount: 0, note: '' };
    next.set(siteId, { ...prev, amount: v });
    setEdits(next);
  }
  function setNote(siteId: number, v: string) {
    const next = new Map(edits);
    const prev = next.get(siteId) ?? { amount: 0, note: '' };
    next.set(siteId, { ...prev, note: v });
    setEdits(next);
  }

  async function save() {
    try {
      for (const [siteId, { amount, note }] of edits.entries()) {
        const prev = existing.get(siteId);
        // Only upsert when changed (or new and non-zero)
        if (!prev && amount === 0 && note === '') continue;
        if (prev && prev.amount === amount && prev.note === note) continue;
        await upsertSiteIncome(year, month, siteId, amount, note);
      }
      setStatus(`Saved ${MONTH_NAMES[month - 1]} ${year}.`);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't save: ${String(e)}`);
    }
  }

  const yearOptions: number[] = [];
  for (let y = t.year + 1; y >= 2024; y--) yearOptions.push(y);

  return (
    <div className="p-8 max-w-4xl space-y-4">
      <div className="flex items-end justify-between gap-3">
        <div>
          <h2 className="display-font text-2xl font-bold persona-accent">Site income wizard</h2>
          <p className="opacity-70 text-sm">Once per month, walk through each site and enter what you earned.</p>
        </div>
        <div className="flex items-end gap-2">
          <label className="flex flex-col gap-1">
            <span className="text-xs uppercase tracking-wider opacity-60">Year</span>
            <select className="pretty-input" value={year} onChange={(e) => setYear(Number(e.target.value))}>
              {yearOptions.map((y) => <option key={y} value={y}>{y}</option>)}
            </select>
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-xs uppercase tracking-wider opacity-60">Month</span>
            <select className="pretty-input" value={month} onChange={(e) => setMonth(Number(e.target.value))}>
              {MONTH_NAMES.map((m, i) => <option key={m} value={i + 1}>{m}</option>)}
            </select>
          </label>
          <button type="button" className="pretty-button secondary" onClick={onClose}>← Back</button>
          <button type="button" className="pretty-button" onClick={save}>💾 Save</button>
        </div>
      </div>

      <div className="pretty-card flex items-center justify-between">
        <div className="text-sm">
          Working on <strong>{MONTH_NAMES[month - 1]} {year}</strong>.
        </div>
        <div className="text-right">
          <div className="text-xs uppercase tracking-wider opacity-60">Grand total</div>
          <div className="display-font text-2xl font-bold persona-accent">{fmtMoney(grandTotal)}</div>
        </div>
      </div>

      {[...grouped.entries()].map(([code, list]) => {
        const persona = personas.find((p) => p.code === code);
        const personaTotal = totalsByPersona.get(code) ?? 0;
        return (
          <div key={code} className="pretty-card">
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center gap-2">
                {persona && (
                  <span className="px-2 py-0.5 rounded-md text-[11px] font-semibold" style={{ background: persona.primaryColor, color: persona.textColor }}>
                    {persona.code}
                  </span>
                )}
                <span className="display-font font-semibold persona-accent">{persona?.name ?? code}</span>
                <span className="text-xs opacity-60">{list.length} site{list.length === 1 ? '' : 's'}</span>
              </div>
              <div className="text-right">
                <div className="text-xs opacity-60">Persona total</div>
                <div className="font-mono font-bold">{fmtMoney(personaTotal)}</div>
              </div>
            </div>
            <div className="space-y-1.5">
              {list.map((s) => {
                const entry = edits.get(s.id) ?? { amount: 0, note: '' };
                return (
                  <div key={s.id} className="grid grid-cols-12 gap-2 items-center text-sm">
                    <div className="col-span-1 flex items-center gap-2">
                      <span className="w-2.5 h-2.5 rounded-full" style={{ background: s.color }} />
                    </div>
                    <div className="col-span-3 truncate">
                      <div className="font-semibold">{s.name}</div>
                      <div className="text-[11px] opacity-60 font-mono">{s.shortCode}</div>
                    </div>
                    <label className="col-span-2 flex flex-col gap-0.5">
                      <span className="text-[10px] uppercase tracking-wider opacity-60">Amount</span>
                      <input
                        className="pretty-input font-mono text-right"
                        inputMode="decimal"
                        value={String(entry.amount)}
                        onChange={(e) => setAmount(s.id, parseMoney(e.target.value))}
                      />
                    </label>
                    <label className="col-span-6 flex flex-col gap-0.5">
                      <span className="text-[10px] uppercase tracking-wider opacity-60">Note (optional)</span>
                      <input className="pretty-input" value={entry.note} onChange={(e) => setNote(s.id, e.target.value)} />
                    </label>
                  </div>
                );
              })}
            </div>
          </div>
        );
      })}

      {loading && <div className="pretty-card text-sm opacity-60 italic">Loading…</div>}
      {!loading && grouped.size === 0 && <div className="pretty-card text-sm opacity-70 italic">No sites yet — add some in Settings → Sites first.</div>}
      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}
