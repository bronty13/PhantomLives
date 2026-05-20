import { useMemo, useState } from 'react';
import type { Cadence, Weekday } from '../../lib/cadence';
import {
  defaultCadence,
  describeCadence,
  isCadenceValid,
  isoDate,
  nextOccurrencesAfter,
  WEEKDAY_LABELS,
} from '../../lib/cadence';
import type { Persona } from '../../data/personas';
import type { Schedule } from '../../data/schedules';

interface Props {
  initial?: Schedule;
  personas: Persona[];
  onCancel: () => void;
  onSave: (next: Omit<Schedule, 'id' | 'createdAt' | 'updatedAt'> & { id?: number }) => void | Promise<void>;
}

type CadenceFamily = 'weekly' | 'monthly' | 'every_n_days' | 'daily';
type MonthlyFlavor = 'dom' | 'days_before_next' | 'days_after_eom';

function familyOf(c: Cadence): CadenceFamily {
  switch (c.kind) {
    case 'daily':                       return 'daily';
    case 'weekly':                      return 'weekly';
    case 'every_n_days':                return 'every_n_days';
    default:                            return 'monthly';
  }
}

function monthlyFlavorOf(c: Cadence): MonthlyFlavor {
  switch (c.kind) {
    case 'monthly_dom':                 return 'dom';
    case 'monthly_days_before_next':    return 'days_before_next';
    case 'monthly_days_after_eom':      return 'days_after_eom';
    default:                            return 'dom';
  }
}

export function ScheduleWizard({ initial, personas, onCancel, onSave }: Props) {
  const [name, setName] = useState(initial?.name ?? '');
  const [personaCode, setPersonaCode] = useState<string | null>(initial?.personaCode ?? null);
  const [notes, setNotes] = useState(initial?.notes ?? '');
  const [leadTimeDays, setLeadTimeDays] = useState(initial?.leadTimeDays ?? 0);
  const [active, setActive] = useState(initial?.active ?? true);
  const [cadence, setCadence] = useState<Cadence>(initial?.cadence ?? defaultCadence());

  const family = familyOf(cadence);
  const valid = name.trim() !== '' && isCadenceValid(cadence);

  const preview = useMemo(() => {
    if (!isCadenceValid(cadence)) return [];
    return nextOccurrencesAfter(cadence, new Date(), 5, true);
  }, [cadence]);

  function setFamily(f: CadenceFamily) {
    switch (f) {
      case 'daily':         setCadence({ kind: 'daily' }); break;
      case 'weekly':        setCadence({ kind: 'weekly', days: [1] }); break;
      case 'every_n_days':  setCadence({ kind: 'every_n_days', n: 3, anchor: isoDate(new Date()) }); break;
      case 'monthly':       setCadence({ kind: 'monthly_dom', day: 1 }); break;
    }
  }

  function setMonthlyFlavor(flavor: MonthlyFlavor) {
    switch (flavor) {
      case 'dom':              setCadence({ kind: 'monthly_dom', day: 1 }); break;
      case 'days_before_next': setCadence({ kind: 'monthly_days_before_next', daysBefore: 10 }); break;
      case 'days_after_eom':   setCadence({ kind: 'monthly_days_after_eom', daysAfter: 3 }); break;
    }
  }

  function toggleWeekday(day: Weekday) {
    if (cadence.kind !== 'weekly') return;
    const set = new Set(cadence.days);
    if (set.has(day)) set.delete(day);
    else set.add(day);
    setCadence({ ...cadence, days: [...set].sort() as Weekday[] });
  }

  async function save() {
    await onSave({
      id: initial?.id,
      name: name.trim(),
      personaCode,
      cadence,
      leadTimeDays,
      notes,
      active,
    });
  }

  const FAMILIES: { value: CadenceFamily; label: string }[] = [
    { value: 'weekly',       label: 'Weekly' },
    { value: 'monthly',      label: 'Monthly' },
    { value: 'every_n_days', label: 'Every N days' },
    { value: 'daily',        label: 'Every day' },
  ];

  return (
    <div className="pretty-card space-y-3">
      <div className="flex items-center justify-between">
        <h3 className="display-font text-xl font-semibold persona-accent">
          {initial ? 'Edit schedule' : 'New schedule'}
        </h3>
        <button type="button" className="pretty-button secondary" onClick={onCancel}>Cancel</button>
      </div>

      <label className="flex flex-col gap-1">
        <span className="text-xs uppercase tracking-wider opacity-60">What do you want to schedule?</span>
        <input
          className="pretty-input"
          placeholder="e.g. Post a new CoC tease video"
          value={name}
          onChange={(e) => setName(e.target.value)}
        />
      </label>

      <label className="flex flex-col gap-1">
        <span className="text-xs uppercase tracking-wider opacity-60">Persona (optional)</span>
        <select className="pretty-input" value={personaCode ?? ''} onChange={(e) => setPersonaCode(e.target.value || null)}>
          <option value="">(applies across personas)</option>
          {personas.map((p) => <option key={p.code} value={p.code}>{p.code} — {p.name}</option>)}
        </select>
      </label>

      <div>
        <div className="text-xs uppercase tracking-wider opacity-60 mb-1">Cadence</div>
        <div className="flex flex-wrap gap-1.5 mb-2">
          {FAMILIES.map((f) => {
            const isOn = family === f.value;
            return (
              <button
                key={f.value}
                type="button"
                onClick={() => setFamily(f.value)}
                className="px-3 py-1 rounded-full text-sm font-semibold"
                style={{
                  background: isOn ? 'rgb(var(--persona-accent))' : 'rgba(255,255,255,0.55)',
                  color: isOn ? 'white' : 'rgb(var(--persona-text))',
                  border: '1px solid rgb(var(--persona-primary) / 0.5)',
                }}
              >
                {f.label}
              </button>
            );
          })}
        </div>

        {cadence.kind === 'weekly' && (
          <div className="space-y-2">
            <div className="flex flex-wrap gap-1.5">
              {WEEKDAY_LABELS.map((label, idx) => {
                const isOn = cadence.days.includes(idx as Weekday);
                return (
                  <button
                    key={label}
                    type="button"
                    onClick={() => toggleWeekday(idx as Weekday)}
                    className="px-3 py-1 rounded-full text-sm font-semibold transition"
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
            <label className="flex items-center gap-2 text-sm">
              <span className="opacity-60">Repeat every</span>
              <input
                type="number"
                min={1}
                max={6}
                className="pretty-input w-20"
                value={cadence.everyN ?? 1}
                onChange={(e) => setCadence({ ...cadence, everyN: Math.max(1, Number(e.target.value) || 1) })}
              />
              <span className="opacity-60">week{(cadence.everyN ?? 1) === 1 ? '' : 's'}</span>
            </label>
          </div>
        )}

        {family === 'monthly' && (
          <MonthlyEditor cadence={cadence} flavor={monthlyFlavorOf(cadence)} setFlavor={setMonthlyFlavor} setCadence={setCadence} />
        )}

        {cadence.kind === 'every_n_days' && (
          <div className="flex items-center gap-2 text-sm">
            <span className="opacity-60">Every</span>
            <input
              type="number"
              min={1}
              max={365}
              className="pretty-input w-20"
              value={cadence.n}
              onChange={(e) => setCadence({ ...cadence, n: Math.max(1, Number(e.target.value) || 1) })}
            />
            <span className="opacity-60">days, anchored on</span>
            <input
              type="date"
              className="pretty-input"
              value={cadence.anchor}
              onChange={(e) => setCadence({ ...cadence, anchor: e.target.value })}
            />
          </div>
        )}

        {cadence.kind === 'daily' && (
          <div className="text-sm opacity-70 italic">Fires every day.</div>
        )}
      </div>

      <div className="text-sm">
        <div className="text-xs uppercase tracking-wider opacity-60 mb-1">Reads as</div>
        <div className="font-semibold persona-accent">{describeCadence(cadence)}</div>
      </div>

      <div>
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

      <div className="grid grid-cols-2 gap-3">
        <label className="flex flex-col gap-1">
          <span className="text-xs uppercase tracking-wider opacity-60">Lead-time reminder (days)</span>
          <input
            type="number"
            min={0}
            max={30}
            className="pretty-input w-32"
            value={leadTimeDays}
            onChange={(e) => setLeadTimeDays(Math.max(0, Number(e.target.value) || 0))}
          />
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-xs uppercase tracking-wider opacity-60">Active?</span>
          <div className="flex items-center gap-2 pt-2">
            <input
              type="checkbox"
              id="active"
              checked={active}
              onChange={(e) => setActive(e.target.checked)}
            />
            <label htmlFor="active" className="text-sm">Yes, materialize occurrences for this schedule</label>
          </div>
        </label>
      </div>

      <label className="flex flex-col gap-1">
        <span className="text-xs uppercase tracking-wider opacity-60">Notes</span>
        <textarea
          className="pretty-input"
          rows={2}
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          placeholder="Anything to remember when this fires…"
        />
      </label>

      <div className="flex justify-end gap-2">
        <button type="button" className="pretty-button secondary" onClick={onCancel}>Cancel</button>
        <button type="button" className="pretty-button" disabled={!valid} onClick={save}>
          {initial ? 'Save changes' : '✨ Create schedule'}
        </button>
      </div>
    </div>
  );
}

function MonthlyEditor({
  cadence,
  flavor,
  setFlavor,
  setCadence,
}: {
  cadence: Cadence;
  flavor: MonthlyFlavor;
  setFlavor: (f: MonthlyFlavor) => void;
  setCadence: (c: Cadence) => void;
}) {
  const FLAVORS: { value: MonthlyFlavor; label: string }[] = [
    { value: 'dom',              label: 'On the Nth' },
    { value: 'days_before_next', label: 'N days before next month' },
    { value: 'days_after_eom',   label: 'N days after the month ends' },
  ];

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap gap-1.5">
        {FLAVORS.map((f) => {
          const isOn = flavor === f.value;
          return (
            <button
              key={f.value}
              type="button"
              onClick={() => setFlavor(f.value)}
              className="px-3 py-1 rounded-full text-xs font-semibold"
              style={{
                background: isOn ? 'rgb(var(--persona-accent))' : 'transparent',
                color: isOn ? 'white' : 'rgb(var(--persona-text))',
                border: '1px solid rgb(var(--persona-primary))',
              }}
            >
              {f.label}
            </button>
          );
        })}
      </div>

      {cadence.kind === 'monthly_dom' && (
        <div className="flex items-center gap-2 text-sm">
          <span className="opacity-60">Day</span>
          <input
            type="number" min={1} max={31}
            className="pretty-input w-20"
            value={cadence.day}
            onChange={(e) => setCadence({ ...cadence, day: Math.max(1, Math.min(31, Number(e.target.value) || 1)) })}
          />
          <span className="opacity-60 italic text-xs">(clamped to last day on short months)</span>
        </div>
      )}

      {cadence.kind === 'monthly_days_before_next' && (
        <div className="flex items-center gap-2 text-sm">
          <input
            type="number" min={0} max={28}
            className="pretty-input w-20"
            value={cadence.daysBefore}
            onChange={(e) => setCadence({ ...cadence, daysBefore: Math.max(0, Math.min(28, Number(e.target.value) || 0)) })}
          />
          <span className="opacity-60">days before next month starts</span>
        </div>
      )}

      {cadence.kind === 'monthly_days_after_eom' && (
        <div className="flex items-center gap-2 text-sm">
          <input
            type="number" min={0} max={28}
            className="pretty-input w-20"
            value={cadence.daysAfter}
            onChange={(e) => setCadence({ ...cadence, daysAfter: Math.max(0, Math.min(28, Number(e.target.value) || 0)) })}
          />
          <span className="opacity-60">days after the current month ends</span>
        </div>
      )}
    </div>
  );
}
