import { useEffect, useMemo, useRef, useState } from 'react';
import type { Persona } from '../../state/personas';
import { listSites, type Site } from '../../data/sites';
import { listPersonas, type Persona as PersonaRow } from '../../data/personas';
import { listSiteIncome, upsertSiteIncome } from '../../data/income';
import { parseSalesReport, type ParseResult } from '../../lib/salesReport';
import { fmtMoney, MONTH_NAMES } from '../../lib/money';

interface Props {
  active: Persona;
}

type Mode = 'replace' | 'add';

export function SalesReportImport({ active }: Props) {
  const fileInput = useRef<HTMLInputElement | null>(null);
  const [sites, setSites] = useState<Site[]>([]);
  const [personas, setPersonas] = useState<PersonaRow[]>([]);
  const [siteId, setSiteId] = useState<number | null>(null);
  const [filename, setFilename] = useState<string>('');
  const [rawText, setRawText] = useState<string>('');
  const [parsed, setParsed] = useState<ParseResult | null>(null);
  const [dateColOverride, setDateColOverride] = useState<string>('');
  const [amountColOverride, setAmountColOverride] = useState<string>('');
  const [mode, setMode] = useState<Mode>('replace');
  const [status, setStatus] = useState<string>('');
  const [existing, setExisting] = useState<Map<string, number>>(new Map()); // "YYYY-MM" -> existing amount

  useEffect(() => {
    Promise.all([listSites(), listPersonas()])
      .then(([s, p]) => {
        setSites(s);
        setPersonas(p);
        // Pre-select first site for the active persona (or any first site).
        const filter = active.code === 'ALL' ? null : active.code;
        const candidate = filter ? s.find((x) => x.personaCode === filter) : s[0];
        if (candidate) setSiteId(candidate.id);
      })
      .catch((e) => setStatus(String(e)));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [active.code]);

  // Re-parse whenever raw text or overrides change.
  useEffect(() => {
    if (!rawText.trim()) {
      setParsed(null);
      return;
    }
    try {
      const result = parseSalesReport(rawText, {
        dateColumn: dateColOverride || undefined,
        amountColumn: amountColOverride || undefined,
      });
      setParsed(result);
    } catch (e) {
      setStatus(`Couldn't parse CSV: ${String(e)}`);
      setParsed(null);
    }
  }, [rawText, dateColOverride, amountColOverride]);

  // Load existing site_income for the buckets we're about to write so we
  // can show "replace 100 → 250" diffs in the preview.
  useEffect(() => {
    async function loadExisting() {
      if (!parsed || !siteId) { setExisting(new Map()); return; }
      const map = new Map<string, number>();
      for (const b of parsed.byMonth) {
        const rows = await listSiteIncome(b.year, b.month);
        const found = rows.find((r) => r.siteId === siteId);
        if (found) map.set(`${b.year}-${b.month.toString().padStart(2, '0')}`, found.amount);
      }
      setExisting(map);
    }
    loadExisting().catch((e) => setStatus(String(e)));
  }, [parsed, siteId]);

  async function onFileChosen(file: File) {
    setFilename(file.name);
    const text = await file.text();
    setRawText(text);
    setDateColOverride('');
    setAmountColOverride('');
    setStatus('');
  }

  async function runImport() {
    if (!parsed || !siteId || parsed.byMonth.length === 0) return;
    let writes = 0;
    try {
      for (const b of parsed.byMonth) {
        const key = `${b.year}-${b.month.toString().padStart(2, '0')}`;
        const prior = existing.get(key);
        let next = b.amount;
        if (mode === 'add' && typeof prior === 'number') next = prior + b.amount;
        await upsertSiteIncome(b.year, b.month, siteId, next, filename || '');
        writes++;
      }
      setStatus(`Imported ${writes} month${writes === 1 ? '' : 's'} for ${sites.find((s) => s.id === siteId)?.name ?? 'site'}.`);
    } catch (e) {
      setStatus(`Import failed after ${writes} month(s): ${String(e)}`);
    }
  }

  const sitesFiltered = useMemo(() => {
    const filter = active.code === 'ALL' ? null : active.code;
    if (!filter) return sites;
    return sites.filter((s) => s.personaCode === filter);
  }, [sites, active]);

  const groupedSites = useMemo(() => {
    const m = new Map<string, Site[]>();
    for (const s of sites) {
      const list = m.get(s.personaCode) ?? [];
      list.push(s);
      m.set(s.personaCode, list);
    }
    return m;
  }, [sites]);

  const selectedSite = sites.find((s) => s.id === siteId);
  const selectedPersona = selectedSite ? personas.find((p) => p.code === selectedSite.personaCode) : null;
  const grandTotal = parsed?.byMonth.reduce((a, b) => a + b.amount, 0) ?? 0;

  return (
    <div className="p-8 max-w-4xl space-y-4">
      <div>
        <h2 className="display-font text-2xl font-bold persona-accent">Sales report import</h2>
        <p className="opacity-70 text-sm">
          Drop in a CSV from any site (Clips4Sale, IWantClips, OnlyFans, …). Molly auto-detects the date and amount
          columns, totals by month, and writes into the site income table — same data the wizard touches.
        </p>
      </div>

      <div className="pretty-card space-y-3">
        <div>
          <label className="block text-xs uppercase tracking-wider opacity-60 mb-1">Site</label>
          <select
            className="pretty-input w-full"
            value={siteId ?? ''}
            onChange={(e) => setSiteId(e.target.value ? Number(e.target.value) : null)}
          >
            <option value="">— choose a site —</option>
            {active.code === 'ALL'
              ? [...groupedSites.entries()].flatMap(([code, list]) => {
                  const persona = personas.find((p) => p.code === code);
                  return [
                    <optgroup key={code} label={`${persona?.code ?? code} — ${persona?.name ?? ''}`}>
                      {list.map((s) => <option key={s.id} value={s.id}>{s.name} [{s.shortCode}]</option>)}
                    </optgroup>,
                  ];
                })
              : sitesFiltered.map((s) => <option key={s.id} value={s.id}>{s.name} [{s.shortCode}]</option>)}
          </select>
          {selectedSite && (
            <div className="text-xs opacity-70 mt-1">
              {selectedPersona && (
                <span className="px-1.5 py-0.5 rounded-md text-[11px] font-semibold mr-2" style={{ background: selectedPersona.primaryColor, color: selectedPersona.textColor }}>
                  {selectedPersona.code}
                </span>
              )}
              {selectedSite.url} · user <span className="font-mono">{selectedSite.username}</span>
            </div>
          )}
        </div>

        <div>
          <input
            ref={fileInput}
            type="file"
            accept=".csv,text/csv"
            className="hidden"
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) onFileChosen(f);
              e.target.value = '';
            }}
          />
          <div className="flex flex-wrap gap-2 items-center">
            <button type="button" className="pretty-button secondary" onClick={() => fileInput.current?.click()} disabled={!siteId}>
              📂 Choose CSV…
            </button>
            {filename && <span className="text-xs opacity-70 font-mono">{filename}</span>}
          </div>
        </div>

        {parsed && parsed.header.length > 0 && (
          <div className="grid grid-cols-2 gap-3">
            <label className="flex flex-col gap-1">
              <span className="text-xs uppercase tracking-wider opacity-60">Date column {parsed.detected.dateColumn && <em className="opacity-50">(auto: {parsed.detected.dateColumn})</em>}</span>
              <select className="pretty-input" value={dateColOverride} onChange={(e) => setDateColOverride(e.target.value)}>
                <option value="">(auto-detect)</option>
                {parsed.header.map((h) => <option key={h} value={h}>{h}</option>)}
              </select>
            </label>
            <label className="flex flex-col gap-1">
              <span className="text-xs uppercase tracking-wider opacity-60">Amount column {parsed.detected.amountColumn && <em className="opacity-50">(auto: {parsed.detected.amountColumn})</em>}</span>
              <select className="pretty-input" value={amountColOverride} onChange={(e) => setAmountColOverride(e.target.value)}>
                <option value="">(auto-detect)</option>
                {parsed.header.map((h) => <option key={h} value={h}>{h}</option>)}
              </select>
            </label>
          </div>
        )}
      </div>

      {parsed && (
        <div className="pretty-card">
          <div className="flex items-center justify-between mb-3">
            <h3 className="display-font text-lg font-semibold persona-accent">Per-month totals</h3>
            <div className="text-right">
              <div className="text-xs opacity-60">Grand total</div>
              <div className="font-mono font-bold">{fmtMoney(grandTotal)}</div>
            </div>
          </div>

          {parsed.byMonth.length === 0 ? (
            <div className="text-sm opacity-70 italic">
              No rows parsed. {parsed.detected.dateColumn === null && 'No date column detected.'}{' '}
              {parsed.detected.amountColumn === null && 'No amount column detected.'}{' '}
              Pick columns manually above.
            </div>
          ) : (
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left">
                  <th className="text-xs uppercase opacity-60 pb-1">Month</th>
                  <th className="text-xs uppercase opacity-60 pb-1 text-right">Rows</th>
                  <th className="text-xs uppercase opacity-60 pb-1 text-right">CSV total</th>
                  <th className="text-xs uppercase opacity-60 pb-1 text-right">Existing</th>
                  <th className="text-xs uppercase opacity-60 pb-1 text-right">{mode === 'replace' ? 'Will become' : 'Add → result'}</th>
                </tr>
              </thead>
              <tbody>
                {parsed.byMonth.map((b) => {
                  const key = `${b.year}-${b.month.toString().padStart(2, '0')}`;
                  const prior = existing.get(key);
                  const result = mode === 'replace' ? b.amount : (prior ?? 0) + b.amount;
                  return (
                    <tr key={key} className="border-t border-black/5">
                      <td className="py-1.5">{MONTH_NAMES[b.month - 1]} {b.year}</td>
                      <td className="py-1.5 text-right font-mono">{b.rowCount}</td>
                      <td className="py-1.5 text-right font-mono">{fmtMoney(b.amount)}</td>
                      <td className="py-1.5 text-right font-mono opacity-70">{typeof prior === 'number' ? fmtMoney(prior) : '—'}</td>
                      <td className="py-1.5 text-right font-mono font-semibold">{fmtMoney(result)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}

          {parsed.unparseable.length > 0 && (
            <details className="mt-3 text-xs">
              <summary className="cursor-pointer opacity-70">
                {parsed.unparseable.length} row{parsed.unparseable.length === 1 ? '' : 's'} couldn't be parsed
              </summary>
              <ul className="mt-1 space-y-0.5 max-h-32 overflow-y-auto font-mono">
                {parsed.unparseable.slice(0, 25).map((u, idx) => (
                  <li key={idx}>line {u.lineNo}: {u.reason}</li>
                ))}
                {parsed.unparseable.length > 25 && <li className="opacity-60">…and {parsed.unparseable.length - 25} more</li>}
              </ul>
            </details>
          )}
        </div>
      )}

      {parsed && parsed.byMonth.length > 0 && (
        <div className="pretty-card flex items-center justify-between gap-3">
          <label className="flex items-center gap-2 text-sm">
            <span className="opacity-60">When a month already has a value:</span>
            <select className="pretty-input" value={mode} onChange={(e) => setMode(e.target.value as Mode)}>
              <option value="replace">Replace (overwrite existing)</option>
              <option value="add">Add (sum into existing)</option>
            </select>
          </label>
          <button type="button" className="pretty-button" onClick={runImport} disabled={!siteId}>
            ✨ Run import
          </button>
        </div>
      )}

      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}
