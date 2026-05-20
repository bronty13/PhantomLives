import { useMemo, useState } from 'react';
import {
  createRecurring,
  deleteRecurring,
  listRecurring,
  materializeRecurringExpenses,
  updateRecurring,
  type RecurringExpense,
} from '../../data/expenses';
import { listPersonas, type Persona as PersonaRow } from '../../data/personas';
import type { Cadence, Weekday } from '../../lib/cadence';
import {
  defaultCadence,
  describeCadence,
  isCadenceValid,
  isoDate,
  nextOccurrencesAfter,
  WEEKDAY_LABELS,
} from '../../lib/cadence';
import { fmtMoney, parseMoney } from '../../lib/money';
import { ConfirmButton } from '../../components/ConfirmButton';
import { useAsyncRefresh } from '../../lib/useAsyncRefresh';

type Family = 'weekly' | 'monthly' | 'every_n_days' | 'daily';
type MonthlyFlavor = 'dom' | 'days_before_next' | 'days_after_eom';

interface Props {
  onChanged: () => void | Promise<void>;
}

const EMPTY = (personaCode: string | null): Omit<RecurringExpense, 'id' | 'lastMaterial'> => ({
  description: '',
  amount: 0,
  personaCode,
  cadence: { kind: 'monthly_dom', day: 1 },
  anchorDate: isoDate(new Date()),
  note: '',
  active: true,
});

export function RecurringExpensesView({ onChanged }: Props) {
  const [rows, setRows] = useState<RecurringExpense[]>([]);
  const [personas, setPersonas] = useState<PersonaRow[]>([]);
  const [draft, setDraft] = useState<(Omit<RecurringExpense, 'id' | 'lastMaterial'> & { id?: number }) | null>(null);
  const [status, setStatus] = useState('');

  const { loading, refresh } = useAsyncRefresh(async (alive) => {
    const [list, p] = await Promise.all([listRecurring(), listPersonas()]);
    if (!alive()) return;
    setRows(list);
    setPersonas(p);
  }, []);

  async function save() {
    if (!draft) return;
    try {
      if (draft.id) {
        await updateRecurring({ ...draft, id: draft.id, lastMaterial: null });
      } else {
        await createRecurring(draft);
      }
      setDraft(null);
      await materializeRecurringExpenses();
      await refresh();
      await onChanged();
      setStatus('Saved.');
    } catch (e) {
      setStatus(`Couldn't save: ${String(e)}`);
    }
  }

  async function remove(r: RecurringExpense) {
    try {
      await deleteRecurring(r.id);
      await refresh();
      await onChanged();
    } catch (e) {
      setStatus(`Couldn't delete: ${String(e)}`);
    }
  }

  async function toggleActive(r: RecurringExpense) {
    try {
      await updateRecurring({ ...r, active: !r.active });
      await refresh();
    } catch (e) {
      setStatus(`Couldn't toggle: ${String(e)}`);
    }
  }

  const personaByCode = useMemo(() => new Map(personas.map((p) => [p.code, p])), [personas]);

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <p className="text-sm opacity-70">
          Recurring expenses (subscriptions, monthly fees). Each fire date materializes into the expense journal.
        </p>
        <button type="button" className="pretty-button" onClick={() => setDraft(EMPTY(null))}>✨ Add recurring</button>
      </div>

      {draft && (
        <RecurringEditor
          draft={draft}
          personas={personas}
          onChange={setDraft}
          onCancel={() => setDraft(null)}
          onSave={save}
        />
      )}

      <div className="space-y-2">
        {rows.map((r) => {
          const isEditing = draft && draft.id === r.id;
          const p = r.personaCode ? personaByCode.get(r.personaCode) : null;
          return (
            <div key={r.id} className="pretty-card">
              <div className="flex items-center justify-between gap-3">
                <div>
                  <div className="flex items-center gap-2">
                    {p ? (
                      <span className="px-2 py-0.5 rounded-md text-[11px] font-semibold" style={{ background: p.primaryColor, color: p.textColor }}>{p.code}</span>
                    ) : (
                      <span className="px-2 py-0.5 rounded-md text-[11px] font-semibold bg-black/10">ALL</span>
                    )}
                    <span className="font-semibold">{r.description}</span>
                    <span className="font-mono">{fmtMoney(r.amount)}</span>
                    {!r.active && <span className="text-[11px] uppercase opacity-50">paused</span>}
                  </div>
                  <div className="text-xs opacity-70 mt-0.5">{describeCadence(r.cadence)} · anchored {r.anchorDate}</div>
                  {r.note && <div className="text-xs opacity-70 italic mt-0.5">{r.note}</div>}
                </div>
                <div className="flex items-center gap-2">
                  <button type="button" className="pretty-button secondary" onClick={() => toggleActive(r)}>
                    {r.active ? 'Pause' : 'Resume'}
                  </button>
                  <button type="button" className="pretty-button secondary" onClick={() => setDraft(isEditing ? null : { ...r })}>
                    {isEditing ? 'Cancel' : 'Edit'}
                  </button>
                  <ConfirmButton label="Delete" confirmLabel="Confirm?" onConfirm={() => remove(r)} />
                </div>
              </div>
            </div>
          );
        })}
        {loading && rows.length === 0 && (
          <div className="pretty-card text-sm opacity-60 italic">Loading recurring expenses…</div>
        )}
        {!loading && rows.length === 0 && !draft && (
          <div className="pretty-card text-sm opacity-70 italic">No recurring expenses yet — click <strong>Add recurring</strong>.</div>
        )}
      </div>

      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}

function RecurringEditor({
  draft, personas, onChange, onCancel, onSave,
}: {
  draft: (Omit<RecurringExpense, 'id' | 'lastMaterial'> & { id?: number });
  personas: PersonaRow[];
  onChange: (d: typeof draft) => void;
  onCancel: () => void;
  onSave: () => void | Promise<void>;
}) {
  const family: Family = (() => {
    switch (draft.cadence.kind) {
      case 'daily':         return 'daily';
      case 'weekly':        return 'weekly';
      case 'every_n_days':  return 'every_n_days';
      default:              return 'monthly';
    }
  })();
  const monthlyFlavor: MonthlyFlavor = (() => {
    switch (draft.cadence.kind) {
      case 'monthly_dom':                 return 'dom';
      case 'monthly_days_before_next':    return 'days_before_next';
      case 'monthly_days_after_eom':      return 'days_after_eom';
      default:                            return 'dom';
    }
  })();

  function setFamily(f: Family) {
    let cadence: Cadence;
    switch (f) {
      case 'daily':         cadence = { kind: 'daily' }; break;
      case 'weekly':        cadence = { kind: 'weekly', days: [1] }; break;
      case 'every_n_days':  cadence = { kind: 'every_n_days', n: 30, anchor: draft.anchorDate }; break;
      case 'monthly':       cadence = defaultCadence().kind === 'weekly' ? { kind: 'monthly_dom', day: 1 } : defaultCadence();
                            if (cadence.kind !== 'monthly_dom') cadence = { kind: 'monthly_dom', day: 1 };
                            break;
    }
    onChange({ ...draft, cadence });
  }

  function setMonthlyFlavor(flavor: MonthlyFlavor) {
    let cadence: Cadence;
    switch (flavor) {
      case 'dom':              cadence = { kind: 'monthly_dom', day: 1 }; break;
      case 'days_before_next': cadence = { kind: 'monthly_days_before_next', daysBefore: 10 }; break;
      case 'days_after_eom':   cadence = { kind: 'monthly_days_after_eom', daysAfter: 3 }; break;
    }
    onChange({ ...draft, cadence });
  }

  function toggleWeekday(day: Weekday) {
    if (draft.cadence.kind !== 'weekly') return;
    const set = new Set(draft.cadence.days);
    if (set.has(day)) set.delete(day); else set.add(day);
    onChange({ ...draft, cadence: { ...draft.cadence, days: [...set].sort() as Weekday[] } });
  }

  const preview = isCadenceValid(draft.cadence)
    ? nextOccurrencesAfter(draft.cadence, new Date(), 5, true)
    : [];
  const valid = draft.description.trim() !== '' && isCadenceValid(draft.cadence);

  return (
    <div className="pretty-card grid grid-cols-12 gap-3">
      <label className="flex flex-col gap-1 col-span-5">
        <span className="text-xs uppercase tracking-wider opacity-60">Description</span>
        <input
          className="pretty-input"
          placeholder="e.g. Adobe CC, Backblaze, gym"
          value={draft.description}
          onChange={(e) => onChange({ ...draft, description: e.target.value })}
        />
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
        <span className="text-xs uppercase tracking-wider opacity-60">Persona</span>
        <select className="pretty-input" value={draft.personaCode ?? ''} onChange={(e) => onChange({ ...draft, personaCode: e.target.value || null })}>
          <option value="">(unassigned)</option>
          {personas.map((p) => <option key={p.code} value={p.code}>{p.code} — {p.name}</option>)}
        </select>
      </label>
      <label className="flex flex-col gap-1 col-span-2">
        <span className="text-xs uppercase tracking-wider opacity-60">Anchor</span>
        <input type="date" className="pretty-input" value={draft.anchorDate} onChange={(e) => onChange({ ...draft, anchorDate: e.target.value })} />
      </label>

      <div className="col-span-12">
        <div className="text-xs uppercase tracking-wider opacity-60 mb-1">Cadence</div>
        <div className="flex flex-wrap gap-1.5 mb-2">
          {([
            { v: 'monthly', l: 'Monthly' },
            { v: 'weekly', l: 'Weekly' },
            { v: 'every_n_days', l: 'Every N days' },
            { v: 'daily', l: 'Daily' },
          ] as { v: Family; l: string }[]).map((f) => {
            const isOn = family === f.v;
            return (
              <button
                key={f.v}
                type="button"
                onClick={() => setFamily(f.v)}
                className="px-3 py-1 rounded-full text-sm font-semibold"
                style={{
                  background: isOn ? 'rgb(var(--persona-accent))' : 'rgba(255,255,255,0.55)',
                  color: isOn ? 'white' : 'rgb(var(--persona-text))',
                  border: '1px solid rgb(var(--persona-primary) / 0.5)',
                }}
              >
                {f.l}
              </button>
            );
          })}
        </div>

        {family === 'weekly' && draft.cadence.kind === 'weekly' && (
          <div className="flex flex-wrap gap-1.5">
            {WEEKDAY_LABELS.map((label, idx) => {
              const isOn = draft.cadence.kind === 'weekly' && draft.cadence.days.includes(idx as Weekday);
              return (
                <button
                  key={label}
                  type="button"
                  onClick={() => toggleWeekday(idx as Weekday)}
                  className="px-3 py-1 rounded-full text-sm font-semibold"
                  style={{
                    background: isOn ? 'rgb(var(--persona-accent))' : 'transparent',
                    color: isOn ? 'white' : 'rgb(var(--persona-text))',
                    border: '1px solid rgb(var(--persona-primary))',
                  }}
                >
                  {label}
                </button>
              );
            })}
          </div>
        )}

        {family === 'monthly' && (
          <div className="space-y-2">
            <div className="flex flex-wrap gap-1.5">
              {([
                { v: 'dom',              l: 'On the Nth' },
                { v: 'days_before_next', l: 'N days before next month' },
                { v: 'days_after_eom',   l: 'N days after month ends' },
              ] as { v: MonthlyFlavor; l: string }[]).map((f) => {
                const isOn = monthlyFlavor === f.v;
                return (
                  <button
                    key={f.v}
                    type="button"
                    onClick={() => setMonthlyFlavor(f.v)}
                    className="px-3 py-1 rounded-full text-xs font-semibold"
                    style={{
                      background: isOn ? 'rgb(var(--persona-accent))' : 'transparent',
                      color: isOn ? 'white' : 'rgb(var(--persona-text))',
                      border: '1px solid rgb(var(--persona-primary))',
                    }}
                  >
                    {f.l}
                  </button>
                );
              })}
            </div>
            {draft.cadence.kind === 'monthly_dom' && (
              <div className="flex items-center gap-2 text-sm">
                <span className="opacity-60">Day</span>
                <input type="number" min={1} max={31} className="pretty-input w-20" value={draft.cadence.day}
                  onChange={(e) => onChange({ ...draft, cadence: { kind: 'monthly_dom', day: Math.max(1, Math.min(31, Number(e.target.value) || 1)) } })} />
              </div>
            )}
            {draft.cadence.kind === 'monthly_days_before_next' && (
              <div className="flex items-center gap-2 text-sm">
                <input type="number" min={0} max={28} className="pretty-input w-20" value={draft.cadence.daysBefore}
                  onChange={(e) => onChange({ ...draft, cadence: { kind: 'monthly_days_before_next', daysBefore: Math.max(0, Math.min(28, Number(e.target.value) || 0)) } })} />
                <span className="opacity-60">days before next month starts</span>
              </div>
            )}
            {draft.cadence.kind === 'monthly_days_after_eom' && (
              <div className="flex items-center gap-2 text-sm">
                <input type="number" min={0} max={28} className="pretty-input w-20" value={draft.cadence.daysAfter}
                  onChange={(e) => onChange({ ...draft, cadence: { kind: 'monthly_days_after_eom', daysAfter: Math.max(0, Math.min(28, Number(e.target.value) || 0)) } })} />
                <span className="opacity-60">days after the current month ends</span>
              </div>
            )}
          </div>
        )}

        {family === 'every_n_days' && draft.cadence.kind === 'every_n_days' && (
          <div className="flex items-center gap-2 text-sm">
            <span className="opacity-60">Every</span>
            <input type="number" min={1} max={365} className="pretty-input w-20" value={draft.cadence.n}
              onChange={(e) => onChange({ ...draft, cadence: { kind: 'every_n_days', n: Math.max(1, Number(e.target.value) || 1), anchor: draft.cadence.kind === 'every_n_days' ? draft.cadence.anchor : draft.anchorDate } })} />
            <span className="opacity-60">days</span>
          </div>
        )}

        {family === 'daily' && <div className="text-sm opacity-70 italic">Fires every day.</div>}
      </div>

      <div className="col-span-12 text-sm">
        <div className="text-xs uppercase tracking-wider opacity-60 mb-1">Reads as</div>
        <div className="font-semibold persona-accent">{describeCadence(draft.cadence)}</div>
      </div>

      <div className="col-span-12">
        <div className="text-xs uppercase tracking-wider opacity-60 mb-1">Next 5 dates</div>
        <div className="flex flex-wrap gap-1.5">
          {preview.length === 0 && <span className="text-xs italic opacity-60">Choose at least one day…</span>}
          {preview.map((d) => (
            <span key={d} className="px-2 py-0.5 rounded-md text-xs font-mono" style={{ background: 'rgb(var(--persona-tint))', border: '1px solid rgb(var(--persona-primary) / 0.45)' }}>
              {d}
            </span>
          ))}
        </div>
      </div>

      <label className="flex flex-col gap-1 col-span-9">
        <span className="text-xs uppercase tracking-wider opacity-60">Note</span>
        <input className="pretty-input" value={draft.note} onChange={(e) => onChange({ ...draft, note: e.target.value })} />
      </label>
      <label className="flex items-center gap-2 text-sm col-span-3 pt-5">
        <input type="checkbox" checked={draft.active} onChange={(e) => onChange({ ...draft, active: e.target.checked })} />
        Active
      </label>

      <div className="col-span-12 flex justify-end gap-2">
        <button type="button" className="pretty-button secondary" onClick={onCancel}>Cancel</button>
        <button type="button" className="pretty-button" disabled={!valid} onClick={onSave}>Save</button>
      </div>
    </div>
  );
}
