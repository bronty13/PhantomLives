import { useState } from 'react';
import { mediaDiagnostics } from '../data/gifStudio';

/**
 * One click → gathers the video-engine diagnostic report (ffmpeg/ffprobe
 * presence, size, PE header, hash, sync/security tamper flags, run result,
 * registered AV) and copies it to the clipboard, so a non-technical user can
 * paste it to Robert when the GIF tools fail. Always available (not just on
 * error) so support can say "click Copy video diagnostics and paste it."
 */
export function MediaDiagnosticsButton({ className }: { className?: string }) {
  const [state, setState] = useState<'idle' | 'working' | 'copied' | 'failed'>('idle');

  const run = async () => {
    setState('working');
    try {
      const report = await mediaDiagnostics();
      await navigator.clipboard.writeText(report);
      setState('copied');
    } catch {
      setState('failed');
    }
    setTimeout(() => setState('idle'), 2500);
  };

  const label =
    state === 'working'
      ? 'Gathering…'
      : state === 'copied'
        ? '✓ Diagnostics copied — paste to Robert'
        : state === 'failed'
          ? 'Copy failed — try again'
          : '🛟 Copy video diagnostics';

  return (
    <button
      type="button"
      onClick={run}
      disabled={state === 'working'}
      className={`text-xs underline opacity-60 hover:opacity-100 disabled:opacity-40 ${className ?? ''}`}
      title="Copies a video-engine report you can paste to Robert if the GIF tools aren't working"
    >
      {label}
    </button>
  );
}
