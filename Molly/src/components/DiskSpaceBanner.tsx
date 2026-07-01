import { useCallback, useEffect, useState } from 'react';
import { diskStatus, type DiskStatus } from '../data/bundles';

/**
 * 200%-cute disk-space banner. Sallie chronically runs low on disk, and low
 * disk is the leading suspect for truncated Squish output — so Molly nudges her
 * to tidy up BEFORE making a bundle. Three tiers:
 *   • green  (≥3 GB free) → hidden
 *   • yellow (<3 GB)      → gentle warning
 *   • red    (<1 GB)      → firm warning (publish + squish are ALSO gated in
 *                           Rust, operation-aware, so this is the friendly
 *                           heads-up, not the only guard)
 * The "Recheck" button re-measures so she can clear the message after tidying.
 */

function fmtGb(bytes: number): string {
  return `${(bytes / 1e9).toFixed(1)} GB`;
}

interface Props {
  /** Where the banner is shown, for a slightly tailored nudge. */
  context?: 'bundle' | 'squish';
}

export function DiskSpaceBanner({ context = 'bundle' }: Props) {
  const [status, setStatus] = useState<DiskStatus | null>(null);
  const [checking, setChecking] = useState(false);

  const refresh = useCallback(async () => {
    setChecking(true);
    try {
      setStatus(await diskStatus());
    } catch {
      setStatus(null);
    } finally {
      setChecking(false);
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  // Green (or unmeasurable) → nothing to say.
  if (!status || status.tier === 'green') return null;

  const red = status.tier === 'red';
  const free = fmtGb(status.availableBytes);
  const action = context === 'squish' ? 'squishing a video' : 'making a bundle';

  const emoji = red ? '🚨' : '🌷';
  const text = red
    ? `Eek! Only ${free} of disk space left — that's too low to safely keep ${action}. `
      + `Please tidy up some files first, then tap Recheck. I'll be right here! 💗`
    : `Getting a little cozy in here — only ${free} of disk space left. A quick tidy-up `
      + `before ${action} keeps everything running smoothly! 💕`;

  return (
    <div
      className="pretty-card relative overflow-hidden"
      style={{
        background: red
          ? 'linear-gradient(135deg, rgb(254 226 226) 0%, rgb(252 165 165 / 0.60) 100%)'
          : 'linear-gradient(135deg, rgb(var(--persona-tint)) 0%, rgb(var(--persona-secondary) / 0.55) 100%)',
        border: red
          ? '1px solid rgb(248 113 113 / 0.70)'
          : '1px solid rgb(var(--persona-primary) / 0.45)',
      }}
    >
      <div className="flex items-start gap-3">
        <div className="text-3xl select-none" aria-hidden>
          {emoji}
        </div>
        <div className="flex-1 min-w-0">
          <div
            style={{
              fontFamily: '"Caveat", cursive',
              fontWeight: 700,
              fontSize: '1.6rem',
              lineHeight: 1.2,
              color: red ? 'rgb(153 27 27)' : 'rgb(var(--persona-accent))',
            }}
          >
            {text}
          </div>
          <div className="text-[11px] uppercase tracking-wider opacity-50 mt-2 font-mono">
            {free} free of {fmtGb(status.totalBytes)}
          </div>
        </div>
        <button
          type="button"
          onClick={() => void refresh()}
          disabled={checking}
          className="pretty-button"
          title="Check disk space again"
        >
          {checking ? '…' : '🔄 Recheck'}
        </button>
      </div>
    </div>
  );
}
