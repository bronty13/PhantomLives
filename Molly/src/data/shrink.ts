import { invoke, Channel } from '@tauri-apps/api/core';

// Wrapper over the native-ffmpeg `shrink_video` command (src-tauri/src/media):
// re-encode a whole video small enough to fit a byte budget (Slack's 1 GB cap),
// writing the result straight to ~/Downloads/Molly/ and returning only metadata
// (never the gigabyte of bytes over the IPC boundary).

export interface ShrinkResult {
  /** Absolute path of the written `<name> (Squished).mov`. */
  outputPath: string;
  outputBytes: number;
  inputBytes: number;
  /** Target output box (aspect-fit inside this). */
  outWidth: number;
  outHeight: number;
  srcWidth: number;
  srcHeight: number;
  durationSec: number;
}

export interface ShrinkParams {
  absolutePath: string;
  /** Target byte budget; omit/null for the Slack default (~0.92 GB). */
  targetBytes?: number | null;
}

interface ShrinkProgress {
  fraction: number;
}

/** Shrink a video to fit under the (Slack) byte budget. `onProgress` receives a
 * fraction in [0,1] streamed from ffmpeg as the encode runs. */
export async function shrinkVideo(
  params: ShrinkParams,
  onProgress?: (fraction: number) => void,
): Promise<ShrinkResult> {
  const ch = new Channel<ShrinkProgress>();
  if (onProgress) ch.onmessage = (m) => onProgress(m.fraction);
  return invoke<ShrinkResult>('shrink_video', { params, onProgress: ch });
}
