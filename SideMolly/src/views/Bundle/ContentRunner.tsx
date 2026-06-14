// Phase 8 — 🎬 Content Post Runner.
//
// Multi-platform fan-out for content bundles. Per-platform card adds
// (on top of the Phase 7 primitives):
//
//   - Asset picker (checkbox grid of all applicable bundle artifacts
//     — processed images, processed videos, master.mp4, transcripts).
//     User picks which subset goes to which platform. Selection is
//     stored as JSON in bundle_postings.selected_assets_json so it
//     persists.
//   - Body override seeded from the manifest description (if present).
//   - Categories chips from manifest, click-to-copy.
//   - Reveal selected files in Finder (for drag-into-platform flows).

import { useCallback, useEffect, useMemo, useState } from 'react';
import { openUrl } from '@tauri-apps/plugin-opener';
import {
  fmtSize, listBundleAssets, listBundlePostings, markPosted,
  upsertBundlePosting,
  type BundleAsset, type BundleDetail, type BundleSummary,
  type PostingCard, type PostingState, type UpsertBundlePostingInput,
} from '../../data/bundles';

interface Props {
  summary: BundleSummary;
  detail: BundleDetail;
}

const STATES: { value: PostingState; label: string; bg: string; fg: string }[] = [
  { value: 'pending',   label: '⏳ pending',   bg: 'rgb(var(--surface-base))', fg: 'rgb(var(--surface-muted))' },
  { value: 'scheduled', label: '🗓 scheduled', bg: '#eef2ff',                  fg: '#3730a3' },
  { value: 'posted',    label: '✓ posted',    bg: '#deffee',                  fg: '#0f5d33' },
  { value: 'skipped',   label: '— skipped',   bg: 'rgb(var(--surface-base))', fg: 'rgb(var(--surface-muted))' },
];

export function ContentRunner({ summary, detail }: Props) {
  const [cards, setCards] = useState<PostingCard[] | null>(null);
  const [assets, setAssets] = useState<BundleAsset[]>([]);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setError(null);
    try {
      const [cs, as] = await Promise.all([
        listBundlePostings(summary.uid),
        listBundleAssets(summary.uid),
      ]);
      setCards(cs);
      setAssets(as);
    } catch (e) { setError(String(e)); }
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
    return <div className="sm-card text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>Loading…</div>;
  }

  const manifest = detail.manifest;

  return (
    <div className="flex flex-col gap-4">
      {/* Bundle summary band */}
      <section className="sm-card">
        <div className="font-semibold mb-1">🎬 Content · {summary.title || '(no title)'}</div>
        {manifest.descriptionText && (
          <div className="text-xs mb-2 whitespace-pre-wrap" style={{ color: 'rgb(var(--surface-text))' }}>
            {manifest.descriptionText}
          </div>
        )}
        {manifest.categories.length > 0 && (
          <div className="flex flex-wrap items-center gap-1.5 mb-1">
            <span className="text-[10px]" style={{ color: 'rgb(var(--surface-muted))' }}>Categories:</span>
            {manifest.categories.map((c) => (
              <button
                key={c}
                type="button"
                title="Copy"
                className="text-[10px] px-1.5 py-0.5 rounded font-semibold"
                style={{
                  background: 'rgb(var(--surface-base))',
                  color: 'rgb(var(--surface-text))',
                  border: '1px solid rgb(var(--surface-border))',
                }}
                onClick={() => navigator.clipboard.writeText(c).catch(() => {})}
              >
                {c}
              </button>
            ))}
            <button
              type="button"
              className="text-[10px] px-1.5 py-0.5 rounded sm-button secondary"
              onClick={() => navigator.clipboard.writeText(manifest.categories.join(' · ')).catch(() => {})}
            >
              📋 all
            </button>
          </div>
        )}
        <div className="text-[11px]" style={{ color: 'rgb(var(--surface-muted))' }}>
          {assets.length} asset{assets.length === 1 ? '' : 's'} available · click a card's <strong>📁 Assets</strong> to pick which go to each platform
        </div>
      </section>

      {cards.length === 0 ? (
        <div className="sm-card text-sm">
          <div className="font-semibold mb-1">No applicable platforms yet</div>
          <div style={{ color: 'rgb(var(--surface-muted))' }}>
            Open <strong>Settings → 🚀 Platforms</strong> to add the
            platforms you post to. Set kind to <code>content</code> or
            <code>any</code>.
          </div>
        </div>
      ) : (
        <div className="grid gap-3" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(380px, 1fr))' }}>
          {cards.map((c) => (
            <PlatformCard
              key={c.target.id}
              card={c}
              bundle={summary}
              detail={detail}
              assets={assets}
              onChange={refresh}
            />
          ))}
        </div>
      )}
    </div>
  );
}

function PlatformCard({ card, bundle, detail, assets, onChange }: {
  card: PostingCard;
  bundle: BundleSummary;
  detail: BundleDetail;
  assets: BundleAsset[];
  onChange: () => void;
}) {
  const state = (card.posting?.state ?? 'pending') as PostingState;
  const sp = STATES.find((s) => s.value === state)!;
  const initialBody = card.posting?.bodyOverride ?? detail.manifest.descriptionText ?? '';
  const [notes, setNotes] = useState(card.posting?.notes ?? '');
  const [body, setBody] = useState(initialBody);
  const [expanded, setExpanded] = useState(state === 'pending' || state === 'scheduled');
  const [showAssets, setShowAssets] = useState(false);

  const selectedPaths = useMemo<Set<string>>(() => {
    try {
      const arr = JSON.parse(card.posting?.selectedAssetsJson ?? '[]') as Array<{path: string}>;
      return new Set(arr.map((a) => a.path));
    } catch { return new Set(); }
  }, [card.posting?.selectedAssetsJson]);

  const upsert = async (patch: Partial<UpsertBundlePostingInput>) => {
    const input: UpsertBundlePostingInput = {
      bundleUid: bundle.uid, targetId: card.target.id, state,
      postedAt: card.posting?.postedAt ?? null,
      postedUrl: card.posting?.postedUrl ?? null,
      bodyOverride: card.posting?.bodyOverride ?? null,
      notes: card.posting?.notes ?? null,
      ...patch,
    };
    try { await upsertBundlePosting(input); onChange(); }
    catch (e) { alert(String(e)); }
  };

  const setState = (next: PostingState) => upsert({ state: next });

  const toggleAsset = async (a: BundleAsset) => {
    const next = new Set(selectedPaths);
    if (next.has(a.path)) next.delete(a.path); else next.add(a.path);
    const arr = assets
      .filter((x) => next.has(x.path))
      .map((x) => ({ kind: x.kind, path: x.path, label: x.label }));
    await upsert({ selectedAssetsJson: JSON.stringify(arr) });
  };

  const openInBrowser = () => {
    if (!card.resolvedUrl) {
      alert('No URL template configured for this platform. Set it in Settings → Platforms.');
      return;
    }
    openUrl(card.resolvedUrl).catch((e) => alert(String(e)));
  };

  const copyTitle = () => navigator.clipboard.writeText(bundle.title ?? '').catch(() => {});
  const copyBody = () => navigator.clipboard.writeText(body).catch(() => {});

  const markPostedNow = async () => {
    // postedUrl was removed (v0.28.0) — there's never a real link to record.
    try { await markPosted(bundle.uid, card.target.id, null); onChange(); }
    catch (e) { alert(String(e)); }
  };

  return (
    <div className="sm-card" style={{ borderLeft: `4px solid ${card.target.color}`, padding: 12 }}>
      <div className="flex items-center gap-2 mb-2">
        <span style={{ fontSize: 22 }}>{card.target.icon}</span>
        <div className="flex-1 min-w-0">
          <div className="font-semibold text-sm truncate">{card.target.name}</div>
          <div className="text-[10px] font-mono truncate" style={{ color: 'rgb(var(--surface-muted))' }}>
            {card.target.kind}{card.target.personaCode && <> · {card.target.personaCode}</>}
          </div>
        </div>
        <span className="text-xs px-2 py-1 rounded font-semibold whitespace-nowrap"
              style={{ background: sp.bg, color: sp.fg }}>
          {sp.label}
        </span>
      </div>

      <div className="flex flex-wrap items-center gap-2 mb-2">
        <button type="button" className="sm-button text-xs" onClick={openInBrowser} disabled={!card.resolvedUrl}>
          🚀 Open
        </button>
        <button type="button" className="sm-button secondary text-xs" onClick={copyTitle}>📋 Title</button>
        <button type="button" className="sm-button secondary text-xs" onClick={copyBody}>📋 Body</button>
        <button type="button" className="sm-button secondary text-xs"
                onClick={() => setShowAssets((v) => !v)}
                style={{ background: selectedPaths.size > 0 ? '#deffee' : undefined }}>
          📁 Assets ({selectedPaths.size})
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
        <button type="button" className="sm-button secondary text-xs" onClick={() => setExpanded((v) => !v)}>
          {expanded ? '▾ Less' : '▸ More'}
        </button>
      </div>

      {showAssets && (
        <AssetPicker
          assets={assets}
          selected={selectedPaths}
          onToggle={toggleAsset}
        />
      )}

      {expanded && (
        <>
          {card.resolvedUrl && (
            <div className="font-mono text-[10px] truncate mb-2"
                 style={{ color: 'rgb(var(--surface-muted))' }}
                 title={card.resolvedUrl}>→ {card.resolvedUrl}</div>
          )}
          <label className="text-[10px]" style={{ color: 'rgb(var(--surface-muted))' }}>
            Body (seeded from manifest description, edit per-platform)
          </label>
          <textarea
            className="sm-input text-xs w-full font-mono"
            rows={4}
            value={body}
            onChange={(e) => setBody(e.target.value)}
            onBlur={() => body !== (card.posting?.bodyOverride ?? detail.manifest.descriptionText ?? '') &&
                          upsert({ bodyOverride: body || null })}
          />

          <div className="flex items-center gap-1.5 mt-2">
            <button type="button" className="sm-button text-xs" onClick={markPostedNow}>
              ✓ Mark posted
            </button>
          </div>

          <label className="text-[10px] mt-2 block" style={{ color: 'rgb(var(--surface-muted))' }}>Notes</label>
          <textarea
            className="sm-input text-xs w-full"
            rows={2}
            value={notes}
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

function AssetPicker({ assets, selected, onToggle }: {
  assets: BundleAsset[];
  selected: Set<string>;
  onToggle: (a: BundleAsset) => void;
}) {
  if (assets.length === 0) {
    return (
      <div className="text-[11px] italic mt-1 mb-2" style={{ color: 'rgb(var(--surface-muted))' }}>
        No processed assets yet — run Edit → Step 2 (process media) or Step 3 (auto-assemble) first.
      </div>
    );
  }
  // Group by broad kind for visual scan.
  const groups: Record<string, BundleAsset[]> = {};
  for (const a of assets) {
    const k = groupOf(a.kind);
    (groups[k] ??= []).push(a);
  }
  const order = ['Images', 'Videos', 'Master', 'Transcripts'];
  return (
    <div
      className="rounded mb-2 p-2"
      style={{ background: 'rgb(var(--surface-base))', border: '1px solid rgb(var(--surface-border))' }}
    >
      {order.filter((g) => groups[g]).map((g) => (
        <div key={g} className="mb-1.5 last:mb-0">
          <div className="text-[10px] font-semibold mb-0.5" style={{ color: 'rgb(var(--surface-muted))' }}>
            {g} ({groups[g].length})
          </div>
          <ul className="flex flex-col gap-0.5">
            {groups[g].map((a) => (
              <li key={a.path} className="flex items-center gap-2">
                <input
                  type="checkbox"
                  checked={selected.has(a.path)}
                  onChange={() => onToggle(a)}
                  id={`asset-${a.path}`}
                />
                <label htmlFor={`asset-${a.path}`} className="font-mono text-[10px] flex-1 truncate cursor-pointer" title={a.path}>
                  {a.label}
                </label>
                <span className="text-[10px]" style={{ color: 'rgb(var(--surface-muted))' }}>
                  {fmtSize(a.sizeBytes)}
                </span>
              </li>
            ))}
          </ul>
        </div>
      ))}
    </div>
  );
}

function groupOf(kind: string): string {
  if (kind.startsWith('processed_image')) return 'Images';
  if (kind.startsWith('processed_video')) return 'Videos';
  if (kind === 'master') return 'Master';
  if (kind.startsWith('transcript_')) return 'Transcripts';
  return 'Other';
}
