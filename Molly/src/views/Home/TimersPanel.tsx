import { useEffect, useRef, useState } from 'react';
import {
  playBirthdayChime,
  playRentDueChime,
  playStopwatchChime,
} from '../../lib/soundFx';

// Timers tucked into the Hi, I'm Molly welcome card on the home page.
// Two date countdowns (label + date, both editable) and one
// hh:mm:ss.cc count-up stopwatch with start/stop/reset. Each timer's
// state persists in localStorage so it survives app launches.
//
// The stopwatch persists *running* state too: it stores
// `accumulatedMs` and `startedAt` (epoch ms), so an unattended timer
// keeps counting even while the app is closed.

interface CountdownState {
  label: string;
  date: string; // ISO YYYY-MM-DD
}

interface StopwatchState {
  running: boolean;
  startedAt: number | null; // epoch ms when current run segment began
  accumulatedMs: number;    // ms accumulated across all prior segments
}

const KEY_C1 = 'molly:timer:countdown1';
const KEY_C2 = 'molly:timer:countdown2';
const KEY_SW = 'molly:timer:stopwatch';

function nextFirstOfMonthIso(now: Date = new Date()): string {
  // Default for Rent Due — first day of the next calendar month.
  const y = now.getMonth() === 11 ? now.getFullYear() + 1 : now.getFullYear();
  const m = (now.getMonth() + 1) % 12;
  return `${y}-${String(m + 1).padStart(2, '0')}-01`;
}

function defaultBirthdayIso(now: Date = new Date()): string {
  // Default for Birthday — next occurrence of December 6th. Rolls to
  // the following year automatically if we've already passed it.
  const thisYear = now.getFullYear();
  const candidate = new Date(thisYear, 11, 6); // month is 0-indexed
  const todayMidnight = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const y = candidate.getTime() >= todayMidnight.getTime() ? thisYear : thisYear + 1;
  return `${y}-12-06`;
}

function loadCountdown(key: string, fallback: CountdownState): CountdownState {
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return fallback;
    const parsed = JSON.parse(raw) as Partial<CountdownState>;
    if (typeof parsed.label !== 'string' || typeof parsed.date !== 'string') return fallback;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(parsed.date)) return fallback;
    return { label: parsed.label, date: parsed.date };
  } catch {
    return fallback;
  }
}

function saveCountdown(key: string, value: CountdownState): void {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // localStorage may be unavailable in private-browsing edge cases;
    // a non-persisted timer is still usable, just won't survive restart.
  }
}

function loadStopwatch(): StopwatchState {
  const fallback: StopwatchState = { running: false, startedAt: null, accumulatedMs: 0 };
  try {
    const raw = localStorage.getItem(KEY_SW);
    if (!raw) return fallback;
    const p = JSON.parse(raw) as Partial<StopwatchState>;
    return {
      running: p.running === true,
      startedAt: typeof p.startedAt === 'number' ? p.startedAt : null,
      accumulatedMs: typeof p.accumulatedMs === 'number' && p.accumulatedMs >= 0 ? p.accumulatedMs : 0,
    };
  } catch {
    return fallback;
  }
}

function saveStopwatch(value: StopwatchState): void {
  try {
    localStorage.setItem(KEY_SW, JSON.stringify(value));
  } catch {
    /* see saveCountdown */
  }
}

export function daysUntil(targetIso: string, now: Date = new Date()): number {
  const [y, m, d] = targetIso.split('-').map(Number);
  if (!y || !m || !d) return 0;
  const target = new Date(y, m - 1, d);
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  return Math.round((target.getTime() - today.getTime()) / (24 * 3600 * 1000));
}

function formatNice(targetIso: string): string {
  const [y, m, d] = targetIso.split('-').map(Number);
  if (!y || !m || !d) return targetIso;
  const dt = new Date(y, m - 1, d);
  return dt.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
}

export function stopwatchElapsedMs(state: StopwatchState, now: number = Date.now()): number {
  if (state.running && state.startedAt !== null) {
    return state.accumulatedMs + Math.max(0, now - state.startedAt);
  }
  return state.accumulatedMs;
}

export function formatStopwatch(totalMs: number): string {
  const ms = Math.max(0, Math.floor(totalMs));
  const hh = Math.floor(ms / 3_600_000);
  const mm = Math.floor((ms % 3_600_000) / 60_000);
  const ss = Math.floor((ms % 60_000) / 1000);
  const cc = Math.floor((ms % 1000) / 10); // centiseconds (two digits)
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${pad(hh)}:${pad(mm)}:${pad(ss)}.${pad(cc)}`;
}

// ---------------------------------------------------------------------------

export function TimersPanel() {
  return (
    <div className="mt-4 grid gap-3 md:grid-cols-3">
      <CountdownCard
        storageKey={KEY_C1}
        emoji="🎂"
        defaultState={{ label: 'Birthday', date: defaultBirthdayIso() }}
        onArrived={playBirthdayChime}
      />
      <CountdownCard
        storageKey={KEY_C2}
        emoji="🏠"
        defaultState={{ label: 'Rent Due', date: nextFirstOfMonthIso() }}
        onArrived={playRentDueChime}
      />
      <StopwatchCard />
    </div>
  );
}

/** YYYY-MM-DD in local time — the natural "day" boundary for
 *  fire-once-per-day countdown chimes. */
function isoToday(now: Date = new Date()): string {
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, '0');
  const d = String(now.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function CountdownCard({
  storageKey,
  emoji,
  defaultState,
  onArrived,
}: {
  storageKey: string;
  emoji: string;
  defaultState: CountdownState;
  onArrived: () => void;
}) {
  const [state, setState] = useState<CountdownState>(() => loadCountdown(storageKey, defaultState));
  const [editing, setEditing] = useState<boolean>(false);
  const [draftLabel, setDraftLabel] = useState<string>(state.label);
  const [draftDate, setDraftDate] = useState<string>(state.date);

  // Re-render once a day so the countdown stays current without
  // needing a high-frequency timer. The 30-min tick is plenty since
  // the visible number only changes on date boundaries.
  const [, forceTick] = useState(0);
  useEffect(() => {
    const id = window.setInterval(() => forceTick((n) => n + 1), 30 * 60_000);
    return () => window.clearInterval(id);
  }, []);

  const remaining = daysUntil(state.date);
  const dateNice = formatNice(state.date);

  // Fire the arrival chime at most once per calendar day per timer —
  // tracked in localStorage so app restarts on the same day stay
  // silent. The check fires both on mount and whenever `remaining`
  // recomputes (e.g. when the 30-min tick crosses midnight from
  // tomorrow into today, or when Sallie edits the date to today).
  useEffect(() => {
    if (remaining !== 0) return;
    const firedKey = `${storageKey}:lastFired`;
    const today = isoToday();
    try {
      if (localStorage.getItem(firedKey) === today) return;
      localStorage.setItem(firedKey, today);
    } catch {
      // localStorage unavailable — fall through and just play it; not
      // worth suppressing the chime over private-browsing.
    }
    onArrived();
  }, [remaining, storageKey, onArrived]);

  function startEdit() {
    setDraftLabel(state.label);
    setDraftDate(state.date);
    setEditing(true);
  }
  function commit() {
    const label = draftLabel.trim() || defaultState.label;
    const date = /^\d{4}-\d{2}-\d{2}$/.test(draftDate) ? draftDate : state.date;
    const next: CountdownState = { label, date };
    setState(next);
    saveCountdown(storageKey, next);
    setEditing(false);
  }

  return (
    <div
      className="rounded-2xl px-4 py-3 relative"
      style={{
        background:
          'linear-gradient(135deg, rgb(var(--persona-tint)), rgb(var(--surface-card)))',
        border: '1px solid rgb(var(--persona-primary) / 0.4)',
        boxShadow: '0 2px 8px -4px rgb(var(--persona-primary) / 0.35)',
      }}
    >
      {!editing ? (
        <>
          <div className="flex items-center justify-between gap-2">
            <div className="flex items-center gap-2 min-w-0">
              <span className="text-xl leading-none" aria-hidden>{emoji}</span>
              <span
                className="display-font font-semibold truncate"
                style={{ color: 'rgb(var(--persona-accent))' }}
                title={state.label}
              >
                {state.label}
              </span>
            </div>
            <button
              type="button"
              onClick={startEdit}
              className="text-xs opacity-50 hover:opacity-100 leading-none px-1"
              title="Edit label and date"
              aria-label="Edit countdown"
            >
              ✏️
            </button>
          </div>
          <div className="flex items-baseline gap-1.5 mt-1">
            <span
              className="persona-accent font-bold"
              style={{
                fontFamily: 'Caveat, "Paper Daisy", cursive',
                fontSize: '2.6rem',
                lineHeight: 1,
              }}
            >
              {remaining}
            </span>
            <span className="text-xs opacity-70">
              {remaining === 1 || remaining === -1 ? 'day' : 'days'}
              {remaining < 0 ? ' ago' : remaining === 0 ? ' — today!' : ''}
            </span>
          </div>
          <div className="text-xs opacity-60 mt-0.5">{dateNice}</div>
        </>
      ) : (
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <span className="text-xl leading-none" aria-hidden>{emoji}</span>
            <input
              type="text"
              value={draftLabel}
              onChange={(e) => setDraftLabel(e.target.value)}
              className="pretty-input flex-1 min-w-0"
              placeholder="Label"
              maxLength={32}
              autoFocus
            />
          </div>
          <input
            type="date"
            value={draftDate}
            onChange={(e) => setDraftDate(e.target.value)}
            className="pretty-input w-full"
          />
          <div className="flex gap-1.5 justify-end">
            <button
              type="button"
              onClick={() => setEditing(false)}
              className="pretty-button secondary text-xs px-3 py-1"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={commit}
              className="pretty-button text-xs px-3 py-1"
            >
              Save
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

function StopwatchCard() {
  const [state, setState] = useState<StopwatchState>(() => loadStopwatch());
  const displayRef = useRef<HTMLSpanElement | null>(null);

  // Tick the display via rAF only while running. Writes directly to
  // the DOM so we don't re-render the rest of the dashboard 30× a
  // second. When stopped, the static accumulated value is rendered by
  // React and the rAF loop is idle.
  useEffect(() => {
    if (!state.running) {
      if (displayRef.current) {
        displayRef.current.textContent = formatStopwatch(stopwatchElapsedMs(state));
      }
      return;
    }
    let raf = 0;
    const loop = () => {
      if (displayRef.current) {
        displayRef.current.textContent = formatStopwatch(stopwatchElapsedMs(state));
      }
      raf = window.requestAnimationFrame(loop);
    };
    raf = window.requestAnimationFrame(loop);
    return () => window.cancelAnimationFrame(raf);
  }, [state]);

  function toggle() {
    setState((cur) => {
      const wasRunning = cur.running;
      const next: StopwatchState = wasRunning
        ? {
            running: false,
            startedAt: null,
            accumulatedMs: stopwatchElapsedMs(cur),
          }
        : {
            running: true,
            startedAt: Date.now(),
            accumulatedMs: cur.accumulatedMs,
          };
      saveStopwatch(next);
      // Soft chime on stop only — start clicks stay silent so Sallie
      // can begin a quick interval without sound feedback every time.
      if (wasRunning && next.accumulatedMs > 0) playStopwatchChime();
      return next;
    });
  }
  function reset() {
    const next: StopwatchState = { running: false, startedAt: null, accumulatedMs: 0 };
    setState(next);
    saveStopwatch(next);
  }

  return (
    <div
      className="rounded-2xl px-4 py-3 relative"
      style={{
        background:
          'linear-gradient(135deg, rgb(var(--persona-tint)), rgb(var(--surface-card)))',
        border: '1px solid rgb(var(--persona-primary) / 0.4)',
        boxShadow: '0 2px 8px -4px rgb(var(--persona-primary) / 0.35)',
      }}
    >
      <div className="flex items-center gap-2">
        <span className="text-xl leading-none" aria-hidden>⏱</span>
        <span
          className="display-font font-semibold text-sm"
          style={{ color: 'rgb(var(--persona-accent))' }}
        >
          Stopwatch
        </span>
      </div>
      <div className="mt-1">
        <span
          ref={displayRef}
          className="persona-accent font-bold tabular-nums"
          style={{
            fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
            fontSize: '1.55rem',
            letterSpacing: '0.5px',
          }}
        >
          {formatStopwatch(stopwatchElapsedMs(state))}
        </span>
      </div>
      <div className="flex gap-1.5 mt-2">
        <button
          type="button"
          onClick={toggle}
          className={state.running ? 'pretty-button danger text-xs px-3 py-1' : 'pretty-button text-xs px-3 py-1'}
        >
          {state.running ? '⏸ Stop' : '▶ Start'}
        </button>
        <button
          type="button"
          onClick={reset}
          className="pretty-button secondary text-xs px-3 py-1"
          disabled={state.running || state.accumulatedMs === 0}
          title={state.running ? 'Stop the timer first' : 'Reset to 00:00:00.00'}
        >
          ↺ Reset
        </button>
      </div>
    </div>
  );
}
