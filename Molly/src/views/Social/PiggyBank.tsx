import { useCallback, useEffect, useState } from 'react';
import type { Persona } from '../../state/personas';
import {
  addSocialDrop,
  computeSocialOverallStreak,
  listSocialToday,
  todayIsoLocal,
  undoLastSocialDrop,
  type PlatformToday,
} from '../../data/socialDrops';
import { isCoinSoundMuted, playCoin, playGoalHit, setCoinSoundMuted } from '../../lib/coinSound';

interface Props {
  active: Persona;
}

const SOUND_KEY = 'molly.piggyBank.soundMuted';

export function PiggyBank({ active }: Props) {
  const personaCode = active.code === 'ALL' ? null : active.code;
  const [rows, setRows] = useState<PlatformToday[]>([]);
  const [streak, setStreak] = useState(0);
  const [busyPlatform, setBusyPlatform] = useState<number | null>(null);
  const [status, setStatus] = useState('');
  const [muted, setMuted] = useState<boolean>(() => {
    try { return localStorage.getItem(SOUND_KEY) === '1'; }
    catch { return false; }
  });
  useEffect(() => { setCoinSoundMuted(muted); }, [muted]);

  const today = todayIsoLocal();

  const refresh = useCallback(async () => {
    try {
      const [r, s] = await Promise.all([
        listSocialToday(personaCode, today),
        computeSocialOverallStreak(personaCode, today),
      ]);
      setRows(r);
      setStreak(s);
    } catch (e) {
      setStatus(String(e));
    }
  }, [personaCode, today]);

  useEffect(() => { void refresh(); }, [refresh]);

  async function onDrop(p: PlatformToday) {
    if (busyPlatform != null) return;
    setBusyPlatform(p.platformId);
    setStatus('');
    try {
      const res = await addSocialDrop({
        personaCode,
        platformId: p.platformId,
        postedDate: today,
      });
      if (res.justHit) playGoalHit();
      else playCoin();
      // Optimistic local update so the count feels instant; refresh
      // re-syncs in case anything else changed (e.g. subreddit_posts).
      setRows((cur) =>
        cur.map((r) =>
          r.platformId === p.platformId
            ? { ...r, count: res.newCount, hit: res.hit }
            : r,
        ),
      );
      // Streak might have just ticked up if this drop completed the
      // last unmet platform for today — re-fetch.
      void computeSocialOverallStreak(personaCode, today).then(setStreak);
    } catch (e) {
      setStatus(String(e));
    } finally {
      setBusyPlatform(null);
    }
  }

  async function onUndo(p: PlatformToday) {
    if (busyPlatform != null) return;
    if (p.count <= 0) return;
    setBusyPlatform(p.platformId);
    try {
      const removed = await undoLastSocialDrop(personaCode, p.platformId, today);
      if (!removed) {
        setStatus('Nothing to undo for that platform today.');
      }
      await refresh();
    } catch (e) {
      setStatus(String(e));
    } finally {
      setBusyPlatform(null);
    }
  }

  const hitCount = rows.filter((r) => r.hit).length;
  const todayLabel = new Date().toLocaleDateString(undefined, {
    weekday: 'long', month: 'long', day: 'numeric',
  });

  return (
    <div className="space-y-3">
      <div
        className="pretty-card flex items-center gap-6 flex-wrap"
        style={{ background: 'rgb(var(--persona-tint))' }}
      >
        <div>
          <div className="display-font text-2xl font-bold persona-accent">{todayLabel}</div>
          <div className="text-xs opacity-60">
            Piggy bank · drop a coin every time you post · resets at midnight
          </div>
        </div>
        <div className="flex gap-6 ml-auto items-center">
          <Stat n={`${hitCount}/${rows.length}`} label="platforms hit" />
          <Stat n={streak} label={streak === 1 ? 'day streak' : 'day streak'} icon={streak > 0 ? '🔥' : undefined} />
          <button
            type="button"
            onClick={() => {
              const next = !muted;
              setMuted(next);
              try { localStorage.setItem(SOUND_KEY, next ? '1' : '0'); }
              catch { /* private mode */ }
              if (!next) playCoin();
            }}
            title={muted ? 'Sound off — click to enable' : 'Sound on — click to mute'}
            className="text-xl opacity-70 hover:opacity-100"
          >
            {muted ? '🔇' : '🔔'}
          </button>
        </div>
      </div>

      {active.code === 'ALL' && (
        <div className="pretty-card text-sm bg-amber-50 border border-amber-200">
          ☝️ The piggy bank is persona-scoped. Pick <strong>Curves</strong> or <strong>Princess</strong>
          in the sidebar to start dropping coins.
        </div>
      )}

      <div className="space-y-2">
        {rows.map((p) => {
          const pct = p.dailyGoal > 0 ? Math.min(100, (p.count / p.dailyGoal) * 100) : 0;
          const isBusy = busyPlatform === p.platformId;
          return (
            <div
              key={p.platformId}
              className="pretty-card flex items-center gap-3 flex-wrap"
              style={{
                background: p.hit ? '#e9f9ee' : undefined,
                borderColor: p.hit ? '#a8e6c1' : undefined,
                borderWidth: 1,
                borderStyle: 'solid',
                transition: 'background 0.25s',
              }}
            >
              <span className="text-2xl select-none" aria-hidden>{p.icon}</span>
              <div className="flex-1 min-w-[180px]">
                <div className="flex items-baseline gap-2">
                  <span className="font-semibold">{p.name}</span>
                  {p.hit && <span className="text-xs text-emerald-700 font-bold">✓ DONE</span>}
                </div>
                <CoinSlots count={p.count} goal={p.dailyGoal} color={p.color} />
                <div
                  className="mt-1 h-1.5 rounded-full bg-black/5 overflow-hidden"
                  aria-hidden
                >
                  <div
                    className="h-full"
                    style={{
                      width: `${pct}%`,
                      background: p.hit ? '#2ecc71' : p.color,
                      transition: 'width 0.3s',
                    }}
                  />
                </div>
              </div>
              <div className="flex items-center gap-2">
                <div className="font-mono text-sm tabular-nums w-12 text-right">
                  {p.count}/{p.dailyGoal}
                </div>
                <button
                  type="button"
                  className="pretty-button"
                  disabled={isBusy || active.code === 'ALL'}
                  onClick={() => onDrop(p)}
                  title={active.code === 'ALL' ? 'Pick a persona first' : '+1 post'}
                >
                  {p.hit ? '+1 More' : '+1 Post'}
                </button>
                <button
                  type="button"
                  className="text-xs opacity-50 hover:opacity-100 hover:text-red-600 px-2"
                  disabled={isBusy || p.count <= 0}
                  onClick={() => onUndo(p)}
                  title="Undo last coin"
                >
                  ↶
                </button>
              </div>
            </div>
          );
        })}
        {rows.length === 0 && (
          <div className="pretty-card opacity-60 italic text-sm">
            No active platforms — add some in Settings → Platforms.
          </div>
        )}
      </div>

      {status && (
        <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>
      )}
    </div>
  );
}

function CoinSlots({ count, goal, color }: { count: number; goal: number; color: string }) {
  // For small goals (<=12) draw discrete coin slots — feels like a
  // piggy bank. For larger goals fall back to just the progress bar
  // (the row below this one) so we don't overflow.
  if (goal > 12) return null;
  const slots = Array.from({ length: goal }, (_, i) => i < count);
  return (
    <div className="flex gap-1 mt-1" aria-hidden>
      {slots.map((filled, i) => (
        <span
          key={i}
          className="inline-block w-3.5 h-3.5 rounded-full transition"
          style={{
            background: filled ? color : 'transparent',
            border: `2px solid ${filled ? color : 'rgba(0,0,0,0.18)'}`,
          }}
        />
      ))}
      {count > goal && (
        <span className="text-[10px] opacity-60 ml-1 self-center">+{count - goal}</span>
      )}
    </div>
  );
}

function Stat({ n, label, icon }: { n: number | string; label: string; icon?: string }) {
  return (
    <div className="text-center">
      <div className="display-font text-2xl font-bold persona-accent leading-none">
        {icon && <span className="mr-1">{icon}</span>}{n}
      </div>
      <div className="text-[10px] uppercase tracking-wider opacity-60 mt-0.5">{label}</div>
    </div>
  );
}

// Force the coin-sound module to read its initial muted state once
// when this module loads (so playCoin() respects the stored pref even
// before PiggyBank mounts and runs its useEffect).
try {
  const v = typeof localStorage !== 'undefined' && localStorage.getItem(SOUND_KEY) === '1';
  setCoinSoundMuted(v);
} catch { /* SSR or private mode */ }
void isCoinSoundMuted; // keep import referenced
