interface Props {
  dayOfMonth: number;
  isInMonth: boolean;
  isComplete: boolean;   // has message AND >=1 file
  hasPartial: boolean;   // has message OR file, but not both
  onClick: () => void;
}

/** One day in the FanSite calendar grid. Color-coded:
 *   - grey when out of month
 *   - empty when in month with no data
 *   - amber when partial (message-only or file-only)
 *   - green/persona-accent when complete (message + 1+ files) */
export function FanDayCell({ dayOfMonth, isInMonth, isComplete, hasPartial, onClick }: Props) {
  if (!isInMonth) {
    return (
      <div
        className="aspect-square rounded-lg text-xs text-center pt-1 opacity-30"
        aria-hidden
      />
    );
  }

  let bg: string;
  let color: string;
  if (isComplete) {
    bg = 'rgb(var(--persona-accent))';
    color = 'white';
  } else if (hasPartial) {
    bg = '#FEF3C7'; // amber-100
    color = '#92400E'; // amber-800
  } else {
    bg = 'rgba(255,255,255,0.55)';
    color = 'rgb(var(--persona-text))';
  }

  const dd = String(dayOfMonth).padStart(2, '0');
  return (
    <button
      type="button"
      id={`bundle-fan-day-${dd}`}
      onClick={onClick}
      className="aspect-square rounded-lg text-sm font-mono flex flex-col items-center justify-center transition hover:scale-105"
      style={{
        background: bg,
        color,
        border: '1px solid rgb(var(--persona-primary) / 0.35)',
      }}
      title={`Day ${dayOfMonth}${isComplete ? ' — complete' : hasPartial ? ' — partial' : ' — empty'}`}
    >
      <span className="text-base">{dayOfMonth}</span>
      <span className="text-[10px] leading-none">
        {isComplete ? '✓' : hasPartial ? '…' : ''}
      </span>
    </button>
  );
}
