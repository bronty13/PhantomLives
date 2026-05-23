import { useEffect, useMemo, useState } from 'react';
import type { Persona } from '../../state/personas';
import { listClips, type Clip } from '../../data/clips';
import { listOccurrencesInRange, type Occurrence } from '../../data/occurrences';
import { listPersonas, type Persona as PersonaRow } from '../../data/personas';
import { listHolidays, type Holiday } from '../../data/holidays';
import {
  listClipTagsInRange,
  listFanSiteDayTagsInRange,
  type ClipTagInDate,
  type FanSiteDayTag,
} from '../../data/contentTags';
import { listSubredditPostsInRange, type SubredditPost } from '../../data/reddit';
import { ClipDetail } from './ClipDetail';
import { useAsyncRefresh } from '../../lib/useAsyncRefresh';
import { holidayPillStyle, resolveHolidaysForMonth } from '../../lib/holidayResolver';

/** localStorage helpers for the per-persona toggle preferences. Keyed
 *  by both the persona code AND the overlay kind so Sallie can have
 *  e.g. FanSite tags on for CoC but Clip tags only for PoA. */
type OverlayKind = 'fansite' | 'clip' | 'reddit';
function toggleKey(personaCode: string, kind: OverlayKind): string {
  return `molly.calendar.show.${kind}.${personaCode}`;
}
function loadToggle(personaCode: string, kind: OverlayKind): boolean {
  try { return localStorage.getItem(toggleKey(personaCode, kind)) === '1'; }
  catch { return false; }
}
function saveToggle(personaCode: string, kind: OverlayKind, on: boolean) {
  try { localStorage.setItem(toggleKey(personaCode, kind), on ? '1' : '0'); }
  catch { /* ignore */ }
}

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
  const [holidays, setHolidays] = useState<Holiday[]>([]);
  const [fanSiteTags, setFanSiteTags] = useState<FanSiteDayTag[]>([]);
  const [clipTags, setClipTags] = useState<ClipTagInDate[]>([]);
  const [redditPosts, setRedditPosts] = useState<SubredditPost[]>([]);
  const [showFanSiteTags, setShowFanSiteTags] = useState<boolean>(() => loadToggle(active.code, 'fansite'));
  const [showClipTags, setShowClipTags] = useState<boolean>(() => loadToggle(active.code, 'clip'));
  const [showRedditPosts, setShowRedditPosts] = useState<boolean>(() => loadToggle(active.code, 'reddit'));
  const [selectedClipId, setSelectedClipId] = useState<string | null>(null);
  const [status, setStatus] = useState<string>('');

  // Hydrate both toggles whenever the active persona changes — each
  // preference is persisted per persona + per kind.
  useEffect(() => {
    setShowFanSiteTags(loadToggle(active.code, 'fansite'));
    setShowClipTags(loadToggle(active.code, 'clip'));
    setShowRedditPosts(loadToggle(active.code, 'reddit'));
  }, [active.code]);

  const monthEnd = useMemo(() => addMonths(month, 1), [month]);

  const { loading, refresh } = useAsyncRefresh(async (alive) => {
    const from = isoDateKey(month);
    const last = new Date(monthEnd.getTime() - 86_400_000); // last day of month
    const to = isoDateKey(last);
    const personaFilter = active.code === 'ALL' ? null : active.code;
    const [c, o, p, h, fst, ct, rp] = await Promise.all([
      listClips({
        personaCode: active.code,
        from,
        to,
        withGoLiveOnly: true,
        limit: 500,
      }),
      listOccurrencesInRange(from, to, { personaCode: active.code }),
      listPersonas(),
      listHolidays(),
      // All three overlays are always fetched — toggles control display,
      // not the query. Each is bounded by (days × items) in the visible
      // month so cost stays cheap.
      listFanSiteDayTagsInRange(from, to, personaFilter),
      listClipTagsInRange(from, to, personaFilter),
      listSubredditPostsInRange(from, to, personaFilter),
    ]);
    if (!alive()) return;
    setClips(c);
    setOccurrences(o);
    setPersonas(p);
    setHolidays(h);
    setFanSiteTags(fst);
    setClipTags(ct);
    setRedditPosts(rp);
  }, [active.code, month]);

  const holidaysByDay = useMemo(
    () => resolveHolidaysForMonth(holidays, month.getFullYear(), month.getMonth() + 1),
    [holidays, month],
  );

  const fanSiteTagsByDay = useMemo(() => {
    const m = new Map<string, FanSiteDayTag[]>();
    for (const t of fanSiteTags) {
      const arr = m.get(t.date) ?? [];
      arr.push(t);
      m.set(t.date, arr);
    }
    return m;
  }, [fanSiteTags]);

  const clipTagsByDay = useMemo(() => {
    const m = new Map<string, ClipTagInDate[]>();
    for (const t of clipTags) {
      const arr = m.get(t.date) ?? [];
      arr.push(t);
      m.set(t.date, arr);
    }
    return m;
  }, [clipTags]);

  const redditPostsByDay = useMemo(() => {
    const m = new Map<string, SubredditPost[]>();
    for (const p of redditPosts) {
      const arr = m.get(p.postedDate) ?? [];
      arr.push(p);
      m.set(p.postedDate, arr);
    }
    return m;
  }, [redditPosts]);

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
            Clip releases by go-live date, plus pending reminders 🔔 and themed holidays 🎉. {active.code !== 'ALL' && <>Filtered to <strong>{active.name}</strong> (holidays are global).</>}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button type="button" className="pretty-button secondary" onClick={() => setMonth((d) => addMonths(d, -1))}>← Prev</button>
          <div className="display-font text-lg font-semibold persona-accent w-44 text-center">{fmtMonthLabel(month)}</div>
          <button type="button" className="pretty-button secondary" onClick={() => setMonth((d) => addMonths(d, 1))}>Next →</button>
          <button type="button" className="pretty-button secondary" onClick={() => setMonth(startOfMonth(new Date()))}>Today</button>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-4 text-xs">
        <label className="inline-flex items-center gap-1.5 cursor-pointer select-none">
          <input
            type="checkbox"
            checked={showFanSiteTags}
            onChange={(e) => {
              const on = e.target.checked;
              setShowFanSiteTags(on);
              saveToggle(active.code, 'fansite', on);
            }}
          />
          <span>🏷️ FanSite day tags</span>
        </label>
        <label className="inline-flex items-center gap-1.5 cursor-pointer select-none">
          <input
            type="checkbox"
            checked={showClipTags}
            onChange={(e) => {
              const on = e.target.checked;
              setShowClipTags(on);
              saveToggle(active.code, 'clip', on);
            }}
          />
          <span>🎬 Clip tags</span>
        </label>
        <label className="inline-flex items-center gap-1.5 cursor-pointer select-none">
          <input
            type="checkbox"
            checked={showRedditPosts}
            onChange={(e) => {
              const on = e.target.checked;
              setShowRedditPosts(on);
              saveToggle(active.code, 'reddit', on);
            }}
          />
          <span>🔴 Reddit posts</span>
        </label>
        <span className="opacity-50">
          (toggles remembered for {active.code === 'ALL' ? 'all personas' : active.name})
        </span>
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
            const dayHols  = holidaysByDay.get(key) ?? [];
            const totalCount = dayClips.length + dayOccs.length + dayHols.length;
            // Holidays first (least-actionable, just context), then reminders,
            // then clips. Each row counts against the same 4-slot budget so
            // dense days collapse with a +N more hint.
            const holsToShow = dayHols.slice(0, 4);
            const occBudget = Math.max(0, 4 - holsToShow.length);
            const occsToShow = dayOccs.slice(0, occBudget);
            const clipBudget = Math.max(0, 4 - holsToShow.length - occsToShow.length);
            const clipsToShow = dayClips.slice(0, clipBudget);
            const hidden = totalCount - clipsToShow.length - occsToShow.length - holsToShow.length;
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
                  {holsToShow.map((h) => (
                    <div
                      key={`h-${h.id}`}
                      className="px-1.5 py-0.5 rounded text-[10px] truncate font-semibold"
                      style={holidayPillStyle(h)}
                      title={h.name}
                    >
                      {h.emoji ? `${h.emoji} ` : ''}{h.name}
                    </div>
                  ))}
                  {showFanSiteTags && (fanSiteTagsByDay.get(key)?.length ?? 0) > 0 && (
                    <div className="flex flex-wrap gap-0.5">
                      {(fanSiteTagsByDay.get(key) ?? []).map((t) => (
                        <span
                          key={`fst-${t.fanDayId}-${t.tagId}`}
                          className="px-1 py-[1px] rounded-full text-[9px] font-semibold whitespace-nowrap"
                          style={{
                            background: t.tagColor,
                            color: '#1F2937',
                            border: `1px solid ${t.tagColor}`,
                          }}
                          title={`FanSite · ${t.tagName}${t.personaCode ? ` · ${t.personaCode}` : ''}`}
                        >
                          {t.tagName}
                        </span>
                      ))}
                    </div>
                  )}
                  {showClipTags && (clipTagsByDay.get(key)?.length ?? 0) > 0 && (
                    <div className="flex flex-wrap gap-0.5">
                      {(clipTagsByDay.get(key) ?? []).map((t) => (
                        <span
                          key={`clt-${t.clipId}-${t.tagId}`}
                          className="px-1 py-[1px] rounded-full text-[9px] font-semibold whitespace-nowrap"
                          style={{
                            background: 'rgba(255,255,255,0.85)',
                            color: '#1F2937',
                            border: `1.5px dashed ${t.tagColor}`,
                          }}
                          title={`Clip · ${t.tagName}${t.personaCode ? ` · ${t.personaCode}` : ''}`}
                        >
                          {t.tagName}
                        </span>
                      ))}
                    </div>
                  )}
                  {showRedditPosts && (redditPostsByDay.get(key)?.length ?? 0) > 0 && (
                    <div className="flex flex-col gap-0.5">
                      {(redditPostsByDay.get(key) ?? []).slice(0, 3).map((p) => {
                        const future = key > isoDateKey(new Date());
                        return (
                          <div
                            key={`rp-${p.id}`}
                            className="text-left px-1.5 py-0.5 rounded text-[10px] truncate font-medium"
                            style={{
                              background: 'rgba(255,107,149,0.15)',
                              color: '#72243E',
                              border: future
                                ? '1px dashed rgba(255,107,149,0.65)'
                                : '1px solid rgba(255,107,149,0.55)',
                              fontStyle: future ? 'italic' : 'normal',
                            }}
                            title={`r/${p.subredditName}${p.notes ? ` · ${p.notes}` : ''}${future ? ' (scheduled)' : ''}`}
                          >
                            🔴 r/{p.subredditName}
                          </div>
                        );
                      })}
                      {(redditPostsByDay.get(key)?.length ?? 0) > 3 && (
                        <div className="text-[9px] opacity-60 italic">
                          +{(redditPostsByDay.get(key)?.length ?? 0) - 3} more
                        </div>
                      )}
                    </div>
                  )}
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
