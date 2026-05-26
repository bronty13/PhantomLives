import { useMemo, useState } from 'react';
import type { Persona } from '../../state/personas';
import {
  createExpense,
  deleteExpense,
  listExpenses,
  netAmount,
  updateExpense,
  type Expense,
} from '../../data/expenses';
import { listPersonas, type Persona as PersonaRow } from '../../data/personas';
import { fmtMoney, MONTH_NAMES, todayParts } from '../../lib/money';
import { ConfirmButton } from '../../components/ConfirmButton';
import { AttachmentField } from '../../components/AttachmentField';
import { MoneyInput } from '../../components/MoneyInput';
import { playCashRegister } from '../../lib/soundFx';
import { useAsyncRefresh } from '../../lib/useAsyncRefresh';

interface Props {
  active: Persona;
}

const EMPTY = (personaCode: string | null): Omit<Expense, 'id' | 'createdAt' | 'updatedAt'> => {
  const t = new Date();
  const iso = `${t.getFullYear()}-${(t.getMonth() + 1).toString().padStart(2, '0')}-${t.getDate().toString().padStart(2, '0')}`;
  return {
    actualDate: iso,
    effectiveDate: iso,
    description: '',
    note: '',
    attachmentPath: null,
    amount: 0,
    personaCode,
    excluded: false,
    exclusionAmount: null,
    recurringId: null,
  };
};

export function ExpenseListView({ active }: Props) {
  const t = todayParts();
  const [year, setYear] = useState<number>(t.year);
  const [month, setMonth] = useState<number | 'all'>(t.month);
  const [rows, setRows] = useState<Expense[]>([]);
  const [personas, setPersonas] = useState<PersonaRow[]>([]);
  const [draft, setDraft] = useState<(Omit<Expense, 'id' | 'createdAt' | 'updatedAt'> & { id?: number }) | null>(null);
  const [status, setStatus] = useState('');

  const { loading, refresh } = useAsyncRefresh(async (alive) => {
    const filter: { year?: number; month?: number; personaCode?: string } = {
      year, personaCode: active.code,
    };
    if (month !== 'all') filter.month = month;
    const [list, p] = await Promise.all([listExpenses(filter), listPersonas()]);
    if (!alive()) return;
    setRows(list);
    setPersonas(p);
  }, [year, month, active.code]);

  const gross = useMemo(() => rows.reduce((acc, r) => acc + r.amount, 0), [rows]);
  const net = useMemo(() => rows.reduce((acc, r) => acc + netAmount(r), 0), [rows]);
  const excludedTotal = gross - net;
  const personaByCode = useMemo(() => new Map(personas.map((p) => [p.code, p])), [personas]);

  async function save() {
    if (!draft) return;
    try {
      const isNew = !draft.id;
      if (draft.id) {
        await updateExpense({ ...draft, id: draft.id, createdAt: '', updatedAt: '' } as Expense);
      } else {
        await createExpense(draft);
      }
      // Sound only — no encouragement toast for expenses; spending
      // money isn't the moment Sallie needs to be cheered on.
      if (isNew) playCashRegister();
      setDraft(null);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't save: ${String(e)}`);
    }
  }

  async function remove(row: Expense) {
    try {
      await deleteExpense(row.id);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't delete: ${String(e)}`);
    }
  }

  const yearOptions: number[] = [];
  for (let y = t.year + 1; y >= 2024; y--) yearOptions.push(y);

  return (
    <div className="p-8 max-w-6xl space-y-4">
      <div className="flex items-end justify-between gap-3">
        <div>
          <h2 className="display-font text-2xl font-bold persona-accent">Expenses</h2>
          <p className="opacity-70 text-sm">Receipts, subscriptions, supplies. Full or partial exclusion supported for personal/business splits.</p>
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
          <button type="button" className="pretty-button" onClick={() => setDraft(EMPTY(active.code === 'ALL' ? null : active.code))}>✨ Add expense</button>
        </div>
      </div>

      <div className="grid grid-cols-3 gap-3">
        <Stat title="Gross" value={fmtMoney(gross)} sub={`${rows.length} expense${rows.length === 1 ? '' : 's'}`} />
        <Stat title="Net (reportable)" value={fmtMoney(net)} sub="after exclusions" />
        <Stat title="Excluded" value={fmtMoney(excludedTotal)} sub="personal / not deductible" />
      </div>

      {draft && (
        <ExpenseEditor
          draft={draft}
          personas={personas}
          onChange={setDraft}
          onCancel={() => setDraft(null)}
          onSave={save}
        />
      )}

      <div className="pretty-card">
        {loading && <div className="text-sm opacity-60 italic">Loading expenses…</div>}
        {!loading && rows.length === 0 && <div className="text-sm opacity-70 italic">Nothing here yet. Click <strong>Add expense</strong>.</div>}
        <div className="divide-y divide-black/5">
          {rows.map((r) => {
            const p = r.personaCode ? personaByCode.get(r.personaCode) : null;
            const n = netAmount(r);
            return (
              <div key={r.id} className="grid grid-cols-12 gap-2 items-center py-2 text-sm">
                <div className="col-span-2 font-mono opacity-70">{r.effectiveDate}</div>
                <div className="col-span-1">
                  {p ? (
                    <span className="px-1.5 py-0.5 rounded-md text-[11px] font-semibold" style={{ background: p.primaryColor, color: p.textColor }}>{p.code}</span>
                  ) : <span className="text-[11px] opacity-50">—</span>}
                </div>
                <div className="col-span-4 truncate">
                  <div className="font-semibold">{r.description || '(no description)'}</div>
                  <div className="text-xs opacity-60 truncate">{r.note}</div>
                </div>
                <div className="col-span-2 text-xs opacity-70">
                  {r.attachmentPath && '📎 '}
                  {r.recurringId && '🔁 '}
                  {r.excluded && '⛔ excluded'}
                  {!r.excluded && r.exclusionAmount ? `↘︎ ${fmtMoney(r.exclusionAmount)} excluded` : null}
                </div>
                <div className="col-span-1 font-mono text-right">{fmtMoney(r.amount)}</div>
                <div className="col-span-1 font-mono text-right" style={{ color: n === r.amount ? undefined : '#7a2a52' }}>{fmtMoney(n)}</div>
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

function Stat({ title, value, sub }: { title: string; value: string; sub: string }) {
  return (
    <div className="pretty-card">
      <div className="text-xs uppercase tracking-wider opacity-60">{title}</div>
      <div className="display-font text-2xl font-bold persona-accent mt-1">{value}</div>
      <div className="text-xs opacity-70 mt-1">{sub}</div>
    </div>
  );
}

function ExpenseEditor({
  draft, personas, onChange, onCancel, onSave,
}: {
  draft: (Omit<Expense, 'id' | 'createdAt' | 'updatedAt'> & { id?: number });
  personas: PersonaRow[];
  onChange: (d: typeof draft) => void;
  onCancel: () => void;
  onSave: () => void | Promise<void>;
}) {
  return (
    <div className="pretty-card grid grid-cols-12 gap-3">
      <label className="flex flex-col gap-1 col-span-3">
        <span className="text-xs uppercase tracking-wider opacity-60">Actual date</span>
        <input type="date" className="pretty-input" value={draft.actualDate} onChange={(e) => onChange({ ...draft, actualDate: e.target.value })} />
      </label>
      <label className="flex flex-col gap-1 col-span-3">
        <span className="text-xs uppercase tracking-wider opacity-60">Effective date (reporting)</span>
        <input type="date" className="pretty-input" value={draft.effectiveDate} onChange={(e) => onChange({ ...draft, effectiveDate: e.target.value })} />
      </label>
      <label className="flex flex-col gap-1 col-span-3">
        <span className="text-xs uppercase tracking-wider opacity-60">Persona</span>
        <select className="pretty-input" value={draft.personaCode ?? ''} onChange={(e) => onChange({ ...draft, personaCode: e.target.value || null })}>
          <option value="">(unassigned)</option>
          {personas.map((p) => <option key={p.code} value={p.code}>{p.code} — {p.name}</option>)}
        </select>
      </label>
      <label className="flex flex-col gap-1 col-span-3">
        <span className="text-xs uppercase tracking-wider opacity-60">Amount</span>
        <MoneyInput
          className="pretty-input font-mono"
          value={draft.amount}
          onChange={(amount) => onChange({ ...draft, amount })}
        />
      </label>
      <label className="flex flex-col gap-1 col-span-6">
        <span className="text-xs uppercase tracking-wider opacity-60">Description</span>
        <input className="pretty-input" placeholder="What was it?" value={draft.description} onChange={(e) => onChange({ ...draft, description: e.target.value })} />
      </label>
      <label className="flex flex-col gap-1 col-span-6">
        <span className="text-xs uppercase tracking-wider opacity-60">Note</span>
        <input className="pretty-input" value={draft.note} onChange={(e) => onChange({ ...draft, note: e.target.value })} />
      </label>

      <div className="col-span-6">
        <span className="text-xs uppercase tracking-wider opacity-60 block mb-1">Receipt / attachment</span>
        <AttachmentField
          value={draft.attachmentPath}
          onChange={(rel) => onChange({ ...draft, attachmentPath: rel })}
          category="expenses"
        />
      </div>

      <div className="col-span-6 flex flex-col gap-1">
        <span className="text-xs uppercase tracking-wider opacity-60">Exclude from reports</span>
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={draft.excluded}
            onChange={(e) => onChange({ ...draft, excluded: e.target.checked, exclusionAmount: e.target.checked ? null : draft.exclusionAmount })}
          />
          Fully exclude this expense
        </label>
        {!draft.excluded && (
          <label className="flex items-center gap-2 text-sm">
            <span className="opacity-60">…or partial exclusion:</span>
            <MoneyInput
              className="pretty-input font-mono w-32"
              value={draft.exclusionAmount ?? 0}
              // 0 is the "no partial exclusion" sentinel; map back to null
              // so the schema's nullable column stays semantically distinct
              // from "$0 excluded." Sallie isn't going to enter a $0 partial.
              onChange={(n) => onChange({ ...draft, exclusionAmount: n === 0 ? null : n })}
            />
          </label>
        )}
      </div>

      <div className="col-span-12 flex justify-end gap-2">
        <button type="button" className="pretty-button secondary" onClick={onCancel}>Cancel</button>
        <button type="button" className="pretty-button" onClick={onSave}>Save</button>
      </div>
    </div>
  );
}
