import { useCallback, useEffect, useState } from 'react';
import type { Persona } from '../../state/personas';
import {
  addSocialDrop,
  computeSocialPlatformStreak,
  listSocialPlatformHistory,
  listSocialToday,
  setSocialPlatformGoal,
  todayIsoLocal,
  undoLastSocialDrop,
  type DayHistoryEntry,
  type PlatformToday,
} from '../../data/socialDrops';
import { playCoin, playGoalHit } from '../../lib/coinSound';

interface Props {
  active: Persona;
  platformId: number;
}

const HISTORY_DAYS = 35; // 5 weeks of grid

export function PlatformTab({ active, platformId }: Props) {
  const personaCode = active.code === 'ALL' ? null : active.code;
  const today = todayIsoLocal();

  const [self, setSelf] = useState<PlatformToday | null>(null);
  const [history, setHistory] = useState<DayHistoryEntry[]>([]);
  const [streak, setStreak] = useState(0);
  const [status, setStatus] = useState('');
  const [busy, setBusy] = useState(false);
  const [goalDraft, setGoalDraft] = useState<string>('');

  const refresh = useCallback(async () => {
    try {
      const [today_, hist, st] = await Promise.all([
        listSocialToday(personaCode, today),
        listSocialPlatformHistory(personaCode, platformId, today, HISTORY_DAYS),
        computeSocialPlatformStreak(personaCode, platformId, today),
      ]);
      const me = today_.find((r) => r.platformId === platformId) ?? null;
      setSelf(me);
      setHistory(hist);
      setStreak(st);
      if (me) setGoalDraft(String(me.dailyGoal));
    } catch (e) {
      setStatus(String(e));
    }
  }, [personaCode, today, platformId]);

  useEffect(() => { void refresh(); }, [refresh]);

  async function onDrop() {
    if (busy || active.code === 'ALL' || !self) return;
    setBusy(true);
    try {
      const res = await addSocialDrop({ personaCode, platformId, postedDate: today });
      if (res.justHit) playGoalHit();
      else playCoin();
      await refresh();
    } catch (e) {
      setStatus(String(e));
    } finally {
      setBusy(false);
    }
  }
  async function onUndo() {
    if (busy || !self || self.count <= 0) return;
    setBusy(true);
    try {
      await undoLastSocialDrop(personaCode, platformId, today);
      await refresh();
    } catch (e) {
      setStatus(String(e));
    } finally {
      setBusy(false);
    }
  }
  async function commitGoal() {
    const n = parseInt(goalDraft, 10);
    if (!Number.isFinite(n) || n < 0 || n > 1000) {
      setStatus('Goal must be 0–1000.');
      setGoalDraft(self ? String(self.dailyGoal) : '1');
      return;
    }
    if (self && n === self.dailyGoal) return;
    try {
      await setSocialPlatformGoal(platformId, n);
      await refresh();
    } catch (e) {
      setStatus(String(e));
    }
  }

  if (!self) {
    return <div className="opacity-60 italic">Loading…</div>;
  }

  return (
    <div className="space-y-4">
      {active.code === 'ALL' && (
        <div className="pretty-card text-sm bg-amber-50 border border-amber-200">
          ☝️ Pick <strong>Curves</strong> or <strong>Princess</strong> in the sidebar to track this platform.
        </div>
      )}

      <div
        className="pretty-card flex items-center gap-4 flex-wrap"
        style={{
          background: self.hit ? '#e9f9ee' : 'rgb(var(--persona-tint))',
          borderColor: self.hit ? '#a8e6c1' : undefined,
          borderWidth: self.hit ? 1 : 0,
          borderStyle: 'solid',
        }}
      >
        <span className="text-4xl select-none" aria-hidden>{self.icon}</span>
        <div className="flex-1 min-w-[220px]">
          <div className="display-font text-2xl font-bold">{self.name}</div>
          <div className="text-xs opacity-60">
            Goal: {self.dailyGoal}/day · {self.hit ? '✓ done for today' : `${self.dailyGoal - self.count} to go`}
          </div>
        </div>
        <div className="flex items-center gap-2">
          <div className="text-right">
            <div className="font-mono text-3xl font-bold tabular-nums leading-none">
              {self.count}/{self.dailyGoal}
            </div>
            <div className="text-[10px] uppercase tracking-wider opacity-60 mt-1">today</div>
          </div>
          <button
            type="button"
            className="pretty-button"
            disabled={busy || active.code === 'ALL'}
            onClick={onDrop}
          >
            {self.hit ? '+1 More' : '+1 Post'}
          </button>
          <button
            type="button"
            className="text-sm opacity-60 hover:opacity-100 hover:text-red-600 px-2"
            disabled={busy || self.count <= 0}
            onClick={onUndo}
            title="Undo last coin"
          >
            ↶
          </button>
        </div>
      </div>

      <div className="pretty-card space-y-2">
        <div className="flex items-center justify-between flex-wrap gap-2">
          <div className="text-xs uppercase tracking-wider opacity-60">
            Last {HISTORY_DAYS} days
          </div>
          <div className="text-sm">
            🔥 <strong>{streak}</strong> day{streak === 1 ? '' : 's'} streak on {self.name}
          </div>
        </div>
        <HistoryGrid history={history} color={self.color} />
        <Legend color={self.color} />
      </div>

      <div className="pretty-card space-y-2">
        <div className="text-xs uppercase tracking-wider opacity-60">Daily goal</div>
        <div className="flex items-center gap-2">
          <input
            type="number"
            min={0}
            max={1000}
            className="pretty-input w-24 font-mono"
            value={goalDraft}
            onChange={(e) => setGoalDraft(e.target.value)}
            onBlur={commitGoal}
            onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur(); }}
          />
          <span className="text-sm opacity-70">posts per day on {self.name}</span>
        </div>
        <div className="text-xs opacity-60">
          Applies to every persona. Set to 0 to drop this platform from the streak calculation.
        </div>
      </div>

      {status && (
        <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>
      )}
    </div>
  );
}

function HistoryGrid({ history, color }: { history: DayHistoryEntry[]; color: string }) {
  // 7 columns (Mon→Sun); rows grow downward. We pad the front so the
  // first column aligns with Monday regardless of how many days back
  // HISTORY_DAYS started on.
  if (history.length === 0) return null;
  const first = new Date(history[0].date + 'T00:00:00');
  // Mon=0, Sun=6
  const padFront = ((first.getDay() + 6) % 7);
  const cells: Array<DayHistoryEntry | null> = [
    ...Array(padFront).fill(null),
    ...history,
  ];
  return (
    <div className="grid grid-cols-7 gap-1 max-w-md">
      {['M','T','W','T','F','S','S'].map((d, i) => (
        <div key={`hdr-${i}`} className="text-[10px] uppercase opacity-50 text-center">{d}</div>
      ))}
      {cells.map((c, i) => {
        if (!c) return <div key={`pad-${i}`} className="h-7 rounded" />;
        const goal = c.goal;
        const ratio = goal > 0 ? c.count / goal : 0;
        let bg = 'rgba(0,0,0,0.04)';
        let label = `${c.date} — ${c.count}/${goal}`;
        if (c.count === 0) bg = 'rgba(0,0,0,0.04)';
        else if (ratio >= 1) bg = '#2ecc71';
        else bg = color;
        const opacity = c.count === 0 ? 1 : Math.min(1, 0.35 + ratio * 0.65);
        return (
          <div
            key={c.date}
            className="h-7 rounded flex items-center justify-center text-[10px] font-mono"
            title={label}
            style={{ background: bg, opacity, color: ratio >= 1 ? 'white' : 'rgba(0,0,0,0.6)' }}
          >
            {c.count > 0 ? c.count : ''}
          </div>
        );
      })}
    </div>
  );
}

function Legend({ color }: { color: string }) {
  return (
    <div className="flex items-center gap-3 text-[10px] opacity-70 flex-wrap">
      <span className="flex items-center gap-1"><Sq bg="rgba(0,0,0,0.04)" /> 0 posts</span>
      <span className="flex items-center gap-1"><Sq bg={color} opacity={0.5} /> partial</span>
      <span className="flex items-center gap-1"><Sq bg="#2ecc71" /> goal hit</span>
    </div>
  );
}
function Sq({ bg, opacity = 1 }: { bg: string; opacity?: number }) {
  return (
    <span
      className="inline-block w-3 h-3 rounded"
      style={{ background: bg, opacity }}
      aria-hidden
    />
  );
}
