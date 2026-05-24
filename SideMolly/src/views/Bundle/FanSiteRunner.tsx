// Phase 10 — 📅 FanSite Post Runner.
//
// Day-by-day calendar walk for FanSite bundles. The manifest gives us
// fan_days[] (a row per day-of-month with message + file_count); the
// runner pairs them with bundle_postings rows keyed on (uid, target,
// fansite_day) so each day can be independently posted/skipped.
//
// Layout matches PLAN.md §8.3 — calendar grid, day glyphs reflect
// state, click a day to focus a per-day card with message + posted-URL
// + mark-posted + advance-on-post.

import { useCallback, useEffect, useMemo, useState } from 'react';
import { openUrl } from '@tauri-apps/plugin-opener';
import {
  listFanSitePlan, markPosted, upsertBundlePosting,
  type BundleDetail, type BundleSummary,
  type FanSiteDayPosting, type FanSitePlan, type PostingState,
  type UpsertBundlePostingInput,
} from '../../data/bundles';

interface Props {
  summary: BundleSummary;
  detail: BundleDetail;
}

const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
const DOW_HEADER = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

export function FanSiteRunner({ summary }: Props) {
  const [plan, setPlan] = useState<FanSitePlan | null>(null);
  const [focused, setFocused] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setError(null);
    try { setPlan(await listFanSitePlan(summary.uid)); }
    catch (e) { setError(String(e)); }
  }, [summary.uid]);

  useEffect(() => { refresh(); }, [refresh]);

  // Auto-focus the next pending day on first load so the user can
  // hit ⏎ and go.
  useEffect(() => {
    if (plan && focused == null) {
      const nextPending = plan.days.find((d) => d.state === 'pending' || d.state === 'scheduled');
      if (nextPending) setFocused(nextPending.dayOfMonth);
    }
  }, [plan, focused]);

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

  const monthLabel = plan.year != null && plan.month != null
    ? `${MONTHS[(plan.month - 1) % 12]} ${plan.year}`
    : (summary.title || summary.uid);
  const counts = countByState(plan.days);
  const total = plan.days.length;

  const advance = (currentDay: number) => {
    const next = plan.days.find((d) => d.dayOfMonth > currentDay
                                   && (d.state === 'pending' || d.state === 'scheduled'));
    setFocused(next ? next.dayOfMonth : null);
  };

  return (
    <div className="flex flex-col gap-4">
      <section className="sm-card">
        <div className="flex items-baseline justify-between">
          <div className="font-semibold">
            📅 FanSite · {monthLabel}
            {plan.target && (
              <span className="ml-2 text-xs font-normal" style={{ color: 'rgb(var(--surface-muted))' }}>
                · target {plan.target.icon} <code>{plan.target.name}</code>
              </span>
            )}
          </div>
          <div className="text-xs font-mono">
            ✓ {counts.posted ?? 0} / {total} · ⏳ {counts.pending ?? 0} · — {counts.skipped ?? 0}
          </div>
        </div>
      </section>

      {!plan.target ? (
        <div className="sm-card text-sm">
          <div className="font-semibold mb-1">No FanSite delivery platform configured</div>
          <div style={{ color: 'rgb(var(--surface-muted))' }}>
            Open <strong>Settings → 🚀 Platforms</strong> and add a
            platform with kind <code>fansite</code> (the fan-site you
            post to daily).
          </div>
        </div>
      ) : (
        <>
          <Calendar
            plan={plan}
            focused={focused}
            onFocus={setFocused}
          />
          {focused != null && (() => {
            const day = plan.days.find((d) => d.dayOfMonth === focused);
            if (!day) return null;
            return (
              <DayCard
                bundleUid={summary.uid}
                targetId={plan.target.id}
                day={day}
                onChange={refresh}
                onAdvance={() => advance(day.dayOfMonth)}
                resolvedTargetUrl={resolveTargetUrl(plan, day)}
              />
            );
          })()}
        </>
      )}
    </div>
  );
}

function resolveTargetUrl(plan: FanSitePlan, _day: FanSiteDayPosting): string {
  return plan.target?.urlTemplate ?? '';
}

function countByState(days: FanSiteDayPosting[]): Record<string, number> {
  const c: Record<string, number> = {};
  for (const d of days) c[d.state] = (c[d.state] ?? 0) + 1;
  return c;
}

function Calendar({ plan, focused, onFocus }: {
  plan: FanSitePlan;
  focused: number | null;
  onFocus: (day: number | null) => void;
}) {
  // Layout the 1..N days into a Mon-Sun grid based on (year, month).
  const cells = useMemo(() => {
    if (plan.year == null || plan.month == null) return null;
    // JS Date: month is 0-indexed. day-of-week 0 = Sun .. 6 = Sat.
    const firstDow = new Date(plan.year, plan.month - 1, 1).getDay();
    // Convert to Mon-Sun: Mon=0..Sun=6
    const offset = (firstDow + 6) % 7;
    return { firstColumnOffset: offset };
  }, [plan.year, plan.month]);

  if (!cells) return null;
  const daysByNumber = new Map<number, FanSiteDayPosting>();
  for (const d of plan.days) daysByNumber.set(d.dayOfMonth, d);

  // 6 rows × 7 cols accommodates any month layout.
  const flat: Array<{ day: number; row?: FanSiteDayPosting } | null> = [];
  for (let i = 0; i < cells.firstColumnOffset; i++) flat.push(null);
  const lastDay = plan.days.reduce((m, d) => Math.max(m, d.dayOfMonth), 0);
  for (let d = 1; d <= 31; d++) {
    if (d > lastDay && d > (cells.firstColumnOffset + lastDay)) break;
    flat.push({ day: d, row: daysByNumber.get(d) });
  }
  // Pad to a multiple of 7.
  while (flat.length % 7 !== 0) flat.push(null);

  return (
    <section className="sm-card">
      <div className="grid grid-cols-7 gap-1 text-[10px] font-semibold mb-1" style={{ color: 'rgb(var(--surface-muted))' }}>
        {DOW_HEADER.map((d) => <div key={d} className="px-1 py-0.5">{d}</div>)}
      </div>
      <div className="grid grid-cols-7 gap-1">
        {flat.map((cell, i) => {
          if (!cell) return <div key={`pad-${i}`} />;
          const pill = cell.row ? statePill(cell.row.state) : null;
          const isFocused = focused === cell.day;
          const hasContent = cell.row != null;
          return (
            <button
              key={cell.day}
              type="button"
              onClick={() => onFocus(cell.day)}
              disabled={!hasContent}
              className="rounded p-1.5 text-left flex flex-col items-stretch transition"
              style={{
                border: isFocused
                  ? '2px solid rgb(var(--surface-accent))'
                  : '1px solid rgb(var(--surface-border))',
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

function statePill(s: PostingState): { glyph: string; bg: string; fg: string } {
  switch (s) {
    case 'posted':    return { glyph: '✓', bg: '#deffee', fg: '#0f5d33' };
    case 'scheduled': return { glyph: '🗓', bg: '#eef2ff', fg: '#3730a3' };
    case 'skipped':   return { glyph: '—', bg: 'rgb(var(--surface-base))', fg: 'rgb(var(--surface-muted))' };
    case 'pending':
    default:          return { glyph: '·', bg: 'rgb(var(--surface-card))', fg: 'rgb(var(--surface-text))' };
  }
}

function DayCard({ bundleUid, targetId, day, onChange, onAdvance, resolvedTargetUrl }: {
  bundleUid: string;
  targetId: number;
  day: FanSiteDayPosting;
  onChange: () => void;
  onAdvance: () => void;
  resolvedTargetUrl: string;
}) {
  const [message, setMessage] = useState(day.message);
  const [postedUrl, setPostedUrl] = useState(day.postedUrl ?? '');
  const [notes, setNotes] = useState(day.notes ?? '');
  const pill = statePill(day.state);

  useEffect(() => {
    // Sync local state when the focused day changes.
    setMessage(day.message);
    setPostedUrl(day.postedUrl ?? '');
    setNotes(day.notes ?? '');
  }, [day.dayOfMonth, day.message, day.postedUrl, day.notes]);

  const upsert = async (patch: Partial<UpsertBundlePostingInput>) => {
    try {
      await upsertBundlePosting({
        bundleUid, targetId,
        state: day.state, fansiteDay: day.dayOfMonth,
        postedAt: day.postedAt, postedUrl: day.postedUrl,
        bodyOverride: null, notes: day.notes,
        ...patch,
      });
      onChange();
    } catch (e) { alert(String(e)); }
  };

  const setState = (next: PostingState) => upsert({ state: next });

  const copyMessage = () => navigator.clipboard.writeText(message).catch(() => {});

  const openTarget = () => {
    if (resolvedTargetUrl) {
      openUrl(resolvedTargetUrl).catch((e) => alert(String(e)));
    } else {
      alert('No URL template — set one in Settings → Platforms.');
    }
  };

  const markPostedAndAdvance = async () => {
    try {
      await markPosted(bundleUid, targetId, postedUrl || null, day.dayOfMonth);
      onChange();
      onAdvance();
    } catch (e) { alert(String(e)); }
  };

  return (
    <section className="sm-card" style={{ borderLeft: `4px solid rgb(var(--surface-accent))` }}>
      <div className="flex items-center gap-2 mb-2">
        <div style={{ fontSize: 28 }}>📅</div>
        <div className="flex-1">
          <div className="font-semibold">
            Day {day.dayOfMonth}
            <span className="ml-2 text-xs font-normal" style={{ color: 'rgb(var(--surface-muted))' }}>
              · {day.fileCount} file{day.fileCount === 1 ? '' : 's'}
            </span>
          </div>
        </div>
        <span
          className="text-xs px-2 py-1 rounded font-semibold whitespace-nowrap"
          style={{ background: pill.bg, color: pill.fg }}
        >
          {pill.glyph} {day.state}
        </span>
      </div>

      <div className="flex flex-wrap items-center gap-2 mb-2">
        <button type="button" className="sm-button text-xs" onClick={openTarget} disabled={!resolvedTargetUrl}>
          🚀 Open fan-site
        </button>
        <button type="button" className="sm-button secondary text-xs" onClick={copyMessage}>
          📋 Copy message
        </button>
        <select
          className="sm-input text-xs"
          style={{ width: 'auto' }}
          value={day.state}
          onChange={(e) => setState(e.target.value as PostingState)}
        >
          {(['pending','scheduled','posted','skipped'] as PostingState[]).map((s) =>
            <option key={s} value={s}>{s}</option>
          )}
        </select>
      </div>

      <label className="text-[10px]" style={{ color: 'rgb(var(--surface-muted))' }}>Day message (from manifest)</label>
      <textarea
        className="sm-input text-xs w-full font-mono"
        rows={3}
        value={message}
        readOnly
      />

      <label className="text-[10px] mt-2 block" style={{ color: 'rgb(var(--surface-muted))' }}>Posted URL</label>
      <div className="flex items-center gap-1.5">
        <input
          type="text"
          className="sm-input text-xs flex-1 font-mono"
          value={postedUrl}
          placeholder="https://…"
          onChange={(e) => setPostedUrl(e.target.value)}
          onBlur={() => postedUrl !== (day.postedUrl ?? '') &&
                        upsert({ postedUrl: postedUrl || null })}
        />
        <button type="button" className="sm-button text-xs" onClick={markPostedAndAdvance}>
          ✓ Mark posted &amp; advance
        </button>
      </div>

      <label className="text-[10px] mt-2 block" style={{ color: 'rgb(var(--surface-muted))' }}>Notes</label>
      <textarea
        className="sm-input text-xs w-full"
        rows={2}
        value={notes}
        onChange={(e) => setNotes(e.target.value)}
        onBlur={() => notes !== (day.notes ?? '') && upsert({ notes: notes || null })}
      />

      {day.postedAt && (
        <div className="text-[10px] mt-1.5" style={{ color: 'rgb(var(--surface-muted))' }}>
          posted {day.postedAt}
        </div>
      )}
    </section>
  );
}
