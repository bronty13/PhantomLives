import { useMemo, useState } from 'react';
import type { Persona } from '../../state/personas';
import {
  perSiteForYear,
  totalsForPeriod,
  type PerSiteIncome,
  type IncomeTotals,
} from '../../data/income';
import { expenseTotalsForPeriod, type ExpenseTotals } from '../../data/expenses';
import { listPersonas, type Persona as PersonaRow } from '../../data/personas';
import { countByPlatform, countTotal, type PromoCount } from '../../data/socialPromos';
import { listPlatforms, type SocialPlatform } from '../../data/socialPlatforms';
import { fmtMoney, MONTH_NAMES, prevMonth, todayParts } from '../../lib/money';
import { useAsyncRefresh } from '../../lib/useAsyncRefresh';

interface Props {
  active: Persona;
}

export function ReportsView({ active }: Props) {
  const t = todayParts();
  const [year, setYear] = useState<number>(t.year);
  const [personas, setPersonas] = useState<PersonaRow[]>([]);
  const [mtdIncome, setMtdIncome] = useState<IncomeTotals | null>(null);
  const [priorMtdIncome, setPriorMtdIncome] = useState<IncomeTotals | null>(null);
  const [ytdIncome, setYtdIncome] = useState<IncomeTotals | null>(null);
  const [mtdExp, setMtdExp] = useState<ExpenseTotals | null>(null);
  const [priorMtdExp, setPriorMtdExp] = useState<ExpenseTotals | null>(null);
  const [ytdExp, setYtdExp] = useState<ExpenseTotals | null>(null);
  const [perSite, setPerSite] = useState<PerSiteIncome[]>([]);
  const [promosMtd, setPromosMtd] = useState(0);
  const [promosYtd, setPromosYtd] = useState(0);
  const [promosByPlatform, setPromosByPlatform] = useState<PromoCount[]>([]);
  const [platforms, setPlatforms] = useState<SocialPlatform[]>([]);

  const { loading, error } = useAsyncRefresh(async (alive) => {
    const persona = active.code === 'ALL' ? undefined : active.code;
    const prior = prevMonth(t.year, t.month);
    const [p, mIn, pIn, yIn, mEx, pEx, yEx, ps, pMtd, pYtd, pByPlat, plats] = await Promise.all([
      listPersonas(),
      totalsForPeriod({ year: t.year, month: t.month, dayCap: t.day, personaCode: persona }),
      totalsForPeriod({ year: prior.year, month: prior.month, dayCap: t.day, personaCode: persona }),
      totalsForPeriod({ year: year, personaCode: persona }),
      expenseTotalsForPeriod({ year: t.year, month: t.month, dayCap: t.day, personaCode: persona }),
      expenseTotalsForPeriod({ year: prior.year, month: prior.month, dayCap: t.day, personaCode: persona }),
      expenseTotalsForPeriod({ year: year, personaCode: persona }),
      perSiteForYear(year, persona),
      countTotal({ year: t.year, month: t.month, personaCode: persona }),
      countTotal({ year, personaCode: persona }),
      countByPlatform({ year, personaCode: persona }),
      listPlatforms(),
    ]);
    if (!alive()) return;
    setPersonas(p);
    setMtdIncome(mIn);
    setPriorMtdIncome(pIn);
    setYtdIncome(yIn);
    setMtdExp(mEx);
    setPriorMtdExp(pEx);
    setYtdExp(yEx);
    setPerSite(ps);
    setPromosMtd(pMtd);
    setPromosYtd(pYtd);
    setPromosByPlatform(pByPlat);
    setPlatforms(plats);
  }, [year, active.code, t.year, t.month, t.day]);

  const yearOptions: number[] = [];
  for (let y = t.year + 1; y >= 2024; y--) yearOptions.push(y);

  const personaByCode = useMemo(() => new Map(personas.map((p) => [p.code, p])), [personas]);
  const sitesGrouped = useMemo(() => {
    const m = new Map<string, PerSiteIncome[]>();
    for (const s of perSite) {
      const list = m.get(s.personaCode) ?? [];
      list.push(s);
      m.set(s.personaCode, list);
    }
    return m;
  }, [perSite]);

  function exportCsv() {
    const persona = active.code === 'ALL' ? 'ALL' : active.code;
    const lines: string[] = [];
    lines.push(`Molly report,${year}-${t.month.toString().padStart(2, '0')}-${t.day.toString().padStart(2, '0')},${persona}`);
    lines.push('');
    lines.push('Period,Income,Expenses (net),Profit');
    if (mtdIncome && mtdExp)         lines.push(`MTD,${mtdIncome.total},${mtdExp.net},${mtdIncome.total - mtdExp.net}`);
    if (priorMtdIncome && priorMtdExp) lines.push(`Prior MTD,${priorMtdIncome.total},${priorMtdExp.net},${priorMtdIncome.total - priorMtdExp.net}`);
    if (ytdIncome && ytdExp)         lines.push(`YTD,${ytdIncome.total},${ytdExp.net},${ytdIncome.total - ytdExp.net}`);
    lines.push('');
    lines.push('Site income (YTD)');
    lines.push('Persona,Site,Short code,Color,Amount');
    for (const s of perSite) {
      lines.push(`${s.personaCode},${csv(s.siteName)},${s.shortCode},${s.color},${s.total}`);
    }
    const csvText = lines.join('\n');
    const blob = new Blob([csvText], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `molly-report-${year}-${t.month.toString().padStart(2, '0')}-${persona}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <div className="p-8 max-w-5xl space-y-4">
      <div className="flex items-end justify-between gap-3">
        <div>
          <h2 className="display-font text-2xl font-bold persona-accent">Reports</h2>
          <p className="opacity-70 text-sm">
            {active.code === 'ALL' ? 'All personas combined.' : `Filtered to ${active.name}.`} · {MONTH_NAMES[t.month - 1]} {t.year}
          </p>
        </div>
        <div className="flex items-end gap-2">
          <label className="flex flex-col gap-1">
            <span className="text-xs uppercase tracking-wider opacity-60">YTD year</span>
            <select className="pretty-input" value={year} onChange={(e) => setYear(Number(e.target.value))}>
              {yearOptions.map((y) => <option key={y} value={y}>{y}</option>)}
            </select>
          </label>
          <button type="button" className="pretty-button" onClick={exportCsv}>📄 Export CSV</button>
        </div>
      </div>

      {loading && <div className="pretty-card text-sm opacity-60 italic">Loading reports…</div>}

      <div className="grid grid-cols-3 gap-3">
        <PeriodCard
          title={`${MONTH_NAMES[t.month - 1]} MTD`}
          income={mtdIncome?.total ?? 0}
          expense={mtdExp?.net ?? 0}
        />
        <PeriodCard
          title={`Prior MTD (${MONTH_NAMES[prevMonth(t.year, t.month).month - 1]})`}
          income={priorMtdIncome?.total ?? 0}
          expense={priorMtdExp?.net ?? 0}
        />
        <PeriodCard
          title={`YTD ${year}`}
          income={ytdIncome?.total ?? 0}
          expense={ytdExp?.net ?? 0}
        />
      </div>

      {mtdIncome && (
        <div className="pretty-card">
          <h3 className="display-font text-lg font-semibold persona-accent mb-2">Income breakdown (MTD)</h3>
          <Breakdown name="Adhoc"      value={mtdIncome.adhocTotal} total={mtdIncome.total || 1} />
          <Breakdown name="Site income" value={mtdIncome.siteTotal}  total={mtdIncome.total || 1} />
        </div>
      )}

      <div className="pretty-card">
        <h3 className="display-font text-lg font-semibold persona-accent mb-2">Site income (YTD {year})</h3>
        {perSite.length === 0 && <div className="text-sm opacity-70 italic">No site income yet.</div>}
        {[...sitesGrouped.entries()].map(([code, list]) => {
          const persona = personaByCode.get(code);
          const personaTotal = list.reduce((acc, s) => acc + s.total, 0);
          const maxForGroup = Math.max(1, ...list.map((s) => s.total));
          return (
            <div key={code} className="mt-3">
              <div className="flex items-center justify-between mb-1">
                <div className="flex items-center gap-2">
                  {persona && (
                    <span className="px-1.5 py-0.5 rounded-md text-[11px] font-semibold" style={{ background: persona.primaryColor, color: persona.textColor }}>{persona.code}</span>
                  )}
                  <span className="font-semibold">{persona?.name ?? code}</span>
                </div>
                <span className="font-mono">{fmtMoney(personaTotal)}</span>
              </div>
              <div className="space-y-1">
                {list.map((s) => (
                  <div key={s.siteId} className="flex items-center gap-3 text-sm">
                    <div className="w-32 truncate">{s.siteName} <span className="font-mono opacity-60 text-[11px]">[{s.shortCode}]</span></div>
                    <div className="flex-1 h-2 rounded-full bg-black/5 overflow-hidden">
                      <div className="h-full" style={{ width: `${(s.total / maxForGroup) * 100}%`, background: s.color }} />
                    </div>
                    <div className="w-24 text-right font-mono">{fmtMoney(s.total)}</div>
                  </div>
                ))}
              </div>
            </div>
          );
        })}
      </div>

      <div className="pretty-card">
        <h3 className="display-font text-lg font-semibold persona-accent mb-1">Promos</h3>
        <p className="text-xs opacity-60 mb-3">Post counts. (Sales attribution lands in a later phase.)</p>
        <div className="grid grid-cols-3 gap-3 mb-3">
          <div className="p-3 rounded-xl persona-tint border border-black/5">
            <div className="text-xs uppercase tracking-wider opacity-60">{MONTH_NAMES[t.month - 1]} MTD</div>
            <div className="display-font text-2xl font-bold persona-accent mt-1">{promosMtd}</div>
          </div>
          <div className="p-3 rounded-xl persona-tint border border-black/5">
            <div className="text-xs uppercase tracking-wider opacity-60">YTD {year}</div>
            <div className="display-font text-2xl font-bold persona-accent mt-1">{promosYtd}</div>
          </div>
          <div className="p-3 rounded-xl persona-tint border border-black/5">
            <div className="text-xs uppercase tracking-wider opacity-60">Platforms tracked</div>
            <div className="display-font text-2xl font-bold persona-accent mt-1">{platforms.length}</div>
          </div>
        </div>
        {promosByPlatform.length === 0 ? (
          <div className="text-sm opacity-70 italic">No promos in {year} yet — start logging on the Promos page.</div>
        ) : (
          <div className="space-y-1.5">
            {promosByPlatform.map((row) => {
              const plat = platforms.find((p) => p.id === row.platformId);
              const max = Math.max(1, ...promosByPlatform.map((r) => r.count));
              return (
                <div key={row.platformId} className="flex items-center gap-3 text-sm">
                  <div className="w-36 flex items-center gap-2">
                    <span className="text-base">{plat?.icon ?? '📣'}</span>
                    <span>{plat?.name ?? '(deleted)'}</span>
                  </div>
                  <div className="flex-1 h-3 rounded-full bg-black/5 overflow-hidden">
                    <div className="h-full" style={{ width: `${(row.count / max) * 100}%`, background: plat?.color ?? '#A16D9C' }} />
                  </div>
                  <div className="w-12 text-right font-mono">{row.count}</div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {error && <div className="pretty-card text-sm text-red-700"><strong>Error:</strong> {error}</div>}
    </div>
  );
}

function PeriodCard({ title, income, expense }: { title: string; income: number; expense: number }) {
  const profit = income - expense;
  return (
    <div className="pretty-card">
      <div className="text-xs uppercase tracking-wider opacity-60">{title}</div>
      <div className="display-font text-2xl font-bold persona-accent mt-1">{fmtMoney(profit)}</div>
      <div className="text-xs opacity-70 mt-1 space-y-0.5">
        <div>Income: <span className="font-mono">{fmtMoney(income)}</span></div>
        <div>Expenses: <span className="font-mono">{fmtMoney(expense)}</span></div>
      </div>
    </div>
  );
}

function Breakdown({ name, value, total }: { name: string; value: number; total: number }) {
  const pct = (value / total) * 100;
  return (
    <div className="flex items-center gap-3 text-sm py-1">
      <div className="w-32 truncate">{name}</div>
      <div className="flex-1 h-2 rounded-full bg-black/5 overflow-hidden">
        <div className="h-full" style={{ width: `${pct}%`, background: 'rgb(var(--persona-accent))' }} />
      </div>
      <div className="w-24 text-right font-mono">{fmtMoney(value)}</div>
    </div>
  );
}

function csv(s: string): string {
  if (s.includes(',') || s.includes('"') || s.includes('\n')) {
    return `"${s.replace(/"/g, '""')}"`;
  }
  return s;
}
