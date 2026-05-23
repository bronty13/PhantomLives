import { useEffect, useRef, useState } from 'react';
import { convertFileSrc } from '@tauri-apps/api/core';
import type { BundleFileInfo } from '../../../data/bundles';

interface Props {
  file: BundleFileInfo;
  /** Number of sample frames to extract from each video. */
  videoFrameCount?: number;
}

/** Inline reviewable preview for a single bundle file.
 *  - image  → 256px tall thumb, click to open a full-window lightbox.
 *  - video  → inline <video controls> + a strip of sample frames
 *             extracted client-side at evenly-spaced times.
 *  - audio  → inline <audio controls>.
 *  Falls back to a labeled placeholder if the WebView can't decode. */
export function BundleFilePreview({ file, videoFrameCount = 5 }: Props) {
  const src = convertFileSrc(file.absolutePath);

  if (file.kind === 'image') {
    return <ImagePreview src={src} alt={file.originalName} />;
  }
  if (file.kind === 'video') {
    return <VideoPreview src={src} name={file.originalName} frameCount={videoFrameCount} />;
  }
  return (
    <audio
      controls
      preload="metadata"
      src={src}
      className="w-full"
      aria-label={file.originalName}
    />
  );
}

function ImagePreview({ src, alt }: { src: string; alt: string }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="block focus:outline-none"
        title="Click to enlarge"
      >
        <img
          src={src}
          alt={alt}
          className="h-48 w-auto max-w-full rounded-lg object-cover border border-black/10 hover:opacity-90 transition"
        />
      </button>
      {open && (
        <div
          className="fixed inset-0 z-50 bg-black/85 flex items-center justify-center p-6 cursor-zoom-out"
          onClick={() => setOpen(false)}
          role="dialog"
          aria-label={`${alt} (enlarged)`}
        >
          <img
            src={src}
            alt={alt}
            className="max-w-full max-h-full object-contain rounded-xl shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          />
          <button
            type="button"
            onClick={() => setOpen(false)}
            className="absolute top-4 right-4 px-3 py-1.5 rounded-full bg-white/90 text-sm font-semibold"
          >
            Close ×
          </button>
        </div>
      )}
    </>
  );
}

interface FrameSlot {
  /** Seconds into the video. Used as a key + tooltip. */
  t: number;
  /** Data URL once captured; null while still loading; 'failed' on error. */
  data: string | null | 'failed';
}

function VideoPreview({
  src,
  name,
  frameCount,
}: {
  src: string;
  name: string;
  frameCount: number;
}) {
  const [frames, setFrames] = useState<FrameSlot[]>([]);
  const [duration, setDuration] = useState<number | null>(null);
  const [decodeError, setDecodeError] = useState(false);
  const [focusedFrame, setFocusedFrame] = useState<string | null>(null);
  const playerRef = useRef<HTMLVideoElement | null>(null);

  useEffect(() => {
    let alive = true;
    setFrames(Array.from({ length: frameCount }, (_, i) => ({ t: i, data: null })));
    setDuration(null);
    setDecodeError(false);
    const video = document.createElement('video');
    video.preload = 'auto';
    video.muted = true;
    video.crossOrigin = 'anonymous';
    video.src = src;

    const cleanup: Array<() => void> = [];
    cleanup.push(() => {
      video.removeAttribute('src');
      video.load();
    });

    function fail() {
      if (!alive) return;
      setDecodeError(true);
      setFrames((prev) => prev.map((f) => ({ ...f, data: 'failed' as const })));
    }

    video.addEventListener('error', fail);
    cleanup.push(() => video.removeEventListener('error', fail));

    video.addEventListener('loadedmetadata', async () => {
      if (!alive) return;
      const dur = video.duration;
      if (!isFinite(dur) || dur <= 0) {
        fail();
        return;
      }
      setDuration(dur);
      // Evenly spaced times skewed slightly inside the playable window so
      // we don't hit the very first/last frame (some codecs return blank
      // canvases there).
      const padding = Math.min(0.3, dur * 0.05);
      const usable = Math.max(dur - 2 * padding, dur * 0.5);
      const slots: number[] =
        frameCount === 1
          ? [padding + usable / 2]
          : Array.from(
              { length: frameCount },
              (_, i) => padding + (usable * i) / (frameCount - 1),
            );
      const canvas = document.createElement('canvas');
      const ctx = canvas.getContext('2d');
      if (!ctx) {
        fail();
        return;
      }
      // Scale captures down so the strip is cheap to render.
      const targetW = 240;
      const w = video.videoWidth || targetW;
      const h = video.videoHeight || 135;
      const scale = Math.min(1, targetW / w);
      canvas.width = Math.max(1, Math.round(w * scale));
      canvas.height = Math.max(1, Math.round(h * scale));

      for (let i = 0; i < slots.length; i++) {
        if (!alive) return;
        const t = slots[i];
        try {
          await seekTo(video, t);
          ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
          const data = canvas.toDataURL('image/jpeg', 0.78);
          if (!alive) return;
          setFrames((prev) => {
            const next = prev.slice();
            next[i] = { t, data };
            return next;
          });
        } catch {
          if (!alive) return;
          setFrames((prev) => {
            const next = prev.slice();
            next[i] = { t, data: 'failed' };
            return next;
          });
        }
      }
    });

    return () => {
      alive = false;
      cleanup.forEach((fn) => fn());
    };
  }, [src, frameCount]);

  function jumpTo(t: number) {
    const p = playerRef.current;
    if (!p) return;
    try {
      p.currentTime = t;
      p.play().catch(() => {/* allow muted-autoplay rejection */});
    } catch { /* ignore */ }
  }

  return (
    <div className="space-y-1.5">
      <video
        ref={playerRef}
        src={src}
        controls
        preload="metadata"
        className="w-full max-h-[360px] rounded-lg bg-black"
        onError={() => setDecodeError(true)}
        aria-label={name}
      />
      {decodeError && (
        <div className="text-xs italic text-amber-700 bg-amber-50 border border-amber-200 rounded px-2 py-1">
          This browser can't decode the file inline (likely a Mac-only container like .mov).
          The file is still saved in the bundle.
        </div>
      )}
      {!decodeError && (
        <div className="flex gap-1 overflow-x-auto py-1">
          {frames.map((f, i) => (
            <FrameThumb
              key={i}
              slot={f}
              onClick={() => {
                if (f.data && f.data !== 'failed') {
                  setFocusedFrame(f.data);
                  jumpTo(f.t);
                }
              }}
              label={duration && f.data !== 'failed' ? formatTime(f.t) : ''}
            />
          ))}
        </div>
      )}
      {focusedFrame && (
        <div
          className="fixed inset-0 z-50 bg-black/85 flex items-center justify-center p-6 cursor-zoom-out"
          onClick={() => setFocusedFrame(null)}
        >
          <img
            src={focusedFrame}
            alt="Sample frame"
            className="max-w-full max-h-full object-contain rounded-xl shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          />
        </div>
      )}
    </div>
  );
}

function FrameThumb({
  slot,
  onClick,
  label,
}: {
  slot: FrameSlot;
  onClick: () => void;
  label: string;
}) {
  if (slot.data === null) {
    return (
      <div className="w-28 h-16 rounded bg-black/10 animate-pulse shrink-0" aria-label="Loading frame" />
    );
  }
  if (slot.data === 'failed') {
    return (
      <div className="w-28 h-16 rounded bg-black/5 border border-dashed border-black/20 shrink-0 flex items-center justify-center text-[10px] text-black/40">
        no preview
      </div>
    );
  }
  return (
    <button
      type="button"
      onClick={onClick}
      className="relative w-28 h-16 rounded overflow-hidden border border-black/10 shrink-0 hover:ring-2 hover:ring-offset-1 transition"
      style={{ outlineColor: 'rgb(var(--persona-accent))' }}
      title={label ? `Jump to ${label}` : ''}
    >
      <img src={slot.data} alt="" className="w-full h-full object-cover" />
      {label && (
        <span className="absolute bottom-0.5 right-0.5 text-[9px] font-mono bg-black/60 text-white px-1 rounded">
          {label}
        </span>
      )}
    </button>
  );
}

/** Race-safe seek that resolves on the next `seeked` event. */
function seekTo(video: HTMLVideoElement, t: number): Promise<void> {
  return new Promise((resolve, reject) => {
    const handleSeeked = () => {
      video.removeEventListener('seeked', handleSeeked);
      video.removeEventListener('error', handleError);
      resolve();
    };
    const handleError = () => {
      video.removeEventListener('seeked', handleSeeked);
      video.removeEventListener('error', handleError);
      reject(new Error('seek error'));
    };
    video.addEventListener('seeked', handleSeeked, { once: true });
    video.addEventListener('error', handleError, { once: true });
    try {
      video.currentTime = Math.min(t, Math.max(0, (video.duration || t) - 0.05));
    } catch (e) {
      video.removeEventListener('seeked', handleSeeked);
      video.removeEventListener('error', handleError);
      reject(e);
    }
  });
}

function formatTime(seconds: number): string {
  if (!isFinite(seconds) || seconds < 0) return '';
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}
