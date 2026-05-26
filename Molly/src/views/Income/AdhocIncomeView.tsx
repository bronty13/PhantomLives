import { useMemo, useState } from 'react';
import type { Persona } from '../../state/personas';
import {
  createAdhoc,
  deleteAdhoc,
  listAdhocUnified,
  totalsForPeriod,
  updateAdhoc,
  type AdhocIncome,
  type UnifiedAdhocRow,
} from '../../data/income';
import { listPersonas, type Persona as PersonaRow } from '../../data/personas';
import { fmtMoney, MONTH_NAMES, todayParts } from '../../lib/money';
import { ConfirmButton } from '../../components/ConfirmButton';
import { MoneyInput } from '../../components/MoneyInput';
import { useAsyncRefresh } from '../../lib/useAsyncRefresh';
import { celebrateIncome } from '../../lib/celebration';
import { useMonthlyGoals, type MonthNumber } from '../../state/incomeGoals';
import { GoalProgress } from './GoalProgress';

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
  const [rows, setRows] = useState<UnifiedAdhocRow[]>([]);
  const [personas, setPersonas] = useState<PersonaRow[]>([]);
  const [draft, setDraft] = useState<(Omit<AdhocIncome, 'id' | 'createdAt' | 'updatedAt'> & { id?: number }) | null>(null);
  const [status, setStatus] = useState('');
  // Bumped after every successful save so <GoalProgress /> re-reads
  // the DB. The view's own data already refetches via useAsyncRefresh,
  // but the progress card lives in a sibling tree and doesn't share
  // the refresh trigger.
  const [goalRefreshKey, setGoalRefreshKey] = useState(0);
  const { goals } = useMonthlyGoals();

  const { loading, refresh } = useAsyncRefresh(async (alive) => {
    const filter: { year?: number; month?: number; personaCode?: string } = {
      year, personaCode: active.code,
    };
    if (month !== 'all') filter.month = month;
    const [list, p] = await Promise.all([
      listAdhocUnified(filter),
      listPersonas(),
    ]);
    if (!alive()) return;
    setRows(list);
    setPersonas(p);
  }, [year, month, active.code]);

  const total = useMemo(() => rows.reduce((acc, r) => acc + r.amount, 0), [rows]);
  const personaByCode = useMemo(() => new Map(personas.map((p) => [p.code, p])), [personas]);

  async function save() {
    if (!draft) return;
    try {
      const isNew = !draft.id;
      // Capture the current-month unified-adhoc total BEFORE the insert
      // so celebrateIncome() can decide whether this save crossed a
      // monthly-goal milestone. Use today's calendar month, not the
      // year/month filter — Sallie can backfill into May from June and
      // her June goal is still the one being chased.
      const todayP = todayParts();
      const totalBefore = isNew
        ? (await totalsForPeriod({ year: todayP.year, month: todayP.month })).adhocTotal
        : 0;
      if (draft.id) {
        await updateAdhoc({ ...draft, id: draft.id, createdAt: '', updatedAt: '' });
      } else {
        await createAdhoc(draft);
      }
      if (isNew) {
        // Re-query after the insert to pick up the new contribution.
        // Adhocs dated outside the current month don't lift the goal —
        // they show as totalAfter === totalBefore, no milestone fires.
        const totalAfter = (await totalsForPeriod({ year: todayP.year, month: todayP.month })).adhocTotal;
        celebrateIncome({
          amountDollars: draft.amount,
          totalBefore,
          totalAfter,
          goalDollars: goals[todayP.month as MonthNumber] ?? 0,
        });
        setGoalRefreshKey((n) => n + 1);
      }
      setDraft(null);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't save: ${String(e)}`);
    }
  }

  async function remove(row: UnifiedAdhocRow) {
    if (row.source !== 'adhoc') return; // sales are managed from the customer view
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
      <GoalProgress year={year} month={month} refreshKey={goalRefreshKey} />

      <div className="flex items-end justify-between gap-3">
        <div>
          <h2 className="display-font text-2xl font-bold persona-accent">Adhoc income</h2>
          <p className="opacity-70 text-sm">One-off sales, tips, customs — plus sales recorded on customer records, marked 🛒. Backfill to any past month for tax prep.</p>
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

        {loading && <div className="text-sm opacity-60 italic">Loading…</div>}
        {!loading && rows.length === 0 && !draft && (
          <div className="text-sm opacity-70 italic">Nothing here yet — click <strong>Add income</strong>.</div>
        )}

        <div className="divide-y divide-black/5">
          {rows.map((r) => {
            const p = r.personaCode ? personaByCode.get(r.personaCode) : null;
            const isSale = r.source === 'sale';
            const noteText = isSale
              ? [`${r.quantity} ${r.unit}${r.quantity === 1 ? '' : 's'}`, r.note].filter(Boolean).join(' · ')
              : r.note;
            return (
              <div key={`${r.source}-${r.id}`} className="grid grid-cols-12 gap-2 items-center py-2 text-sm">
                <div className="col-span-2 font-mono opacity-70">{r.dateEarned}</div>
                <div className="col-span-1">
                  {p ? (
                    <span className="px-1.5 py-0.5 rounded-md text-[11px] font-semibold" style={{ background: p.primaryColor, color: p.textColor }}>{p.code}</span>
                  ) : <span className="text-[11px] opacity-50">—</span>}
                </div>
                <div className="col-span-3 truncate font-semibold" title={isSale ? 'From a customer sale — edit on the customer record' : undefined}>
                  {isSale && <span className="mr-1" aria-label="From customer sale">🛒</span>}
                  {r.sourceLabel || '(no source)'}
                </div>
                <div className="col-span-3 text-xs opacity-70 truncate">{noteText}</div>
                <div className="col-span-1 font-mono text-right whitespace-nowrap">{fmtMoney(r.amount)}</div>
                <div className="col-span-2 flex justify-end items-center gap-1">
                  {isSale ? (
                    <span className="text-[11px] opacity-50 italic" title="Edit this sale from the customer's history">on customer</span>
                  ) : (
                    <>
                      <button type="button" className="pretty-button secondary" onClick={() => setDraft({
                        id: r.id,
                        dateEarned: r.dateEarned,
                        amount: r.amount,
                        personaCode: r.personaCode,
                        sourceLabel: r.sourceLabel,
                        note: r.note,
                      })}>Edit</button>
                      <ConfirmButton label="✕" confirmLabel="✕?" onConfirm={() => remove(r)} />
                    </>
                  )}
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
        <MoneyInput
          className="pretty-input font-mono"
          value={draft.amount}
          onChange={(amount) => onChange({ ...draft, amount })}
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
