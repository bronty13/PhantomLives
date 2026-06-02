import { useCallback, useEffect, useRef, useState } from 'react';
import { open, save } from '@tauri-apps/plugin-dialog';
import { convertFileSrc } from '@tauri-apps/api/core';
import {
  captureAndEncode,
  clampSettings,
  MAX_DURATION_S,
  MAX_FPS,
  MAX_WIDTH,
  type CropBox,
  type GifQuality,
  type GifSettings,
} from './encodeGif';

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
  onClose: () => void;
  /** Render inline (standalone GIF Studio) instead of as a modal overlay. */
  embedded?: boolean;
}

const FPS_OPTIONS = [5, 8, 10, 12, 15, 20, MAX_FPS];
const WIDTH_OPTIONS = [240, 320, 400, 480, MAX_WIDTH];

/** In-app video→GIF maker. 100% client-side (canvas seek + gifenc) so it
 * works identically on Windows with no ffmpeg. Mirrors the controls of a
 * browser converter: trim, fps, size, quality, crop, caption. */
export function GifCreator({ bundleVideos = [], initialVideo = null, onUseAsTeaser, onClose, embedded = false }: Props) {
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

  const videoSrc = source ? convertFileSrc(source.absolutePath) : null;

  // Revoke the object URL when the result changes / unmounts.
  useEffect(() => () => { if (result) URL.revokeObjectURL(result.url); }, [result]);

  function resetForNewSource() {
    setStartSec(0);
    setEndSec(3);
    setCrop(null);
    if (result) { URL.revokeObjectURL(result.url); setResult(null); }
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

  async function generate() {
    const v = videoRef.current;
    if (!v || !source) { setError('Pick a video first.'); return; }
    setEncoding(true);
    setError(null);
    setProgress({ done: 0, total: 0 });
    if (result) { URL.revokeObjectURL(result.url); setResult(null); }
    try {
      const bytes = await captureAndEncode(v, settings, (done, total) => setProgress({ done, total }));
      const url = URL.createObjectURL(new Blob([bytes as BlobPart], { type: 'image/gif' }));
      setResult({ url, bytes });
    } catch (e) {
      setError(`Couldn't make the GIF: ${e}. On a Mac, .mov files sometimes won't decode — try an .mp4.`);
    } finally {
      setEncoding(false);
      setProgress(null);
    }
  }

  function defaultGifName(): string {
    const base = (source?.name ?? 'teaser').replace(/\.[^.]+$/, '');
    return `${base}.gif`;
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
        defaultPath: defaultGifName(),
        filters: [{ name: 'GIF', extensions: ['gif'] }],
      });
      if (!target) return;
      const { writeBytesToPath } = await import('../../data/bundles');
      // Default the dir to ~/Downloads/Molly GIF/ when the user didn't navigate.
      await writeBytesToPath(target, result.bytes);
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
            <h2 className="display-font text-xl font-bold">🎞️ Make a GIF from a video</h2>
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
                className="absolute inset-0 cursor-crosshair"
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
              Drag on the preview to crop. {crop && <button type="button" className="underline" onClick={() => setCrop(null)}>Clear crop</button>}
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
            <div className="flex items-center gap-3">
              <button type="button" className="pretty-button" onClick={generate} disabled={encoding}>
                {encoding ? 'Making GIF…' : '✨ Generate GIF'}
              </button>
              {progress && progress.total > 0 && (
                <div className="flex-1">
                  <div className="h-2 bg-pink-100 rounded-full overflow-hidden">
                    <div className="h-full bg-pink-400" style={{ width: `${(progress.done / progress.total) * 100}%` }} />
                  </div>
                  <div className="text-xs opacity-60 mt-1">Frame {progress.done} / {progress.total}</div>
                </div>
              )}
            </div>

            {/* Result */}
            {result && (
              <div className="space-y-2 border-t border-black/5 pt-3">
                <div className="text-xs font-semibold opacity-75">Preview ({Math.round(result.bytes.length / 1024)} KB)</div>
                <img src={result.url} alt="Generated GIF preview" className="rounded-lg border border-pink-200 max-h-[40vh]" />
                <div className="flex gap-2">
                  {onUseAsTeaser && (
                    <button type="button" className="pretty-button" onClick={useAsTeaser} disabled={busy}>
                      🎁 Use as Teaser GIF
                    </button>
                  )}
                  <button type="button" className="pretty-button secondary" onClick={download} disabled={busy}>
                    ⬇️ Download
                  </button>
                </div>
              </div>
            )}
          </>
        ) : (
          <div className="text-sm opacity-60 italic py-8 text-center">
            Pick a video to get started — from this bundle or from your disk.
          </div>
        )}

        {error && <div className="text-sm text-red-700 bg-red-50 border border-red-200 rounded-xl px-3 py-2">{error}</div>}
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
