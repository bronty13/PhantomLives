import { probeVideo } from '../data/gifStudio';
import type { BundleFileInfo } from '../data/bundles';

// Sum the durations of a bundle's videos so we can suggest a default price.
// Probing is metadata-only (ffprobe), so it's cheap, but we still memoize by
// absolute path: the content form AND the publish wizard both probe the same
// files, and a bundle's files don't change paths once saved. A probe that
// fails or returns a non-positive duration is NOT cached (so a transient
// failure — e.g. the Windows ffmpeg 193 case — can recover on a later visit)
// and is counted so the UI can warn that the suggestion may be low.

const durationCache = new Map<string, number>();

export interface DurationTotal {
  totalSeconds: number;
  videoCount: number;
  /** Videos whose duration couldn't be read (probe error or 0s). */
  failedCount: number;
}

/** Probe every `kind === 'video'` file and sum the readable durations. Never throws. */
export async function sumVideoDurations(files: BundleFileInfo[]): Promise<DurationTotal> {
  const videos = files.filter((f) => f.kind === 'video');
  let totalSeconds = 0;
  let failedCount = 0;
  for (const f of videos) {
    const cached = durationCache.get(f.absolutePath);
    if (cached != null) {
      totalSeconds += cached;
      continue;
    }
    try {
      const r = await probeVideo(f.absolutePath);
      const d = Number.isFinite(r.durationSec) && r.durationSec > 0 ? r.durationSec : 0;
      if (d > 0) {
        durationCache.set(f.absolutePath, d);
        totalSeconds += d;
      } else {
        failedCount += 1;
      }
    } catch {
      failedCount += 1;
    }
  }
  return { totalSeconds, videoCount: videos.length, failedCount };
}
