import { useMemo, useState } from 'react';
import type { Persona } from '../../state/personas';
import { listClips, type Clip } from '../../data/clips';
import { listOccurrencesInRange, type Occurrence } from '../../data/occurrences';
import { listPersonas, type Persona as PersonaRow } from '../../data/personas';
import { ClipDetail } from './ClipDetail';
import { useAsyncRefresh } from '../../lib/useAsyncRefresh';

interface Props {
  active: Persona;
}

function startOfMonth(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), 1);
}
function addMonths(d: Date, n: number): Date {
  return new Date(d.getFullYear(), d.getMonth() + n, 1);
}
function fmtMonthLabel(d: Date): string {
  return d.toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
}
function isoDateKey(d: Date): string {
  const y = d.getFullYear().toString().padStart(4, '0');
  const m = (d.getMonth() + 1).toString().padStart(2, '0');
  const day = d.getDate().toString().padStart(2, '0');
  return `${y}-${m}-${day}`;
}

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

export function CalendarView({ active }: Props) {
  const [month, setMonth] = useState<Date>(startOfMonth(new Date()));
  const [clips, setClips] = useState<Clip[]>([]);
  const [occurrences, setOccurrences] = useState<Occurrence[]>([]);
  const [personas, setPersonas] = useState<PersonaRow[]>([]);
  const [selectedClipId, setSelectedClipId] = useState<string | null>(null);
  const [status, setStatus] = useState<string>('');

  const monthEnd = useMemo(() => addMonths(month, 1), [month]);

  const { loading, refresh } = useAsyncRefresh(async (alive) => {
    const from = isoDateKey(month);
    const last = new Date(monthEnd.getTime() - 86_400_000); // last day of month
    const to = isoDateKey(last);
    const [c, o, p] = await Promise.all([
      listClips({
        personaCode: active.code,
        from,
        to,
        withGoLiveOnly: true,
        limit: 500,
      }),
      listOccurrencesInRange(from, to, { personaCode: active.code }),
      listPersonas(),
    ]);
    if (!alive()) return;
    setClips(c);
    setOccurrences(o);
    setPersonas(p);
  }, [active.code, month]);

  const personaByCode = useMemo(() => new Map(personas.map((p) => [p.code, p])), [personas]);

  const clipsByDay = useMemo(() => {
    const m = new Map<string, Clip[]>();
    for (const c of clips) {
      if (!c.goLiveDate) continue;
      const key = c.goLiveDate.slice(0, 10);
      const list = m.get(key) ?? [];
      list.push(c);
      m.set(key, list);
    }
    return m;
  }, [clips]);

  const occurrencesByDay = useMemo(() => {
    const m = new Map<string, Occurrence[]>();
    for (const o of occurrences) {
      const key = o.dueAt.slice(0, 10);
      const list = m.get(key) ?? [];
      list.push(o);
      m.set(key, list);
    }
    return m;
  }, [occurrences]);

  // Build 6×7 grid starting from the Sunday on/before month start.
  const gridStart = useMemo(() => {
    const d = new Date(month);
    d.setDate(d.getDate() - d.getDay());
    return d;
  }, [month]);

  const cells: Date[] = useMemo(() => {
    const arr: Date[] = [];
    for (let i = 0; i < 42; i++) {
      arr.push(new Date(gridStart.getFullYear(), gridStart.getMonth(), gridStart.getDate() + i));
    }
    return arr;
  }, [gridStart]);

  return (
    <div className="p-8 max-w-6xl space-y-4">
      <div className="flex items-end justify-between">
        <div>
          <h2 className="display-font text-2xl font-bold persona-accent">Calendar</h2>
          <p className="opacity-70 text-sm">
            Clip releases by go-live date, plus pending reminders 🔔. {active.code !== 'ALL' && <>Filtered to <strong>{active.name}</strong>.</>}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button type="button" className="pretty-button secondary" onClick={() => setMonth((d) => addMonths(d, -1))}>← Prev</button>
          <div className="display-font text-lg font-semibold persona-accent w-44 text-center">{fmtMonthLabel(month)}</div>
          <button type="button" className="pretty-button secondary" onClick={() => setMonth((d) => addMonths(d, 1))}>Next →</button>
          <button type="button" className="pretty-button secondary" onClick={() => setMonth(startOfMonth(new Date()))}>Today</button>
        </div>
      </div>

      <div className="pretty-card">
        <div className="grid grid-cols-7 gap-1 mb-1">
          {WEEKDAYS.map((w) => (
            <div key={w} className="text-xs uppercase tracking-wider opacity-60 text-center">{w}</div>
          ))}
        </div>
        <div className="grid grid-cols-7 gap-1">
          {cells.map((d) => {
            const key = isoDateKey(d);
            const inMonth = d.getMonth() === month.getMonth();
            const isToday = isoDateKey(new Date()) === key;
            const dayClips = clipsByDay.get(key) ?? [];
            const dayOccs  = occurrencesByDay.get(key) ?? [];
            const totalCount = dayClips.length + dayOccs.length;
            // Reminder pills come first (chronological prompt), then clips.
            const clipBudget = Math.max(0, 4 - dayOccs.length);
            const clipsToShow = dayClips.slice(0, clipBudget);
            const occsToShow  = dayOccs.slice(0, 4);
            const hidden = totalCount - clipsToShow.length - occsToShow.length;
            return (
              <div
                key={key}
                className="rounded-xl p-1.5 min-h-[88px] border"
                style={{
                  background: inMonth ? 'rgb(var(--persona-tint))' : 'rgba(255,255,255,0.4)',
                  borderColor: isToday ? 'rgb(var(--persona-accent))' : 'rgb(var(--persona-primary) / 0.25)',
                  opacity: inMonth ? 1 : 0.55,
                }}
              >
                <div className="flex items-center justify-between text-[11px]">
                  <span style={{ fontWeight: isToday ? 700 : 500, color: isToday ? 'rgb(var(--persona-accent))' : undefined }}>
                    {d.getDate()}
                  </span>
                  {totalCount > 0 && (
                    <span className="text-[10px] opacity-70">{totalCount}</span>
                  )}
                </div>
                <div className="flex flex-col gap-0.5 mt-1">
                  {occsToShow.map((o) => {
                    const persona = o.personaCode ? personaByCode.get(o.personaCode) : null;
                    const tint = persona?.primaryColor ?? '#A16D9C';
                    const text = persona?.textColor ?? '#3C283C';
                    return (
                      <div
                        key={`o-${o.id}`}
                        className="text-left px-1.5 py-0.5 rounded text-[10px] truncate"
                        style={{
                          background: 'rgba(255,255,255,0.7)',
                          color: text,
                          border: `1px dashed ${tint}`,
                        }}
                        title={`Reminder: ${o.scheduleName}${persona ? ` (${persona.code})` : ''}`}
                      >
                        🔔 {o.scheduleName}
                      </div>
                    );
                  })}
                  {clipsToShow.map((c) => {
                    const persona = c.personaCode ? personaByCode.get(c.personaCode) : null;
                    const color = persona?.primaryColor ?? '#A16D9C';
                    const text = persona?.textColor ?? '#3C283C';
                    return (
                      <button
                        key={c.id}
                        type="button"
                        onClick={() => setSelectedClipId(c.id)}
                        className="text-left px-1.5 py-0.5 rounded text-[10px] truncate transition"
                        style={{
                          background: color,
                          color: text,
                          border: `1px solid ${persona?.accentColor ?? '#7C3AED'}`,
                        }}
                        title={`${c.title} (${c.id})`}
                      >
                        {c.title || c.id}
                      </button>
                    );
                  })}
                  {hidden > 0 && (
                    <div className="text-[10px] opacity-70 italic">+{hidden} more</div>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {loading && (
        <div className="pretty-card text-sm opacity-60 italic">Loading clips for this month…</div>
      )}
      {!loading && clips.length === 0 && occurrences.length === 0 && (
        <div className="pretty-card text-sm opacity-70 italic">
          No clips or reminders in this month. Import a MasterClipper CSV from the <strong>Clips</strong> page, or add a schedule from <strong>Reminders</strong>.
        </div>
      )}
      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}

      {selectedClipId && (
        <ClipDetail
          clipId={selectedClipId}
          personas={personas}
          onClose={async () => {
            setSelectedClipId(null);
            try { await refresh(); } catch (e) { setStatus(String(e)); }
          }}
        />
      )}
    </div>
  );
}
