// Phase 9 — 🎁 Custom Post Runner.
//
// One-to-one delivery for custom bundles. Single card (no fan-out)
// surfacing the recipient + delivery details + payment information
// from the bundle's manifest, plus a posting checklist for the
// delivery platform.
//
// Layout matches PLAN.md §8.2:
//
//   recipient · delivery method · price · handled-in-platform flag
//   ──────────────────────────────────────────────────────────────
//   📋 Copy handle  📋 Copy delivery msg  📁 Reveal files  🚀 Open
//   payment received via [C4S | Tip | Other]
//   delivered: ✓ at <ts>
//   notes
//
// Posting target resolution: first enabled posting_target of
// kind='custom' (or 'any') matching the bundle's persona. The card
// uses that target's url_template + color + icon.

import { useCallback, useEffect, useState } from 'react';
import { openUrl } from '@tauri-apps/plugin-opener';
import {
  fmtSize, listBundleAssets, listBundlePostings, markPosted, revealWorkingDir,
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
  { value: 'posted',    label: '✓ delivered', bg: '#deffee',                  fg: '#0f5d33' },
  { value: 'skipped',   label: '— skipped',   bg: 'rgb(var(--surface-base))', fg: 'rgb(var(--surface-muted))' },
];

export function CustomRunner({ summary, detail }: Props) {
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
  // Prefer a custom-kind target; fall back to 'any'. Same shape as
  // server-side filter in list_bundle_postings.
  const target = cards.find((c) => c.target.kind === 'custom')
              ?? cards.find((c) => c.target.kind === 'any')
              ?? null;

  const recipient = manifest.deliveryRecipient ?? '';
  const deliverySite = manifest.deliverySiteName ?? '';
  const deliveryUrl = manifest.deliveryUrl ?? '';
  const priceLabel = manifest.handledInPlatform
    ? 'handled in platform'
    : manifest.priceCents != null ? `$${(manifest.priceCents / 100).toFixed(2)}` : '—';

  const copyRecipient = () => navigator.clipboard.writeText(recipient).catch(() => {});

  // Auto-compose a basic delivery message (user can override).
  const defaultDeliveryBody = [
    recipient ? `Hi ${recipient},` : 'Hi,',
    '',
    `Your custom is ready: "${manifest.title || summary.uid}".`,
    manifest.specialInstructions ? `\n${manifest.specialInstructions}\n` : '',
  ].filter(Boolean).join('\n');

  return (
    <div className="flex flex-col gap-4">
      {/* Recipient + delivery + payment band */}
      <section className="sm-card">
        <div className="font-semibold mb-1">🎁 Custom · {summary.title || '(no title)'}</div>
        <div className="grid grid-cols-[140px_1fr] gap-x-3 gap-y-1.5 text-sm">
          <div className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Recipient</div>
          <div className="flex items-center gap-2">
            <code className="text-sm">{recipient || '(unknown)'}</code>
            {recipient && (
              <button type="button" className="sm-button secondary text-xs" onClick={copyRecipient}>
                📋 Copy
              </button>
            )}
          </div>

          <div className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Delivery via</div>
          <div className="flex items-center gap-2">
            {deliverySite && <code className="text-sm">{deliverySite}</code>}
            {deliveryUrl && (
              <button
                type="button"
                className="sm-button secondary text-xs"
                onClick={() => openUrl(deliveryUrl).catch((e) => alert(String(e)))}
              >
                🚀 Open delivery URL
              </button>
            )}
            {!deliverySite && !deliveryUrl && (
              <span className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>—</span>
            )}
          </div>

          <div className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Price</div>
          <div className="font-semibold">{priceLabel}</div>

          {manifest.specialInstructions && (
            <>
              <div className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Special instructions</div>
              <div className="text-sm whitespace-pre-wrap">{manifest.specialInstructions}</div>
            </>
          )}
        </div>
      </section>

      {/* Files for delivery */}
      <section className="sm-card">
        <div className="flex items-center justify-between mb-2">
          <div className="font-semibold text-sm">📁 Files for delivery ({assets.length})</div>
          <button
            type="button"
            className="sm-button secondary text-xs"
            onClick={() => revealWorkingDir(summary.uid).catch((e) => alert(String(e)))}
          >
            📁 Reveal bundle workspace
          </button>
        </div>
        {assets.length === 0 ? (
          <div className="text-xs italic" style={{ color: 'rgb(var(--surface-muted))' }}>
            No processed assets yet — run Edit → Step 2 (process media) first.
          </div>
        ) : (
          <ul className="flex flex-col gap-0.5">
            {assets.map((a) => (
              <li key={a.path} className="flex items-center gap-2">
                <span style={{ minWidth: 20 }}>{groupGlyph(a.kind)}</span>
                <span className="font-mono text-xs flex-1 truncate" title={a.path}>{a.label}</span>
                <span className="text-[10px]" style={{ color: 'rgb(var(--surface-muted))' }}>
                  {fmtSize(a.sizeBytes)}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>

      {/* Delivery checklist */}
      {target ? (
        <DeliveryCard
          card={target}
          bundle={summary}
          detail={detail}
          defaultBody={defaultDeliveryBody}
          onChange={refresh}
        />
      ) : (
        <div className="sm-card text-sm">
          <div className="font-semibold mb-1">No delivery platform configured</div>
          <div style={{ color: 'rgb(var(--surface-muted))' }}>
            Open <strong>Settings → 🚀 Platforms</strong> and add a
            platform with kind <code>custom</code> (or <code>any</code>).
            Typically a Studio Messages or DM service.
          </div>
        </div>
      )}
    </div>
  );
}

function DeliveryCard({ card, bundle, detail, defaultBody, onChange }: {
  card: PostingCard;
  bundle: BundleSummary;
  detail: BundleDetail;
  defaultBody: string;
  onChange: () => void;
}) {
  const state = (card.posting?.state ?? 'pending') as PostingState;
  const sp = STATES.find((s) => s.value === state)!;
  const [postedUrl, setPostedUrl] = useState(card.posting?.postedUrl ?? '');
  const [notes, setNotes] = useState(card.posting?.notes ?? '');
  const [body, setBody] = useState(card.posting?.bodyOverride ?? defaultBody);
  // Light "received via" tracker stored inside notes by prefix so we
  // don't need a schema migration for one field.
  const [receivedVia, setReceivedVia] = useState<string>(() => extractTag(card.posting?.notes ?? '', 'received_via') ?? 'platform');

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

  const openInBrowser = () => {
    if (card.resolvedUrl) {
      openUrl(card.resolvedUrl).catch((e) => alert(String(e)));
    } else if (detail.manifest.deliveryUrl) {
      openUrl(detail.manifest.deliveryUrl).catch((e) => alert(String(e)));
    } else {
      alert('No URL set. Configure a URL template in Settings → Platforms or set the bundle\'s delivery URL.');
    }
  };

  const copyBody = () => navigator.clipboard.writeText(body).catch(() => {});

  const markDelivered = async () => {
    try { await markPosted(bundle.uid, card.target.id, postedUrl || null); onChange(); }
    catch (e) { alert(String(e)); }
  };

  const saveReceivedVia = (v: string) => {
    setReceivedVia(v);
    const stripped = stripTag(notes, 'received_via');
    const combined = `[received_via=${v}] ${stripped}`.trim();
    setNotes(combined);
    upsert({ notes: combined });
  };

  return (
    <section className="sm-card" style={{ borderLeft: `4px solid ${card.target.color}` }}>
      <div className="flex items-center gap-2 mb-2">
        <span style={{ fontSize: 22 }}>{card.target.icon}</span>
        <div className="flex-1 min-w-0">
          <div className="font-semibold text-sm truncate">{card.target.name}</div>
          <div className="text-[10px] font-mono truncate" style={{ color: 'rgb(var(--surface-muted))' }}>
            {card.target.kind}
            {card.target.personaCode && <> · {card.target.personaCode}</>}
          </div>
        </div>
        <span className="text-xs px-2 py-1 rounded font-semibold whitespace-nowrap"
              style={{ background: sp.bg, color: sp.fg }}>
          {sp.label}
        </span>
      </div>

      <div className="flex flex-wrap items-center gap-2 mb-2">
        <button type="button" className="sm-button text-xs" onClick={openInBrowser}>
          🚀 Open delivery
        </button>
        <button type="button" className="sm-button secondary text-xs" onClick={copyBody}>
          📋 Copy message
        </button>
        <select
          className="sm-input text-xs"
          style={{ width: 'auto' }}
          value={state}
          onChange={(e) => setState(e.target.value as PostingState)}
        >
          {STATES.map((s) => <option key={s.value} value={s.value}>{s.label}</option>)}
        </select>
      </div>

      <label className="text-[10px]" style={{ color: 'rgb(var(--surface-muted))' }}>
        Delivery message
      </label>
      <textarea
        className="sm-input text-xs w-full font-mono"
        rows={5}
        value={body}
        onChange={(e) => setBody(e.target.value)}
        onBlur={() => body !== (card.posting?.bodyOverride ?? defaultBody) &&
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
        <button type="button" className="sm-button text-xs" onClick={markDelivered}>
          ✓ Mark delivered
        </button>
      </div>

      <div className="flex items-center gap-3 mt-2 text-xs flex-wrap">
        <span style={{ color: 'rgb(var(--surface-muted))' }}>Payment received via</span>
        {['platform','tip','other'].map((opt) => (
          <label key={opt} className="flex items-center gap-1 cursor-pointer">
            <input
              type="radio"
              name="received_via"
              checked={receivedVia === opt}
              onChange={() => saveReceivedVia(opt)}
            />
            {opt === 'platform' ? '🏦 in-platform' : opt === 'tip' ? '💸 tip' : '· other'}
          </label>
        ))}
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
          delivered {card.posting.postedAt}
        </div>
      )}
    </section>
  );
}

function extractTag(text: string, key: string): string | null {
  const m = text.match(new RegExp(`\\[${key}=([^\\]]+)\\]`));
  return m ? m[1] : null;
}
function stripTag(text: string, key: string): string {
  return text.replace(new RegExp(`\\[${key}=[^\\]]+\\]\\s*`, 'g'), '').trim();
}

function groupGlyph(kind: string): string {
  if (kind.startsWith('processed_image')) return '🖼';
  if (kind.startsWith('processed_video')) return '🎥';
  if (kind === 'master') return '🎬';
  if (kind.startsWith('transcript_')) return '📝';
  return '·';
}
