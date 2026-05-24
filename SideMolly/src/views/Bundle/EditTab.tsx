// Edit tab — the primary working surface for a bundle. v0.9.0 redesign:
// a linear 4-step flow (Rotate → Process → Auto-assemble → Outputs)
// with inline live-queue widgets in each step so the user never has to
// leave this tab to see what's happening.
//
// Data flow:
//
//   BundleWorkspace ──┬── useBundleJobs(uid) ──┐
//                     │                         │
//                     ├── jobs (shared) ────────┼── EditTab
//                     │                         │       ├── StepCard 1 (rotate)
//                     │                         │       ├── StepCard 2 (process media)
//                     │                         │       │     └── LiveQueue filtered to process_video
//                     │                         │       ├── StepCard 3 (auto-assemble)
//                     │                         │       │     └── LiveQueue filtered to title+normalize+assemble
//                     │                         │       └── StepCard 4 (outputs)
//                     │
//                     └── header StatusPill (jobs-busy chip)
//
// Rotation clicks update local component state immediately (no full
// bundle refetch), so the user can rotate 30 files without losing
// scroll position. The DB write happens in the background; on next
// bundle mount the persisted state is read.

import { useCallback, useEffect, useMemo, useState } from 'react';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';
import {
  clearBundleLog, enqueueAutoAssemble, enqueueBundleTranscripts,
  enqueueBundleVideoOps, exportBundleLog, fmtSize, getBundleThumbnails,
  getMasterCutStatus, getProcessedPreviews, getTranscribeStatus,
  listLogEntries, listProcessedFiles, listTranscripts, openMasterCut,
  processBundleImages, revealBundleLog, revealMasterCut, revealProcessedFile,
  revealTranscript, revealWorkingFile, setBundleFileRotation,
  type BundleFileRow, type BundleSummary, type ImageOpsInput, type JobRow,
  type LogRow, type MasterCutStatus, type ProcessedFileRow,
  type TranscribeStatus, type TranscriptRow, type VideoOpsInput,
} from '../../data/bundles';
import type { BundleJobsSnapshot } from '../../lib/useBundleJobs';

type Rotation = 0 | 90 | 180 | 270;
const ROTATIONS: Rotation[] = [0, 90, 180, 270];
const ROTATION_LABEL: Record<Rotation, string> = {
  0:   '0°',
  90:  '90° ↻',
  180: '180°',
  270: '270° ↺',
};

interface ImageProgress {
  bundleUid: string;
  done: number;
  total: number;
  currentInZipPath: string;
}

interface Props {
  summary: BundleSummary;
  files: BundleFileRow[];
  refreshSignal: number;
  jobs: BundleJobsSnapshot;
  /** Called after non-rotation persistence so the parent re-fetches. */
  onFileUpdated?: () => void;
}

export function EditTab({ summary, files, refreshSignal, jobs, onFileUpdated: _unused }: Props) {
  // ── Local file mirror so rotation clicks update instantly without
  //   round-tripping through a full getBundle() refetch. Sync from prop
  //   when bundle UID changes (navigated to a different bundle) or when
  //   a non-rotation field is modified (refreshSignal bump).
  const [localFiles, setLocalFiles] = useState<BundleFileRow[]>(files);
  useEffect(() => { setLocalFiles(files); }, [files]);

  const images = useMemo(() => localFiles.filter((f) => f.kind === 'image'), [localFiles]);
  const videos = useMemo(() => localFiles.filter((f) => f.kind === 'video'), [localFiles]);
  const allMedia = useMemo(() => localFiles.filter((f) => f.kind === 'image' || f.kind === 'video'), [localFiles]);

  const [imageOps, setImageOps] = useState<ImageOpsInput>({ watermark: true, stripExif: true, rename: false });
  const [videoOps, setVideoOps] = useState<VideoOpsInput>({ watermark: true, stripMetadata: true, rename: false });
  const [busy, setBusy] = useState(false);
  const [busyLabel, setBusyLabel] = useState<string | null>(null);
  const [imageProgress, setImageProgress] = useState<ImageProgress | null>(null);
  const [lastResult, setLastResult] = useState<{ ok: number; skipped: number; errors: string[]; what: string } | null>(null);
  const [processed, setProcessed] = useState<ProcessedFileRow[]>([]);
  const [previews, setPreviews] = useState<Record<string, string>>({});
  const [thumbs, setThumbs] = useState<Record<string, string>>({});
  const [master, setMaster] = useState<MasterCutStatus | null>(null);
  const [transcripts, setTranscripts] = useState<TranscriptRow[]>([]);
  const [transcribeStatus, setTranscribeStatus] = useState<TranscribeStatus | null>(null);
  const [logRows, setLogRows] = useState<LogRow[]>([]);

  // ── Image-progress live counter while running.
  useEffect(() => {
    let alive = true;
    let unlisten: UnlistenFn | undefined;
    (async () => {
      unlisten = await listen<ImageProgress>('image-progress', (event) => {
        if (!alive) return;
        if (event.payload.bundleUid !== summary.uid) return;
        setImageProgress(event.payload);
      });
    })();
    return () => { alive = false; unlisten?.(); };
  }, [summary.uid]);

  // ── Thumbnails (one fetch per bundle, drives the rotation grid).
  useEffect(() => {
    let alive = true;
    getBundleThumbnails(summary.uid)
      .then((t) => { if (alive) setThumbs(t); })
      .catch((e) => console.warn('thumbs load failed', e));
    return () => { alive = false; };
  }, [summary.uid]);

  // ── Processed outputs + previews + master cut. Refreshed on
  //   refreshSignal bumps (job-updated events from App.tsx) so Steps
  //   2-4 stay in sync as jobs complete.
  const refreshProcessed = useCallback(async () => {
    try {
      const [rows, prev, mc, tx, ts, lg] = await Promise.all([
        listProcessedFiles(summary.uid),
        getProcessedPreviews(summary.uid),
        getMasterCutStatus(summary.uid),
        listTranscripts(summary.uid).catch(() => [] as TranscriptRow[]),
        getTranscribeStatus().catch(() => null as TranscribeStatus | null),
        listLogEntries(summary.uid, 200).catch(() => [] as LogRow[]),
      ]);
      setProcessed(rows);
      setPreviews(prev);
      setMaster(mc);
      setTranscripts(tx);
      setTranscribeStatus(ts);
      setLogRows(lg);
    } catch (e) {
      console.warn('refreshProcessed failed', e);
    }
  }, [summary.uid]);
  useEffect(() => { refreshProcessed(); }, [refreshProcessed, refreshSignal]);

  // ── Optimistic rotation: update local state immediately, then write
  //   to the DB. No full bundle refetch — that was causing the scroll
  //   snap on every click.
  const cycleRotation = useCallback(async (inZipPath: string, current: Rotation) => {
    const next: Rotation = ROTATIONS[(ROTATIONS.indexOf(current) + 1) % 4];
    setLocalFiles((arr) =>
      arr.map((f) => f.inZipPath === inZipPath ? { ...f, rotationDegrees: next } : f),
    );
    try {
      await setBundleFileRotation(summary.uid, inZipPath, next);
    } catch (e) {
      // Rollback on failure so the UI doesn't lie about persistence.
      setLocalFiles((arr) =>
        arr.map((f) => f.inZipPath === inZipPath ? { ...f, rotationDegrees: current } : f),
      );
      alert(String(e));
    }
  }, [summary.uid]);

  const rotationCount = localFiles.filter((f) => (f.rotationDegrees ?? 0) !== 0).length;

  const resetAllRotations = async () => {
    const targets = localFiles.filter((f) => (f.rotationDegrees ?? 0) !== 0);
    if (targets.length === 0) return;
    setLocalFiles((arr) => arr.map((f) => ({ ...f, rotationDegrees: 0 as Rotation })));
    try {
      await Promise.all(targets.map((f) => setBundleFileRotation(summary.uid, f.inZipPath, 0)));
    } catch (e) { alert(String(e)); }
  };

  // ── Run handlers (process / auto-assemble).
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

  const runEnqueueVideos = async () => {
    setBusy(true);
    setBusyLabel(`Queueing ${videos.length} video job${videos.length === 1 ? '' : 's'}…`);
    setLastResult(null);
    try {
      const r = await enqueueBundleVideoOps(summary.uid, videoOps);
      setLastResult({
        ok: r.enqueuedCount, skipped: r.skipped, errors: r.errors,
        what: `${r.enqueuedCount} video job${r.enqueuedCount === 1 ? '' : 's'} queued · running below ↓`,
      });
    } catch (e) {
      setLastResult({ ok: 0, skipped: 0, errors: [String(e)], what: 'enqueue failed' });
    } finally {
      setBusy(false);
      setBusyLabel(null);
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
        what: `🎞 Auto-assembly queued — ${r.videoCount} clip${r.videoCount === 1 ? '' : 's'} + title + master · running below ↓`,
      });
    } catch (e) {
      setLastResult({ ok: 0, skipped: 0, errors: [String(e)], what: 'auto-assemble failed' });
    } finally {
      setBusy(false);
      setBusyLabel(null);
    }
  };

  const videoProcessingJobs = useMemo(
    () => jobs.all.filter((j) => j.kind === 'process_video'),
    [jobs.all],
  );
  const autoAssembleJobs = useMemo(
    () => jobs.all.filter((j) => ['render_title', 'normalize_video', 'assemble_master'].includes(j.kind)),
    [jobs.all],
  );
  const transcribeJobs = useMemo(
    () => jobs.all.filter((j) => j.kind === 'transcribe_video'),
    [jobs.all],
  );

  const runTranscribe = async (forceAll: boolean) => {
    setBusy(true);
    setBusyLabel(
      forceAll
        ? `Re-transcribing all ${videos.length} video${videos.length === 1 ? '' : 's'}…`
        : `Transcribing missing video${videos.length === 1 ? '' : 's'}…`,
    );
    setLastResult(null);
    try {
      const r = await enqueueBundleTranscripts(summary.uid, forceAll);
      const ok = r.jobIds.length;
      setLastResult({
        ok, skipped: r.skipped, errors: r.errors,
        what: ok > 0
          ? `📝 ${ok} transcribe job${ok === 1 ? '' : 's'} queued${r.skipped > 0 ? ` · ${r.skipped} skipped (already done)` : ''} · running below ↓`
          : `📝 Nothing to transcribe — all ${r.videoCount} video${r.videoCount === 1 ? '' : 's'} already have transcripts. Use "Re-transcribe all" to redo.`,
      });
    } catch (e) {
      setLastResult({ ok: 0, skipped: 0, errors: [String(e)], what: 'transcribe failed' });
    } finally {
      setBusy(false);
      setBusyLabel(null);
    }
  };

  const exportLog = async () => {
    try {
      const r = await exportBundleLog(summary.uid);
      setLastResult({
        ok: r.rowCount, skipped: 0, errors: [],
        what: `📜 Log exported — ${r.rowCount} entries → ${r.outputPath}`,
      });
      // Auto-reveal in Finder for convenience.
      revealBundleLog(summary.uid).catch(() => {});
    } catch (e) {
      setLastResult({ ok: 0, skipped: 0, errors: [String(e)], what: 'log export failed' });
    }
  };

  const clearLog = async () => {
    if (!confirm(`Clear the activity log for bundle ${summary.uid}? This wipes ${logRows.length} entries.`)) return;
    try {
      await clearBundleLog(summary.uid);
      setLogRows([]);
    } catch (e) {
      alert(String(e));
    }
  };

  if (allMedia.length === 0) {
    return (
      <div className="sm-card text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>
        No images or videos in this bundle to process.
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      {/* ────────────────────────────────────────────────────────────
          STEP 1 — Review & rotate
          ──────────────────────────────────────────────────────────── */}
      <StepCard num={1} title="Review &amp; rotate" subtitle={
        <>Click any tile to cycle <code>0° → 90° → 180° → 270°</code>. The preview rotates instantly so you can verify before processing. Applies during the next image/video process run.</>
      }>
        <RotationGrid files={allMedia} thumbs={thumbs} onClick={cycleRotation} />
        <div className="mt-3 flex items-center justify-between text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
          <span>
            {rotationCount > 0 ? (
              <><strong style={{ color: 'rgb(var(--surface-accent))' }}>{rotationCount}</strong> rotated · {allMedia.length - rotationCount} untouched</>
            ) : (
              <>{allMedia.length} files · none rotated yet</>
            )}
          </span>
          {rotationCount > 0 && (
            <button type="button" className="sm-button secondary text-xs" onClick={resetAllRotations}>
              Reset all to 0°
            </button>
          )}
        </div>
      </StepCard>

      {/* ────────────────────────────────────────────────────────────
          STEP 2 — Process media
          ──────────────────────────────────────────────────────────── */}
      <StepCard num={2} title="Process media" subtitle={
        <>Images run synchronously in the foreground; videos queue into 🛠 Jobs (one at a time). Watermark uses your persona profile from <em>Settings → Watermark</em> (bundle persona <code>{summary.personaCode ?? '(none)'}</code>). Source files are never touched — outputs land in <code>…/work/{summary.uid}/processed/</code>.</>
      }>
        {images.length > 0 && (
          <div className="flex flex-wrap items-center gap-4 py-2">
            <span className="text-sm" style={{ minWidth: 92 }}>
              🖼 <strong>{images.length}</strong> images
            </span>
            <OpsToggle label="🖋 Watermark" checked={imageOps.watermark}
                       onChange={(c) => setImageOps({ ...imageOps, watermark: c })} />
            <OpsToggle label="🪪 Strip EXIF" checked={imageOps.stripExif}
                       onChange={(c) => setImageOps({ ...imageOps, stripExif: c })} />
            <OpsToggle label="🏷 Rename" checked={imageOps.rename}
                       onChange={(c) => setImageOps({ ...imageOps, rename: c })} />
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
        )}

        {videos.length > 0 && (
          <div className="flex flex-wrap items-center gap-4 py-2 mt-2" style={{ borderTop: images.length > 0 ? '1px dashed rgb(var(--surface-border))' : 'none', paddingTop: images.length > 0 ? 12 : 0 }}>
            <span className="text-sm" style={{ minWidth: 92 }}>
              🎬 <strong>{videos.length}</strong> videos
            </span>
            <OpsToggle label="🖋 Watermark" checked={videoOps.watermark}
                       onChange={(c) => setVideoOps({ ...videoOps, watermark: c })} />
            <OpsToggle label="🪪 Strip metadata" checked={videoOps.stripMetadata}
                       onChange={(c) => setVideoOps({ ...videoOps, stripMetadata: c })} />
            <OpsToggle label="🏷 Rename" checked={videoOps.rename}
                       onChange={(c) => setVideoOps({ ...videoOps, rename: c })} />
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
        )}

        {/* Inline progress: image counter (sync) + video queue (async). */}
        {busy && imageProgress && imageProgress.total > 0 && (
          <ProgressBanner
            label={busyLabel ?? 'Working…'}
            done={imageProgress.done}
            total={imageProgress.total}
            currentLabel={imageProgress.currentInZipPath}
          />
        )}
        <LiveQueue
          title="Video processing queue"
          jobs={videoProcessingJobs}
          emptyHint="Process videos above to queue them here."
        />

        {lastResult && (
          <ResultPill r={lastResult} />
        )}
      </StepCard>

      {/* ────────────────────────────────────────────────────────────
          STEP 3 — Auto-assemble master cut
          ──────────────────────────────────────────────────────────── */}
      {videos.length > 0 && (
        <StepCard num={3} title="Auto-assemble master cut" subtitle={
          <>One-click <strong>master.mp4</strong>: 10s title card → 1.0s cross-dissolves between every clip (normalized to 1920×1080, watermarked, audio-enhanced) → 1.0s fade-to-black. Output lands at <code>…/work/{summary.uid}/auto/master.mp4</code>. Tune defaults in <em>Settings → Auto-Assembly</em>.</>
        }>
          <div className="flex justify-end mb-3">
            <button
              type="button"
              className="sm-button"
              disabled={busy || jobs.busy}
              onClick={runAutoAssemble}
            >
              {jobs.busy ? '⚙️ Working — see queue below' : `🎞 Auto-assemble (${videos.length} clip${videos.length === 1 ? '' : 's'})`}
            </button>
          </div>

          <LiveQueue
            title="Auto-assemble queue"
            jobs={autoAssembleJobs}
            emptyHint="Click 🎞 Auto-assemble to start the title → normalize → assemble pipeline."
          />

          <MasterCutCard
            master={master}
            onOpen={() => openMasterCut(summary.uid).catch((e) => alert(String(e)))}
            onReveal={() => revealMasterCut(summary.uid).catch((e) => alert(String(e)))}
          />
        </StepCard>
      )}

      {/* ────────────────────────────────────────────────────────────
          STEP 4 — Transcripts (videos only)
          ──────────────────────────────────────────────────────────── */}
      {videos.length > 0 && (
        <StepCard num={4} title="Transcripts" subtitle={
          <>Per-video transcripts via MLX-accelerated Whisper. Writes
            <code className="mx-1">.txt</code> +
            <code className="mr-1">.srt</code> +
            <code>.json</code> sidecars to
            <code className="ml-1">…/work/{summary.uid}/transcripts/</code>.
            Phase 5 ships flat-transcript + word-timestamps; diarization
            (speaker turns) lands in 5.1.</>
        }>
          <TranscriptsPanel
            videos={videos}
            transcripts={transcripts}
            transcribeJobs={transcribeJobs}
            status={transcribeStatus}
            busy={busy || jobs.busy}
            onRunMissing={() => runTranscribe(false)}
            onRunAll={() => runTranscribe(true)}
            onReveal={(inZipPath) => revealTranscript(summary.uid, inZipPath).catch((e) => alert(String(e)))}
          />
          <LiveQueue
            title="Transcription queue"
            jobs={transcribeJobs}
            emptyHint="Click 📝 Transcribe all videos to start the queue."
          />
        </StepCard>
      )}

      {/* ────────────────────────────────────────────────────────────
          STEP 5 — Processed outputs
          ──────────────────────────────────────────────────────────── */}
      <StepCard
        num={5}
        title={`Processed outputs (${processed.length})`}
        subtitle={<>Latest run per source file shown. Click <strong>📁 output</strong> to reveal the processed file in Finder.</>}
      >
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
                source={images.find((f) => f.inZipPath === p.inZipPath)
                     ?? videos.find((f) => f.inZipPath === p.inZipPath)}
                uid={summary.uid}
              />
            ))}
          </ul>
        )}
      </StepCard>

      {/* ────────────────────────────────────────────────────────────
          STEP 6 — Activity log
          ──────────────────────────────────────────────────────────── */}
      <StepCard
        num={6}
        title={`Activity log (${logRows.length})`}
        subtitle={<>Every job lifecycle event for this bundle — started, done, failed — newest first. <strong>Export</strong> writes <code>processing.log</code> to the bundle workspace; that file gets folded into the return bundle back to Molly (Phase 11).</>}
      >
        <ActivityLog
          rows={logRows}
          onExport={exportLog}
          onClear={clearLog}
        />
      </StepCard>
    </div>
  );
}

// ─── Reusable components ────────────────────────────────────────────

function StepCard({ num, title, subtitle, children }: {
  num: number;
  title: React.ReactNode;
  subtitle?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <section className="sm-card">
      <div className="flex items-baseline gap-3 mb-1">
        <span
          className="inline-flex items-center justify-center font-bold"
          style={{
            width: 28, height: 28,
            borderRadius: 14,
            background: 'rgb(var(--surface-accent))',
            color: 'white',
            fontSize: 14,
            flexShrink: 0,
          }}
        >
          {num}
        </span>
        <h2 className="font-semibold text-lg" style={{ color: 'rgb(var(--surface-text))' }}>
          {title}
        </h2>
      </div>
      {subtitle && (
        <div className="text-xs mb-3 ml-10" style={{ color: 'rgb(var(--surface-muted))' }}>
          {subtitle}
        </div>
      )}
      <div className="ml-10">
        {children}
      </div>
    </section>
  );
}

function OpsToggle({ label, checked, onChange }: {
  label: string; checked: boolean; onChange: (v: boolean) => void;
}) {
  return (
    <label className="flex items-center gap-2 text-sm cursor-pointer whitespace-nowrap">
      <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} />
      <span>{label}</span>
    </label>
  );
}

function ProgressBanner({ label, done, total, currentLabel }: {
  label: string; done: number; total: number; currentLabel?: string;
}) {
  const pct = Math.round((done / total) * 100);
  return (
    <div
      className="mt-3 p-3 rounded flex flex-col gap-1.5"
      style={{ background: '#fff4d6', color: '#7a5b00', border: '1px solid #d4a000' }}
    >
      <div className="flex items-center gap-3">
        <span className="inline-block animate-spin" style={{ fontSize: 18 }}>⏳</span>
        <span className="flex-1 font-semibold text-sm">{label}</span>
        <span className="font-mono text-sm font-bold">{pct}%</span>
        <span className="font-mono text-xs">{done} / {total}</span>
      </div>
      <div className="w-full rounded overflow-hidden" style={{ background: 'rgba(122, 91, 0, 0.2)', height: 8 }}>
        <div className="h-full transition-all duration-200"
             style={{ width: `${pct}%`, background: '#7a5b00' }} />
      </div>
      {currentLabel && (
        <div className="font-mono text-[11px] truncate" title={currentLabel}>
          ▸ {currentLabel}
        </div>
      )}
    </div>
  );
}

function ResultPill({ r }: { r: { ok: number; skipped: number; errors: string[]; what: string } }) {
  const isError = r.errors.length > 0 && r.ok === 0;
  return (
    <div
      className="mt-3 sm-card text-sm"
      style={{
        color: isError ? '#7a0000' : '#0f5d33',
        background: isError ? '#ffe4e4' : '#deffee',
      }}
    >
      ✓ {r.what}{r.skipped > 0 ? ` · ${r.skipped} skipped` : ''}
      {r.errors.length > 0 && (
        <details className="mt-1">
          <summary className="cursor-pointer text-xs">
            {r.errors.length} error{r.errors.length === 1 ? '' : 's'}
          </summary>
          <ul className="text-xs mt-1 font-mono">
            {r.errors.map((e, i) => <li key={i}>· {e}</li>)}
          </ul>
        </details>
      )}
    </div>
  );
}

/** Inline live queue — shows every job for this bundle of the given
 *  kinds, with status pills and the running one's filename. Updates
 *  in real time via the parent's useBundleJobs subscription. */
function LiveQueue({ title, jobs, emptyHint }: {
  title: string; jobs: JobRow[]; emptyHint: string;
}) {
  if (jobs.length === 0) {
    return (
      <div className="mt-3 text-xs italic" style={{ color: 'rgb(var(--surface-muted))' }}>
        {emptyHint}
      </div>
    );
  }
  const done = jobs.filter((j) => j.status === 'done').length;
  const running = jobs.find((j) => j.status === 'running');
  const pending = jobs.filter((j) => j.status === 'pending').length;
  const failed = jobs.filter((j) => j.status === 'failed').length;

  return (
    <div
      className="mt-3 rounded"
      style={{
        background: 'rgb(var(--surface-base))',
        border: '1px solid rgb(var(--surface-border))',
        padding: 12,
      }}
    >
      <div className="flex items-center justify-between mb-2">
        <span className="text-xs font-semibold" style={{ color: 'rgb(var(--surface-muted))' }}>
          {title}
        </span>
        <span className="text-xs font-mono">
          {done}/{jobs.length} done
          {running && <span> · ⚙️ 1 running</span>}
          {pending > 0 && <span> · ⏳ {pending} pending</span>}
          {failed > 0 && <span style={{ color: '#7a0000' }}> · ⚠ {failed} failed</span>}
        </span>
      </div>
      <div className="flex flex-col gap-0.5">
        {jobs.slice().reverse().map((j) => (
          <JobRowMini key={j.id} job={j} />
        ))}
      </div>
    </div>
  );
}

function JobRowMini({ job }: { job: JobRow }) {
  const sp = jobStatusPill(job.status);
  const subject = job.sourceInZipPath
    ?? (job.kind === 'render_title' ? 'title card'
        : job.kind === 'assemble_master' ? 'assemble master'
        : job.kind);
  return (
    <div className="flex items-center gap-2 text-xs">
      <span
        className="inline-block px-1.5 py-0.5 rounded text-[10px] font-semibold"
        style={{ background: sp.bg, color: sp.fg, minWidth: 56, textAlign: 'center' }}
      >
        {sp.glyph} {job.status}
      </span>
      <span className="font-mono truncate flex-1" style={{ color: 'rgb(var(--surface-muted))' }}>
        {job.kind} · {subject}
      </span>
      {job.lastError && (
        <span className="text-[10px]" style={{ color: '#7a0000' }} title={job.lastError}>
          ⚠
        </span>
      )}
    </div>
  );
}

function jobStatusPill(s: JobRow['status']): { glyph: string; bg: string; fg: string } {
  switch (s) {
    case 'pending': return { glyph: '⏳', bg: 'rgb(var(--surface-card))', fg: 'rgb(var(--surface-muted))' };
    case 'running': return { glyph: '⚙️', bg: '#fff4d6', fg: '#7a5b00' };
    case 'done':    return { glyph: '✓',  bg: '#deffee', fg: '#0f5d33' };
    case 'failed':  return { glyph: '⚠',  bg: '#ffe4e4', fg: '#7a0000' };
  }
}

function MasterCutCard({ master, onOpen, onReveal }: {
  master: MasterCutStatus | null;
  onOpen: () => void;
  onReveal: () => void;
}) {
  if (!master) return null;
  if (!master.exists) {
    return (
      <div className="mt-3 text-xs italic" style={{ color: 'rgb(var(--surface-muted))' }}>
        Master cut not yet built — click 🎞 Auto-assemble above.
      </div>
    );
  }
  return (
    <div
      className="mt-3 rounded p-3"
      style={{ background: '#deffee', border: '2px solid #0f5d33' }}
    >
      <div className="flex items-center gap-3">
        <span style={{ fontSize: 28 }}>🎬</span>
        <div className="flex-1 min-w-0">
          <div className="font-semibold text-base" style={{ color: '#0f5d33' }}>
            Master cut ✓ ready
          </div>
          <div className="text-xs mt-0.5" style={{ color: '#0f5d33' }}>
            {fmtSize(master.sizeBytes)} · built {master.modifiedAt}
          </div>
        </div>
        <div className="flex items-center gap-2">
          <button type="button" className="sm-button text-sm" onClick={onOpen}
                  title="Open in QuickLook / default video player">
            ▶ Open
          </button>
          <button type="button" className="sm-button secondary text-sm" onClick={onReveal}
                  title="Reveal master.mp4 in Finder">
            📁 Reveal
          </button>
          <button type="button" className="sm-button secondary text-sm"
                  onClick={() => navigator.clipboard.writeText(master.masterPath).catch(() => {})}
                  title="Copy master.mp4 path">
            ⧉ Copy path
          </button>
        </div>
      </div>
      <div className="font-mono text-[11px] truncate mt-2" style={{ color: '#0f5d33' }}
           title={master.masterPath}>
        → {master.masterPath}
      </div>
    </div>
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
      style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(120px, 1fr))' }}
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
                    maxWidth: '100%', maxHeight: '100%', objectFit: 'contain',
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
          {source?.kind === 'video' ? '🎬' : '🖼'}
        </div>
      )}
      <div className="flex-1 min-w-0">
        <div className="font-mono text-xs truncate">{row.inZipPath}</div>
        <div className="text-[11px] mt-0.5" style={{ color: 'rgb(var(--surface-muted))' }}>
          <span className="font-semibold">{row.opKind}</span>
          {source && (<><span> · src {fmtSize(source.sizeBytes)}</span></>)}
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
      <button type="button" className="sm-button secondary text-xs"
              onClick={() => revealProcessedFile(uid, row.inZipPath, row.opKind).catch((e) => alert(String(e)))}
              title="Reveal processed output in Finder">
        📁 output
      </button>
      <button type="button" className="sm-button secondary text-xs"
              onClick={() => navigator.clipboard.writeText(row.outputPath).catch(() => {})}
              title="Copy output path">
        ⧉
      </button>
      <button type="button" className="sm-button secondary text-xs"
              onClick={() => revealWorkingFile(uid, row.inZipPath).catch(() => {})}
              title="Reveal source in Finder">
        📁 src
      </button>
    </li>
  );
}

function TranscriptsPanel({ videos, transcripts, transcribeJobs, status, busy, onRunMissing, onRunAll, onReveal }: {
  videos: BundleFileRow[];
  transcripts: TranscriptRow[];
  transcribeJobs: JobRow[];
  status: TranscribeStatus | null;
  busy: boolean;
  onRunMissing: () => void;
  onRunAll: () => void;
  onReveal: (inZipPath: string) => void;
}) {
  const transcribedCount = transcripts.filter((t) => t.txtPath != null).length;
  const failedCount = transcribeJobs.filter((j) => j.status === 'failed').length;
  const installed = status?.installed ?? false;
  const missingCount = videos.length - transcribedCount;

  // Per-video status: cross-reference (a) the on-disk transcript
  // sidecar — definitive "done" signal — with (b) the live job
  // status from the queue. Without the job lookup a row stays at
  // "… pending" even when the worker is actively running on it OR
  // has failed it; user reads that as "stuck". Job-based status
  // beats disk-based status when the job is still active.
  const statusFor = (
    inZipPath: string,
  ): { pill: string; bg: string; fg: string; lastError?: string } => {
    const t = transcripts.find((x) => x.inZipPath === inZipPath);
    if (t?.txtPath) {
      return { pill: '✓ done',   bg: '#deffee', fg: '#0f5d33' };
    }
    // Find the newest job for this clip (worker is sequential so at
    // most one is running at a time; multiple historical jobs may
    // exist if the user clicked Transcribe twice).
    const latest = transcribeJobs
      .filter((j) => j.sourceInZipPath === inZipPath)
      .sort((a, b) => b.id - a.id)[0];
    if (!latest) {
      return { pill: '… not started', bg: 'rgb(var(--surface-base))', fg: 'rgb(var(--surface-muted))' };
    }
    switch (latest.status) {
      case 'running': return { pill: '⚙ running', bg: '#fff4d6', fg: '#7a5b00' };
      case 'pending': return { pill: '⏳ queued',   bg: '#eef2ff', fg: '#3730a3' };
      case 'failed':  return {
        pill: '⚠ failed', bg: '#ffe4e4', fg: '#7a0000',
        lastError: latest.lastError ?? undefined,
      };
      case 'done':    return { pill: '✓ done',    bg: '#deffee', fg: '#0f5d33' };
    }
  };

  return (
    <>
      <div className="flex items-center justify-between gap-3 mb-3">
        <div className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
          {installed ? (
            <>
              <span style={{ color: '#0f5d33' }}>✓ transcribe ready</span>
              {status?.version && (
                <span> · {status.version}</span>
              )}
              {' '}· {transcribedCount} / {videos.length} done
              {failedCount > 0 && (
                <span style={{ color: '#7a0000' }}> · {failedCount} failed</span>
              )}
            </>
          ) : (
            <>
              <span style={{ color: '#7a0000' }}>⚠ transcribe (MLX) not detected</span>
              {' '}— install from{' '}
              <code className="text-[10px]">~/dev/PhantomLives/transcribe/</code>
            </>
          )}
        </div>
        <div className="flex items-center gap-2">
          <button
            type="button"
            className="sm-button"
            disabled={busy || !installed || missingCount === 0}
            onClick={onRunMissing}
            title={
              !installed
                ? 'Install PhantomLives transcribe first'
                : missingCount === 0
                  ? 'All videos already transcribed'
                  : `Run transcribe on ${missingCount} video${missingCount === 1 ? '' : 's'} without a .txt sidecar (includes previously-failed ones)`
            }
          >
            📝 Transcribe missing ({missingCount})
          </button>
          <button
            type="button"
            className="sm-button secondary"
            disabled={busy || !installed || videos.length === 0}
            onClick={onRunAll}
            title={installed ? `Re-run transcribe on every video, regardless of existing .txt` : 'Install PhantomLives transcribe first'}
          >
            🔄 Re-transcribe all
          </button>
        </div>
      </div>

      <ul className="flex flex-col gap-1">
        {videos.map((v) => {
          const t = transcripts.find((x) => x.inZipPath === v.inZipPath);
          const s = statusFor(v.inZipPath);
          const done = t?.txtPath != null;
          return (
            <li
              key={v.inZipPath}
              className="flex items-start gap-3 py-1.5"
              style={{ borderBottom: '1px solid rgb(var(--surface-border) / 0.5)' }}
            >
              <span
                className="text-xs px-1.5 py-0.5 rounded font-semibold whitespace-nowrap"
                style={{
                  background: s.bg, color: s.fg,
                  minWidth: 76, textAlign: 'center',
                }}
                title={s.lastError ?? ''}
              >
                {s.pill}
              </span>
              <div className="flex-1 min-w-0">
                <div className="font-mono text-xs truncate">
                  🎬 {v.inZipPath.split('/').pop()}
                </div>
                {t?.txtPreview && (
                  <div
                    className="text-[11px] mt-0.5 truncate italic"
                    style={{ color: 'rgb(var(--surface-muted))' }}
                    title={t.txtPreview}
                  >
                    “{t.txtPreview.replace(/\s+/g, ' ').trim()}”
                  </div>
                )}
                {s.lastError && (
                  <div
                    className="text-[10px] mt-0.5 truncate font-mono"
                    style={{ color: '#7a0000' }}
                    title={s.lastError}
                  >
                    {s.lastError}
                  </div>
                )}
              </div>
              {done && (
                <button
                  type="button"
                  className="sm-button secondary text-xs"
                  onClick={() => onReveal(v.inZipPath)}
                  title="Reveal transcript in Finder"
                >
                  📁 Reveal
                </button>
              )}
            </li>
          );
        })}
      </ul>
    </>
  );
}

function ActivityLog({ rows, onExport, onClear }: {
  rows: LogRow[];
  onExport: () => void;
  onClear: () => void;
}) {
  return (
    <>
      <div className="flex items-center justify-between gap-3 mb-2 text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
        <span>
          {rows.length === 0
            ? 'No activity yet — log fills in as jobs run.'
            : `Showing ${rows.length} most-recent event${rows.length === 1 ? '' : 's'}.`}
        </span>
        <div className="flex items-center gap-2">
          <button
            type="button"
            className="sm-button text-xs"
            disabled={rows.length === 0}
            onClick={onExport}
            title="Write a text-format log file into the bundle workspace + reveal it"
          >
            💾 Export processing.log
          </button>
          <button
            type="button"
            className="sm-button secondary text-xs"
            disabled={rows.length === 0}
            onClick={onClear}
            title="Wipe activity-log history for this bundle"
          >
            🗑 Clear
          </button>
        </div>
      </div>

      {rows.length > 0 && (
        <div
          className="rounded overflow-auto font-mono text-[11px]"
          style={{
            maxHeight: 360,
            background: 'rgb(var(--surface-base))',
            border: '1px solid rgb(var(--surface-border))',
            padding: 8,
          }}
        >
          {rows.map((r) => (
            <div key={r.id} className="flex gap-2 py-0.5">
              <span style={{ color: 'rgb(var(--surface-muted))', minWidth: 140 }}>
                {r.timestamp}
              </span>
              <span style={logLevelStyle(r.level)} className="font-semibold" >
                {r.level}
              </span>
              {r.kind && (
                <span style={{ color: 'rgb(var(--surface-muted))', minWidth: 130 }}>
                  {r.kind}
                </span>
              )}
              {r.subject && (
                <span className="truncate" style={{ maxWidth: 260 }} title={r.subject}>
                  {r.subject.split('/').pop()}
                </span>
              )}
              <span className="flex-1 truncate" title={r.message}>
                {r.message}
              </span>
              {r.details && (
                <span
                  className="truncate italic"
                  style={{ color: '#7a0000', maxWidth: 280 }}
                  title={r.details}
                >
                  {r.details.split('\n')[0]}
                </span>
              )}
            </div>
          ))}
        </div>
      )}
    </>
  );
}

function logLevelStyle(level: 'info' | 'warn' | 'error'): React.CSSProperties {
  switch (level) {
    case 'info':  return { color: 'rgb(var(--surface-accent))', minWidth: 40 };
    case 'warn':  return { color: '#7a5b00', minWidth: 40 };
    case 'error': return { color: '#7a0000', minWidth: 40 };
  }
}
