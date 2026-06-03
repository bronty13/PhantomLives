import { useEffect, useState } from 'react';
import { convertFileSrc } from '@tauri-apps/api/core';
import { makePreviewProxy } from '../../data/gifStudio';
import { DECODE_HELP } from './sourceUrl';

export type VideoSourceStatus = 'idle' | 'loading' | 'preparing' | 'ready' | 'error';

export interface VideoSourceState {
  /** A URL the WebView can decode for scrubbing, or null until ready. */
  videoSrc: string | null;
  status: VideoSourceStatus;
  error: string | null;
}

/** Can the WebView decode this URL's video frames? iPhone HEVC on Windows
 * loads metadata with `videoWidth === 0` (or errors); width is the signal.
 * Resolves false on error/timeout. */
function canDecode(url: string): Promise<boolean> {
  return new Promise((resolve) => {
    const v = document.createElement('video');
    v.muted = true;
    v.preload = 'metadata';
    let done = false;
    const finish = (ok: boolean) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      v.removeAttribute('src');
      v.load();
      resolve(ok);
    };
    const timer = setTimeout(() => finish(false), 12_000);
    v.onloadedmetadata = () => finish(v.videoWidth > 0 && v.videoHeight > 0);
    v.onerror = () => finish(false);
    v.src = url;
  });
}

/**
 * Provide a decodable preview URL for the GIF Studio / Frame Grabber.
 *
 * The preview `<video>` is only for scrubbing + positioning the crop overlay —
 * it's never drawn to a canvas (the native ffmpeg engine renders the actual
 * outputs from the original file), so `convertFileSrc` is fine here (no
 * canvas-taint concern). When the WebView can't decode the source (iPhone
 * HEVC on Windows), Molly builds a small H.264 proxy via ffmpeg and previews
 * that instead. Either way, the real GIF/MP4/frame is generated from the
 * ORIGINAL `source.absolutePath` at full quality.
 */
export function useVideoSource(source: { absolutePath: string; name: string } | null): VideoSourceState {
  const [videoSrc, setVideoSrc] = useState<string | null>(null);
  const [status, setStatus] = useState<VideoSourceStatus>('idle');
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!source) {
      setVideoSrc(null);
      setStatus('idle');
      setError(null);
      return;
    }
    let cancelled = false;
    (async () => {
      setStatus('loading');
      setError(null);
      setVideoSrc(null);
      try {
        const direct = convertFileSrc(source.absolutePath);
        if (await canDecode(direct)) {
          if (!cancelled) {
            setVideoSrc(direct);
            setStatus('ready');
          }
          return;
        }
        if (cancelled) return;
        // Undecodable (e.g. iPhone HEVC on Windows) → native H.264 proxy.
        setStatus('preparing');
        const proxyPath = await makePreviewProxy(source.absolutePath);
        if (cancelled) return;
        const proxyUrl = convertFileSrc(proxyPath);
        if (await canDecode(proxyUrl)) {
          if (!cancelled) {
            setVideoSrc(proxyUrl);
            setStatus('ready');
          }
        } else if (!cancelled) {
          setError(DECODE_HELP);
          setStatus('error');
        }
      } catch (e) {
        if (!cancelled) {
          setError(`Couldn't load that video: ${e}`);
          setStatus('error');
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [source?.absolutePath, source?.name]);

  return { videoSrc, status, error };
}
