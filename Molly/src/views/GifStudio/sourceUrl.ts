import { readFileBytes } from '../../data/bundles';

/** Guess a video MIME type from a filename so the <video> element and any
 * decoder pick the right demuxer. */
function videoMimeFor(name: string): string {
  const ext = name.toLowerCase().split('.').pop() ?? '';
  switch (ext) {
    case 'mp4':
    case 'm4v': return 'video/mp4';
    case 'mov': return 'video/quicktime';
    case 'webm': return 'video/webm';
    case 'mkv': return 'video/x-matroska';
    case 'avi': return 'video/x-msvideo';
    default: return 'video/mp4';
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
