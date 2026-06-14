import { useCallback, useEffect, useRef, useState } from 'react';
import { open, save } from '@tauri-apps/plugin-dialog';
import { downloadDir, join } from '@tauri-apps/api/path';
import { computeOutputSize, renderCaptionPng, type CropBox } from './encodeGif';
import { probeVideo, grabFrame } from '../../data/gifStudio';
import { CopyableError } from '../../components/CopyableError';
import { MediaDiagnosticsButton } from '../../components/MediaDiagnosticsButton';
import { DECODE_HELP } from './sourceUrl';
import { useVideoSource } from './useVideoSource';
import { useVideoStage } from './useVideoStage';
import type { GifSource } from './GifCreator';

interface Props {
  /** Videos already attached to the bundle, offered in the source dropdown. */
  bundleVideos?: GifSource[];
  initialVideo?: GifSource | null;
  /** When provided, shows a "Use as Thumbnail" button (bundle context). */
  onUseAsThumbnail?: (bytes: Uint8Array, name: string) => Promise<void>;
  onClose: () => void;
}

const WIDTH_OPTIONS = [480, 640, 800, 1080];

/** Pick a single key frame from a video and use it as the bundle thumbnail.
 * Sibling of GifCreator — same source picker, scrubbing, crop overlay, and
 * caption — but captures one JPEG frame instead of an animated GIF. */
export function FrameGrabber({ bundleVideos = [], initialVideo = null, onUseAsThumbnail, onClose }: Props) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const [source, setSource] = useState<GifSource | null>(initialVideo);
  const [duration, setDuration] = useState(0);
  const [timeSec, setTimeSec] = useState(0);
  const [outputWidth, setOutputWidth] = useState(640);
  const [crop, setCrop] = useState<CropBox | null>(null);
  const [captionText, setCaptionText] = useState('');
  const [captionPos, setCaptionPos] = useState<'top' | 'bottom'>('bottom');

  const [result, setResult] = useState<{ url: string; bytes: Uint8Array } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Decodable, same-origin blob: URL — reads bytes (origin-clean, not
  // convertFileSrc) and transcodes undecodable sources (iPhone HEVC) to H.264
  // in-app. See useVideoSource.ts.
  const { videoSrc, status: srcStatus, error: srcError } = useVideoSource(source);
  const srcReady = srcStatus === 'ready';

  const stage = useVideoStage(videoRef, source?.absolutePath);

  useEffect(() => () => { if (result) URL.revokeObjectURL(result.url); }, [result]);

  function resetForNewSource() {
    setTimeSec(0);
    setCrop(null);
    if (result) { URL.revokeObjectURL(result.url); setResult(null); }
    setError(null);
  }

  function onLoadedMetadata() {
    const v = videoRef.current;
    if (!v) return;
    setDuration(v.duration || 0);
  }

  // Seek the preview to the chosen time so the user sees exactly the frame.
  useEffect(() => {
    const v = videoRef.current;
    if (v && Number.isFinite(timeSec)) {
      try { v.currentTime = Math.min(timeSec, Math.max(0, (v.duration || timeSec) - 0.02)); } catch { /* not seekable yet */ }
    }
  }, [timeSec, source]);

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
    dragStart.current = null;
    setCrop((prev) => (prev && (prev.w < 0.04 || prev.h < 0.04) ? null : prev));
  }, []);

  async function capture() {
    if (!source) { setError('Pick a video first.'); return; }
    setBusy(true);
    setError(null);
    if (result) { URL.revokeObjectURL(result.url); setResult(null); }
    try {
      const useCrop = crop && crop.w > 0.02 && crop.h > 0.02 ? crop : null;
      const caption = captionText.trim() ? { text: captionText.trim(), position: captionPos, sizeFrac: 0.09 } as const : null;
      const probe = await probeVideo(source.absolutePath);
      const g = computeOutputSize(probe.width, probe.height, useCrop, outputWidth);
      const captionPng = caption ? Array.from(await renderCaptionPng(caption, g.width, g.height)) : null;
      const bytes = await grabFrame({
        absolutePath: source.absolutePath,
        timeSec,
        outWidth: g.width, outHeight: g.height,
        crop: useCrop ? { sx: g.sx, sy: g.sy, sw: g.sw, sh: g.sh } : null,
        isHdr: probe.isHdr,
        captionPng,
      });
      const url = URL.createObjectURL(new Blob([bytes as BlobPart], { type: 'image/jpeg' }));
      setResult({ url, bytes });
    } catch (e) {
      setError(`Couldn't grab the frame: ${e}. ${DECODE_HELP}`);
    } finally {
      setBusy(false);
    }
  }

  function defaultName(): string {
    const base = (source?.name ?? 'thumbnail').replace(/\.[^.]+$/, '');
    return `${base}.jpg`;
  }

  async function useAsThumbnail() {
    if (!result || !onUseAsThumbnail) return;
    setBusy(true);
    setError(null);
    try {
      await onUseAsThumbnail(result.bytes, defaultName());
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
      const target = await save({ title: 'Save image', defaultPath: await join(await downloadDir(), defaultName()), filters: [{ name: 'JPEG', extensions: ['jpg'] }] });
      if (!target) return;
      const { writeBytesToPath } = await import('../../data/bundles');
      await writeBytesToPath(target, result.bytes);
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }

  const cropStyle = crop
    ? { left: `${crop.x * 100}%`, top: `${crop.y * 100}%`, width: `${crop.w * 100}%`, height: `${crop.h * 100}%` }
    : null;

  return (
    <div className="fixed inset-0 z-50 bg-black/40 flex items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl shadow-xl max-w-4xl w-full max-h-[92vh] overflow-auto p-6 space-y-4" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between">
          <h2 className="display-font text-xl font-bold">🖼️ Grab a frame from a video</h2>
          <button type="button" onClick={onClose} className="pretty-button secondary text-xs">Close</button>
        </div>

        {/* Source */}
        <div className="flex flex-wrap items-center gap-2">
          {bundleVideos.length > 0 && (
            <select className="pretty-input" value={source?.absolutePath ?? ''}
              onChange={(e) => { const v = bundleVideos.find((b) => b.absolutePath === e.target.value); if (v) { resetForNewSource(); setSource(v); } }}>
              <option value="">— pick a bundle video —</option>
              {bundleVideos.map((b) => <option key={b.absolutePath} value={b.absolutePath}>{b.name}</option>)}
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
              <video ref={videoRef} src={videoSrc} onLoadedMetadata={onLoadedMetadata} className="block max-h-[44vh] max-w-full" muted playsInline preload="auto" />
              <div ref={overlayRef} className="absolute cursor-crosshair"
                style={stage ? { left: stage.left, top: stage.top, width: stage.width, height: stage.height } : { inset: 0 }}
                onMouseDown={onOverlayDown} onMouseMove={onOverlayMove} onMouseUp={onOverlayUp} onMouseLeave={onOverlayUp}>
                {cropStyle && <div className="absolute border-2 border-pink-400 bg-pink-300/20" style={cropStyle} />}
              </div>
            </div>
            <div className="text-xs opacity-60">
              Cropping is optional — without it you get the whole frame. Drag on the preview to crop, or{' '}
              <button type="button" className="underline" onClick={() => setCrop({ x: 0, y: 0, w: 1, h: 1 })}>select whole frame</button>.
              {crop && <> · <button type="button" className="underline" onClick={() => setCrop(null)}>Clear crop</button></>}
            </div>

            {/* Scrub */}
            <label className="space-y-1 block">
              <span className="text-xs font-semibold opacity-75">Frame at {timeSec.toFixed(2)}s</span>
              <input type="range" min={0} max={duration || 1} step={0.05} value={timeSec}
                onChange={(e) => setTimeSec(parseFloat(e.target.value))} className="w-full" />
            </label>
            <div className="flex gap-2">
              <button type="button" className="pretty-button secondary text-xs" onClick={() => setTimeSec((t) => Math.max(0, t - 0.05))}>◀ −0.05s</button>
              <button type="button" className="pretty-button secondary text-xs" onClick={() => setTimeSec((t) => Math.min(duration, t + 0.05))}>+0.05s ▶</button>
            </div>

            {/* Settings */}
            <div className="grid grid-cols-3 gap-4 items-end">
              <label className="space-y-1 block">
                <span className="text-xs font-semibold opacity-75">Width</span>
                <select className="pretty-input w-full" value={outputWidth} onChange={(e) => setOutputWidth(parseInt(e.target.value, 10))}>
                  {WIDTH_OPTIONS.map((w) => <option key={w} value={w}>{w}px</option>)}
                </select>
              </label>
              <label className="space-y-1 block col-span-2">
                <span className="text-xs font-semibold opacity-75">Caption (optional)</span>
                <input className="pretty-input w-full" value={captionText} maxLength={80}
                  onChange={(e) => setCaptionText(e.target.value)} placeholder="Overlay text…" />
              </label>
            </div>
            {captionText.trim() && (
              <label className="space-y-1 block w-40">
                <span className="text-xs font-semibold opacity-75">Caption position</span>
                <select className="pretty-input w-full" value={captionPos} onChange={(e) => setCaptionPos(e.target.value as 'top' | 'bottom')}>
                  <option value="bottom">Bottom</option>
                  <option value="top">Top</option>
                </select>
              </label>
            )}

            <button type="button" className="pretty-button" onClick={capture} disabled={busy || !srcReady}>
              {busy ? 'Working…' : '📸 Capture frame'}
            </button>

            {/* Result */}
            {result && (
              <div className="space-y-2 border-t border-black/5 pt-3">
                <div className="text-xs font-semibold opacity-75">Preview ({Math.round(result.bytes.length / 1024)} KB)</div>
                <img src={result.url} alt="Captured frame preview" className="rounded-lg border border-pink-200 max-h-[40vh]" />
                <div className="flex gap-2">
                  {onUseAsThumbnail ? (
                    <button type="button" className="pretty-button" onClick={useAsThumbnail} disabled={busy}>🖼️ Use as Thumbnail</button>
                  ) : (
                    <button type="button" className="pretty-button secondary" onClick={download} disabled={busy}>⬇️ Download</button>
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

        {(error || srcError) && <CopyableError message={String(error || srcError)} />}
        <div className="flex justify-end pt-1">
          <MediaDiagnosticsButton />
        </div>
      </div>
    </div>
  );
}
