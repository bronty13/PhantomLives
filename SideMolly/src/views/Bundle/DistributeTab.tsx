// Phase 6 — Distribute tab. Ships processed bundle artifacts to the
// user's local Dropbox folder. Two phases per bundle:
//
//   1. Dry-run preview — list every artifact that would be copied,
//      with status (new / skip / changed / missing) per row. Driven
//      by the sha256 we recorded on previous copies (idempotent).
//
//   2. Copy — actually write the files. Skips already-clean ones
//      (sha unchanged), copies the rest atomically (.sm-dropbox-tmp
//      → rename), re-hashes the destination and flags verify
//      mismatches.
//
// The user lands here, hits "Refresh preview", reviews the list,
// then clicks "Copy to Dropbox". Per-row status updates inline.

import { useCallback, useEffect, useState } from 'react';
import {
  copyToDropbox, dryRunDropbox, fmtSize, getDropboxSettings,
  revealDropboxDest,
  type BundleSummary,
  type CopyResultSummary, type DropboxSettings, type DryRunSummary,
} from '../../data/bundles';

interface Props {
  summary: BundleSummary;
  refreshSignal: number;
}

export function DistributeTab({ summary, refreshSignal }: Props) {
  const [dropboxSettings, setDropboxSettings] = useState<DropboxSettings | null>(null);
  const [preview, setPreview] = useState<DryRunSummary | null>(null);
  const [lastCopy, setLastCopy] = useState<CopyResultSummary | null>(null);
  const [busy, setBusy] = useState(false);
  const [busyLabel, setBusyLabel] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setError(null);
    try {
      const [s, p] = await Promise.all([
        getDropboxSettings(),
        dryRunDropbox(summary.uid),
      ]);
      setDropboxSettings(s);
      setPreview(p);
    } catch (e) {
      setError(String(e));
    }
  }, [summary.uid]);

  useEffect(() => { refresh(); }, [refresh, refreshSignal]);

  const runCopy = async () => {
    setBusy(true);
    setBusyLabel('Copying to Dropbox…');
    try {
      const r = await copyToDropbox(summary.uid);
      setLastCopy(r);
      // Re-run preview to refresh the per-row statuses.
      await refresh();
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
      setBusyLabel(null);
    }
  };

  const reveal = () => {
    revealDropboxDest(summary.uid).catch((e) => alert(String(e)));
  };

  if (error) {
    return (
      <div className="sm-card text-sm" style={{ color: '#7a0000', background: '#ffe4e4' }}>
        ⚠ {error}
      </div>
    );
  }
  if (!preview || !dropboxSettings) {
    return (
      <div className="sm-card text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>
        Loading preview…
      </div>
    );
  }

  const items = preview.items;
  const counts = countByStatus(items);
  const hasWork = (counts.new ?? 0) + (counts.changed ?? 0) > 0;

  return (
    <div className="flex flex-col gap-6">
      {/* ─── Destination + actions ─────────────────────────────── */}
      <section className="sm-card">
        <div className="font-semibold mb-1">📦 Dropbox destination</div>
        {!preview.rootConfigured ? (
          <div className="text-xs" style={{ color: '#7a0000' }}>
            Dropbox root not configured. Open <strong>Settings → Dropbox</strong>{' '}
            and pick the local Dropbox folder.
          </div>
        ) : (
          <div className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
            Root: <code>{preview.dropboxRoot}</code>
            <br />
            This bundle: <code className="font-semibold">{preview.destinationDir}</code>
            <span className="ml-2">
              (template: <code>{dropboxSettings.template}</code>)
            </span>
          </div>
        )}

        <div className="flex items-center gap-2 mt-3">
          <button type="button" className="sm-button secondary text-xs" onClick={refresh}>
            🔄 Refresh preview
          </button>
          <button
            type="button"
            className="sm-button"
            disabled={busy || !preview.rootConfigured || !hasWork}
            onClick={runCopy}
            title={
              !preview.rootConfigured ? 'Configure Dropbox root in Settings first' :
              !hasWork ? 'Nothing new or changed — already in sync' :
              `Copy ${(counts.new ?? 0) + (counts.changed ?? 0)} item${(counts.new ?? 0) + (counts.changed ?? 0) === 1 ? '' : 's'} to Dropbox`
            }
          >
            {busy ? '⏳ Copying…' : `📦 Copy to Dropbox (${(counts.new ?? 0) + (counts.changed ?? 0)})`}
          </button>
          <button
            type="button"
            className="sm-button secondary text-xs"
            onClick={reveal}
            title="Open the bundle's Dropbox destination folder in Finder"
          >
            📁 Reveal
          </button>
        </div>

        {busyLabel && (
          <div className="mt-3 p-3 rounded text-sm flex items-center gap-3"
               style={{ background: '#fff4d6', color: '#7a5b00', border: '1px solid #d4a000' }}>
            <span className="inline-block animate-spin">⏳</span>
            <span>{busyLabel}</span>
          </div>
        )}

        {lastCopy && !busy && (
          <div
            className="mt-3 sm-card text-sm"
            style={{
              background: lastCopy.failed > 0 ? '#ffe4e4' : '#deffee',
              color: lastCopy.failed > 0 ? '#7a0000' : '#0f5d33',
            }}
          >
            ✓ Copied {lastCopy.copied} · skipped {lastCopy.skipped}
            {lastCopy.failed > 0 && <> · <strong>⚠ {lastCopy.failed} failed</strong></>}
          </div>
        )}
      </section>

      {/* ─── Preview table ───────────────────────────────────── */}
      <section className="sm-card">
        <div className="flex items-baseline justify-between mb-2">
          <div className="font-semibold">Preview ({items.length} item{items.length === 1 ? '' : 's'})</div>
          <div className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
            {(counts.new ?? 0)} new · {(counts.changed ?? 0)} changed · {(counts.skip ?? 0)} already in sync
            {(counts.missing ?? 0) > 0 && <> · <span style={{ color: '#7a0000' }}>{counts.missing} missing</span></>}
          </div>
        </div>

        {items.length === 0 ? (
          <div className="text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>
            Nothing to copy yet. Process some media (Edit tab → Step 2) or
            build a master cut (Edit → Step 3) and come back.
          </div>
        ) : (
          <ul className="flex flex-col gap-1">
            {items.map((it) => (
              <PreviewRow key={`${it.kind}-${it.destinationName}`} item={it} />
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}

function countByStatus(items: DryRunSummary['items']): Record<string, number> {
  const c: Record<string, number> = {};
  for (const i of items) c[i.status] = (c[i.status] ?? 0) + 1;
  return c;
}

function PreviewRow({ item }: { item: DryRunSummary['items'][number] }) {
  const sp = statusPill(item.status);
  return (
    <li
      className="flex items-center gap-3 py-1.5"
      style={{ borderBottom: '1px solid rgb(var(--surface-border) / 0.5)' }}
    >
      <span
        className="text-xs px-1.5 py-0.5 rounded font-semibold whitespace-nowrap"
        style={{ background: sp.bg, color: sp.fg, minWidth: 72, textAlign: 'center' }}
      >
        {sp.glyph} {item.status}
      </span>
      <span
        className="text-[10px] px-1.5 py-0.5 rounded whitespace-nowrap"
        style={{ background: 'rgb(var(--surface-base))', color: 'rgb(var(--surface-muted))', minWidth: 80, textAlign: 'center' }}
        title={item.kind}
      >
        {kindGlyph(item.kind)} {kindShort(item.kind)}
      </span>
      <div className="flex-1 min-w-0">
        <div className="font-mono text-xs truncate">{item.destinationName}</div>
        <div className="text-[10px] mt-0.5 truncate" style={{ color: 'rgb(var(--surface-muted))' }}>
          → {item.dropboxPath}
        </div>
      </div>
      <span className="text-[11px] font-mono whitespace-nowrap" style={{ color: 'rgb(var(--surface-muted))' }}>
        {fmtSize(item.sourceSizeBytes)}
      </span>
    </li>
  );
}

function statusPill(s: string): { glyph: string; bg: string; fg: string } {
  switch (s) {
    case 'new':     return { glyph: '✨', bg: '#eef2ff', fg: '#3730a3' };
    case 'changed': return { glyph: '✎',  bg: '#fff4d6', fg: '#7a5b00' };
    case 'skip':    return { glyph: '✓',  bg: '#deffee', fg: '#0f5d33' };
    case 'missing': return { glyph: '⚠',  bg: '#ffe4e4', fg: '#7a0000' };
    default:        return { glyph: '·',  bg: 'rgb(var(--surface-card))', fg: 'rgb(var(--surface-muted))' };
  }
}

function kindGlyph(kind: string): string {
  if (kind === 'image' || kind.startsWith('image_')) return '🖼';
  if (kind === 'master') return '🎬';
  if (kind.startsWith('transcript')) return '📝';
  if (kind === 'video' || kind.startsWith('video_')) return '🎥';
  return '·';
}

function kindShort(kind: string): string {
  if (kind.startsWith('transcript-')) return kind.replace('transcript-', '');
  return kind;
}
