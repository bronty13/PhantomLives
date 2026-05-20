import { useEffect, useMemo, useState } from 'react';
import type { Persona } from '../../state/personas';
import {
  createAdhoc,
  deleteAdhoc,
  listAdhoc,
  updateAdhoc,
  type AdhocIncome,
} from '../../data/income';
import { listPersonas, type Persona as PersonaRow } from '../../data/personas';
import { fmtMoney, MONTH_NAMES, parseMoney, todayParts } from '../../lib/money';
import { ConfirmButton } from '../../components/ConfirmButton';

interface Props {
  active: Persona;
}

const EMPTY = (personaCode: string | null): Omit<AdhocIncome, 'id' | 'createdAt' | 'updatedAt'> => {
  const t = new Date();
  const iso = `${t.getFullYear()}-${(t.getMonth() + 1).toString().padStart(2, '0')}-${t.getDate().toString().padStart(2, '0')}`;
  return { dateEarned: iso, amount: 0, personaCode, sourceLabel: '', note: '' };
};

export function AdhocIncomeView({ active }: Props) {
  const t = todayParts();
  const [year, setYear] = useState<number>(t.year);
  const [month, setMonth] = useState<number | 'all'>(t.month);
  const [rows, setRows] = useState<AdhocIncome[]>([]);
  const [personas, setPersonas] = useState<PersonaRow[]>([]);
  const [draft, setDraft] = useState<(Omit<AdhocIncome, 'id' | 'createdAt' | 'updatedAt'> & { id?: number }) | null>(null);
  const [status, setStatus] = useState('');

  async function refresh() {
    const filter: { year?: number; month?: number; personaCode?: string } = {
      year, personaCode: active.code,
    };
    if (month !== 'all') filter.month = month;
    const [list, p] = await Promise.all([
      listAdhoc(filter),
      listPersonas(),
    ]);
    setRows(list);
    setPersonas(p);
  }

  useEffect(() => {
    refresh().catch((e) => setStatus(String(e)));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [year, month, active.code]);

  const total = useMemo(() => rows.reduce((acc, r) => acc + r.amount, 0), [rows]);
  const personaByCode = useMemo(() => new Map(personas.map((p) => [p.code, p])), [personas]);

  async function save() {
    if (!draft) return;
    try {
      if (draft.id) {
        await updateAdhoc({ ...draft, id: draft.id, createdAt: '', updatedAt: '' });
      } else {
        await createAdhoc(draft);
      }
      setDraft(null);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't save: ${String(e)}`);
    }
  }

  async function remove(row: AdhocIncome) {
    try {
      await deleteAdhoc(row.id);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't delete: ${String(e)}`);
    }
  }

  const yearOptions: number[] = [];
  for (let y = t.year + 1; y >= 2024; y--) yearOptions.push(y);

  return (
    <div className="p-8 max-w-5xl space-y-4">
      <div className="flex items-end justify-between gap-3">
        <div>
          <h2 className="display-font text-2xl font-bold persona-accent">Adhoc income</h2>
          <p className="opacity-70 text-sm">One-off sales, tips, customs. Backfill to any past month for tax prep.</p>
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
            <select className="pretty-input" value={String(month)} onChange={(e) => setMonth(e.target.value === 'all' ? 'all' : Number(e.target.value))}>
              <option value="all">All</option>
              {MONTH_NAMES.map((m, i) => <option key={m} value={i + 1}>{m}</option>)}
            </select>
          </label>
          <button type="button" className="pretty-button" onClick={() => setDraft(EMPTY(active.code === 'ALL' ? null : active.code))}>
            ✨ Add income
          </button>
        </div>
      </div>

      <div className="pretty-card">
        <div className="flex items-center justify-between mb-3">
          <div className="text-xs uppercase tracking-wider opacity-60">Total this view</div>
          <div className="display-font text-2xl font-bold persona-accent">{fmtMoney(total)}</div>
        </div>

        {draft && (
          <AdhocEditor
            draft={draft}
            personas={personas}
            onChange={setDraft}
            onCancel={() => setDraft(null)}
            onSave={save}
          />
        )}

        {rows.length === 0 && !draft && (
          <div className="text-sm opacity-70 italic">Nothing here yet — click <strong>Add income</strong>.</div>
        )}

        <div className="divide-y divide-black/5">
          {rows.map((r) => {
            const p = r.personaCode ? personaByCode.get(r.personaCode) : null;
            return (
              <div key={r.id} className="grid grid-cols-12 gap-2 items-center py-2 text-sm">
                <div className="col-span-2 font-mono opacity-70">{r.dateEarned}</div>
                <div className="col-span-1">
                  {p ? (
                    <span className="px-1.5 py-0.5 rounded-md text-[11px] font-semibold" style={{ background: p.primaryColor, color: p.textColor }}>{p.code}</span>
                  ) : <span className="text-[11px] opacity-50">—</span>}
                </div>
                <div className="col-span-3 truncate font-semibold">{r.sourceLabel || '(no source)'}</div>
                <div className="col-span-4 text-xs opacity-70 truncate">{r.note}</div>
                <div className="col-span-1 font-mono text-right">{fmtMoney(r.amount)}</div>
                <div className="col-span-1 flex justify-end gap-1">
                  <button type="button" className="pretty-button secondary" onClick={() => setDraft({ ...r })}>Edit</button>
                  <ConfirmButton label="✕" confirmLabel="✕?" onConfirm={() => remove(r)} />
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

function AdhocEditor({
  draft, personas, onChange, onCancel, onSave,
}: {
  draft: (Omit<AdhocIncome, 'id' | 'createdAt' | 'updatedAt'> & { id?: number });
  personas: PersonaRow[];
  onChange: (d: typeof draft) => void;
  onCancel: () => void;
  onSave: () => void | Promise<void>;
}) {
  return (
    <div className="mb-3 p-3 rounded-xl bg-white border border-black/5 grid grid-cols-6 gap-3">
      <label className="flex flex-col gap-1 col-span-2">
        <span className="text-xs uppercase tracking-wider opacity-60">Date earned</span>
        <input type="date" className="pretty-input" value={draft.dateEarned} onChange={(e) => onChange({ ...draft, dateEarned: e.target.value })} />
      </label>
      <label className="flex flex-col gap-1 col-span-2">
        <span className="text-xs uppercase tracking-wider opacity-60">Persona</span>
        <select className="pretty-input" value={draft.personaCode ?? ''} onChange={(e) => onChange({ ...draft, personaCode: e.target.value || null })}>
          <option value="">(unassigned)</option>
          {personas.map((p) => <option key={p.code} value={p.code}>{p.code} — {p.name}</option>)}
        </select>
      </label>
      <label className="flex flex-col gap-1 col-span-2">
        <span className="text-xs uppercase tracking-wider opacity-60">Amount</span>
        <input
          className="pretty-input font-mono"
          inputMode="decimal"
          value={String(draft.amount)}
          onChange={(e) => onChange({ ...draft, amount: parseMoney(e.target.value) })}
        />
      </label>
      <label className="flex flex-col gap-1 col-span-3">
        <span className="text-xs uppercase tracking-wider opacity-60">Source</span>
        <input className="pretty-input" placeholder="e.g. custom for Mike, tip jar" value={draft.sourceLabel} onChange={(e) => onChange({ ...draft, sourceLabel: e.target.value })} />
      </label>
      <label className="flex flex-col gap-1 col-span-3">
        <span className="text-xs uppercase tracking-wider opacity-60">Note</span>
        <input className="pretty-input" value={draft.note} onChange={(e) => onChange({ ...draft, note: e.target.value })} />
      </label>
      <div className="col-span-6 flex justify-end gap-2">
        <button type="button" className="pretty-button secondary" onClick={onCancel}>Cancel</button>
        <button type="button" className="pretty-button" onClick={onSave}>Save</button>
      </div>
    </div>
  );
}
