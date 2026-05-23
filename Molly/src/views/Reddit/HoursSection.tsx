import { useEffect, useRef, useState } from 'react';
import {
  deleteSession,
  getHoursTotals,
  listRewardMilestones,
  listSessions,
  startSession,
  stopSession,
  type ClockSession,
  type HoursTotals,
  type RewardMilestone,
} from '../../data/hours';

export function HoursSection() {
  const [totals, setTotals] = useState<HoursTotals | null>(null);
  const [sessions, setSessions] = useState<ClockSession[]>([]);
  const [milestones, setMilestones] = useState<RewardMilestone[]>([]);
  const [tick, setTick] = useState(0);
  const [status, setStatus] = useState('');
  const tickRef = useRef<number | null>(null);

  async function refresh() {
    try {
      const [t, s, m] = await Promise.all([
        getHoursTotals(),
        listSessions(50),
        listRewardMilestones(),
      ]);
      setTotals(t);
      setSessions(s);
      setMilestones(m);
    } catch (e) {
      setStatus(String(e));
    }
  }

  useEffect(() => {
    refresh();
  }, []);

  // Live ticking while a session is open. Re-renders once per second so
  // the running counter + reward bars + totals update.
  useEffect(() => {
    const open = totals?.openSessionStartMs != null;
    if (!open) {
      if (tickRef.current != null) { clearInterval(tickRef.current); tickRef.current = null; }
      return;
    }
    if (tickRef.current == null) {
      tickRef.current = window.setInterval(() => setTick((n) => n + 1), 1000);
    }
    return () => {
      if (tickRef.current != null) { clearInterval(tickRef.current); tickRef.current = null; }
    };
  }, [totals?.openSessionStartMs]);

  async function toggleClock() {
    try {
      if (totals?.openSessionStartMs != null) {
        await stopSession();
      } else {
        await startSession(null);
      }
      await refresh();
    } catch (e) {
      setStatus(String(e));
    }
  }

  async function removeSession(id: number) {
    if (!confirm('Delete this session?')) return;
    try { await deleteSession(id); await refresh(); }
    catch (e) { setStatus(String(e)); }
  }

  const open = totals?.openSessionStartMs != null;
  // Live extras while open — added on top of the Rust-computed totals.
  const liveExtraMs = open && totals
    ? Math.max(0, Date.now() - totals.openSessionStartMs!)
    : 0;
  void tick; // tick is the re-render driver only.

  const liveTotal = (totals?.allTimeMs ?? 0); // already includes open portion from Rust
  const todayMs = (totals?.todayMs ?? 0);
  const weekMs  = (totals?.weekMs  ?? 0);
  const monthMs = (totals?.monthMs ?? 0);
  const totalHrs = liveTotal / 3_600_000;

  return (
    <div className="space-y-3">
      <div
        className="rounded-3xl px-8 py-10 text-center flex flex-col items-center gap-3 shadow-xl"
        style={{ background: '#1a1a2e', color: 'white' }}
      >
        <div
          className="text-[10px] font-bold tracking-[0.2em] uppercase"
          style={{ color: open ? '#2ecc71' : 'rgba(255,255,255,0.4)' }}
        >
          {open ? 'LOGGED IN' : 'LOGGED OUT'}
        </div>
        <div
          className="display-font text-5xl font-bold tracking-widest leading-none"
          style={{ color: open ? '#FF8FB1' : 'white' }}
        >
          {open ? fmtClock(liveExtraMs) : '00:00:00'}
        </div>
        <div className="text-xs opacity-40">
          {open && totals?.openSessionStartMs
            ? `since ${new Date(totals.openSessionStartMs).toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })}`
            : '—'}
        </div>
        <button
          type="button"
          onClick={toggleClock}
          className="mt-2 px-12 py-3.5 rounded-full font-bold text-base transition hover:scale-105"
          style={{
            background: open ? 'white' : '#FF6B95',
            color: open ? '#72243E' : 'white',
          }}
        >
          {open ? 'Log Out' : 'Log In'}
        </button>
      </div>

      <div className="grid grid-cols-3 gap-3">
        <StatCard n={fmtHM(todayMs)} label="today" />
        <StatCard n={fmtHM(weekMs)}  label="this week" />
        <StatCard n={fmtHM(monthMs)} label="this month" />
      </div>

      <div className="pretty-card">
        <div className="flex items-baseline justify-between mb-3">
          <h3 className="display-font text-lg font-semibold persona-accent">🎁 Reward milestones</h3>
          <div className="text-xs opacity-60">
            Edit goals in <strong>Settings → Rewards</strong>
          </div>
        </div>
        {milestones.length === 0 ? (
          <div className="text-sm opacity-60 italic">
            No milestones yet. Add some in <strong>Settings → Rewards</strong> — let the goals be goals.
          </div>
        ) : (
          <ul className="space-y-2">
            {milestones.map((m) => {
              const pct = Math.min(100, (totalHrs / m.hoursGoal) * 100);
              const reached = totalHrs >= m.hoursGoal;
              return (
                <li
                  key={m.id}
                  className="flex items-center gap-3 rounded-xl px-3 py-2.5 border"
                  style={{
                    background: reached ? '#eafbf1' : '#fafafa',
                    borderColor: reached ? '#a8e6c1' : 'rgb(var(--persona-primary) / 0.25)',
                  }}
                >
                  <span className="text-xl">{reached ? '🎉' : '🎁'}</span>
                  <div className="flex-1 min-w-0">
                    <div className="text-sm font-medium">{m.label}</div>
                    <div className="h-1.5 mt-1.5 rounded-full" style={{ background: 'rgb(var(--persona-primary) / 0.2)' }}>
                      <div
                        className="h-full rounded-full transition-all"
                        style={{
                          width: `${pct}%`,
                          background: 'linear-gradient(90deg, #FF8FB1, #FF6B95)',
                        }}
                      />
                    </div>
                    <div className="text-[10px] opacity-60 mt-0.5">
                      {reached
                        ? 'Achieved! 🎊'
                        : `${totalHrs.toFixed(1)} / ${m.hoursGoal} hrs · ${Math.round(pct)}%`}
                    </div>
                  </div>
                  <span className="text-xs font-bold whitespace-nowrap persona-accent">
                    {m.hoursGoal}h
                  </span>
                </li>
              );
            })}
          </ul>
        )}
      </div>

      <div className="pretty-card">
        <h3 className="display-font text-lg font-semibold persona-accent mb-3">Session log</h3>
        {sessions.length === 0 ? (
          <div className="text-sm opacity-60 italic">No sessions yet — tap <strong>Log In</strong> to start.</div>
        ) : (
          <ul className="space-y-1.5">
            {sessions.map((s) => {
              const start = new Date(s.startMs);
              const stop = s.durationMs != null ? new Date(s.startMs + s.durationMs) : null;
              return (
                <li key={s.id} className="flex items-center gap-3 rounded-xl px-3 py-2 border" style={{ borderColor: 'rgb(var(--persona-primary) / 0.25)' }}>
                  <div className="text-xs font-bold w-20 persona-accent">
                    {start.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' })}
                  </div>
                  <div className="text-xs flex-1 opacity-70">
                    {start.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })} →
                    {' '}{stop ? stop.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' }) : <em>running…</em>}
                  </div>
                  <div className="display-font text-base font-bold whitespace-nowrap">
                    {s.durationMs != null ? fmtHM(s.durationMs) : '…'}
                  </div>
                  <button
                    type="button"
                    className="text-base opacity-50 hover:opacity-100 hover:text-red-600 px-1"
                    onClick={() => removeSession(s.id)}
                    title="Delete"
                  >
                    ✕
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </div>

      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}

function StatCard({ n, label }: { n: string; label: string }) {
  return (
    <div className="pretty-card text-center">
      <div className="display-font text-2xl font-bold persona-accent">{n}</div>
      <div className="text-[10px] uppercase tracking-wider opacity-60">{label}</div>
    </div>
  );
}

function fmtClock(ms: number): string {
  const s = Math.floor(ms / 1000);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sc = s % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(sc).padStart(2, '0')}`;
}

function fmtHM(ms: number): string {
  const m = Math.floor(ms / 60000);
  const h = Math.floor(m / 60);
  return h ? `${h}h ${m % 60}m` : `${m}m`;
}
