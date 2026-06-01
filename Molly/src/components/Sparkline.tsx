// Tiny dependency-free sparkline for the Followers overview rows.
// Draws a single polyline through the logged points (gaps are bridged by
// the straight connector — a skipped day just becomes a longer segment).
// Empty → a faint dashed baseline. Single point → one dot.

import { daysBetween } from '../lib/followerForecast';

interface Props {
  points: Array<{ date: string; count: number | null }>;
  color: string;
  width?: number;
  height?: number;
}

export function Sparkline({ points, color, width = 96, height = 28 }: Props) {
  const logged = points.filter((p): p is { date: string; count: number } => p.count != null);
  const pad = 3;

  if (logged.length === 0) {
    return (
      <svg width={width} height={height} role="img" aria-label="No history yet">
        <line
          x1={pad}
          y1={height / 2}
          x2={width - pad}
          y2={height / 2}
          stroke="rgba(0,0,0,0.18)"
          strokeWidth={1}
          strokeDasharray="3 3"
        />
      </svg>
    );
  }

  const x0 = logged[0].date;
  const xs = logged.map((p) => daysBetween(x0, p.date));
  const ys = logged.map((p) => p.count);
  const xSpan = Math.max(1, xs[xs.length - 1]);
  const yMin = Math.min(...ys);
  const yMax = Math.max(...ys);
  const ySpan = Math.max(1, yMax - yMin);

  const px = (x: number) => pad + (x / xSpan) * (width - pad * 2);
  const py = (y: number) => height - pad - ((y - yMin) / ySpan) * (height - pad * 2);

  if (logged.length === 1) {
    return (
      <svg width={width} height={height} role="img" aria-label="One day logged">
        <circle cx={width / 2} cy={height / 2} r={3} fill={color} />
      </svg>
    );
  }

  const d = logged.map((_, i) => `${px(xs[i])},${py(ys[i])}`).join(' ');
  const last = logged.length - 1;
  return (
    <svg width={width} height={height} role="img" aria-label={`Trend across ${logged.length} logged days`}>
      <polyline points={d} fill="none" stroke={color} strokeWidth={1.5} strokeLinejoin="round" strokeLinecap="round" />
      <circle cx={px(xs[last])} cy={py(ys[last])} r={2.5} fill={color} />
    </svg>
  );
}
