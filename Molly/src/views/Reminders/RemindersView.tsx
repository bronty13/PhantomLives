import { useEffect, useState } from 'react';
import type { Persona } from '../../state/personas';
import {
  checkOff,
  describeDueDate,
  listComingUp,
  listOverdue,
  listRecentlyCompleted,
  listToday,
  materializeOccurrences,
  undoCheckOff,
  type Occurrence,
} from '../../data/occurrences';
import {
  createSchedule,
  deleteSchedule,
  listSchedules,
  updateSchedule,
  type Schedule,
} from '../../data/schedules';
import { describeCadence } from '../../lib/cadence';
import { listPersonas, type Persona as PersonaRow } from '../../data/personas';
import { ScheduleWizard } from './ScheduleWizard';
import { ConfirmButton } from '../../components/ConfirmButton';
import { CheckOffBurst } from '../../components/CheckOffBurst';
import { useAsyncRefresh } from '../../lib/useAsyncRefresh';

interface Props {
  active: Persona;
  onCountsChanged: () => void | Promise<void>;
}

type Tab = 'reminders' | 'schedules';

export function RemindersView({ active, onCountsChanged }: Props) {
  const [tab, setTab] = useState<Tab>('reminders');

  const [today, setToday] = useState<Occurrence[]>([]);
  const [upcoming, setUpcoming] = useState<Occurrence[]>([]);
  const [overdue, setOverdue] = useState<Occurrence[]>([]);
  const [recent, setRecent] = useState<Occurrence[]>([]);

  const [schedules, setSchedules] = useState<Schedule[]>([]);
  const [personas, setPersonas] = useState<PersonaRow[]>([]);

  const [editing, setEditing] = useState<Schedule | 'new' | null>(null);
  const [burst, setBurst] = useState<{ fire: number; color: string } | null>(null);
  const [undo, setUndo] = useState<{ occurrenceId: number; deadline: number } | null>(null);
  const [status, setStatus] = useState<string>('');

  const { loading, refresh } = useAsyncRefresh(async (alive) => {
    const opts = active.code === 'ALL' ? undefined : { personaCode: active.code };
    const [t, u, o, r, s, p] = await Promise.all([
      listToday(opts),
      listComingUp(opts),
      listOverdue(opts),
      listRecentlyCompleted(opts),
      listSchedules(),
      listPersonas(),
    ]);
    if (!alive()) return;
    setToday(t);
    setUpcoming(u);
    setOverdue(o);
    setRecent(r);
    setSchedules(s);
    setPersonas(p);
    try { await onCountsChanged(); } catch (e) { console.warn('onCountsChanged failed', e); }
  }, [active.code]);

  // Auto-clear the undo toast.
  useEffect(() => {
    if (!undo) return;
    const ms = undo.deadline - Date.now();
    if (ms <= 0) { setUndo(null); return; }
    const t = setTimeout(() => setUndo(null), ms);
    return () => clearTimeout(t);
  }, [undo]);

  async function onCheckOff(o: Occurrence) {
    try {
      const p = o.personaCode ? personas.find((x) => x.code === o.personaCode) : null;
      const color = p?.primaryColor ?? '#FFC0CB';
      setBurst({ fire: Date.now(), color });
      await checkOff(o.id);
      setUndo({ occurrenceId: o.id, deadline: Date.now() + 10_000 });
      await refresh();
    } catch (e) {
      setStatus(`Couldn't check off: ${String(e)}`);
    }
  }

  async function onUndo() {
    if (!undo) return;
    try {
      await undoCheckOff(undo.occurrenceId);
      setUndo(null);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't undo: ${String(e)}`);
    }
  }

  async function saveSchedule(s: Omit<Schedule, 'id' | 'createdAt' | 'updatedAt'> & { id?: number }) {
    try {
      if (s.id) {
        await updateSchedule({ ...s, id: s.id, createdAt: '', updatedAt: '' });
        setStatus(`Saved ${s.name}.`);
      } else {
        await createSchedule(s);
        setStatus(`Created ${s.name}.`);
      }
      setEditing(null);
      // Materialize any new occurrences for the changed schedule.
      await materializeOccurrences();
      await refresh();
    } catch (e) {
      setStatus(`Couldn't save: ${String(e)}`);
    }
  }

  async function removeSchedule(s: Schedule) {
    try {
      await deleteSchedule(s.id);
      setStatus(`Removed ${s.name}.`);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't delete: ${String(e)}`);
    }
  }

  async function toggleActive(s: Schedule) {
    try {
      await updateSchedule({ ...s, active: !s.active });
      if (!s.active) await materializeOccurrences();
      await refresh();
    } catch (e) {
      setStatus(`Couldn't toggle: ${String(e)}`);
    }
  }

  const personaByCode = new Map(personas.map((p) => [p.code, p]));

  return (
    <div className="p-8 max-w-5xl space-y-4">
      <div className="flex items-end justify-between gap-3">
        <div>
          <h2 className="display-font text-2xl font-bold persona-accent">Reminders</h2>
          <p className="opacity-70 text-sm">
            {active.code === 'ALL' ? 'Everything that wants your attention.' : `${active.name}'s upcoming work.`}
          </p>
        </div>
        <div className="flex items-center gap-1.5">
          {(['reminders', 'schedules'] as Tab[]).map((t) => {
            const isOn = tab === t;
            return (
              <button
                key={t}
                type="button"
                onClick={() => setTab(t)}
                className="px-3.5 py-1.5 rounded-full text-sm font-semibold"
                style={{
                  background: isOn ? 'rgb(var(--persona-accent))' : 'rgba(255,255,255,0.55)',
                  color: isOn ? 'white' : 'rgb(var(--persona-text))',
                  border: '1px solid rgb(var(--persona-primary) / 0.45)',
                }}
              >
                {t === 'reminders' ? 'Reminders' : 'Schedules'}
              </button>
            );
          })}
        </div>
      </div>

      {tab === 'reminders' && loading && overdue.length === 0 && today.length === 0 && upcoming.length === 0 && recent.length === 0 && (
        <div className="pretty-card text-sm opacity-60 italic">Loading reminders…</div>
      )}
      {tab === 'reminders' && (
        <>
          <Section title={overdue.length > 0 ? `⏰ Overdue (${overdue.length})` : '⏰ Overdue'} items={overdue} personaByCode={personaByCode} onCheckOff={onCheckOff} emptyText="Nothing overdue. You're winning." overdue />
          <Section title={`💖 Today (${today.length})`} items={today} personaByCode={personaByCode} onCheckOff={onCheckOff} emptyText="Nothing due today — go make something pretty." />
          <Section title="🌷 Coming up (next 7 days)" items={upcoming} personaByCode={personaByCode} onCheckOff={onCheckOff} emptyText="Quiet week ahead." />

          {recent.length > 0 && (
            <div className="pretty-card">
              <h3 className="display-font text-lg font-semibold persona-accent mb-2">✨ Recently done</h3>
              <div className="space-y-1.5">
                {recent.map((o) => (
                  <div key={o.id} className="flex items-center justify-between text-sm py-1.5 px-2 rounded-lg" style={{ background: 'rgb(var(--persona-tint))' }}>
                    <div>
                      <span className="line-through opacity-70">{o.scheduleName}</span>
                      <span className="ml-2 text-xs opacity-60">{o.dueAt} → ✓ {o.completedAt?.slice(0, 16).replace('T', ' ')}</span>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </>
      )}

      {tab === 'schedules' && (
        <>
          <div className="flex items-center justify-between">
            <p className="text-sm opacity-70">Manage what fires when. New occurrences materialize automatically out 60 days.</p>
            <button type="button" className="pretty-button" onClick={() => setEditing('new')}>✨ New schedule</button>
          </div>

          {editing === 'new' && (
            <ScheduleWizard
              personas={personas}
              onCancel={() => setEditing(null)}
              onSave={saveSchedule}
            />
          )}

          <div className="space-y-2">
            {schedules.map((s) => {
              const isEditing = editing && editing !== 'new' && editing.id === s.id;
              const persona = s.personaCode ? personaByCode.get(s.personaCode) : null;
              return (
                <div key={s.id} className="pretty-card">
                  <div className="flex items-center justify-between gap-3">
                    <div>
                      <div className="flex items-center gap-2">
                        {persona ? (
                          <span className="px-2 py-0.5 rounded-md text-[11px] font-semibold" style={{ background: persona.primaryColor, color: persona.textColor }}>
                            {persona.code}
                          </span>
                        ) : (
                          <span className="px-2 py-0.5 rounded-md text-[11px] font-semibold bg-black/10">ALL</span>
                        )}
                        <span className="font-semibold">{s.name}</span>
                        {!s.active && <span className="text-[11px] uppercase opacity-50">paused</span>}
                      </div>
                      <div className="text-xs opacity-70 mt-0.5">{describeCadence(s.cadence)}</div>
                      {s.notes && <div className="text-xs opacity-70 italic mt-0.5">{s.notes}</div>}
                    </div>
                    <div className="flex items-center gap-2">
                      <button type="button" className="pretty-button secondary" onClick={() => toggleActive(s)}>
                        {s.active ? 'Pause' : 'Resume'}
                      </button>
                      <button type="button" className="pretty-button secondary" onClick={() => setEditing(isEditing ? null : s)}>
                        {isEditing ? 'Cancel' : 'Edit'}
                      </button>
                      <ConfirmButton label="Delete" confirmLabel="Confirm?" onConfirm={() => removeSchedule(s)} />
                    </div>
                  </div>
                  {isEditing && (
                    <div className="mt-3">
                      <ScheduleWizard
                        initial={s}
                        personas={personas}
                        onCancel={() => setEditing(null)}
                        onSave={saveSchedule}
                      />
                    </div>
                  )}
                </div>
              );
            })}
            {schedules.length === 0 && (
              <div className="pretty-card text-sm opacity-70 italic">No schedules yet — click <strong>New schedule</strong>.</div>
            )}
          </div>
        </>
      )}

      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}

      {undo && (
        <div className="fixed bottom-4 right-4 pretty-card flex items-center gap-3 z-40 shadow-lg">
          <span className="text-sm">✓ Done! Want to take it back?</span>
          <button type="button" className="pretty-button secondary" onClick={onUndo}>Undo</button>
        </div>
      )}

      {burst && <CheckOffBurst fire={burst.fire} color={burst.color} />}
    </div>
  );
}

function Section({
  title, items, personaByCode, onCheckOff, emptyText, overdue,
}: {
  title: string;
  items: Occurrence[];
  personaByCode: Map<string, PersonaRow>;
  onCheckOff: (o: Occurrence) => void | Promise<void>;
  emptyText: string;
  overdue?: boolean;
}) {
  return (
    <div className="pretty-card">
      <h3 className="display-font text-lg font-semibold persona-accent mb-2">{title}</h3>
      {items.length === 0 && <div className="text-sm opacity-70 italic">{emptyText}</div>}
      <div className="space-y-2">
        {items.map((o) => {
          const persona = o.personaCode ? personaByCode.get(o.personaCode) : null;
          const color = persona?.primaryColor ?? '#A16D9C';
          return (
            <div
              key={o.id}
              className="flex items-center gap-3 p-2.5 rounded-xl"
              style={{
                background: overdue ? 'rgba(254, 226, 226, 0.4)' : 'rgb(var(--persona-tint))',
                border: `1px solid ${overdue ? '#fca5a5' : 'rgb(var(--persona-primary) / 0.35)'}`,
              }}
            >
              <button
                type="button"
                onClick={() => onCheckOff(o)}
                className="w-7 h-7 rounded-full grid place-items-center transition"
                style={{
                  background: 'white',
                  border: `2px solid ${color}`,
                }}
                title="Check off"
              >
                <span style={{ color, fontSize: 16, lineHeight: 1 }}>✓</span>
              </button>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  {persona ? (
                    <span className="px-1.5 py-0.5 rounded-md text-[11px] font-semibold" style={{ background: persona.primaryColor, color: persona.textColor }}>
                      {persona.code}
                    </span>
                  ) : (
                    <span className="px-1.5 py-0.5 rounded-md text-[11px] font-semibold bg-black/10">ALL</span>
                  )}
                  <span className="font-semibold">{o.scheduleName}</span>
                </div>
                <div className="text-xs opacity-70">{describeDueDate(o.dueAt)} · <span className="font-mono">{o.dueAt}</span></div>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
