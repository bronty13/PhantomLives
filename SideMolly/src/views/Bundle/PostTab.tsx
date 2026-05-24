// Phase 7 — generic per-bundle posting checklist.
//
// Lists every applicable posting target (filtered by bundle.bundleType
// + persona) as a card. Per-card actions:
//
//   - Copy title          → bundle.title to clipboard
//   - Copy description    → from manifest (when present)
//   - Open URL            → tauri-plugin-opener launches the resolved
//                           URL template in the default browser
//   - State selector      → pending / scheduled / posted / skipped
//   - Posted URL field    → captures what the user actually posted to
//   - Notes textarea
//
// Phases 8-10 layer the flavor-specific runners on top:
//   8 — 🎬 Content (grid + per-platform body overrides + file picker)
//   9 — 🎁 Custom (single delivery card + payment surface)
//   10 — 📅 FanSite (day-by-day calendar)
//
// This Phase 7 surface is what every bundle gets in the meantime.

import { useCallback, useEffect, useState } from 'react';
import { openUrl } from '@tauri-apps/plugin-opener';
import {
  listBundlePostings, markPosted, upsertBundlePosting,
  type BundleSummary, type PostingCard, type PostingState,
  type UpsertBundlePostingInput,
} from '../../data/bundles';

interface Props {
  summary: BundleSummary;
}

const STATES: { value: PostingState; label: string; bg: string; fg: string }[] = [
  { value: 'pending',   label: '⏳ pending',   bg: 'rgb(var(--surface-base))', fg: 'rgb(var(--surface-muted))' },
  { value: 'scheduled', label: '🗓 scheduled', bg: '#eef2ff',                  fg: '#3730a3' },
  { value: 'posted',    label: '✓ posted',    bg: '#deffee',                  fg: '#0f5d33' },
  { value: 'skipped',   label: '— skipped',   bg: 'rgb(var(--surface-base))', fg: 'rgb(var(--surface-muted))' },
];

export function PostTab({ summary }: Props) {
  const [cards, setCards] = useState<PostingCard[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setError(null);
    try {
      const r = await listBundlePostings(summary.uid);
      setCards(r);
    } catch (e) {
      setError(String(e));
    }
  }, [summary.uid]);

  useEffect(() => { refresh(); }, [refresh]);

  if (error) {
    return (
      <div className="sm-card text-sm" style={{ color: '#7a0000', background: '#ffe4e4' }}>
        ⚠ {error}
      </div>
    );
  }
  if (cards == null) {
    return (
      <div className="sm-card text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>
        Loading platforms…
      </div>
    );
  }

  if (cards.length === 0) {
    return (
      <div className="sm-card text-sm">
        <div className="font-semibold mb-1">No applicable platforms yet</div>
        <div style={{ color: 'rgb(var(--surface-muted))' }}>
          Open <strong>Settings → 🚀 Platforms</strong> to add the
          platforms you post to. Set <code>kind</code> to{' '}
          <code>{summary.bundleType}</code> or <code>any</code> so they
          show up on this bundle.
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="sm-card text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
        {cards.length} applicable platform{cards.length === 1 ? '' : 's'} for
        bundle kind <code>{summary.bundleType}</code>
        {summary.personaCode && <> · persona <code>{summary.personaCode}</code></>}.
      </div>

      <div
        className="grid gap-3"
        style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(360px, 1fr))' }}
      >
        {cards.map((c) => (
          <PlatformCard
            key={c.target.id}
            card={c}
            bundle={summary}
            onChange={refresh}
          />
        ))}
      </div>
    </div>
  );
}

function PlatformCard({ card, bundle, onChange }: {
  card: PostingCard;
  bundle: BundleSummary;
  onChange: () => void;
}) {
  const state = (card.posting?.state ?? 'pending') as PostingState;
  const sp = STATES.find((s) => s.value === state)!;
  const [postedUrl, setPostedUrl] = useState(card.posting?.postedUrl ?? '');
  const [notes, setNotes] = useState(card.posting?.notes ?? '');
  const [body, setBody] = useState(card.posting?.bodyOverride ?? '');
  const [expanded, setExpanded] = useState(state === 'pending' || state === 'scheduled');

  const upsert = async (patch: Partial<UpsertBundlePostingInput>) => {
    const input: UpsertBundlePostingInput = {
      bundleUid: bundle.uid,
      targetId: card.target.id,
      state,
      postedAt: card.posting?.postedAt ?? null,
      postedUrl: card.posting?.postedUrl ?? null,
      bodyOverride: card.posting?.bodyOverride ?? null,
      notes: card.posting?.notes ?? null,
      ...patch,
    };
    try {
      await upsertBundlePosting(input);
      onChange();
    } catch (e) { alert(String(e)); }
  };

  const setState = (next: PostingState) => upsert({ state: next });

  const openInBrowser = () => {
    if (!card.resolvedUrl) {
      alert('No URL template configured for this platform. Set it in Settings → Platforms.');
      return;
    }
    openUrl(card.resolvedUrl).catch((e) => alert(String(e)));
  };

  const copyTitle = () => {
    navigator.clipboard.writeText(bundle.title ?? '').catch(() => {});
  };

  const markPostedNow = async () => {
    try {
      await markPosted(bundle.uid, card.target.id, postedUrl || null);
      onChange();
    } catch (e) { alert(String(e)); }
  };

  return (
    <div
      className="sm-card"
      style={{
        borderLeft: `4px solid ${card.target.color}`,
        padding: 12,
      }}
    >
      <div className="flex items-center gap-2 mb-2">
        <span style={{ fontSize: 22 }}>{card.target.icon}</span>
        <div className="flex-1 min-w-0">
          <div className="font-semibold text-sm truncate">{card.target.name}</div>
          <div className="text-[10px] font-mono truncate" style={{ color: 'rgb(var(--surface-muted))' }}>
            {card.target.kind}
            {card.target.personaCode && <> · {card.target.personaCode}</>}
          </div>
        </div>
        <span
          className="text-xs px-2 py-1 rounded font-semibold whitespace-nowrap"
          style={{ background: sp.bg, color: sp.fg }}
        >
          {sp.label}
        </span>
      </div>

      <div className="flex flex-wrap items-center gap-2 mb-2">
        <button
          type="button"
          className="sm-button text-xs"
          onClick={openInBrowser}
          disabled={!card.resolvedUrl}
          title={card.resolvedUrl || 'No URL template — set one in Settings → Platforms'}
        >
          🚀 Open
        </button>
        <button type="button" className="sm-button secondary text-xs" onClick={copyTitle}>
          📋 Title
        </button>
        <select
          className="sm-input text-xs"
          style={{ width: 'auto' }}
          value={state}
          onChange={(e) => setState(e.target.value as PostingState)}
        >
          {STATES.map((s) => <option key={s.value} value={s.value}>{s.label}</option>)}
        </select>
        <div className="flex-1" />
        <button
          type="button"
          className="sm-button secondary text-xs"
          onClick={() => setExpanded((v) => !v)}
        >
          {expanded ? '▾ Less' : '▸ More'}
        </button>
      </div>

      {expanded && (
        <>
          {card.resolvedUrl && (
            <div className="font-mono text-[10px] truncate mb-2" style={{ color: 'rgb(var(--surface-muted))' }}
                 title={card.resolvedUrl}>
              → {card.resolvedUrl}
            </div>
          )}

          <label className="text-[10px]" style={{ color: 'rgb(var(--surface-muted))' }}>Body override</label>
          <textarea
            className="sm-input text-xs w-full font-mono"
            rows={3}
            value={body}
            placeholder={bundle.title ?? '(no title)'}
            onChange={(e) => setBody(e.target.value)}
            onBlur={() => body !== (card.posting?.bodyOverride ?? '') &&
                          upsert({ bodyOverride: body || null })}
          />

          <label className="text-[10px] mt-2 block" style={{ color: 'rgb(var(--surface-muted))' }}>Posted URL</label>
          <div className="flex items-center gap-1.5">
            <input
              type="text"
              className="sm-input text-xs flex-1 font-mono"
              value={postedUrl}
              placeholder="https://…"
              onChange={(e) => setPostedUrl(e.target.value)}
              onBlur={() => postedUrl !== (card.posting?.postedUrl ?? '') &&
                            upsert({ postedUrl: postedUrl || null })}
            />
            <button type="button" className="sm-button text-xs" onClick={markPostedNow}>
              ✓ Mark posted
            </button>
          </div>

          <label className="text-[10px] mt-2 block" style={{ color: 'rgb(var(--surface-muted))' }}>Notes</label>
          <textarea
            className="sm-input text-xs w-full"
            rows={2}
            value={notes}
            placeholder="…"
            onChange={(e) => setNotes(e.target.value)}
            onBlur={() => notes !== (card.posting?.notes ?? '') &&
                          upsert({ notes: notes || null })}
          />

          {card.posting?.postedAt && (
            <div className="text-[10px] mt-1.5" style={{ color: 'rgb(var(--surface-muted))' }}>
              posted {card.posting.postedAt}
            </div>
          )}
        </>
      )}
    </div>
  );
}
