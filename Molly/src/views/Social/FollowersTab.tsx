import { useCallback, useEffect, useState } from 'react';
import type { Persona } from '../../state/personas';
import {
  listFollowersToday,
  listFollowerHistory,
  listCombinedFollowersToday,
  upsertFollowerCount,
  todayIsoLocal,
  type PlatformFollowerToday,
  type CombinedFollowerToday,
  type FollowerHistoryEntry,
} from '../../data/socialFollowers';
import { fmtFollowers } from '../../lib/followerForecast';
import { celebrateFollowerSave } from '../../lib/followerCelebration';
import { Sparkline } from '../../components/Sparkline';

const SPARK_DAYS = 30;

interface Props {
  active: Persona;
  onOpenPlatform: (platformId: number) => void;
  /** Bubble up after a save so the sidebar nudge-dot can refresh. */
  onChanged?: () => void;
}

export function FollowersTab({ active, onOpenPlatform, onChanged }: Props) {
  const personaCode = active.code === 'ALL' ? null : active.code;
  const today = todayIsoLocal();

  const [rows, setRows] = useState<PlatformFollowerToday[]>([]);
  const [combined, setCombined] = useState<CombinedFollowerToday[]>([]);
  const [sparks, setSparks] = useState<Record<number, FollowerHistoryEntry[]>>({});
  const [drafts, setDrafts] = useState<Record<number, string>>({});
  const [busy, setBusy] = useState<number | null>(null);
  const [status, setStatus] = useState('');

  const refresh = useCallback(async () => {
    try {
      if (personaCode == null) {
        setCombined(await listCombinedFollowersToday(today));
        setRows([]);
        return;
      }
      const today_ = await listFollowersToday(personaCode, today);
      setRows(today_);
      // Seed entry drafts from the latest known count so Sallie nudges up
      // from where she was instead of retyping the whole number.
      setDrafts((cur) => {
        const next = { ...cur };
        for (const r of today_) {
          if (next[r.platformId] === undefined) {
            next[r.platformId] = r.todayCount != null ? String(r.todayCount)
              : r.latestCount != null ? String(r.latestCount) : '';
          }
        }
        return next;
      });
      const series = await Promise.all(
        today_.map((r) => listFollowerHistory(personaCode, r.platformId, today, SPARK_DAYS)),
      );
      const map: Record<number, FollowerHistoryEntry[]> = {};
      today_.forEach((r, i) => { map[r.platformId] = series[i]; });
      setSparks(map);
    } catch (e) {
      setStatus(String(e));
    }
  }, [personaCode, today]);

  useEffect(() => { void refresh(); }, [refresh]);

  async function save(r: PlatformFollowerToday) {
    if (personaCode == null || busy != null) return;
    const raw = (drafts[r.platformId] ?? '').trim();
    if (raw === '') return;
    const n = Math.round(Number(raw));
    if (!Number.isFinite(n) || n < 0) { setStatus('Enter a whole number 💖'); return; }
    setBusy(r.platformId);
    try {
      const res = await upsertFollowerCount({ personaCode, platformId: r.platformId, countDate: today, followerCount: n });
      celebrateFollowerSave({
        platformName: r.name,
        delta: res.delta,
        justHitGoal: res.justHitGoal,
        goal: res.followerGoal,
      });
      await refresh();
      onChanged?.();
    } catch (e) {
      setStatus(`Couldn't save: ${String(e)}`);
    } finally {
      setBusy(null);
    }
  }

  // ----- ALL persona: combined, read-only -----
  if (personaCode == null) {
    return (
      <div className="space-y-3">
        <div className="pretty-card text-sm bg-amber-50 border border-amber-200">
          ☝️ This is the <strong>combined</strong> view across all your personas. Pick a persona in the
          sidebar to log today’s numbers.
        </div>
        {combined.map((c) => (
          <button
            key={c.platformId}
            type="button"
            onClick={() => onOpenPlatform(c.platformId)}
            className="pretty-card w-full text-left flex items-center gap-3 hover:shadow-md transition"
          >
            <span className="text-3xl select-none" aria-hidden>{c.icon}</span>
            <div className="flex-1 min-w-0">
              <div className="display-font text-lg font-semibold">{c.name}</div>
              <div className="text-[11px] opacity-60">
                {c.contributingPersonas > 0
                  ? `Combined from ${c.contributingPersonas} persona${c.contributingPersonas === 1 ? '' : 's'}’ latest entry`
                  : 'No follower history yet'}
              </div>
            </div>
            <div className="text-right">
              <div className="font-mono text-2xl font-bold tabular-nums leading-none" title={c.combinedLatest?.toLocaleString('en-US')}>
                {c.combinedLatest != null ? fmtFollowers(c.combinedLatest) : '—'}
              </div>
              <div className="text-[10px] uppercase tracking-wider opacity-60 mt-1">combined</div>
            </div>
          </button>
        ))}
        {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
      </div>
    );
  }

  // ----- Single persona: log + overview -----
  const unlogged = rows.filter((r) => r.todayCount == null);

  return (
    <div className="space-y-3">
      {unlogged.length > 0 && (
        <div className="pretty-card text-sm" style={{ background: 'rgb(var(--persona-tint))' }}>
          🌱 <strong>Psst —</strong> you haven’t told me today’s numbers for{' '}
          <strong>{unlogged.map((r) => r.name).join(', ')}</strong> yet. Pop them in below? 💖
        </div>
      )}

      {rows.map((r) => {
        const arrow = r.delta == null ? '▬' : r.delta > 0 ? '▲' : r.delta < 0 ? '▼' : '▬';
        const arrowColor = r.delta == null || r.delta === 0 ? 'rgba(0,0,0,0.35)' : r.delta > 0 ? '#1a7a45' : '#A32D2D';
        const loggedToday = r.todayCount != null;
        return (
          <div
            key={r.platformId}
            className="pretty-card flex items-center gap-3 flex-wrap"
            style={loggedToday ? { background: '#f3fbf6' } : undefined}
          >
            <button
              type="button"
              onClick={() => onOpenPlatform(r.platformId)}
              className="flex items-center gap-3 flex-1 min-w-[200px] text-left hover:opacity-80 transition"
              title="Open details, chart & forecast"
            >
              <span className="text-3xl select-none" aria-hidden>{r.icon}</span>
              <div className="min-w-0">
                <div className="display-font text-lg font-semibold">{r.name}</div>
                <div className="text-[11px] flex items-center gap-1.5">
                  <span className="font-mono font-bold tabular-nums" title={r.latestCount?.toLocaleString('en-US')}>
                    {r.latestCount != null ? fmtFollowers(r.latestCount) : '—'}
                  </span>
                  {r.delta != null && (
                    <span style={{ color: arrowColor }}>
                      {arrow} {fmtFollowers(Math.abs(r.delta))}
                    </span>
                  )}
                  {r.goalHit && <span title="Goal reached!">🎯</span>}
                </div>
              </div>
            </button>

            <Sparkline points={(sparks[r.platformId] ?? []).map((h) => ({ date: h.date, count: h.count }))} color={r.color} />

            <div className="flex items-center gap-2">
              <input
                type="number"
                inputMode="numeric"
                min={0}
                className="pretty-input w-28 font-mono text-right"
                placeholder="followers"
                value={drafts[r.platformId] ?? ''}
                onChange={(e) => setDrafts((d) => ({ ...d, [r.platformId]: e.target.value }))}
                onKeyDown={(e) => { if (e.key === 'Enter') void save(r); }}
              />
              <button
                type="button"
                className="pretty-button"
                disabled={busy === r.platformId}
                onClick={() => save(r)}
              >
                {loggedToday ? 'Update' : 'Save'}
              </button>
            </div>
          </div>
        );
      })}

      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}
