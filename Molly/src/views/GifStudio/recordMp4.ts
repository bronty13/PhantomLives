import { Muxer, ArrayBufferTarget } from 'mp4-muxer';
import { computeOutputSize, drawCaption, type CaptionSettings, type CropBox } from './encodeGif';

// MP4 clip spec (per requirements): max 60s, max 100 MB.
export const MP4_MAX_DURATION_S = 60;
export const MP4_MAX_BYTES = 100 * 1024 * 1024;

const AUDIO_BPS = 128_000;
const MAX_VIDEO_BPS = 8_000_000;
const MIN_VIDEO_BPS = 1_000_000;

export interface ClipSettings {
  startSec: number;
  endSec: number;
  fps: number;
  outputWidth: number;
  crop?: CropBox | null;
  caption?: CaptionSettings | null;
  includeAudio: boolean;
}

/** Pick the best available recorder container, preferring real MP4 (H.264).
 * Returns null when the WebView can't record video at all. */
export function supportedClipType(): { mimeType: string; ext: string } | null {
  if (typeof MediaRecorder === 'undefined') return null;
  const candidates: { mimeType: string; ext: string }[] = [
    { mimeType: 'video/mp4;codecs=avc1.42E01E,mp4a.40.2', ext: 'mp4' },
    { mimeType: 'video/mp4;codecs=avc1.640028,mp4a.40.2', ext: 'mp4' },
    { mimeType: 'video/mp4;codecs=h264,aac', ext: 'mp4' },
    { mimeType: 'video/mp4', ext: 'mp4' },
    { mimeType: 'video/webm;codecs=vp9,opus', ext: 'webm' },
    { mimeType: 'video/webm;codecs=vp8,opus', ext: 'webm' },
    { mimeType: 'video/webm', ext: 'webm' },
  ];
  for (const c of candidates) {
    try { if (MediaRecorder.isTypeSupported(c.mimeType)) return c; } catch { /* keep trying */ }
  }
  return null;
}

/** Video bitrate (bps) that keeps `durationSec` of clip under the 100 MB cap,
 * leaving room for audio. Clamped to a sane [1, 8] Mbps range. Pure —
 * unit-tested. */
export function clipVideoBitrate(durationSec: number, includeAudio: boolean): number {
  const d = Math.max(0.2, durationSec);
  const budgetTotalBps = (MP4_MAX_BYTES * 8 * 0.9) / d;
  const forVideo = budgetTotalBps - (includeAudio ? AUDIO_BPS : 0);
  return Math.max(MIN_VIDEO_BPS, Math.min(MAX_VIDEO_BPS, Math.floor(forVideo)));
}

// HTMLMediaElement.captureStream is unprefixed in Chromium and prefixed in
// some WebKit builds; treat both.
interface CapturableVideo extends HTMLVideoElement {
  captureStream?: () => MediaStream;
  mozCaptureStream?: () => MediaStream;
}

function elementAudioTracks(video: CapturableVideo): MediaStreamTrack[] {
  try {
    const s = video.captureStream ? video.captureStream() : video.mozCaptureStream?.();
    return s ? s.getAudioTracks() : [];
  } catch {
    return [];
  }
}

/** Force a dimension even — H.264 requires even width/height. */
function even(n: number): number {
  const v = Math.max(2, Math.round(n));
  return v % 2 === 1 ? v - 1 : v;
}

/** Record the trimmed/cropped/captioned clip in real time via MediaRecorder.
 * Video comes from a canvas we redraw each frame (so crop + caption match the
 * GIF exactly); audio is the source element's own track. Returns the encoded
 * bytes plus the container actually used. Real-time: takes ~clip length. */
export async function recordClip(
  video: HTMLVideoElement,
  raw: ClipSettings,
  onProgress?: (fraction: number) => void,
): Promise<{ bytes: Uint8Array; mimeType: string; ext: string; audioIncluded: boolean }> {
  const type = supportedClipType();
  if (!type) throw new Error("This system's browser engine can't record video.");

  const srcW = video.videoWidth;
  const srcH = video.videoHeight;
  if (!srcW || !srcH) throw new Error('Video has no decodable dimensions yet.');

  const start = Math.max(0, Math.min(raw.startSec, video.duration || raw.startSec));
  const end = Math.min(raw.endSec, start + MP4_MAX_DURATION_S, video.duration || raw.endSec);
  const durationSec = Math.max(0.2, end - start);

  const { width, height, sx, sy, sw, sh } = computeOutputSize(srcW, srcH, raw.crop, raw.outputWidth);
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('Could not get a 2D canvas context.');

  const canvasStream = canvas.captureStream(raw.fps);
  let tracks: MediaStreamTrack[] = [...canvasStream.getVideoTracks()];
  let audioIncluded = false;
  const wasMuted = video.muted;
  if (raw.includeAudio) {
    video.muted = false; // a muted element captures a silent audio track
    const aTracks = elementAudioTracks(video);
    if (aTracks.length) { tracks = tracks.concat(aTracks); audioIncluded = true; }
  }
  const stream = new MediaStream(tracks);

  // Bitrate budget so duration * total_bps / 8 stays comfortably under 100 MB.
  const videoBps = clipVideoBitrate(durationSec, audioIncluded);

  const rec = new MediaRecorder(stream, {
    mimeType: type.mimeType,
    videoBitsPerSecond: videoBps,
    ...(audioIncluded ? { audioBitsPerSecond: AUDIO_BPS } : {}),
  });
  const chunks: BlobPart[] = [];
  rec.ondataavailable = (e) => { if (e.data && e.data.size) chunks.push(e.data); };

  return await new Promise((resolve, reject) => {
    let rafId = 0;
    let hardStop: ReturnType<typeof setTimeout> | null = null;
    const restore = () => { video.muted = wasMuted; };
    const stop = () => {
      if (rafId) cancelAnimationFrame(rafId);
      if (hardStop) { clearTimeout(hardStop); hardStop = null; }
      if (rec.state !== 'inactive') rec.stop();
    };
    const cleanup = () => {
      if (rafId) cancelAnimationFrame(rafId);
      if (hardStop) { clearTimeout(hardStop); hardStop = null; }
      try { video.pause(); } catch { /* */ }
      restore();
    };

    const draw = () => {
      ctx.drawImage(video, sx, sy, sw, sh, 0, 0, width, height);
      if (raw.caption && raw.caption.text.trim()) drawCaption(ctx, raw.caption, width, height);
      const t = video.currentTime;
      onProgress?.(Math.min(1, (t - start) / durationSec));
      // Stop at the trim end. `>=` against the absolute end-time handles the
      // common case; the wall-clock backstop below guarantees the clip can
      // never exceed durationSec (≤ 60s) even if playback didn't begin
      // exactly at `start` (a missed/slow seek).
      if (t >= end - 0.02 || video.ended) { stop(); return; }
      rafId = requestAnimationFrame(draw);
    };

    rec.onstop = async () => {
      cleanup();
      try {
        const blob = new Blob(chunks, { type: type.mimeType });
        const bytes = new Uint8Array(await blob.arrayBuffer());
        resolve({ bytes, mimeType: type.mimeType, ext: type.ext, audioIncluded });
      } catch (e) { reject(e); }
    };
    rec.onerror = () => { cleanup(); reject(new Error('Recording failed.')); };

    const begin = () => {
      try {
        rec.start();
        // Hard ceiling: never record longer than the clamped duration,
        // regardless of where playback actually started. +300ms covers the
        // MediaRecorder stop tail.
        hardStop = setTimeout(stop, durationSec * 1000 + 300);
        video.play()
          .then(() => { rafId = requestAnimationFrame(draw); })
          .catch((e) => { cleanup(); reject(e); });
      } catch (e) { cleanup(); reject(e as Error); }
    };

    const onSeeked = () => { video.removeEventListener('seeked', onSeeked); begin(); };
    // Setting currentTime to its current value fires no 'seeked' event, so
    // start directly when we're already at (or essentially at) `start`.
    if (Math.abs(video.currentTime - start) < 0.05) {
      begin();
    } else {
      video.addEventListener('seeked', onSeeked);
      try { video.currentTime = start; } catch (e) { video.removeEventListener('seeked', onSeeked); reject(e as Error); }
    }
  });
}

// ── WebCodecs MP4 path ──────────────────────────────────────────────────────
// MediaRecorder's MP4 (the path Chromium/WebView2 takes on Windows) writes its
// index/duration metadata at the *end* of the file in a streaming layout.
// Chromium and VLC tolerate that, but Windows' own players (Movies & TV, Media
// Player) and most upload targets reject it as corrupt — duration reads 0, no
// seek table up front. So when WebCodecs is available we encode H.264 ourselves
// and mux a proper progressive MP4 (moov at the front, real duration) via
// mp4-muxer. WKWebView (the maintainer's Mac) lacks MediaStreamTrackProcessor,
// so it cleanly falls back to the MediaRecorder/.webm path above.

export type ClipEngine = 'webcodecs' | 'mediarecorder';

/** True when this engine can produce a real, seekable MP4 via WebCodecs +
 * MediaStreamTrackProcessor (canvas → H.264, element audio → AAC). */
export function webCodecsClipSupported(): boolean {
  return (
    typeof VideoEncoder !== 'undefined' &&
    typeof AudioEncoder !== 'undefined' &&
    typeof VideoFrame !== 'undefined' &&
    typeof EncodedVideoChunk !== 'undefined' &&
    typeof MediaStreamTrackProcessor !== 'undefined'
  );
}

/** Pick the clip engine + resulting container. WebCodecs (real .mp4) wins when
 * available; otherwise we fall back to MediaRecorder (.mp4 or .webm). */
export function bestClipEngine(): { engine: ClipEngine; ext: 'mp4' | 'webm' } | null {
  if (webCodecsClipSupported()) return { engine: 'webcodecs', ext: 'mp4' };
  const t = supportedClipType();
  return t ? { engine: 'mediarecorder', ext: t.ext as 'mp4' | 'webm' } : null;
}

// H.264 codec strings to try, most-compatible first: Baseline 3.0, Main 4.0,
// High 4.0. Baseline is what stubborn Windows players like best.
export const AVC_CANDIDATES = ['avc1.42E01E', 'avc1.4D0028', 'avc1.640028'];

/** First H.264 config the local VideoEncoder will accept, or null. Pure-ish
 * (async, queries the platform) — the candidate list is unit-tested. */
export async function pickAvcCodec(
  width: number,
  height: number,
  bitrate: number,
  framerate: number,
): Promise<string | null> {
  for (const codec of AVC_CANDIDATES) {
    try {
      const support = await VideoEncoder.isConfigSupported({
        codec,
        width,
        height,
        bitrate,
        framerate,
        avc: { format: 'avc' },
      });
      if (support.supported) return codec;
    } catch {
      /* try the next profile */
    }
  }
  return null;
}

/** Record the trimmed/cropped/captioned clip into a real progressive MP4 using
 * WebCodecs + mp4-muxer. Same draw pipeline as the GIF/MediaRecorder paths, so
 * crop + caption match exactly. Real-time: takes ~clip length. */
export async function recordClipWebCodecs(
  video: HTMLVideoElement,
  raw: ClipSettings,
  onProgress?: (fraction: number) => void,
): Promise<{ bytes: Uint8Array; mimeType: string; ext: string; audioIncluded: boolean }> {
  if (!webCodecsClipSupported()) throw new Error("This system can't encode MP4 with WebCodecs.");

  const srcW = video.videoWidth;
  const srcH = video.videoHeight;
  if (!srcW || !srcH) throw new Error('Video has no decodable dimensions yet.');

  const start = Math.max(0, Math.min(raw.startSec, video.duration || raw.startSec));
  const end = Math.min(raw.endSec, start + MP4_MAX_DURATION_S, video.duration || raw.endSec);
  const durationSec = Math.max(0.2, end - start);

  const sz = computeOutputSize(srcW, srcH, raw.crop, raw.outputWidth);
  const width = even(sz.width);
  const height = even(sz.height);
  const { sx, sy, sw, sh } = sz;

  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('Could not get a 2D canvas context.');

  const videoBps = clipVideoBitrate(durationSec, raw.includeAudio);
  const codec = await pickAvcCodec(width, height, videoBps, raw.fps);
  if (!codec) throw new Error('No H.264 encoder configuration is supported here.');

  // Source audio: unmute so the captured track carries real samples.
  const wasMuted = video.muted;
  let audioTrack: MediaStreamTrack | null = null;
  if (raw.includeAudio) {
    video.muted = false;
    audioTrack = elementAudioTracks(video as CapturableVideo)[0] ?? null;
  }

  let encError: Error | null = null;
  const fail = (e: unknown) => { if (!encError) encError = e instanceof Error ? e : new Error(String(e)); };

  // Encoders + muxer are built lazily once we know the audio params (sample
  // rate / channels come from the first AudioData frame).
  let muxer: Muxer<ArrayBufferTarget> | null = null;
  let videoEncoder: VideoEncoder | null = null;
  let audioEncoder: AudioEncoder | null = null;
  let audioIncluded = false;
  let audioReader: ReadableStreamDefaultReader<AudioData> | null = null;
  let audioPump: Promise<void> | null = null;
  let videoReader: ReadableStreamDefaultReader<VideoFrame> | null = null;

  const restore = () => { video.muted = wasMuted; };
  const encodeAudio = (data: AudioData) => {
    try { audioEncoder?.encode(data); } catch (e) { fail(e); } finally { data.close(); }
  };

  try {
    // Seek to the trim start before playing so the first frame is right.
    await new Promise<void>((resolve, reject) => {
      if (Math.abs(video.currentTime - start) < 0.05) { resolve(); return; }
      const onSeeked = () => { video.removeEventListener('seeked', onSeeked); resolve(); };
      video.addEventListener('seeked', onSeeked);
      try { video.currentTime = start; } catch (e) { video.removeEventListener('seeked', onSeeked); reject(e as Error); }
    });
    await video.play();

    // Learn audio params from the first frame (with a short timeout so a
    // silent / track-less source degrades to a clean video-only MP4).
    let firstAudio: AudioData | null = null;
    if (audioTrack) {
      const proc = new MediaStreamTrackProcessor<AudioData>({ track: audioTrack });
      audioReader = proc.readable.getReader();
      const timeout = new Promise<{ timedOut: true }>((res) => setTimeout(() => res({ timedOut: true }), 1500));
      const first = await Promise.race([audioReader.read(), timeout]);
      if ('timedOut' in first || first.done || !first.value) {
        try { await audioReader.cancel(); } catch { /* */ }
        audioReader = null;
        if ('value' in first && first.value) first.value.close();
      } else {
        firstAudio = first.value;
        const cfg: AudioEncoderConfig = {
          codec: 'mp4a.40.2',
          sampleRate: firstAudio.sampleRate,
          numberOfChannels: firstAudio.numberOfChannels,
          bitrate: AUDIO_BPS,
        };
        let aacOk = false;
        try { aacOk = (await AudioEncoder.isConfigSupported(cfg)).supported ?? false; } catch { aacOk = false; }
        audioIncluded = aacOk;
        if (!aacOk) {
          // No AAC encoder — ship a clean silent MP4 rather than a broken one.
          firstAudio.close();
          firstAudio = null;
          try { await audioReader.cancel(); } catch { /* */ }
          audioReader = null;
        }
      }
    }

    // Build the muxer (fast-start MP4 with moov up front) and encoders.
    muxer = new Muxer({
      target: new ArrayBufferTarget(),
      fastStart: 'in-memory',
      firstTimestampBehavior: 'offset',
      video: { codec: 'avc', width, height, frameRate: raw.fps },
      ...(audioIncluded && firstAudio
        ? { audio: { codec: 'aac' as const, numberOfChannels: firstAudio.numberOfChannels, sampleRate: firstAudio.sampleRate } }
        : {}),
    });

    videoEncoder = new VideoEncoder({
      output: (chunk, meta) => { try { muxer!.addVideoChunk(chunk, meta); } catch (e) { fail(e); } },
      error: fail,
    });
    videoEncoder.configure({ codec, width, height, bitrate: videoBps, framerate: raw.fps, avc: { format: 'avc' } });

    if (audioIncluded && firstAudio) {
      audioEncoder = new AudioEncoder({
        output: (chunk, meta) => { try { muxer!.addAudioChunk(chunk, meta); } catch (e) { fail(e); } },
        error: fail,
      });
      audioEncoder.configure({
        codec: 'mp4a.40.2',
        sampleRate: firstAudio.sampleRate,
        numberOfChannels: firstAudio.numberOfChannels,
        bitrate: AUDIO_BPS,
      });
      encodeAudio(firstAudio);
      firstAudio = null;
      // Pump the rest of the audio track concurrently until it ends.
      const reader = audioReader!;
      audioPump = (async () => {
        while (!encError) {
          const { value, done } = await reader.read();
          if (done || !value) break;
          encodeAudio(value);
        }
      })();
    }

    // Capture the canvas as a video track and pump its frames into the
    // encoder. We deliberately do NOT build frames with `new VideoFrame(canvas)`
    // — that constructor enforces a strict origin-clean check and throws on
    // Tauri asset-protocol video sources ("VideoFrames can't be created from
    // tainted sources"), even though the canvas is fine for captureStream /
    // getImageData. Reading the canvas's own captureStream is the exact route
    // MediaRecorder used (which worked), and isn't subject to that check.
    // Prime the canvas with the start frame so captureStream's first sample
    // isn't blank.
    ctx.drawImage(video, sx, sy, sw, sh, 0, 0, width, height);
    if (raw.caption && raw.caption.text.trim()) drawCaption(ctx, raw.caption, width, height);
    const canvasStream = canvas.captureStream(raw.fps);
    const videoTrack = canvasStream.getVideoTracks()[0];
    const videoProc = new MediaStreamTrackProcessor<VideoFrame>({ track: videoTrack });
    videoReader = videoProc.readable.getReader();
    let frameIdx = 0;
    const reader = videoReader;
    const videoPump = (async () => {
      while (!encError) {
        const { value, done } = await reader.read();
        if (done || !value) break;
        try {
          // Keyframe at the start and every ~2s for seekability. 'offset' in
          // the muxer rebases the captureStream timestamps to start at zero.
          videoEncoder!.encode(value, { keyFrame: frameIdx % (raw.fps * 2) === 0 });
          frameIdx++;
        } catch (e) { fail(e); }
        value.close();
      }
    })();

    // Draw the trimmed/cropped/captioned frames in real time; captureStream
    // samples the canvas at `fps`. Stop at the trim end, with a wall-clock
    // backstop that guarantees we never exceed durationSec (≤60s).
    await new Promise<void>((resolve) => {
      let rafId = 0;
      let hardStop: ReturnType<typeof setTimeout> | null = null;
      let stopped = false;
      const finish = () => {
        if (stopped) return;
        stopped = true;
        if (rafId) cancelAnimationFrame(rafId);
        if (hardStop) { clearTimeout(hardStop); hardStop = null; }
        resolve();
      };

      const draw = () => {
        if (stopped) return;
        if (encError) { finish(); return; }
        ctx.drawImage(video, sx, sy, sw, sh, 0, 0, width, height);
        if (raw.caption && raw.caption.text.trim()) drawCaption(ctx, raw.caption, width, height);
        const t = video.currentTime;
        onProgress?.(Math.min(1, (t - start) / durationSec));
        if (t >= end - 0.02 || video.ended) { finish(); return; }
        rafId = requestAnimationFrame(draw);
      };

      hardStop = setTimeout(finish, durationSec * 1000 + 300);
      rafId = requestAnimationFrame(draw);
    });

    try { video.pause(); } catch { /* */ }

    // Stop both capture tracks so the pumps see `done` and drain, then flush.
    try { videoTrack.stop(); } catch { /* */ }
    if (audioTrack) { try { audioTrack.stop(); } catch { /* */ } }
    try { await videoPump; } catch (e) { fail(e); }
    if (audioPump) { try { await audioPump; } catch (e) { fail(e); } }
    if (videoEncoder.state !== 'closed') await videoEncoder.flush();
    if (audioEncoder && audioEncoder.state !== 'closed') await audioEncoder.flush();
    if (encError) throw encError;

    muxer.finalize();
    const bytes = new Uint8Array(muxer.target.buffer);
    return { bytes, mimeType: 'video/mp4', ext: 'mp4', audioIncluded };
  } finally {
    restore();
    try { videoEncoder?.state !== 'closed' && videoEncoder?.close(); } catch { /* */ }
    try { audioEncoder?.state !== 'closed' && audioEncoder?.close(); } catch { /* */ }
    if (videoReader) { try { await videoReader.cancel(); } catch { /* */ } }
    if (audioReader) { try { await audioReader.cancel(); } catch { /* */ } }
  }
}
