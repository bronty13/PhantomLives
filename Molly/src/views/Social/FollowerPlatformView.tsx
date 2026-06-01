import { useCallback, useEffect, useState } from 'react';
import type { Persona } from '../../state/personas';
import {
  listFollowersToday,
  listFollowerHistory,
  listLoggedFollowerHistory,
  listCombinedFollowersToday,
  upsertFollowerCount,
  deleteFollowerCount,
  setSocialPlatformFollowerGoal,
  todayIsoLocal,
  type PlatformFollowerToday,
  type FollowerHistoryEntry,
  type LoggedPoint,
  type CombinedFollowerToday,
} from '../../data/socialFollowers';
import { forecast, fmtFollowers, daysBetween, prettyDate } from '../../lib/followerForecast';
import { celebrateFollowerSave } from '../../lib/followerCelebration';
import { FollowerChart } from '../../components/FollowerChart';

const HISTORY_DAYS = 90;

interface Props {
  active: Persona;
  platformId: number;
  onBack: () => void;
  onChanged?: () => void;
}

export function FollowerPlatformView({ active, platformId, onBack, onChanged }: Props) {
  const personaCode = active.code === 'ALL' ? null : active.code;
  const today = todayIsoLocal();

  const [row, setRow] = useState<PlatformFollowerToday | null>(null);
  const [dense, setDense] = useState<FollowerHistoryEntry[]>([]);
  const [logged, setLogged] = useState<LoggedPoint[]>([]);
  const [combinedRow, setCombinedRow] = useState<CombinedFollowerToday | null>(null);
  const [goalDraft, setGoalDraft] = useState('');
  const [backfillDate, setBackfillDate] = useState(today);
  const [backfillCount, setBackfillCount] = useState('');
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState('');

  const refresh = useCallback(async () => {
    try {
      if (personaCode == null) {
        const combined = await listCombinedFollowersToday(today);
        setCombinedRow(combined.find((c) => c.platformId === platformId) ?? null);
        return;
      }
      const [today_, d, lg] = await Promise.all([
        listFollowersToday(personaCode, today),
        listFollowerHistory(personaCode, platformId, today, HISTORY_DAYS),
        listLoggedFollowerHistory(personaCode, platformId, today),
      ]);
      const me = today_.find((r) => r.platformId === platformId) ?? null;
      setRow(me);
      setDense(d);
      setLogged(lg);
      if (me) setGoalDraft(String(me.followerGoal));
    } catch (e) {
      setStatus(String(e));
    }
  }, [personaCode, today, platformId]);

  useEffect(() => { void refresh(); }, [refresh]);

  async function saveCount(date: string, raw: string, quiet: boolean) {
    if (personaCode == null) return;
    const n = Math.round(Number(raw.trim()));
    if (raw.trim() === '' || !Number.isFinite(n) || n < 0) { setStatus('Enter a whole number 💖'); return; }
    setBusy(true);
    try {
      const res = await upsertFollowerCount({ personaCode, platformId, countDate: date, followerCount: n });
      celebrateFollowerSave({ platformName: row?.name ?? 'this platform', delta: res.delta, justHitGoal: res.justHitGoal, goal: res.followerGoal, quiet });
      await refresh();
      onChanged?.();
    } catch (e) {
      setStatus(`Couldn't save: ${String(e)}`);
    } finally {
      setBusy(false);
    }
  }

  async function removeDay(date: string) {
    if (personaCode == null) return;
    if (!confirm(`Remove the entry for ${date}?`)) return;
    setBusy(true);
    try {
      await deleteFollowerCount(personaCode, platformId, date);
      setStatus(`Removed ${date}.`);
      await refresh();
      onChanged?.();
    } catch (e) {
      setStatus(`Couldn't remove: ${String(e)}`);
    } finally {
      setBusy(false);
    }
  }

  async function commitGoal() {
    if (!row) return;
    const n = Math.round(Number(goalDraft));
    if (!Number.isFinite(n) || n < 0) { setGoalDraft(String(row.followerGoal)); return; }
    if (n === row.followerGoal) return;
    try {
      await setSocialPlatformFollowerGoal(platformId, n);
      await refresh();
    } catch (e) {
      setStatus(String(e));
    }
  }

  const backLink = (
    <button type="button" className="text-sm opacity-70 hover:opacity-100 mb-1" onClick={onBack}>
      ← Back to all platforms
    </button>
  );

  // ----- ALL persona: combined breakdown only (no combined history line) -----
  if (personaCode == null) {
    return (
      <div className="space-y-3">
        {backLink}
        <div className="pretty-card flex items-center gap-3">
          <span className="text-4xl select-none" aria-hidden>{combinedRow?.icon}</span>
          <div className="flex-1">
            <div className="display-font text-2xl font-bold">{combinedRow?.name}</div>
            <div className="text-xs opacity-60">Combined across personas (each persona’s latest entry)</div>
          </div>
          <div className="text-right">
            <div className="font-mono text-3xl font-bold tabular-nums" title={combinedRow?.combinedLatest?.toLocaleString('en-US')}>
              {combinedRow?.combinedLatest != null ? fmtFollowers(combinedRow.combinedLatest) : '—'}
            </div>
            <div className="text-[10px] uppercase tracking-wider opacity-60">combined</div>
          </div>
        </div>
        <div className="pretty-card">
          <div className="text-xs uppercase tracking-wider opacity-60 mb-2">Per-persona breakdown</div>
          {combinedRow && combinedRow.breakdown.length > 0 ? (
            <table className="w-full text-sm">
              <tbody>
                {combinedRow.breakdown.map((b) => (
                  <tr key={b.personaCode} className="border-t" style={{ borderColor: 'rgba(0,0,0,0.08)' }}>
                    <td className="py-2 font-semibold">{b.personaName}</td>
                    <td className="py-2 text-right font-mono" title={b.latestCount?.toLocaleString('en-US')}>
                      {b.latestCount != null ? fmtFollowers(b.latestCount) : '—'}
                    </td>
                    <td className="py-2 text-right text-xs opacity-50">{b.latestDate ? `as of ${b.latestDate}` : ''}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <div className="text-sm opacity-60 italic">No follower history yet. Pick a persona to start logging.</div>
          )}
          <div className="text-xs opacity-60 mt-2">
            💡 Pick a single persona in the sidebar to see the growth chart, trend & forecast.
          </div>
        </div>
        {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
      </div>
    );
  }

  if (!row) return <div className="opacity-60 italic">Loading…</div>;

  const fc = forecast(logged, row.followerGoal, today);
  const chartPoints = dense.map((h) => ({ date: h.date, count: h.count }));
  const overlay =
    fc.status === 'on-track' && fc.etaDate != null && row.latestCount != null && row.latestDate != null
      ? { slopePerDay: fc.slopePerDay!, fromDate: row.latestDate, fromCount: row.latestCount, etaDate: fc.etaDate, goal: row.followerGoal }
      : null;

  // Δ over the last ~7 days (nearest logged on/before today-7).
  const weekAgo = addDaysLocal(today, -7);
  const baselineWeek = lastOnOrBefore(logged, weekAgo);
  const weekDelta = row.latestCount != null && baselineWeek != null ? row.latestCount - baselineWeek : null;
  const goalPct = row.followerGoal > 0 && row.latestCount != null
    ? Math.min(100, Math.round((row.latestCount / row.followerGoal) * 100)) : null;

  const loggedDesc = [...dense].filter((h) => h.isLogged).reverse();

  return (
    <div className="space-y-3">
      {backLink}

      {/* Header */}
      <div className="pretty-card flex items-center gap-4 flex-wrap" style={{ background: row.goalHit ? '#e9f9ee' : 'rgb(var(--persona-tint))' }}>
        <span className="text-4xl select-none" aria-hidden>{row.icon}</span>
        <div className="flex-1 min-w-[200px]">
          <div className="display-font text-2xl font-bold">{row.name}</div>
          <div className="text-xs opacity-60">
            {row.todayCount != null ? '✓ logged today' : 'not logged today yet'}
            {row.followerGoal > 0 && <> · goal {fmtFollowers(row.followerGoal)} 🎯</>}
          </div>
        </div>
        <div className="text-right">
          <div className="font-mono text-3xl font-bold tabular-nums leading-none" title={row.latestCount?.toLocaleString('en-US')}>
            {row.latestCount != null ? fmtFollowers(row.latestCount) : '—'}
          </div>
          <div className="text-[10px] uppercase tracking-wider opacity-60 mt-1">followers</div>
        </div>
      </div>

      {/* Chart */}
      <div className="pretty-card overflow-x-auto">
        <FollowerChart points={chartPoints} goal={row.followerGoal} forecast={overlay} color={row.color} />
      </div>

      {/* Forecast card */}
      <div className="pretty-card" style={{ background: 'rgb(var(--persona-secondary) / 0.4)' }}>
        <div className="text-xs uppercase tracking-wider opacity-60 mb-1">🔮 Forecast</div>
        <div className="text-base">{fc.message}</div>
        {fc.status === 'on-track' && fc.etaDate && (
          <div className="text-xs opacity-60 mt-1">Estimated to reach your goal by {prettyDate(fc.etaDate)}.</div>
        )}
      </div>

      {/* Stats strip */}
      <div className="pretty-card grid grid-cols-2 sm:grid-cols-4 gap-3 text-center">
        <Stat label="Latest" value={row.latestCount != null ? fmtFollowers(row.latestCount) : '—'} />
        <Stat label="This week" value={weekDelta != null ? `${weekDelta >= 0 ? '+' : ''}${fmtFollowers(weekDelta)}` : '—'} accent={weekDelta != null ? (weekDelta >= 0 ? '#1a7a45' : '#A32D2D') : undefined} />
        <Stat label="Avg / day" value={fc.avgPerDay != null ? `${fc.avgPerDay >= 0 ? '+' : ''}${fmtFollowers(Math.round(fc.avgPerDay))}` : '—'} />
        <Stat label={row.followerGoal > 0 ? 'To goal' : 'Days logged'} value={row.followerGoal > 0 ? (goalPct != null ? `${goalPct}%` : '—') : String(logged.length)} />
      </div>

      {/* Goal editor */}
      <div className="pretty-card space-y-2">
        <div className="text-xs uppercase tracking-wider opacity-60">Follower goal 🎯</div>
        <div className="flex items-center gap-2">
          <input
            type="number"
            min={0}
            className="pretty-input w-32 font-mono"
            value={goalDraft}
            onChange={(e) => setGoalDraft(e.target.value)}
            onBlur={commitGoal}
            onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur(); }}
          />
          <span className="text-sm opacity-70">target followers on {row.name}</span>
        </div>
        <div className="text-xs opacity-60">Applies to every persona. Set to 0 for no goal (forecast shows trend only).</div>
      </div>

      {/* History editor */}
      <div className="pretty-card space-y-2">
        <div className="text-xs uppercase tracking-wider opacity-60">History · edit or backfill</div>
        <div className="flex items-center gap-2 flex-wrap">
          <input type="date" className="pretty-input" max={today} value={backfillDate} onChange={(e) => setBackfillDate(e.target.value)} />
          <input
            type="number" min={0} className="pretty-input w-28 font-mono text-right" placeholder="followers"
            value={backfillCount} onChange={(e) => setBackfillCount(e.target.value)}
          />
          <button
            type="button" className="pretty-button" disabled={busy}
            onClick={() => { void saveCount(backfillDate, backfillCount, backfillDate !== today); setBackfillCount(''); }}
          >
            ＋ Add / update
          </button>
        </div>
        {loggedDesc.length === 0 ? (
          <div className="text-sm opacity-60 italic">No entries yet.</div>
        ) : (
          <table className="w-full text-sm">
            <tbody>
              {loggedDesc.map((h) => (
                <HistoryRow key={h.date} date={h.date} count={h.count!} busy={busy} onSave={(v) => saveCount(h.date, v, h.date !== today)} onDelete={() => removeDay(h.date)} />
              ))}
            </tbody>
          </table>
        )}
      </div>

      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}

function Stat({ label, value, accent }: { label: string; value: string; accent?: string }) {
  return (
    <div>
      <div className="font-mono text-xl font-bold tabular-nums" style={accent ? { color: accent } : undefined}>{value}</div>
      <div className="text-[10px] uppercase tracking-wider opacity-60 mt-0.5">{label}</div>
    </div>
  );
}

function HistoryRow({ date, count, busy, onSave, onDelete }: {
  date: string; count: number; busy: boolean; onSave: (v: string) => void; onDelete: () => void;
}) {
  const [draft, setDraft] = useState(String(count));
  useEffect(() => { setDraft(String(count)); }, [count]);
  const dirty = draft.trim() !== String(count);
  return (
    <tr className="border-t" style={{ borderColor: 'rgba(0,0,0,0.08)' }}>
      <td className="py-1.5 font-mono text-xs opacity-70">{date}</td>
      <td className="py-1.5 text-right">
        <input
          type="number" min={0} className="pretty-input w-28 font-mono text-right" value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') onSave(draft); }}
        />
      </td>
      <td className="py-1.5 text-right whitespace-nowrap">
        {dirty && (
          <button type="button" className="text-xs pretty-button px-2 py-1 mr-1" disabled={busy} onClick={() => onSave(draft)}>Save</button>
        )}
        <button type="button" className="text-base opacity-50 hover:opacity-100 hover:text-red-600 px-1" disabled={busy} onClick={onDelete} title="Remove">✕</button>
      </td>
    </tr>
  );
}

// Local date helpers (avoid importing the forecast internals).
function addDaysLocal(iso: string, n: number): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!m) return iso;
  const d = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])) + n * 86_400_000);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
}
function lastOnOrBefore(series: LoggedPoint[], date: string): number | null {
  let best: number | null = null;
  for (const p of series) {
    if (daysBetween(p.date, date) >= 0) best = p.count; // series is oldest-first
    else break;
  }
  return best;
}
