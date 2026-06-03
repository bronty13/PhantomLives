import { useCallback, useEffect, useRef, useState } from 'react';
import { open, save } from '@tauri-apps/plugin-dialog';
import { downloadDir, join } from '@tauri-apps/api/path';
import {
  clampSettings,
  computeOutputSize,
  renderCaptionPng,
  MAX_DURATION_S,
  MAX_FPS,
  MAX_WIDTH,
  MP4_MAX_DURATION_S,
  MP4_MAX_BYTES,
  type CropBox,
  type GifQuality,
  type GifSettings,
} from './encodeGif';
import { probeVideo, generateGif, generateTeaserMp4, type CropPx } from '../../data/gifStudio';
import { DECODE_HELP } from './sourceUrl';
import { useVideoSource } from './useVideoSource';
import { useVideoStage } from './useVideoStage';

export interface GifSource {
  absolutePath: string;
  name: string;
}

interface Props {
  /** Videos already attached to the bundle, offered in the source dropdown. */
  bundleVideos?: GifSource[];
  /** Pre-selected source (standalone tool opens empty). */
  initialVideo?: GifSource | null;
  /** When provided, shows a "Use as Teaser GIF" button (bundle context). */
  onUseAsTeaser?: (bytes: Uint8Array, name: string) => Promise<void>;
  /** When provided (bundle context), the MP4 attaches to the bundle as a
   * video file ("Add to bundle") instead of offering a download. */
  onUseClip?: (bytes: Uint8Array, name: string) => Promise<void>;
  onClose: () => void;
  /** Render inline (standalone GIF Studio) instead of as a modal overlay. */
  embedded?: boolean;
}

const FPS_OPTIONS = [5, 8, 10, 12, 15, 20, MAX_FPS];
const WIDTH_OPTIONS = [240, 320, 400, 480, MAX_WIDTH];

/** In-app video→GIF/MP4 maker. The UI picks trim, fps, size, quality, crop,
 * caption; the native ffmpeg engine (src-tauri/src/media) renders the output
 * from the original file, so any iPhone/Windows format works. */
export function GifCreator({ bundleVideos = [], initialVideo = null, onUseAsTeaser, onUseClip, onClose, embedded = false }: Props) {
  const inBundle = !!onUseAsTeaser;
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const [source, setSource] = useState<GifSource | null>(initialVideo);
  const [duration, setDuration] = useState(0);

  const [startSec, setStartSec] = useState(0);
  const [endSec, setEndSec] = useState(3);
  const [fps, setFps] = useState(12);
  const [outputWidth, setOutputWidth] = useState(320);
  const [quality, setQuality] = useState<GifQuality>('high');
  const [crop, setCrop] = useState<CropBox | null>(null);
  const [captionText, setCaptionText] = useState('');
  const [captionPos, setCaptionPos] = useState<'top' | 'bottom'>('bottom');

  const [encoding, setEncoding] = useState(false);
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null);
  const [result, setResult] = useState<{ url: string; bytes: Uint8Array } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // MP4 export runs alongside the GIF flow (real-time MediaRecorder capture).
  const [recording, setRecording] = useState(false);
  const [recProgress, setRecProgress] = useState(0);
  const [mp4, setMp4] = useState<{ url: string; bytes: Uint8Array; ext: string; audioIncluded: boolean } | null>(null);

  // Decodable preview URL for scrubbing only (never drawn to a canvas, so
  // convertFileSrc is fine); undecodable sources get a native H.264 proxy.
  const { videoSrc, status: srcStatus, error: srcError } = useVideoSource(source);
  const srcReady = srcStatus === 'ready';

  const stage = useVideoStage(videoRef, source?.absolutePath);

  // Revoke object URLs when results change / unmount.
  useEffect(() => () => { if (result) URL.revokeObjectURL(result.url); }, [result]);
  useEffect(() => () => { if (mp4) URL.revokeObjectURL(mp4.url); }, [mp4]);

  function resetForNewSource() {
    setStartSec(0);
    setEndSec(3);
    setCrop(null);
    if (result) { URL.revokeObjectURL(result.url); setResult(null); }
    if (mp4) { URL.revokeObjectURL(mp4.url); setMp4(null); }
    setError(null);
  }

  function onLoadedMetadata() {
    const v = videoRef.current;
    if (!v) return;
    const d = v.duration || 0;
    setDuration(d);
    setEndSec(Math.min(d || 3, Math.max(1, Math.min(3, d || 3))));
  }

  async function pickFromDisk() {
    try {
      const picked = await open({
        multiple: false, directory: false, title: 'Pick a video',
        filters: [{ name: 'Video', extensions: ['mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi'] }],
      });
      if (!picked || typeof picked !== 'string') return;
      const name = picked.split(/[/\\]/).pop() ?? 'video';
      resetForNewSource();
      setSource({ absolutePath: picked, name });
    } catch (e) {
      setError(String(e));
    }
  }

  // Seek the preview to the in-point whenever start changes, so the user
  // sees the frame the GIF will begin on.
  useEffect(() => {
    const v = videoRef.current;
    if (v && Number.isFinite(startSec)) {
      try { v.currentTime = Math.min(startSec, Math.max(0, (v.duration || startSec) - 0.05)); } catch { /* not seekable yet */ }
    }
  }, [startSec, source]);

  // ---- Crop overlay (drag to draw a normalized rectangle) ----
  const overlayRef = useRef<HTMLDivElement | null>(null);
  const dragStart = useRef<{ x: number; y: number } | null>(null);
  const onOverlayDown = useCallback((e: React.MouseEvent) => {
    const el = overlayRef.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    dragStart.current = { x: (e.clientX - r.left) / r.width, y: (e.clientY - r.top) / r.height };
    setCrop({ x: dragStart.current.x, y: dragStart.current.y, w: 0, h: 0 });
  }, []);
  const onOverlayMove = useCallback((e: React.MouseEvent) => {
    const el = overlayRef.current;
    const s = dragStart.current;
    if (!el || !s) return;
    const r = el.getBoundingClientRect();
    const cx = Math.max(0, Math.min(1, (e.clientX - r.left) / r.width));
    const cy = Math.max(0, Math.min(1, (e.clientY - r.top) / r.height));
    setCrop({ x: Math.min(s.x, cx), y: Math.min(s.y, cy), w: Math.abs(cx - s.x), h: Math.abs(cy - s.y) });
  }, []);
  const onOverlayUp = useCallback(() => {
    const c = dragStart.current;
    dragStart.current = null;
    // Discard a too-tiny accidental drag.
    setCrop((prev) => (prev && (prev.w < 0.04 || prev.h < 0.04) ? null : prev));
    void c;
  }, []);

  const settings: GifSettings = {
    startSec, endSec, fps, outputWidth, quality,
    crop: crop && crop.w > 0.02 && crop.h > 0.02 ? crop : null,
    caption: captionText.trim() ? { text: captionText.trim(), position: captionPos, sizeFrac: 0.09 } : null,
  };
  const clamped = clampSettings(settings, duration || MAX_DURATION_S);

  // Map a (possibly cropped) source to the pixel crop rect + output dims the
  // native engine wants — same math as the canvas path used, so the caption
  // PNG (sized to the output) and ffmpeg's crop/scale agree to the pixel.
  async function geometryFor(outputWidth: number, crop: CropBox | null | undefined, caption: GifSettings['caption']) {
    if (!source) throw new Error('Pick a video first.');
    const probe = await probeVideo(source.absolutePath);
    const g = computeOutputSize(probe.width, probe.height, crop, outputWidth);
    const cropPx: CropPx | null = crop ? { sx: g.sx, sy: g.sy, sw: g.sw, sh: g.sh } : null;
    const captionPng = caption && caption.text.trim()
      ? Array.from(await renderCaptionPng(caption, g.width, g.height))
      : null;
    return { probe, width: g.width, height: g.height, cropPx, captionPng };
  }

  async function generate() {
    if (!source) { setError('Pick a video first.'); return; }
    setEncoding(true);
    setError(null);
    setProgress({ done: 0, total: 100 });
    if (result) { URL.revokeObjectURL(result.url); setResult(null); }
    try {
      const { probe, width, height, cropPx, captionPng } = await geometryFor(clamped.outputWidth, clamped.crop, clamped.caption);
      const bytes = await generateGif({
        absolutePath: source.absolutePath,
        startSec: clamped.startSec, endSec: clamped.endSec, fps: clamped.fps,
        outWidth: width, outHeight: height, crop: cropPx,
        isHdr: probe.isHdr, quality: clamped.quality, captionPng,
      }, (f) => setProgress({ done: Math.round(f * 100), total: 100 }));
      const url = URL.createObjectURL(new Blob([bytes as BlobPart], { type: 'image/gif' }));
      setResult({ url, bytes });
    } catch (e) {
      setError(`Couldn't make the GIF: ${e}. ${DECODE_HELP}`);
    } finally {
      setEncoding(false);
      setProgress(null);
    }
  }

  function defaultGifName(): string {
    const base = (source?.name ?? 'teaser').replace(/\.[^.]+$/, '');
    return `${base}_tease.gif`;
  }

  async function useAsTeaser() {
    if (!result || !onUseAsTeaser) return;
    setBusy(true);
    setError(null);
    try {
      await onUseAsTeaser(result.bytes, defaultGifName());
      onClose();
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }

  async function download() {
    if (!result) return;
    setBusy(true);
    setError(null);
    try {
      const target = await save({
        title: 'Save GIF',
        defaultPath: await join(await downloadDir(), defaultGifName()),
        filters: [{ name: 'GIF', extensions: ['gif'] }],
      });
      if (!target) return;
      const { writeBytesToPath } = await import('../../data/bundles');
      await writeBytesToPath(target, result.bytes);
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }

  async function exportMp4() {
    if (!source) { setError('Pick a video first.'); return; }
    setRecording(true);
    setError(null);
    setRecProgress(0);
    if (mp4) { URL.revokeObjectURL(mp4.url); setMp4(null); }
    try {
      // MP4 allows a longer clip than the GIF (≤60s); use the raw trim capped
      // to the MP4 ceiling, not the GIF-clamped 15s.
      const endCapped = Math.min(endSec, startSec + MP4_MAX_DURATION_S);
      // Encode near native resolution for quality (not the small GIF width);
      // computeOutputSize caps to the source, and the engine fits it under
      // 100 MB via a budget-derived bitrate ceiling. 1920 keeps 4K sane.
      const { probe, width, height, cropPx, captionPng } = await geometryFor(1920, settings.crop, settings.caption);
      const bytes = await generateTeaserMp4({
        absolutePath: source.absolutePath,
        startSec, endSec: endCapped,
        outWidth: width, outHeight: height, crop: cropPx,
        isHdr: probe.isHdr, includeAudio: true, captionPng,
      }, (f) => setRecProgress(f));
      const url = URL.createObjectURL(new Blob([bytes as BlobPart], { type: 'video/mp4' }));
      setMp4({ url, bytes, ext: 'mp4', audioIncluded: probe.hasAudio });
      if (bytes.length > MP4_MAX_BYTES) {
        setError(`Heads up: that clip came out ${(bytes.length / (1024 * 1024)).toFixed(0)} MB, over the 100 MB target. Try a shorter trim or smaller width.`);
      }
    } catch (e) {
      setError(`Couldn't make the clip: ${e}. ${DECODE_HELP}`);
    } finally {
      setRecording(false);
      setRecProgress(0);
    }
  }

  function defaultClipName(): string {
    const base = (source?.name ?? 'teaser').replace(/\.[^.]+$/, '');
    return `${base}_tease.${mp4?.ext ?? 'mp4'}`;
  }

  async function addClipToBundle() {
    if (!mp4 || !onUseClip) return;
    setBusy(true);
    setError(null);
    try {
      await onUseClip(mp4.bytes, defaultClipName());
      onClose();
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }

  async function downloadMp4() {
    if (!mp4) return;
    setBusy(true);
    setError(null);
    try {
      const target = await save({
        title: 'Save clip',
        defaultPath: await join(await downloadDir(), defaultClipName()),
        filters: [{ name: mp4.ext.toUpperCase(), extensions: [mp4.ext] }],
      });
      if (!target) return;
      const { writeBytesToPath } = await import('../../data/bundles');
      await writeBytesToPath(target, mp4.bytes);
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }

  const cropStyle = crop
    ? {
        left: `${crop.x * 100}%`, top: `${crop.y * 100}%`,
        width: `${crop.w * 100}%`, height: `${crop.h * 100}%`,
      }
    : null;

  const body = (
      <>
        {!embedded && (
          <div className="flex items-center justify-between">
            <h2 className="display-font text-xl font-bold">🎞️ Make a Teaser Video/GIF</h2>
            <button type="button" onClick={onClose} className="pretty-button secondary text-xs">Close</button>
          </div>
        )}

        {/* Source */}
        <div className="flex flex-wrap items-center gap-2">
          {bundleVideos.length > 0 && (
            <select
              className="pretty-input"
              value={source?.absolutePath ?? ''}
              onChange={(e) => {
                const v = bundleVideos.find((b) => b.absolutePath === e.target.value);
                if (v) { resetForNewSource(); setSource(v); }
              }}
            >
              <option value="">— pick a bundle video —</option>
              {bundleVideos.map((b) => (
                <option key={b.absolutePath} value={b.absolutePath}>{b.name}</option>
              ))}
            </select>
          )}
          <button type="button" className="pretty-button secondary" onClick={pickFromDisk}>📁 Pick from disk</button>
          {source && <span className="text-sm opacity-70 font-mono truncate max-w-[16rem]">{source.name}</span>}
          {srcStatus === 'loading' && <span className="text-xs text-pink-600">loading video…</span>}
          {srcStatus === 'preparing' && (
            <span className="text-xs text-pink-600">✨ Preparing iPhone video…</span>
          )}
        </div>

        {videoSrc ? (
          <>
            {/* Preview + crop overlay */}
            <div className="relative inline-block max-w-full bg-black/5 rounded-lg overflow-hidden select-none">
              <video
                ref={videoRef}
                src={videoSrc}
                onLoadedMetadata={onLoadedMetadata}
                className="block max-h-[40vh] max-w-full"
                muted
                playsInline
                preload="auto"
              />
              <div
                ref={overlayRef}
                className="absolute cursor-crosshair"
                style={stage ? { left: stage.left, top: stage.top, width: stage.width, height: stage.height } : { inset: 0 }}
                onMouseDown={onOverlayDown}
                onMouseMove={onOverlayMove}
                onMouseUp={onOverlayUp}
                onMouseLeave={onOverlayUp}
              >
                {cropStyle && (
                  <div className="absolute border-2 border-pink-400 bg-pink-300/20" style={cropStyle} />
                )}
              </div>
            </div>
            <div className="text-xs opacity-60">
              Cropping is optional — without it you get the whole frame. Drag on the preview to crop, or{' '}
              <button type="button" className="underline" onClick={() => setCrop({ x: 0, y: 0, w: 1, h: 1 })}>select whole frame</button>.
              {crop && <> · <button type="button" className="underline" onClick={() => setCrop(null)}>Clear crop</button></>}
            </div>

            {/* Trim */}
            <div className="grid grid-cols-2 gap-4">
              <label className="space-y-1 block">
                <span className="text-xs font-semibold opacity-75">Start: {startSec.toFixed(1)}s</span>
                <input type="range" min={0} max={duration || 1} step={0.1} value={startSec}
                  onChange={(e) => { const v = parseFloat(e.target.value); setStartSec(v); if (v > endSec) setEndSec(v); }}
                  className="w-full" />
              </label>
              <label className="space-y-1 block">
                <span className="text-xs font-semibold opacity-75">End: {endSec.toFixed(1)}s ({(endSec - startSec).toFixed(1)}s clip)</span>
                <input type="range" min={0} max={duration || 1} step={0.1} value={endSec}
                  onChange={(e) => { const v = parseFloat(e.target.value); setEndSec(v); if (v < startSec) setStartSec(v); }}
                  className="w-full" />
              </label>
            </div>
            {(endSec - startSec) > MAX_DURATION_S && (
              <div className="text-xs text-amber-700">Clips are capped at {MAX_DURATION_S}s — I'll trim the end.</div>
            )}

            {/* Settings */}
            <div className="grid grid-cols-3 gap-4">
              <label className="space-y-1 block">
                <span className="text-xs font-semibold opacity-75">Frame rate</span>
                <select className="pretty-input w-full" value={fps} onChange={(e) => setFps(parseInt(e.target.value, 10))}>
                  {FPS_OPTIONS.map((f) => <option key={f} value={f}>{f} fps</option>)}
                </select>
              </label>
              <label className="space-y-1 block">
                <span className="text-xs font-semibold opacity-75">Width</span>
                <select className="pretty-input w-full" value={outputWidth} onChange={(e) => setOutputWidth(parseInt(e.target.value, 10))}>
                  {WIDTH_OPTIONS.map((w) => <option key={w} value={w}>{w}px</option>)}
                </select>
              </label>
              <label className="space-y-1 block">
                <span className="text-xs font-semibold opacity-75">Quality</span>
                <select className="pretty-input w-full" value={quality} onChange={(e) => setQuality(e.target.value as GifQuality)}>
                  <option value="high">High (256 colors)</option>
                  <option value="medium">Medium (128)</option>
                  <option value="low">Low (64)</option>
                </select>
              </label>
            </div>

            {/* Caption */}
            <div className="grid grid-cols-3 gap-4 items-end">
              <label className="space-y-1 block col-span-2">
                <span className="text-xs font-semibold opacity-75">Caption (optional)</span>
                <input className="pretty-input w-full" value={captionText} maxLength={80}
                  onChange={(e) => setCaptionText(e.target.value)} placeholder="Overlay text…" />
              </label>
              <label className="space-y-1 block">
                <span className="text-xs font-semibold opacity-75">Position</span>
                <select className="pretty-input w-full" value={captionPos} onChange={(e) => setCaptionPos(e.target.value as 'top' | 'bottom')}>
                  <option value="bottom">Bottom</option>
                  <option value="top">Top</option>
                </select>
              </label>
            </div>

            <div className="text-xs opacity-60">
              ≈ {clamped.fps} fps × {(clamped.endSec - clamped.startSec).toFixed(1)}s → about {Math.max(1, Math.round((clamped.endSec - clamped.startSec) * clamped.fps))} frames at {clamped.outputWidth}px wide.
            </div>

            {/* Generate */}
            <div className="flex items-center gap-3 flex-wrap">
              <button type="button" className="pretty-button" onClick={generate} disabled={encoding || recording || !srcReady}>
                {encoding ? 'Making GIF…' : '✨ Generate GIF'}
              </button>
              <button type="button" className="pretty-button secondary" onClick={exportMp4} disabled={encoding || recording || !srcReady}>
                {recording ? 'Making clip…' : '🎬 Export MP4 clip'}
              </button>
              {progress && progress.total > 0 && (
                <div className="flex-1 min-w-[8rem]">
                  <div className="h-2 bg-pink-100 rounded-full overflow-hidden">
                    <div className="h-full bg-pink-400" style={{ width: `${(progress.done / progress.total) * 100}%` }} />
                  </div>
                  <div className="text-xs opacity-60 mt-1">Making GIF… {Math.round((progress.done / progress.total) * 100)}%</div>
                </div>
              )}
              {recording && (
                <div className="flex-1 min-w-[8rem]">
                  <div className="h-2 bg-pink-100 rounded-full overflow-hidden">
                    <div className="h-full bg-pink-400" style={{ width: `${recProgress * 100}%` }} />
                  </div>
                  <div className="text-xs opacity-60 mt-1">Making clip… {Math.round(recProgress * 100)}%</div>
                </div>
              )}
            </div>
            <div className="text-xs opacity-50">
              The MP4 keeps your trim + crop + caption, includes audio, and is capped at {MP4_MAX_DURATION_S}s / 100 MB.
            </div>
            {(endSec - startSec) > MP4_MAX_DURATION_S && (
              <div className="text-xs text-amber-700">
                Your trim is {(endSec - startSec).toFixed(0)}s — the MP4 will be capped at the first {MP4_MAX_DURATION_S}s. Tighten the trim if you want the whole moment.
              </div>
            )}

            {/* GIF result */}
            {result && (
              <div className="space-y-2 border-t border-black/5 pt-3">
                <div className="text-xs font-semibold opacity-75">GIF preview ({Math.round(result.bytes.length / 1024)} KB)</div>
                <img src={result.url} alt="Generated GIF preview" className="rounded-lg border border-pink-200 max-h-[40vh]" />
                <div className="flex gap-2">
                  {inBundle ? (
                    <button type="button" className="pretty-button" onClick={useAsTeaser} disabled={busy}>
                      🎁 Use as Teaser GIF
                    </button>
                  ) : (
                    <button type="button" className="pretty-button" onClick={download} disabled={busy}>
                      ⬇️ Download GIF
                    </button>
                  )}
                </div>
              </div>
            )}

            {/* MP4 result */}
            {mp4 && (
              <div className="space-y-2 border-t border-black/5 pt-3">
                <div className="text-xs font-semibold opacity-75">
                  MP4 preview ({(mp4.bytes.length / (1024 * 1024)).toFixed(1)} MB{mp4.audioIncluded ? ' · with audio' : ' · no audio'})
                </div>
                <video src={mp4.url} controls playsInline className="rounded-lg border border-pink-200 w-full max-h-[55vh] bg-black" />
                <div className="flex gap-2">
                  {inBundle && onUseClip ? (
                    <button type="button" className="pretty-button" onClick={addClipToBundle} disabled={busy}>
                      🎁 Add MP4 to bundle
                    </button>
                  ) : (
                    <button type="button" className="pretty-button secondary" onClick={downloadMp4} disabled={busy}>
                      ⬇️ Download MP4
                    </button>
                  )}
                </div>
              </div>
            )}
          </>
        ) : (
          <div className="text-sm opacity-60 italic py-8 text-center">
            Pick a video to get started — from this bundle or from your disk.
          </div>
        )}

        {(error || srcError) && <div className="text-sm text-red-700 bg-red-50 border border-red-200 rounded-xl px-3 py-2">{error || srcError}</div>}
      </>
  );

  if (embedded) {
    return (
      <div className="bg-white rounded-2xl shadow-sm border border-black/5 p-6 space-y-4">
        {body}
      </div>
    );
  }
  return (
    <div className="fixed inset-0 z-50 bg-black/40 flex items-center justify-center p-4" onClick={onClose}>
      <div
        className="bg-white rounded-2xl shadow-xl max-w-4xl w-full max-h-[92vh] overflow-auto p-6 space-y-4"
        onClick={(e) => e.stopPropagation()}
      >
        {body}
      </div>
    </div>
  );
}
