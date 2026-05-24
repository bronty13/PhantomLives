import { useCallback, useEffect, useMemo, useState } from 'react';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';
import {
  enqueueAutoAssemble, enqueueBundleVideoOps, fmtSize, getBundleThumbnails,
  getMasterCutStatus, getProcessedPreviews, listProcessedFiles, openMasterCut,
  processBundleImages, revealMasterCut, revealProcessedFile,
  revealWorkingDir, revealWorkingFile, setBundleFileRotation,
  type BundleFileRow, type BundleSummary, type ImageOpsInput,
  type MasterCutStatus, type ProcessedFileRow, type VideoOpsInput,
} from '../../data/bundles';

interface ImageProgress {
  bundleUid: string;
  done: number;
  total: number;
  currentInZipPath: string;
}

type Rotation = 0 | 90 | 180 | 270;
const ROTATIONS: Rotation[] = [0, 90, 180, 270];
const ROTATION_LABEL: Record<Rotation, string> = {
  0:   '0°',
  90:  '90° ↻',
  180: '180°',
  270: '270° ↺',
};

interface Props {
  summary: BundleSummary;
  files: BundleFileRow[];
  /** Bumped whenever a job-updated event lands so the processed list refreshes. */
  refreshSignal: number;
  /** Called after a per-file rotation save so the parent re-fetches the bundle detail. */
  onFileUpdated?: () => void;
}

export function EditTab({ summary, files, refreshSignal, onFileUpdated }: Props) {
  const images = useMemo(() => files.filter((f) => f.kind === 'image'), [files]);
  const videos = useMemo(() => files.filter((f) => f.kind === 'video'), [files]);
  const [imageOps, setImageOps] = useState<ImageOpsInput>({ watermark: true, stripExif: true, rename: false });
  const [videoOps, setVideoOps] = useState<VideoOpsInput>({ watermark: true, stripMetadata: true, rename: false });
  const [thumbs, setThumbs] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [busyLabel, setBusyLabel] = useState<string | null>(null);
  const [imageProgress, setImageProgress] = useState<ImageProgress | null>(null);
  // Heartbeat — bumps every 500ms while busy so the banner shows
  // movement even before/between Tauri events arrive. Tells the user
  // the app is still alive even if real progress hasn't pinged yet.
  const [heartbeat, setHeartbeat] = useState(0);
  useEffect(() => {
    if (!busy) return;
    const t = setInterval(() => setHeartbeat((n) => (n + 1) % 4), 500);
    return () => clearInterval(t);
  }, [busy]);
  const [lastResult, setLastResult] = useState<{ ok: number; skipped: number; errors: string[]; what: string } | null>(null);
  const [processed, setProcessed] = useState<ProcessedFileRow[]>([]);
  const [previews, setPreviews] = useState<Record<string, string>>({});
  const [master, setMaster] = useState<MasterCutStatus | null>(null);

  const refreshProcessed = async () => {
    try {
      const [rows, prev, mc] = await Promise.all([
        listProcessedFiles(summary.uid),
        getProcessedPreviews(summary.uid),
        getMasterCutStatus(summary.uid),
      ]);
      setProcessed(rows);
      setPreviews(prev);
      setMaster(mc);
    } catch (e) {
      console.warn('list processed failed', e);
    }
  };

  useEffect(() => { refreshProcessed(); }, [summary.uid, refreshSignal]);

  // Subscribe to per-image progress while processing — fires once per
  // file from process_bundle_images so the busy banner stays live
  // instead of looking frozen on bundles with 30+ images.
  useEffect(() => {
    let alive = true;
    let unlisten: UnlistenFn | undefined;
    (async () => {
      unlisten = await listen<ImageProgress>('image-progress', (event) => {
        if (!alive) return;
        // eslint-disable-next-line no-console
        console.log('[image-progress]', event.payload);
        if (event.payload.bundleUid !== summary.uid) return;
        setImageProgress(event.payload);
      });
      // eslint-disable-next-line no-console
      console.log('[image-progress] listener attached for uid', summary.uid);
    })();
    return () => { alive = false; unlisten?.(); };
  }, [summary.uid]);

  // Load per-file thumbnail data-URLs once per bundle. Powers the
  // rotation preview tiles below.
  useEffect(() => {
    let alive = true;
    getBundleThumbnails(summary.uid)
      .then((t) => { if (alive) setThumbs(t); })
      .catch((e) => console.warn('thumbs load failed', e));
    return () => { alive = false; };
  }, [summary.uid]);

  const cycleRotation = useCallback(async (inZipPath: string, current: Rotation) => {
    const next: Rotation = ROTATIONS[(ROTATIONS.indexOf(current) + 1) % 4];
    try {
      await setBundleFileRotation(summary.uid, inZipPath, next);
      onFileUpdated?.();
    } catch (e) {
      alert(String(e));
    }
  }, [summary.uid, onFileUpdated]);

  const runProcessImages = async () => {
    setBusy(true);
    setBusyLabel(`Processing ${images.length} image${images.length === 1 ? '' : 's'}…`);
    setImageProgress({ bundleUid: summary.uid, done: 0, total: images.length, currentInZipPath: '' });
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
      setBusyLabel(null);
      setImageProgress(null);
    }
  };

  const runAutoAssemble = async () => {
    setBusy(true);
    setBusyLabel(`Queueing auto-assembly — title + ${videos.length} clip${videos.length === 1 ? '' : 's'} + master…`);
    setLastResult(null);
    try {
      const r = await enqueueAutoAssemble(summary.uid);
      setLastResult({
        ok: r.jobIds.length, skipped: 0, errors: r.errors,
        what: `🎞 Auto-assembly queued — ${r.videoCount} clip${r.videoCount === 1 ? '' : 's'} + title + master · see 🛠 Jobs`,
      });
    } catch (e) {
      setLastResult({ ok: 0, skipped: 0, errors: [String(e)], what: 'auto-assemble failed' });
    } finally {
      setBusy(false);
      setBusyLabel(null);
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

      {videos.length > 0 && (
        <section className="sm-card">
          <div className="font-semibold mb-2">🎞 Auto-assemble ({videos.length} clip{videos.length === 1 ? '' : 's'})</div>
          <div className="text-xs mb-3" style={{ color: 'rgb(var(--surface-muted))' }}>
            One-click master cut. Compiles every bundle video into a single
            landscape 16:9 MP4: <strong>10s title card</strong> →
            <strong> 1.0s cross-dissolves</strong> between every clip
            (normalized to 1920×1080, watermarked, audio-enhanced) →
            <strong> 1.0s fade-to-black</strong> at the end. Decomposes
            into per-step jobs in 🛠 Jobs; output lands at
            <code className="ml-1 text-[11px]">work/&lt;uid&gt;/auto/master.mp4</code>.
            Tune defaults in Settings → Auto-Assembly.
          </div>
          <div className="flex justify-end">
            <button
              type="button"
              className="sm-button"
              disabled={busy}
              onClick={runAutoAssemble}
            >
              {busy ? '⏳ Queueing…' : '🎞 Auto-assemble master'}
            </button>
          </div>
        </section>
      )}

      {busy && (
        <div
          className="sm-card flex flex-col gap-2"
          style={{
            background: '#fff4d6',
            color: '#7a5b00',
            border: '2px solid #d4a000',
            padding: '14px 16px',
          }}
        >
          <div className="flex items-center gap-3">
            <span style={{ fontSize: 28 }}>
              {['⏳', '⌛', '⏳', '⌛'][heartbeat]}
            </span>
            <div className="flex-1">
              <div className="font-semibold text-base">
                {busyLabel ?? 'Working…'}
              </div>
              {imageProgress && imageProgress.total > 0 && (
                <div className="font-mono text-sm mt-0.5">
                  {imageProgress.done} of {imageProgress.total} done
                  {' · '}
                  <span className="opacity-70">
                    {'.'.repeat(heartbeat + 1)}
                  </span>
                </div>
              )}
            </div>
            {imageProgress && imageProgress.total > 0 && (
              <span className="font-mono text-2xl whitespace-nowrap font-bold">
                {Math.round((imageProgress.done / imageProgress.total) * 100)}%
              </span>
            )}
          </div>
          {imageProgress && imageProgress.total > 0 && (
            <>
              <div
                className="w-full rounded overflow-hidden"
                style={{ background: 'rgba(122, 91, 0, 0.2)', height: 10 }}
              >
                <div
                  className="h-full transition-all duration-200"
                  style={{
                    width: `${Math.round((imageProgress.done / imageProgress.total) * 100)}%`,
                    background: '#7a5b00',
                  }}
                />
              </div>
              {imageProgress.currentInZipPath && (
                <div className="font-mono text-xs truncate" title={imageProgress.currentInZipPath}>
                  ▸ {imageProgress.currentInZipPath}
                </div>
              )}
            </>
          )}
        </div>
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

      {(images.length > 0 || videos.length > 0) && (
        <section className="sm-card">
          <div className="font-semibold mb-1">
            🔄 Per-file rotation ({images.length + videos.length})
          </div>
          <div className="text-xs mb-3" style={{ color: 'rgb(var(--surface-muted))' }}>
            Click a thumbnail to cycle 0° → 90° → 180° → 270°. The preview
            rotates immediately so you can see the result before processing.
            Applies during the next image/video process run.
          </div>
          <RotationGrid
            files={[...images, ...videos]}
            thumbs={thumbs}
            onClick={cycleRotation}
          />
        </section>
      )}

      {videos.length > 0 && (
        <section
          className="sm-card"
          style={{
            background: master?.exists ? '#deffee' : 'rgb(var(--surface-card))',
            border: master?.exists
              ? '2px solid #0f5d33'
              : '1px solid rgb(var(--surface-border))',
          }}
        >
          <div className="flex items-center gap-3 mb-2">
            <span style={{ fontSize: 28 }}>{master?.exists ? '🎬' : '🎞'}</span>
            <div className="flex-1">
              <div className="font-semibold text-base">
                Master cut
                {master?.exists ? (
                  <span className="ml-2 text-xs font-normal" style={{ color: '#0f5d33' }}>
                    ✓ ready
                  </span>
                ) : (
                  <span className="ml-2 text-xs font-normal" style={{ color: 'rgb(var(--surface-muted))' }}>
                    not yet built — click 🎞 Auto-assemble above
                  </span>
                )}
              </div>
              {master?.exists && (
                <div className="text-xs mt-0.5" style={{ color: 'rgb(var(--surface-muted))' }}>
                  {fmtSize(master.sizeBytes)} · built {master.modifiedAt}
                </div>
              )}
            </div>
            {master?.exists && (
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  className="sm-button text-sm"
                  onClick={() => openMasterCut(summary.uid).catch((e) => alert(String(e)))}
                  title="Open the master in QuickLook / default video player"
                >
                  ▶ Open
                </button>
                <button
                  type="button"
                  className="sm-button secondary text-sm"
                  onClick={() => revealMasterCut(summary.uid).catch((e) => alert(String(e)))}
                  title="Reveal master.mp4 in Finder"
                >
                  📁 Reveal
                </button>
                <button
                  type="button"
                  className="sm-button secondary text-sm"
                  onClick={() => navigator.clipboard.writeText(master.masterPath).catch(() => {})}
                  title="Copy master.mp4 path"
                >
                  ⧉ Copy path
                </button>
              </div>
            )}
          </div>
          {master?.exists && (
            <div
              className="font-mono text-[11px] truncate"
              style={{ color: 'rgb(var(--surface-muted))' }}
              title={master.masterPath}
            >
              → {master.masterPath}
            </div>
          )}
        </section>
      )}

      <section className="sm-card">
        <div className="flex items-baseline justify-between mb-2 gap-3">
          <div className="font-semibold">Processed outputs ({processed.length})</div>
          <button
            type="button"
            className="sm-button secondary text-xs"
            onClick={() => revealWorkingDir(summary.uid).catch(() => {})}
            title="Open the bundle workspace in Finder"
          >
            📁 Open bundle workspace
          </button>
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
        <div
          className="font-mono text-[10px] mt-0.5 truncate"
          style={{ color: 'rgb(var(--surface-muted))' }}
          title={row.outputPath}
        >
          → {row.outputPath}
        </div>
      </div>
      <button
        type="button"
        className="sm-button secondary text-xs"
        onClick={() => revealProcessedFile(uid, row.inZipPath, row.opKind).catch((e) => alert(String(e)))}
        title="Reveal processed output in Finder"
      >
        📁 output
      </button>
      <button
        type="button"
        className="sm-button secondary text-xs"
        onClick={() => navigator.clipboard.writeText(row.outputPath).catch(() => {})}
        title="Copy output path"
      >
        ⧉ copy
      </button>
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

function RotationGrid({ files, thumbs, onClick }: {
  files: BundleFileRow[];
  thumbs: Record<string, string>;
  onClick: (inZipPath: string, current: Rotation) => void;
}) {
  return (
    <div
      className="grid gap-2"
      style={{
        gridTemplateColumns: 'repeat(auto-fill, minmax(120px, 1fr))',
      }}
    >
      {files.map((f) => {
        const rot = (f.rotationDegrees ?? 0) as Rotation;
        const isVideo = f.kind === 'video';
        const dataUrl = thumbs[f.inZipPath];
        return (
          <button
            key={f.inZipPath}
            type="button"
            onClick={() => onClick(f.inZipPath, rot)}
            className="flex flex-col items-stretch text-left p-1.5 rounded transition"
            style={{
              border: `1px solid ${rot === 0 ? 'rgb(var(--surface-border))' : 'rgb(var(--surface-accent))'}`,
              background: 'rgb(var(--surface-card))',
            }}
            title={`Click to rotate (current: ${ROTATION_LABEL[rot]})`}
          >
            <div
              className="w-full overflow-hidden flex items-center justify-center"
              style={{
                aspectRatio: '1 / 1',
                background: 'rgb(var(--surface-base))',
                borderRadius: 4,
              }}
            >
              {dataUrl ? (
                <img
                  src={dataUrl}
                  alt=""
                  style={{
                    maxWidth: '100%',
                    maxHeight: '100%',
                    objectFit: 'contain',
                    transform: `rotate(${rot}deg)`,
                    transition: 'transform 200ms ease',
                  }}
                />
              ) : (
                <span style={{ color: 'rgb(var(--surface-muted))', fontSize: 22 }}>
                  {isVideo ? '🎬' : '🖼'}
                </span>
              )}
            </div>
            <div
              className="font-mono text-[10px] mt-1.5 truncate"
              style={{ color: 'rgb(var(--surface-text))' }}
            >
              {isVideo ? '🎬' : '🖼'} {f.inZipPath.split('/').pop()}
            </div>
            <div
              className="text-[10px] mt-0.5 flex items-center justify-between"
              style={{
                color: rot === 0 ? 'rgb(var(--surface-muted))' : 'rgb(var(--surface-accent))',
                fontWeight: rot === 0 ? 400 : 600,
              }}
            >
              <span>{ROTATION_LABEL[rot]}</span>
              <span style={{ fontSize: 10 }}>↻</span>
            </div>
          </button>
        );
      })}
    </div>
  );
}
