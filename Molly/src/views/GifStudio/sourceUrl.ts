import { readFileBytes } from '../../data/bundles';

/** Friendly guidance shown when the WebView can't decode a source video's
 * frames. The usual Windows culprit is iPhone HEVC/H.265 (.mov) — Chromium /
 * WebView2 has no built-in HEVC decoder (Safari/WKWebView on macOS does, which
 * is why such clips work on a Mac but not Windows). */
export const DECODE_HELP =
  "Windows may not be able to decode this video's format — iPhone HEVC/H.265 .mov clips are the usual culprit. " +
  'Try an H.264 .mp4, or install Microsoft’s free "HEVC Video Extensions" from the Store and reopen the video.';

/** Pick a blob MIME type the WebView will actually accept. We give explicit,
 * known-good types for the containers Chromium/WebView2 supports natively, and
 * leave the rest blank so the engine sniffs the bytes instead of rejecting an
 * unsupported container label. (Notably `video/quicktime` for .mov is NOT
 * something Chromium claims to support — labelling a .mov that way makes the
 * <video> element refuse it even when the H.264 inside is perfectly decodable,
 * so we let .mov sniff.) */
function videoMimeFor(name: string): string {
  const ext = name.toLowerCase().split('.').pop() ?? '';
  switch (ext) {
    case 'mp4':
    case 'm4v': return 'video/mp4';
    case 'webm': return 'video/webm';
    // mov / mkv / avi and anything else: let the engine sniff the bytes.
    default: return '';
  }
}

/** Build a **same-origin** `blob:` URL for a local video file.
 *
 * We deliberately avoid `convertFileSrc`, which serves files through Tauri's
 * asset protocol — a *cross-origin* source (`http://asset.localhost` /
 * `tauri://`) that ships no `Access-Control-Allow-Origin` header (see
 * tauri-apps/tauri#12999). Drawing such a `<video>` onto a canvas taints it,
 * and on Windows (WebView2) a tainted canvas blocks every pixel read we need:
 * `getImageData` (GIF export), `new VideoFrame()` / `captureStream()` (MP4
 * export), and `toBlob`/`toDataURL` (Frame Grabber thumbnails). A `blob:` URL
 * is same-origin, so the canvas stays origin-clean and all of those work.
 *
 * Trade-off: the whole file is read into memory. That's fine for typical
 * teaser sources and keeps seeking instant (everything is in the blob), which
 * the trim sliders rely on. The caller MUST `URL.revokeObjectURL` when done.
 */
export async function loadVideoObjectUrl(absolutePath: string, name: string): Promise<string> {
  const bytes = await readFileBytes(absolutePath);
  const blob = new Blob([bytes as BlobPart], { type: videoMimeFor(name) });
  return URL.createObjectURL(blob);
}
