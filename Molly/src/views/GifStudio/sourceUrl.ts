/** Shown only as a last resort — when a video won't decode AND the native
 * proxy/transcode also failed. The normal path for an undecodable source
 * (e.g. iPhone HEVC) is for the native ffmpeg engine to transcode it in-app;
 * see transcode in src-tauri/src/media. We deliberately do NOT tell Sallie to
 * install anything or convert files elsewhere — that's Molly's job. */
export const DECODE_HELP =
  "I couldn't read this video on this device. If it keeps happening, send the clip to Robert and we'll sort it out together. 🩷";
