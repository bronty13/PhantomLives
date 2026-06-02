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
  clearBundleLog, clearBundleProcessing, detectBundleFormat,
  enqueueAutoAssemble, enqueueBundleTranscripts,
  enqueueBundleVideoOps, exportBundleLog, fmtSize, getBundleThumbnails,
  getEditDefaults, getMasterCutStatus, getProcessedPreviews, getTranscribeStatus,
  listLogEntries, listProcessedFiles, listTranscripts, openMasterCut,
  processBundleImages, revealBundleLog, revealMasterCut, revealProcessedFile,
  revealTranscript, revealWorkingFile, rotateBundleFiles, setBundleFileRotation,
  setBundleTitleOverride,
  type AssemblyFormat, type DetectedFormat,
  type BundleFileRow, type BundleSummary, type ImageOpsInput, type JobRow,
  type LogRow, type MasterCutStatus, type ProcessedFileRow, type RotationUpdate,
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

export function EditTab({ summary, files, refreshSignal, jobs, onFileUpdated }: Props) {
  // ── Local file mirror so rotation clicks update instantly without
  //   round-tripping through a full getBundle() refetch. Sync from prop
  //   when bundle UID changes (navigated to a different bundle) or when
  //   a non-rotation field is modified (refreshSignal bump).
  const [localFiles, setLocalFiles] = useState<BundleFileRow[]>(files);
  useEffect(() => { setLocalFiles(files); }, [files]);

  const images = useMemo(() => localFiles.filter((f) => f.kind === 'image'), [localFiles]);
  const videos = useMemo(() => localFiles.filter((f) => f.kind === 'video'), [localFiles]);
  const allMedia = useMemo(() => localFiles.filter((f) => f.kind === 'image' || f.kind === 'video'), [localFiles]);

  // Seeded from the global Edit defaults (Settings → Edit defaults) on mount;
  // the hardcoded literals are just the pre-load fallback.
  const [imageOps, setImageOps] = useState<ImageOpsInput>({ watermark: true, stripExif: true, rename: true });
  const [videoOps, setVideoOps] = useState<VideoOpsInput>({ watermark: true, stripMetadata: true, rename: true });
  useEffect(() => {
    let alive = true;
    getEditDefaults().then((d) => {
      if (!alive) return;
      setImageOps({ watermark: d.imageWatermark, stripExif: d.imageStripExif, rename: d.imageRename });
      setVideoOps({ watermark: d.videoWatermark, stripMetadata: d.videoStripMetadata, rename: d.videoRename });
    }).catch(() => { /* keep fallback defaults */ });
    return () => { alive = false; };
  }, []);
  const [busy, setBusy] = useState(false);
  const [busyLabel, setBusyLabel] = useState<string | null>(null);
  const [imageProgress, setImageProgress] = useState<ImageProgress | null>(null);
  const [lastResult, setLastResult] = useState<{ ok: number; skipped: number; errors: string[]; what: string } | null>(null);
  const [processed, setProcessed] = useState<ProcessedFileRow[]>([]);
  const [previews, setPreviews] = useState<Record<string, string>>({});
  const [thumbs, setThumbs] = useState<Record<string, string>>({});
  const [master, setMaster] = useState<MasterCutStatus | null>(null);
  // Per-bundle output orientation for the master cut. Defaults to 'auto'
  // (backend probes the clips); an explicit pick is remembered across
  // reloads (localStorage keyed by uid). `detectedFormat` holds what
  // 'auto' currently resolves to, for the hint next to the radio.
  const fmtKey = `sm.assemblyFormat.${summary.uid}`;
  const [assemblyFormat, setAssemblyFormat] = useState<AssemblyFormat>(() => {
    const saved = localStorage.getItem(fmtKey);
    return saved === 'vertical' || saved === 'horizontal' ? saved : 'auto';
  });
  const [detectedFormat, setDetectedFormat] = useState<DetectedFormat | null>(null);
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

  // ── Auto-detect the clips' orientation for the Format hint / 'auto'.
  useEffect(() => {
    let alive = true;
    detectBundleFormat(summary.uid)
      .then((f) => { if (alive) setDetectedFormat(f); })
      .catch(() => { if (alive) setDetectedFormat(null); });
    return () => { alive = false; };
  }, [summary.uid]);

  // ── Testing aid: wipe regenerable processing outputs for this bundle.
  const clearProcessing = async () => {
    if (!confirm(
      'Clear ALL processing for this bundle?\n\n' +
      'Deletes the auto-assemble, processed-media, and transcript outputs ' +
      '(files + queue + log rows). Your imported source clips stay put, so ' +
      'you can re-run everything from scratch. This cannot be undone.'
    )) return;
    setBusy(true);
    setBusyLabel('Clearing processing…');
    setLastResult(null);
    try {
      const r = await clearBundleProcessing(summary.uid);
      setLastResult({
        ok: 0, skipped: 0, errors: [],
        what: `🧹 Cleared processing — ${r.dirsRemoved.length} folder${r.dirsRemoved.length === 1 ? '' : 's'}, ` +
          `${r.processedRows} processed row${r.processedRows === 1 ? '' : 's'}, ${r.jobRows} job${r.jobRows === 1 ? '' : 's'} removed.`,
      });
      await refreshProcessed();
    } catch (e) {
      setLastResult({ ok: 0, skipped: 0, errors: [String(e)], what: 'clear processing failed' });
    } finally {
      setBusy(false);
      setBusyLabel(null);
    }
  };

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

  // ── Multi-select rotation. Tick clips, then rotate the selection (or
  //   all) 90° CW per press. The batch command returns the new rotation
  //   per file, which we merge into localFiles (same optimistic feel).
  const [selected, setSelected] = useState<Set<string>>(new Set());
  // Clear the selection when navigating to a different bundle.
  useEffect(() => { setSelected(new Set()); }, [summary.uid]);

  const toggleSelected = useCallback((inZipPath: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(inZipPath)) next.delete(inZipPath); else next.add(inZipPath);
      return next;
    });
  }, []);

  const rotatePaths = useCallback(async (paths: string[]) => {
    if (paths.length === 0) return;
    try {
      const updates: RotationUpdate[] = await rotateBundleFiles(summary.uid, paths, 90);
      const byPath = new Map(updates.map((u) => [u.inZipPath, u.rotationDegrees]));
      setLocalFiles((arr) =>
        arr.map((f) => byPath.has(f.inZipPath)
          ? { ...f, rotationDegrees: byPath.get(f.inZipPath)! as Rotation }
          : f),
      );
    } catch (e) { alert(String(e)); }
  }, [summary.uid]);

  const rotateSelected = () => rotatePaths([...selected]);
  const rotateAll = () => rotatePaths(allMedia.map((f) => f.inZipPath));
  const allSelected = allMedia.length > 0 && selected.size === allMedia.length;
  const selectAll = () => setSelected(new Set(allMedia.map((f) => f.inZipPath)));
  const clearSelection = () => setSelected(new Set());

  // ── Working title editor. Draft mirrors the effective title; saving
  //   sets the override (empty clears it), then refreshes the parent so
  //   the header + all processing pick up the new title.
  const [titleDraft, setTitleDraft] = useState(summary.title);
  const [savingTitle, setSavingTitle] = useState(false);
  useEffect(() => { setTitleDraft(summary.title); }, [summary.uid, summary.title]);
  const titleDirty = titleDraft.trim() !== summary.title.trim();
  const titleOverridden = summary.titleOverride.trim() !== ''
    && summary.titleOverride.trim() !== summary.originalTitle.trim();

  const saveTitle = async () => {
    setSavingTitle(true);
    try {
      await setBundleTitleOverride(summary.uid, titleDraft.trim());
      onFileUpdated?.();
    } catch (e) {
      alert(String(e));
    } finally {
      setSavingTitle(false);
    }
  };
  const resetTitle = async () => {
    setSavingTitle(true);
    try {
      await setBundleTitleOverride(summary.uid, '');
      setTitleDraft(summary.originalTitle);
      onFileUpdated?.();
    } catch (e) {
      alert(String(e));
    } finally {
      setSavingTitle(false);
    }
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
      const r = await enqueueAutoAssemble(summary.uid, assemblyFormat);
      const effective = assemblyFormat === 'auto' ? (detectedFormat ?? 'horizontal') : assemblyFormat;
      const fmtLabel = (assemblyFormat === 'auto' ? 'auto → ' : '') +
        (effective === 'vertical' ? '9:16 vertical' : '16:9 horizontal');
      setLastResult({
        ok: r.jobIds.length, skipped: 0, errors: r.errors,
        what: `🎞 Auto-assembly queued (${fmtLabel}) — ${r.videoCount} clip${r.videoCount === 1 ? '' : 's'} + title + master · running below ↓`,
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
          Working title — preserves Molly's original, used in processing
          ──────────────────────────────────────────────────────────── */}
      <div className="sm-card">
        <div className="font-semibold mb-1">✏️ Working title</div>
        <div className="text-xs mb-2" style={{ color: 'rgb(var(--surface-muted))' }}>
          Used for the master-cut filename, title card, Dropbox folder, and posting.
          Molly's original is preserved and the change is logged in the post-bundle.
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <input
            type="text"
            className="sm-input flex-1 min-w-[16rem]"
            value={titleDraft}
            disabled={savingTitle}
            onChange={(e) => setTitleDraft(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter' && titleDirty) saveTitle(); }}
            placeholder={summary.originalTitle || '(untitled)'}
          />
          <button
            type="button"
            className="sm-button"
            disabled={savingTitle || !titleDirty}
            onClick={saveTitle}
          >
            💾 Save title
          </button>
          {titleOverridden && (
            <button
              type="button"
              className="sm-button secondary text-xs"
              disabled={savingTitle}
              onClick={resetTitle}
              title="Revert to Molly's original title"
            >
              Reset to original
            </button>
          )}
        </div>
        {titleOverridden && (
          <div className="text-xs mt-2" style={{ color: 'rgb(var(--surface-muted))' }}>
            Edited from original: <em>{summary.originalTitle || '(untitled)'}</em>
          </div>
        )}
      </div>

      {/* ────────────────────────────────────────────────────────────
          STEP 1 — Review & rotate
          ──────────────────────────────────────────────────────────── */}
      <StepCard num={1} title="Review &amp; rotate" subtitle={
        <>Click a tile to cycle <code>0° → 90° → 180° → 270°</code>, or tick clips and use <strong>Rotate selected</strong> / <strong>Rotate all</strong> to turn them 90° at a time. The preview rotates instantly. Applies during the next image/video process run.</>
      }>
        <div className="mb-3 flex items-center gap-2 flex-wrap text-xs">
          <button
            type="button"
            className="sm-button secondary text-xs"
            disabled={allSelected}
            onClick={selectAll}
          >
            Select all
          </button>
          <button
            type="button"
            className="sm-button secondary text-xs"
            disabled={selected.size === 0}
            onClick={clearSelection}
          >
            Clear selection
          </button>
          <span style={{ color: 'rgb(var(--surface-muted))' }}>
            {selected.size} of {allMedia.length} selected
          </span>
          <span style={{ flex: 1 }} />
          <button
            type="button"
            className="sm-button secondary text-xs"
            disabled={selected.size === 0}
            onClick={rotateSelected}
            title={selected.size === 0 ? 'Tick one or more clips first' : `Rotate ${selected.size} selected 90° CW`}
          >
            ↻ Rotate selected ({selected.size})
          </button>
          <button
            type="button"
            className="sm-button secondary text-xs"
            disabled={allMedia.length === 0}
            onClick={rotateAll}
            title="Rotate every clip 90° CW"
          >
            ↻ Rotate all
          </button>
        </div>
        <RotationGrid
          files={allMedia}
          thumbs={thumbs}
          onClick={cycleRotation}
          selected={selected}
          onToggleSelect={toggleSelected}
        />
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
          <>One-click <strong>&lt;Title&gt;.mp4</strong>: 10s title card → 1.0s cross-dissolves between every clip (normalized, watermarked, audio-enhanced) → 1.0s fade-to-black. Pick the output format below. Output lands at <code>…/work/{summary.uid}/auto/&lt;Title&gt;.mp4</code>. Tune defaults in <em>Settings → Auto-Assembly</em>.</>
        }>
          <div className="flex items-center justify-between mb-3 gap-3 flex-wrap">
            <fieldset className="flex items-center gap-3 text-sm">
              <span className="text-zinc-500">Format:</span>
              {([
                ['auto', detectedFormat
                  ? `✨ Auto (${detectedFormat === 'vertical' ? '9:16' : '16:9'})`
                  : '✨ Auto'],
                ['horizontal', '🖥 16:9 Horizontal'],
                ['vertical', '📱 9:16 Vertical'],
              ] as [AssemblyFormat, string][]).map(([val, label]) => (
                <label key={val} className="flex items-center gap-1.5 cursor-pointer">
                  <input
                    type="radio"
                    name="assemblyFormat"
                    value={val}
                    checked={assemblyFormat === val}
                    disabled={busy || jobs.busy}
                    onChange={() => {
                      setAssemblyFormat(val);
                      localStorage.setItem(fmtKey, val);
                    }}
                  />
                  {label}
                </label>
              ))}
            </fieldset>
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

      {/* ────────────────────────────────────────────────────────────
          Testing — reset processing
          ──────────────────────────────────────────────────────────── */}
      <div className="flex items-center justify-between gap-3 flex-wrap px-1 py-2 text-xs"
           style={{ color: 'rgb(var(--surface-muted))' }}>
        <span>
          🧪 <strong>Testing:</strong> wipe this bundle's auto-assemble,
          processed-media, and transcript outputs (files + queue + log) so
          you can re-run from scratch. Imported source clips are kept.
        </span>
        <button
          type="button"
          className="sm-button secondary text-sm"
          disabled={busy || jobs.busy}
          onClick={clearProcessing}
        >
          🧹 Clear processing
        </button>
      </div>
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
                  title="Reveal the master cut in Finder">
            📁 Reveal
          </button>
          <button type="button" className="sm-button secondary text-sm"
                  onClick={() => navigator.clipboard.writeText(master.masterPath).catch(() => {})}
                  title="Copy the master cut path">
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

function RotationGrid({ files, thumbs, onClick, selected, onToggleSelect }: {
  files: BundleFileRow[];
  thumbs: Record<string, string>;
  onClick: (inZipPath: string, current: Rotation) => void;
  selected: Set<string>;
  onToggleSelect: (inZipPath: string) => void;
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
        const isSelected = selected.has(f.inZipPath);
        return (
          <button
            key={f.inZipPath}
            type="button"
            onClick={() => onClick(f.inZipPath, rot)}
            className="relative flex flex-col items-stretch text-left p-1.5 rounded transition"
            style={{
              border: `1px solid ${isSelected ? 'rgb(var(--surface-accent))' : rot === 0 ? 'rgb(var(--surface-border))' : 'rgb(var(--surface-accent))'}`,
              outline: isSelected ? '2px solid rgb(var(--surface-accent) / 0.5)' : 'none',
              background: 'rgb(var(--surface-card))',
            }}
            title={`Click to rotate (current: ${ROTATION_LABEL[rot]})`}
          >
            {/* Selection checkbox — stops propagation so ticking doesn't rotate. */}
            <label
              className="absolute top-1 left-1 z-10 flex items-center justify-center rounded"
              style={{ background: 'rgb(var(--surface-card) / 0.85)', padding: 2 }}
              onClick={(e) => e.stopPropagation()}
            >
              <input
                type="checkbox"
                checked={isSelected}
                onChange={() => onToggleSelect(f.inZipPath)}
                title="Select for batch rotate"
              />
            </label>
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
