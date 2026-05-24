import { useEffect, useMemo, useState } from 'react';
import {
  enqueueBundleVideoOps, fmtSize, getProcessedPreviews, listProcessedFiles,
  processBundleImages, revealWorkingFile,
  type BundleFileRow, type BundleSummary, type ImageOpsInput, type ProcessedFileRow,
  type VideoOpsInput,
} from '../../data/bundles';

interface Props {
  summary: BundleSummary;
  files: BundleFileRow[];
  /** Bumped whenever a job-updated event lands so the processed list refreshes. */
  refreshSignal: number;
}

export function EditTab({ summary, files, refreshSignal }: Props) {
  const images = useMemo(() => files.filter((f) => f.kind === 'image'), [files]);
  const videos = useMemo(() => files.filter((f) => f.kind === 'video'), [files]);
  const [imageOps, setImageOps] = useState<ImageOpsInput>({ watermark: true, stripExif: true, rename: false });
  const [videoOps, setVideoOps] = useState<VideoOpsInput>({ watermark: true, stripMetadata: true, rename: false });
  const [busy, setBusy] = useState(false);
  const [lastResult, setLastResult] = useState<{ ok: number; skipped: number; errors: string[]; what: string } | null>(null);
  const [processed, setProcessed] = useState<ProcessedFileRow[]>([]);
  const [previews, setPreviews] = useState<Record<string, string>>({});

  const refreshProcessed = async () => {
    try {
      const [rows, prev] = await Promise.all([
        listProcessedFiles(summary.uid),
        getProcessedPreviews(summary.uid),
      ]);
      setProcessed(rows);
      setPreviews(prev);
    } catch (e) {
      console.warn('list processed failed', e);
    }
  };

  useEffect(() => { refreshProcessed(); }, [summary.uid, refreshSignal]);

  const runProcessImages = async () => {
    setBusy(true);
    setLastResult(null);
    try {
      const r = await processBundleImages(summary.uid, imageOps);
      setLastResult({
        ok: r.processed.length, skipped: r.skipped, errors: r.errors,
        what: `${r.processed.length} images processed`,
      });
      await refreshProcessed();
    } catch (e) {
      setLastResult({ ok: 0, skipped: 0, errors: [String(e)], what: 'image processing failed' });
    } finally {
      setBusy(false);
    }
  };

  const runEnqueueVideos = async () => {
    setBusy(true);
    setLastResult(null);
    try {
      const r = await enqueueBundleVideoOps(summary.uid, videoOps);
      setLastResult({
        ok: r.enqueuedCount, skipped: r.skipped, errors: r.errors,
        what: `${r.enqueuedCount} video job${r.enqueuedCount === 1 ? '' : 's'} enqueued — see 🛠 Jobs`,
      });
    } catch (e) {
      setLastResult({ ok: 0, skipped: 0, errors: [String(e)], what: 'enqueue failed' });
    } finally {
      setBusy(false);
    }
  };

  if (images.length === 0 && videos.length === 0) {
    return (
      <div className="sm-card text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>
        No images or videos in this bundle to process.
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      {images.length > 0 && (
        <section className="sm-card">
          <div className="font-semibold mb-2">Image ops ({images.length})</div>
          <div className="text-xs mb-3" style={{ color: 'rgb(var(--surface-muted))' }}>
            Synchronous — runs in the foreground. Watermark uses the persona profile
            from Settings → Watermark (bundle persona: <code>{summary.personaCode ?? '(none)'}</code>).
            Sources are never touched.
          </div>
          <div className="flex flex-wrap items-center gap-4">
            <label className="flex items-center gap-2 text-sm cursor-pointer">
              <input type="checkbox" checked={imageOps.watermark}
                     onChange={(e) => setImageOps({ ...imageOps, watermark: e.target.checked })} />
              <span>🖋 Watermark</span>
            </label>
            <label className="flex items-center gap-2 text-sm cursor-pointer">
              <input type="checkbox" checked={imageOps.stripExif}
                     onChange={(e) => setImageOps({ ...imageOps, stripExif: e.target.checked })} />
              <span>🪪 Strip EXIF</span>
            </label>
            <label className="flex items-center gap-2 text-sm cursor-pointer">
              <input type="checkbox" checked={imageOps.rename}
                     onChange={(e) => setImageOps({ ...imageOps, rename: e.target.checked })} />
              <span>🏷 Rename (output only)</span>
            </label>
            <div className="flex-1" />
            <button
              type="button"
              className="sm-button"
              disabled={busy || (!imageOps.watermark && !imageOps.stripExif && !imageOps.rename)}
              onClick={runProcessImages}
            >
              {busy ? '⏳ Working…' : `Process ${images.length} image${images.length === 1 ? '' : 's'}`}
            </button>
          </div>
        </section>
      )}

      {videos.length > 0 && (
        <section className="sm-card">
          <div className="font-semibold mb-2">Video ops ({videos.length})</div>
          <div className="text-xs mb-3" style={{ color: 'rgb(var(--surface-muted))' }}>
            Asynchronous — videos queue into 🛠 Jobs and process one at a time.
            Always re-encodes to H.264 1080p · CRF 23 · AAC 128k. Watermark
            uses the same persona profile as images.
          </div>
          <div className="flex flex-wrap items-center gap-4">
            <label className="flex items-center gap-2 text-sm cursor-pointer">
              <input type="checkbox" checked={videoOps.watermark}
                     onChange={(e) => setVideoOps({ ...videoOps, watermark: e.target.checked })} />
              <span>🖋 Watermark</span>
            </label>
            <label className="flex items-center gap-2 text-sm cursor-pointer">
              <input type="checkbox" checked={videoOps.stripMetadata}
                     onChange={(e) => setVideoOps({ ...videoOps, stripMetadata: e.target.checked })} />
              <span>🪪 Strip metadata</span>
            </label>
            <label className="flex items-center gap-2 text-sm cursor-pointer">
              <input type="checkbox" checked={videoOps.rename}
                     onChange={(e) => setVideoOps({ ...videoOps, rename: e.target.checked })} />
              <span>🏷 Rename (output only)</span>
            </label>
            <div className="flex-1" />
            <button
              type="button"
              className="sm-button"
              disabled={busy}
              onClick={runEnqueueVideos}
            >
              {busy ? '⏳ Enqueuing…' : `Process ${videos.length} video${videos.length === 1 ? '' : 's'}`}
            </button>
          </div>
        </section>
      )}

      {lastResult && (
        <div className="sm-card text-sm"
             style={{ color: lastResult.errors.length > 0 ? '#7a0000' : '#0f5d33',
                      background: lastResult.errors.length > 0 ? '#ffe4e4' : '#deffee' }}>
          ✓ {lastResult.what}{lastResult.skipped > 0 ? ` · ${lastResult.skipped} skipped` : ''}
          {lastResult.errors.length > 0 && (
            <details className="mt-1">
              <summary className="cursor-pointer text-xs">
                {lastResult.errors.length} error{lastResult.errors.length === 1 ? '' : 's'}
              </summary>
              <ul className="text-xs mt-1 font-mono">
                {lastResult.errors.map((e, i) => <li key={i}>· {e}</li>)}
              </ul>
            </details>
          )}
        </div>
      )}

      <section className="sm-card">
        <div className="flex items-baseline justify-between mb-2">
          <div className="font-semibold">Processed outputs ({processed.length})</div>
          <div className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
            Latest run per source file shown
          </div>
        </div>

        {processed.length === 0 ? (
          <div className="text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>
            No processed outputs yet for this bundle.
          </div>
        ) : (
          <ul className="flex flex-col gap-1">
            {processed.map((p) => (
              <ProcessedRow
                key={`${p.bundleFileId}-${p.opKind}`}
                row={p}
                preview={previews[p.inZipPath]}
                source={images.find((f) => f.inZipPath === p.inZipPath)}
                uid={summary.uid}
              />
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}

function ProcessedRow({ row, preview, source, uid }: {
  row: ProcessedFileRow;
  preview: string | undefined;
  source: BundleFileRow | undefined;
  uid: string;
}) {
  const px = 64;
  return (
    <li
      className="flex items-center gap-3 py-1.5"
      style={{ borderBottom: '1px solid rgb(var(--surface-border) / 0.5)' }}
    >
      {preview ? (
        <img src={preview} alt="" width={px} height={px}
             className="rounded object-cover"
             style={{ border: '1px solid rgb(var(--surface-border))' }} />
      ) : (
        <div className="rounded flex items-center justify-center"
             style={{
               width: px, height: px,
               background: 'rgb(var(--surface-base))',
               border: '1px solid rgb(var(--surface-border))',
             }}>
          🖼
        </div>
      )}
      <div className="flex-1 min-w-0">
        <div className="font-mono text-xs truncate">{row.inZipPath}</div>
        <div className="text-[11px] mt-0.5" style={{ color: 'rgb(var(--surface-muted))' }}>
          <span className="font-semibold">{row.opKind}</span>
          {source && (
            <>
              <span> · src {fmtSize(source.sizeBytes)}</span>
            </>
          )}
          <span> · {row.createdAt}</span>
        </div>
      </div>
      <button
        type="button"
        className="sm-button secondary text-xs"
        onClick={() => revealWorkingFile(uid, row.inZipPath).catch(() => {})}
        title="Reveal source in Finder"
      >
        📁 src
      </button>
    </li>
  );
}
