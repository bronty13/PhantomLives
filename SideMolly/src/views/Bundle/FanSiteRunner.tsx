// Phase 13 — 📅 FanSite multi-site Post Runner.
//
// FanSite bundles post before the start of each month, on a calendar
// cadence, to a FIXED ROSTER of sites per persona (CoC → OnlyFans /
// ManyVids / Niteflirt; PoA → OnlyFans / Niteflirt / LoyalFans; Sheer
// excluded). None of the sites take API posts, so the runner's whole
// job is to put the right info + the right media in front of Robert
// and track what's posted where.
//
// Workflow: pick a site, walk every day posting it, then switch to the
// next site. Per-day state is keyed (uid, target, day) in the DB so
// stop/resume just works — the runner auto-focuses the next pending day
// for the active site. "Reset this site" / "Reset all" unwind to start
// fresh. Every posted/unposted/reset action lands in the posting log
// (viewable below + carried back to Molly in the post-bundle).
//
// The media is made infallible by `prepare_fansite_day`: it stages
// exactly that day's files (rotated + EXIF-stripped, no watermark —
// the sites stamp their own) into one folder, so the upload dialog can
// only ever see the correct files.

import { useCallback, useEffect, useMemo, useState } from 'react';
import { openUrl } from '@tauri-apps/plugin-opener';
import {
  getBundleThumbnails, getFanSitePlan, listPostingLog, prepareFanSiteDay,
  resetFanSitePostings, revealFanSiteDay, seedFanSiteTargets, setFanSiteDay,
  type BundleDetail, type BundleSummary,
  type FanSiteDay, type FanSitePlan, type FanSiteTargetDay,
  type PostingLogRow, type PostingState, type PostingTarget, type PreparedDay,
} from '../../data/bundles';

interface Props {
  summary: BundleSummary;
  detail: BundleDetail;
}

const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
const DOW_HEADER = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

// Normalize a user-typed site URL so the opener accepts it: lowercase
// the scheme (the ACL glob "https://*" is case-sensitive, so a typed
// "Https://…" would be rejected) and add https:// when no scheme is
// present ("www.onlyfans.com" → "https://www.onlyfans.com").
function normalizeUrl(raw: string): string {
  const u = raw.trim();
  const m = u.match(/^(https?):\/\//i);
  if (m) return m[1].toLowerCase() + u.slice(m[1].length);
  return `https://${u}`;
}

// Persona prominent colors — mirror the --persona-* CSS vars.
function personaTheme(code: string | null): { rgbVar: string; fg: string; label: string } {
  switch (code) {
    case 'CoC': return { rgbVar: '--persona-coc', fg: '#3a0a24', label: 'CoC' };
    case 'PoA': return { rgbVar: '--persona-poa', fg: '#ffffff', label: 'PoA' };
    case 'Sa':  return { rgbVar: '--persona-sa',  fg: '#3A2F22', label: 'Sa'  };
    default:    return { rgbVar: '--surface-border', fg: 'rgb(var(--surface-text))', label: code ?? '—' };
  }
}

export function FanSiteRunner({ summary }: Props) {
  const [plan, setPlan] = useState<FanSitePlan | null>(null);
  const [thumbs, setThumbs] = useState<Record<string, string>>({});
  const [log, setLog] = useState<PostingLogRow[]>([]);
  const [activeTargetId, setActiveTargetId] = useState<number | null>(null);
  const [focused, setFocused] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(async () => {
    setError(null);
    try {
      const [p, lg] = await Promise.all([
        getFanSitePlan(summary.uid),
        listPostingLog(summary.uid),
      ]);
      setPlan(p);
      setLog(lg);
    } catch (e) { setError(String(e)); }
  }, [summary.uid]);

  useEffect(() => { refresh(); }, [refresh]);

  // Thumbnails are bundle-wide; load once.
  useEffect(() => {
    getBundleThumbnails(summary.uid).then(setThumbs).catch(() => {});
  }, [summary.uid]);

  // Resolve the active site: prefer the persisted choice, else the
  // first site with pending days, else the first site.
  useEffect(() => {
    if (!plan || plan.targets.length === 0) return;
    if (activeTargetId != null && plan.targets.some((t) => t.id === activeTargetId)) return;
    const stored = Number(localStorage.getItem(`fansite-active-${summary.uid}`));
    if (stored && plan.targets.some((t) => t.id === stored)) {
      setActiveTargetId(stored);
      return;
    }
    const firstPending = plan.targets.find((t) => countForTarget(plan, t.id).pending > 0);
    setActiveTargetId((firstPending ?? plan.targets[0]).id);
  }, [plan, activeTargetId, summary.uid]);

  const selectSite = (id: number) => {
    setActiveTargetId(id);
    setFocused(null);
    localStorage.setItem(`fansite-active-${summary.uid}`, String(id));
  };

  // Auto-focus the next pending day for the active site.
  useEffect(() => {
    if (plan && activeTargetId != null && focused == null) {
      const next = plan.days.find((d) => stateFor(d, activeTargetId) === 'pending'
                                       || stateFor(d, activeTargetId) === 'scheduled');
      if (next) setFocused(next.dayOfMonth);
    }
  }, [plan, activeTargetId, focused]);

  if (error) {
    return (
      <div className="sm-card text-sm" style={{ color: '#7a0000', background: '#ffe4e4' }}>
        ⚠ {error}
      </div>
    );
  }
  if (!plan) {
    return <div className="sm-card text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>Loading…</div>;
  }

  const theme = personaTheme(plan.personaCode);
  const monthLabel = plan.year != null && plan.month != null
    ? `${MONTHS[(plan.month - 1) % 12]} ${plan.year}`
    : (plan.title || summary.uid);
  const isSheer = plan.personaCode === 'Sa';

  const doSeed = async () => {
    setBusy(true);
    try { await seedFanSiteTargets(); await refresh(); }
    catch (e) { alert(String(e)); }
    finally { setBusy(false); }
  };

  const activeTarget = plan.targets.find((t) => t.id === activeTargetId) ?? null;

  return (
    <div className="flex flex-col gap-4">
      {/* Persona banner — prominent persona color. */}
      <section
        className="rounded-lg p-3"
        style={{ background: `rgb(var(${theme.rgbVar}))`, color: theme.fg }}
      >
        <div className="flex items-center justify-between flex-wrap gap-2">
          <div className="flex items-center gap-2 text-base font-bold">
            <span style={{ fontSize: 22 }}>📅</span>
            <span>FanSite · {theme.label} · {monthLabel}</span>
          </div>
          <div className="flex items-center gap-1.5">
            <CopyChip label="Persona" value={theme.label} fg={theme.fg} />
            {plan.year != null && plan.month != null && (
              <CopyChip label="Month" value={`${plan.year}-${String(plan.month).padStart(2, '0')}`} fg={theme.fg} />
            )}
            <CopyChip label="Title" value={plan.title} fg={theme.fg} />
          </div>
        </div>
        {plan.title && (
          <div className="text-sm mt-1 opacity-90 font-semibold">{plan.title}</div>
        )}
      </section>

      {plan.targets.length === 0 ? (
        <div className="sm-card text-sm">
          {isSheer ? (
            <div>
              <div className="font-semibold mb-1">Sheer has no fan-sites</div>
              <div style={{ color: 'rgb(var(--surface-muted))' }}>
                Per the workflow, we don't post fan-sites for Sheer (Sa).
              </div>
            </div>
          ) : (
            <div>
              <div className="font-semibold mb-1">No fan-sites set up for {theme.label}</div>
              <div className="mb-2" style={{ color: 'rgb(var(--surface-muted))' }}>
                Create the canonical roster
                {plan.personaCode === 'CoC' && ' (OnlyFans · ManyVids · Niteflirt)'}
                {plan.personaCode === 'PoA' && ' (OnlyFans · Niteflirt · LoyalFans)'}
                . Idempotent — your edits in Settings → Platforms are preserved.
              </div>
              <button type="button" className="sm-button text-sm" onClick={doSeed} disabled={busy}>
                🚀 Set up fan-sites for {theme.label}
              </button>
            </div>
          )}
        </div>
      ) : (
        <>
          {/* Site tabs with per-site progress. */}
          <SiteTabs
            plan={plan}
            activeTargetId={activeTargetId}
            onSelect={selectSite}
          />

          {activeTarget && activeTargetId != null && (
            <>
              <Calendar
                plan={plan}
                targetId={activeTargetId}
                focused={focused}
                onFocus={setFocused}
              />
              {focused != null && (() => {
                const day = plan.days.find((d) => d.dayOfMonth === focused);
                if (!day) return null;
                return (
                  <DayCard
                    plan={plan}
                    target={activeTarget}
                    day={day}
                    thumbs={thumbs}
                    onChange={refresh}
                    onAdvance={() => advance(plan, activeTargetId, day.dayOfMonth, setFocused)}
                  />
                );
              })()}

              <ResetControls
                target={activeTarget}
                onReset={async (scope) => {
                  setBusy(true);
                  try {
                    await resetFanSitePostings(summary.uid, scope === 'site' ? activeTargetId : null);
                    setFocused(null);
                    await refresh();
                  } catch (e) { alert(String(e)); }
                  finally { setBusy(false); }
                }}
                busy={busy}
              />
            </>
          )}
        </>
      )}

      <PostingLogPanel log={log} />
    </div>
  );
}

// ---------------------------------------------------------------------------
// State helpers
// ---------------------------------------------------------------------------

function stateFor(day: FanSiteDay, targetId: number): PostingState {
  return (day.targets.find((t) => t.targetId === targetId)?.state ?? 'pending') as PostingState;
}

function targetDayFor(day: FanSiteDay, targetId: number): FanSiteTargetDay {
  return day.targets.find((t) => t.targetId === targetId)
    ?? { targetId, state: 'pending', postedAt: null, postedUrl: null, notes: null };
}

function countForTarget(plan: FanSitePlan, targetId: number): Record<PostingState, number> & { total: number } {
  const c = { pending: 0, scheduled: 0, posted: 0, skipped: 0, total: plan.days.length } as
    Record<PostingState, number> & { total: number };
  for (const d of plan.days) c[stateFor(d, targetId)] += 1;
  return c;
}

function advance(plan: FanSitePlan, targetId: number, currentDay: number,
                 setFocused: (d: number | null) => void) {
  const next = plan.days.find((d) => d.dayOfMonth > currentDay
                                 && (stateFor(d, targetId) === 'pending' || stateFor(d, targetId) === 'scheduled'));
  setFocused(next ? next.dayOfMonth : null);
}

function statePill(s: PostingState): { glyph: string; bg: string; fg: string } {
  switch (s) {
    case 'posted':    return { glyph: '✓', bg: '#deffee', fg: '#0f5d33' };
    case 'scheduled': return { glyph: '🗓', bg: '#eef2ff', fg: '#3730a3' };
    case 'skipped':   return { glyph: '—', bg: 'rgb(var(--surface-base))', fg: 'rgb(var(--surface-muted))' };
    case 'pending':
    default:          return { glyph: '·', bg: 'rgb(var(--surface-card))', fg: 'rgb(var(--surface-text))' };
  }
}

// ---------------------------------------------------------------------------
// Site tabs
// ---------------------------------------------------------------------------

function SiteTabs({ plan, activeTargetId, onSelect }: {
  plan: FanSitePlan;
  activeTargetId: number | null;
  onSelect: (id: number) => void;
}) {
  return (
    <div className="flex flex-wrap gap-1.5">
      {plan.targets.map((t) => {
        const c = countForTarget(plan, t.id);
        const active = t.id === activeTargetId;
        const done = c.posted === c.total && c.total > 0;
        return (
          <button
            key={t.id}
            type="button"
            onClick={() => onSelect(t.id)}
            className="rounded px-3 py-1.5 text-xs flex items-center gap-1.5 transition"
            style={{
              border: active ? `2px solid ${t.color}` : '1px solid rgb(var(--surface-border))',
              background: active ? `${t.color}22` : 'rgb(var(--surface-card))',
              fontWeight: active ? 700 : 500,
            }}
          >
            <span style={{ fontSize: 14 }}>{t.icon}</span>
            <span>{t.name}</span>
            <span className="font-mono" style={{ color: done ? '#0f5d33' : 'rgb(var(--surface-muted))' }}>
              {done ? '✓ done' : `${c.posted}/${c.total}`}
            </span>
          </button>
        );
      })}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Calendar
// ---------------------------------------------------------------------------

function Calendar({ plan, targetId, focused, onFocus }: {
  plan: FanSitePlan;
  targetId: number;
  focused: number | null;
  onFocus: (day: number | null) => void;
}) {
  const offset = useMemo(() => {
    if (plan.year == null || plan.month == null) return null;
    const firstDow = new Date(plan.year, plan.month - 1, 1).getDay(); // 0=Sun
    return (firstDow + 6) % 7; // Mon=0..Sun=6
  }, [plan.year, plan.month]);

  if (offset == null) return null;

  const daysByNumber = new Map<number, FanSiteDay>();
  for (const d of plan.days) daysByNumber.set(d.dayOfMonth, d);
  const lastDay = plan.days.reduce((m, d) => Math.max(m, d.dayOfMonth), 0);

  const flat: Array<{ day: number; row?: FanSiteDay } | null> = [];
  for (let i = 0; i < offset; i++) flat.push(null);
  for (let d = 1; d <= lastDay; d++) flat.push({ day: d, row: daysByNumber.get(d) });
  while (flat.length % 7 !== 0) flat.push(null);

  return (
    <section className="sm-card">
      <div className="grid grid-cols-7 gap-1 text-[10px] font-semibold mb-1" style={{ color: 'rgb(var(--surface-muted))' }}>
        {DOW_HEADER.map((d) => <div key={d} className="px-1 py-0.5">{d}</div>)}
      </div>
      <div className="grid grid-cols-7 gap-1">
        {flat.map((cell, i) => {
          if (!cell) return <div key={`pad-${i}`} />;
          const hasContent = cell.row != null;
          const pill = cell.row ? statePill(stateFor(cell.row, targetId)) : null;
          const isFocused = focused === cell.day;
          return (
            <button
              key={cell.day}
              type="button"
              onClick={() => onFocus(cell.day)}
              disabled={!hasContent}
              className="rounded p-1.5 text-left flex flex-col items-stretch transition"
              style={{
                border: isFocused ? '2px solid rgb(var(--surface-accent))' : '1px solid rgb(var(--surface-border))',
                background: pill?.bg ?? 'rgb(var(--surface-card))',
                color: pill?.fg ?? 'rgb(var(--surface-text))',
                opacity: hasContent ? 1 : 0.4,
                cursor: hasContent ? 'pointer' : 'default',
                minHeight: 60,
              }}
            >
              <div className="text-xs font-bold">{cell.day}</div>
              {cell.row && (
                <>
                  <div className="text-[9px] truncate" style={{ opacity: 0.85 }} title={cell.row.message}>
                    {cell.row.message || '—'}
                  </div>
                  <div className="text-[9px] mt-auto flex items-center justify-between">
                    <span>{pill?.glyph}</span>
                    <span>{cell.row.fileCount} file{cell.row.fileCount === 1 ? '' : 's'}</span>
                  </div>
                </>
              )}
            </button>
          );
        })}
      </div>
    </section>
  );
}

// ---------------------------------------------------------------------------
// Day card
// ---------------------------------------------------------------------------

function DayCard({ plan, target, day, thumbs, onChange, onAdvance }: {
  plan: FanSitePlan;
  target: PostingTarget;
  day: FanSiteDay;
  thumbs: Record<string, string>;
  onChange: () => void;
  onAdvance: () => void;
}) {
  const td = targetDayFor(day, target.id);
  // FanSite posting is binary — posted or not. (No scheduled/skipped,
  // no URL to record: the sites don't surface a post URL.)
  const isPosted = td.state === 'posted';
  const [notes, setNotes] = useState(td.notes ?? '');
  const [prepared, setPrepared] = useState<PreparedDay | null>(null);
  const [preparing, setPreparing] = useState(false);

  // Date for THIS day (year-month-day), for the copy chip.
  const dayDate = plan.year != null && plan.month != null
    ? `${plan.year}-${String(plan.month).padStart(2, '0')}-${String(day.dayOfMonth).padStart(2, '0')}`
    : null;

  useEffect(() => {
    setNotes(td.notes ?? '');
  }, [target.id, day.dayOfMonth, td.notes]);

  // Stage the day's media on focus (and when the day changes).
  const stage = useCallback(async () => {
    setPreparing(true);
    try { setPrepared(await prepareFanSiteDay(plan.bundleUid, day.dayOfMonth)); }
    catch (e) { alert(String(e)); }
    finally { setPreparing(false); }
  }, [plan.bundleUid, day.dayOfMonth]);

  useEffect(() => { stage(); }, [stage]);

  const set = async (patch: Partial<{ state: PostingState; notes: string | null }>) => {
    try {
      await setFanSiteDay({
        bundleUid: plan.bundleUid, targetId: target.id, fansiteDay: day.dayOfMonth,
        state: patch.state ?? td.state,
        notes: patch.notes !== undefined ? patch.notes : undefined,
      });
      onChange();
    } catch (e) { alert(String(e)); }
  };

  // Toggle posted ⇄ pending; undoes a mistaken check.
  const togglePosted = (checked: boolean) => set({ state: checked ? 'posted' : 'pending' });

  const openTarget = () => {
    if (target.urlTemplate) openUrl(normalizeUrl(target.urlTemplate)).catch((e) => alert(String(e)));
    else alert('No URL set for this site — add one in Settings → Platforms.');
  };

  const markPostedAndAdvance = async () => {
    await set({ state: 'posted' });
    onAdvance();
  };

  return (
    <section className="sm-card" style={{ borderLeft: `4px solid ${target.color}` }}>
      <div className="flex items-center gap-2 mb-2">
        <div style={{ fontSize: 26 }}>{target.icon}</div>
        <div className="flex-1">
          <div className="font-semibold">
            {target.name} · Day {day.dayOfMonth}
            <span className="ml-2 text-xs font-normal" style={{ color: 'rgb(var(--surface-muted))' }}>
              · {day.fileCount} file{day.fileCount === 1 ? '' : 's'}
            </span>
          </div>
        </div>
        <label className="text-xs px-2 py-1 rounded font-semibold whitespace-nowrap flex items-center gap-1.5 cursor-pointer"
               style={isPosted
                 ? { background: '#deffee', color: '#0f5d33' }
                 : { background: 'rgb(var(--surface-base))', color: 'rgb(var(--surface-muted))' }}>
          <input type="checkbox" checked={isPosted} onChange={(e) => togglePosted(e.target.checked)} />
          {isPosted ? '✓ posted' : 'not posted'}
        </label>
      </div>

      {/* Field copy chips. */}
      <div className="flex flex-wrap items-center gap-1.5 mb-2">
        <CopyChip label="Persona" value={personaTheme(plan.personaCode).label} />
        {dayDate && <CopyChip label="Date" value={dayDate} />}
        <CopyChip label="Title" value={plan.title} />
        <CopyChip label="Message" value={day.message} />
      </div>

      {/* Media folder. */}
      <div className="rounded p-2 mb-2" style={{ background: 'rgb(var(--surface-base))' }}>
        <div className="flex items-center justify-between mb-1.5">
          <div className="text-[11px] font-semibold" style={{ color: 'rgb(var(--surface-muted))' }}>
            📁 Day media {preparing ? '· staging…' : prepared ? `· ${prepared.processedCount} ready` : ''}
          </div>
          <div className="flex items-center gap-1.5">
            <button type="button" className="sm-button secondary text-[10px]" onClick={stage} disabled={preparing}>
              ♻︎ Re-stage
            </button>
            <button
              type="button" className="sm-button secondary text-[10px]"
              disabled={!prepared}
              onClick={() => prepared && navigator.clipboard.writeText(prepared.folderPath).catch(() => {})}
              title={prepared?.folderPath}
            >
              📋 Copy folder path
            </button>
            <button type="button" className="sm-button text-[10px]"
                    onClick={() => revealFanSiteDay(plan.bundleUid, day.dayOfMonth).catch((e) => alert(String(e)))}>
              👁 Reveal folder
            </button>
          </div>
        </div>
        {prepared && prepared.folderPath && (
          <>
            <div className="text-[10px] font-mono mb-1 break-all" style={{ color: 'rgb(var(--surface-muted))' }}>
              {prepared.folderPath}
            </div>
            <div className="text-[10px] mb-1.5 leading-snug" style={{ color: 'rgb(var(--surface-muted))' }}>
              In the site's upload dialog, pick <strong>Downloads → SideMolly → FanSite</strong>,
              or press <kbd>⌘⇧G</kbd> and paste the path above.
            </div>
          </>
        )}
        {prepared && prepared.files.length > 0 ? (
          <div className="flex flex-wrap gap-1.5">
            {prepared.files.map((f) => (
              <div key={f.path} className="rounded overflow-hidden text-center"
                   style={{ width: 64, border: '1px solid rgb(var(--surface-border))' }}>
                {thumbs[f.inZipPath] ? (
                  <img src={thumbs[f.inZipPath]} alt={f.name}
                       style={{ width: 64, height: 64, objectFit: 'cover', display: 'block' }} />
                ) : (
                  <div style={{ width: 64, height: 64, display: 'flex', alignItems: 'center',
                                justifyContent: 'center', fontSize: 22, background: 'rgb(var(--surface-card))' }}>
                    {f.kind === 'video' ? '🎞' : f.kind === 'audio' ? '🎵' : '🖼'}
                  </div>
                )}
                <button
                  type="button"
                  className="w-full text-[8px] truncate px-0.5 py-0.5"
                  style={{ background: 'rgb(var(--surface-card))' }}
                  title={`Copy path: ${f.path}`}
                  onClick={() => navigator.clipboard.writeText(f.path).catch(() => {})}
                >
                  📋 {f.name}
                </button>
              </div>
            ))}
          </div>
        ) : !preparing && (
          <div className="text-[10px] italic" style={{ color: 'rgb(var(--surface-muted))' }}>
            No media staged for this day.
          </div>
        )}
        {prepared && prepared.errors.length > 0 && (
          <div className="text-[10px] mt-1" style={{ color: '#7a0000' }}>
            ⚠ {prepared.errors.join('; ')}
          </div>
        )}
      </div>

      {/* Actions. */}
      <div className="flex flex-wrap items-center gap-2 mb-2">
        <button type="button" className="sm-button text-xs" onClick={openTarget} disabled={!target.urlTemplate}>
          🚀 Open {target.name}
        </button>
        <button type="button" className="sm-button secondary text-xs"
                onClick={() => navigator.clipboard.writeText(day.message).catch(() => {})}>
          📋 Copy message
        </button>
        <button type="button" className="sm-button text-xs" onClick={markPostedAndAdvance}>
          ✓ Mark posted &amp; advance
        </button>
      </div>

      <label className="text-[10px]" style={{ color: 'rgb(var(--surface-muted))' }}>Day message (from manifest)</label>
      <textarea className="sm-input text-xs w-full font-mono" rows={3} value={day.message} readOnly />

      <label className="text-[10px] mt-2 block" style={{ color: 'rgb(var(--surface-muted))' }}>Notes</label>
      <textarea
        className="sm-input text-xs w-full" rows={2} value={notes}
        onChange={(e) => setNotes(e.target.value)}
        onBlur={() => notes !== (td.notes ?? '') && set({ notes: notes || null })}
      />

      {td.postedAt && (
        <div className="text-[10px] mt-1.5" style={{ color: 'rgb(var(--surface-muted))' }}>
          posted {td.postedAt}
        </div>
      )}
    </section>
  );
}

// ---------------------------------------------------------------------------
// Reset controls
// ---------------------------------------------------------------------------

function ResetControls({ target, onReset, busy }: {
  target: PostingTarget;
  onReset: (scope: 'site' | 'all') => void;
  busy: boolean;
}) {
  return (
    <section className="sm-card flex items-center justify-between flex-wrap gap-2">
      <div className="text-[11px]" style={{ color: 'rgb(var(--surface-muted))' }}>
        Unwind posting state to start fresh. The posting log keeps the history.
      </div>
      <div className="flex items-center gap-1.5">
        <button
          type="button" className="sm-button secondary text-xs" disabled={busy}
          style={{ color: '#7a0000' }}
          onClick={() => confirm(`Reset all posting state for ${target.name}? (history is kept in the log)`) && onReset('site')}
        >
          ↺ Reset {target.name}
        </button>
        <button
          type="button" className="sm-button secondary text-xs" disabled={busy}
          style={{ color: '#7a0000' }}
          onClick={() => confirm('Reset posting state for ALL fan-sites on this bundle? (history is kept in the log)') && onReset('all')}
        >
          ↺ Reset all sites
        </button>
      </div>
    </section>
  );
}

// ---------------------------------------------------------------------------
// Posting log
// ---------------------------------------------------------------------------

function PostingLogPanel({ log }: { log: PostingLogRow[] }) {
  const [open, setOpen] = useState(false);
  const actionGlyph = (a: PostingLogRow['action']) =>
    a === 'posted' ? '✓' : a === 'unposted' ? '↩' : '↺';
  return (
    <section className="sm-card">
      <button type="button" className="flex items-center justify-between w-full text-left"
              onClick={() => setOpen((v) => !v)}>
        <span className="font-semibold text-sm">📝 Posting log ({log.length})</span>
        <span className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>{open ? '▾ hide' : '▸ show'}</span>
      </button>
      {open && (
        log.length === 0 ? (
          <div className="text-xs italic mt-2" style={{ color: 'rgb(var(--surface-muted))' }}>
            Nothing posted yet — actions appear here with a timestamp.
          </div>
        ) : (
          <ul className="mt-2 flex flex-col gap-1 text-xs">
            {log.map((r) => (
              <li key={r.id} className="flex items-baseline gap-2 font-mono"
                  style={{ color: 'rgb(var(--surface-text))' }}>
                <span style={{ color: 'rgb(var(--surface-muted))' }}>{r.loggedAt}</span>
                <span>{actionGlyph(r.action)} {r.action}</span>
                <span className="font-semibold">{r.targetName || (r.details ?? '')}</span>
                {r.fansiteDay != null && <span>day {r.fansiteDay}</span>}
                {r.postedUrl && (
                  <span className="truncate" style={{ color: 'rgb(var(--surface-accent))' }} title={r.postedUrl}>
                    {r.postedUrl}
                  </span>
                )}
              </li>
            ))}
          </ul>
        )
      )}
    </section>
  );
}

// ---------------------------------------------------------------------------
// Small copy chip with transient confirmation
// ---------------------------------------------------------------------------

function CopyChip({ label, value, fg }: { label: string; value: string; fg?: string }) {
  const [copied, setCopied] = useState(false);
  const copy = () => {
    navigator.clipboard.writeText(value ?? '').then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 1200);
    }).catch(() => {});
  };
  return (
    <button
      type="button"
      onClick={copy}
      disabled={!value}
      className="text-[10px] px-1.5 py-0.5 rounded font-semibold"
      style={{
        border: `1px solid ${fg ? `${fg}55` : 'rgb(var(--surface-border))'}`,
        color: fg ?? 'rgb(var(--surface-text))',
        opacity: value ? 1 : 0.4,
      }}
      title={value}
    >
      {copied ? '✓ copied' : `📋 ${label}`}
    </button>
  );
}
