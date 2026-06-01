// Hand-rolled, dependency-free SVG line chart for the follower drill-down.
// Persona-/platform-themed. Draws the logged history line (gaps bridged by
// a straight connector + dots on real points), an optional dashed green
// goal line, and an optional dashed forecast tail to the goal. Hovering a
// point shows an HTML tooltip with the exact value + Δ from the prior point.

import { useState } from 'react';
import { daysBetween, fmtFollowers, prettyDate } from '../lib/followerForecast';

export interface ChartPoint {
  date: string;
  count: number | null; // null = a gap (unlogged day)
}

export interface ForecastOverlay {
  slopePerDay: number;
  fromDate: string;
  fromCount: number;
  etaDate: string;
  goal: number;
}

interface Props {
  points: ChartPoint[]; // dense daily window, oldest-first, gaps = null
  goal?: number; // 0 / undefined = no goal line
  forecast?: ForecastOverlay | null;
  color: string; // platform brand color for the data line
  height?: number;
  width?: number;
}

const PAD = { left: 52, right: 18, top: 16, bottom: 28 };

export function FollowerChart({ points, goal = 0, forecast, color, height = 260, width = 680 }: Props) {
  const [hover, setHover] = useState<number | null>(null);

  const logged = points
    .map((p, i) => ({ ...p, i }))
    .filter((p): p is { date: string; count: number; i: number } => p.count != null);

  if (logged.length === 0) {
    return (
      <EmptyChart height={height} message="No history yet — pop in today’s number to start your line! 📈" />
    );
  }

  const innerW = width - PAD.left - PAD.right;
  const innerH = height - PAD.top - PAD.bottom;
  const start = points[0]?.date ?? logged[0].date;

  // X domain: window start → max(last point, forecast ETA).
  const lastDate = points[points.length - 1]?.date ?? logged[logged.length - 1].date;
  const showForecast = !!forecast && forecast.slopePerDay > 0 && !!forecast.etaDate;
  const xMaxIdx = Math.max(
    daysBetween(start, lastDate),
    showForecast ? daysBetween(start, forecast!.etaDate) : 0,
    1,
  );

  // Y domain: include logged counts, the goal, and the forecast target.
  const ys = logged.map((p) => p.count);
  let yDataMin = Math.min(...ys);
  let yDataMax = Math.max(...ys);
  if (goal > 0) yDataMax = Math.max(yDataMax, goal);
  const span = Math.max(1, yDataMax - yDataMin);
  let yMin = Math.max(0, Math.floor(yDataMin - span * 0.12));
  let yMax = Math.ceil(yDataMax + span * 0.12);
  if (yMax === yMin) yMax = yMin + 1;
  const ticks = niceTicks(yMin, yMax, 4);
  yMin = Math.min(yMin, ticks[0]);
  yMax = Math.max(yMax, ticks[ticks.length - 1]);

  const px = (dateOrIdx: string | number) => {
    const idx = typeof dateOrIdx === 'number' ? dateOrIdx : daysBetween(start, dateOrIdx);
    return PAD.left + (idx / xMaxIdx) * innerW;
  };
  const py = (v: number) => PAD.top + innerH - ((v - yMin) / (yMax - yMin)) * innerH;

  const linePts = logged.map((p) => `${px(p.date)},${py(p.count)}`).join(' ');

  // X labels: start, mid, end, and the ETA (if forecasting).
  const xLabels: Array<{ x: number; label: string }> = [
    { x: px(start), label: shortDate(start) },
    { x: px(lastDate), label: shortDate(lastDate) },
  ];
  if (showForecast) xLabels.push({ x: px(forecast!.etaDate), label: shortDate(forecast!.etaDate) });

  const hoverPt = hover != null ? logged[hover] : null;
  const hoverPrev = hover != null && hover > 0 ? logged[hover - 1] : null;
  const hoverDelta = hoverPt && hoverPrev ? hoverPt.count - hoverPrev.count : null;

  function onMove(e: React.MouseEvent<SVGSVGElement>) {
    const rect = e.currentTarget.getBoundingClientRect();
    const mx = ((e.clientX - rect.left) / rect.width) * width;
    let best = 0;
    let bestD = Infinity;
    logged.forEach((p, i) => {
      const d = Math.abs(px(p.date) - mx);
      if (d < bestD) { bestD = d; best = i; }
    });
    setHover(best);
  }

  const ariaSummary = `Follower history: latest ${fmtFollowers(logged[logged.length - 1].count)} across ${logged.length} logged days`;

  return (
    <div className="relative" style={{ width, maxWidth: '100%' }}>
      <svg
        width={width}
        height={height}
        role="img"
        aria-label={ariaSummary}
        onMouseMove={onMove}
        onMouseLeave={() => setHover(null)}
        style={{ maxWidth: '100%' }}
      >
        {/* Y gridlines + labels */}
        {ticks.map((t) => (
          <g key={t}>
            <line x1={PAD.left} y1={py(t)} x2={width - PAD.right} y2={py(t)} stroke="rgba(0,0,0,0.07)" strokeWidth={1} />
            <text x={PAD.left - 8} y={py(t) + 3} textAnchor="end" fontSize={10} fill="rgb(var(--persona-text) / 0.55)">
              {fmtFollowers(t)}
            </text>
          </g>
        ))}

        {/* Goal line */}
        {goal > 0 && goal >= yMin && goal <= yMax && (
          <g>
            <line x1={PAD.left} y1={py(goal)} x2={width - PAD.right} y2={py(goal)} stroke="#2ecc71" strokeWidth={1.5} strokeDasharray="5 4" />
            <text x={width - PAD.right} y={py(goal) - 5} textAnchor="end" fontSize={10} fill="#1a7a45" fontWeight={600}>
              🎯 {fmtFollowers(goal)}
            </text>
          </g>
        )}

        {/* Forecast tail */}
        {showForecast && (
          <g>
            <line
              x1={px(forecast!.fromDate)}
              y1={py(forecast!.fromCount)}
              x2={px(forecast!.etaDate)}
              y2={py(forecast!.goal)}
              stroke="rgb(var(--persona-accent))"
              strokeWidth={2}
              strokeDasharray="5 4"
              opacity={0.7}
            />
            <text x={px(forecast!.etaDate)} y={py(forecast!.goal) - 8} textAnchor="middle" fontSize={13}>🚀</text>
          </g>
        )}

        {/* Data line + dots */}
        <polyline points={linePts} fill="none" stroke={color} strokeWidth={2.5} strokeLinejoin="round" strokeLinecap="round" />
        {logged.map((p, i) => (
          <circle
            key={p.date}
            cx={px(p.date)}
            cy={py(p.count)}
            r={hover === i ? 5 : 3}
            fill={hover === i ? color : 'white'}
            stroke={color}
            strokeWidth={2}
          />
        ))}

        {/* X labels */}
        {xLabels.map((l, i) => (
          <text key={i} x={l.x} y={height - 8} textAnchor="middle" fontSize={10} fill="rgb(var(--persona-text) / 0.55)">
            {l.label}
          </text>
        ))}
      </svg>

      {hoverPt && (
        <div
          className="absolute pointer-events-none rounded-lg px-2 py-1 text-xs shadow-lg"
          style={{
            left: Math.min(width - 120, Math.max(0, px(hoverPt.date) - 50)),
            top: Math.max(0, py(hoverPt.count) - 46),
            background: 'rgb(var(--persona-text))',
            color: 'white',
            whiteSpace: 'nowrap',
          }}
        >
          <div className="font-semibold">{hoverPt.count.toLocaleString('en-US')}</div>
          <div className="opacity-80">
            {prettyDate(hoverPt.date)}
            {hoverDelta != null && (
              <span style={{ color: hoverDelta >= 0 ? '#7Cf0a8' : '#ffb3c1' }}>
                {' '}({hoverDelta >= 0 ? '+' : ''}{hoverDelta.toLocaleString('en-US')})
              </span>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

function EmptyChart({ height, message }: { height: number; message: string }) {
  return (
    <div
      className="flex items-center justify-center text-center text-sm opacity-60 italic rounded-xl"
      style={{ height, background: 'rgba(0,0,0,0.03)' }}
    >
      {message}
    </div>
  );
}

function shortDate(iso: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  return m ? `${m[2]}/${m[3]}` : iso;
}

/** A handful of "nice" round tick values spanning [min, max]. */
function niceTicks(min: number, max: number, count: number): number[] {
  const range = niceNum(max - min, false);
  const step = niceNum(range / Math.max(1, count - 1), true);
  const niceMin = Math.floor(min / step) * step;
  const niceMax = Math.ceil(max / step) * step;
  const out: number[] = [];
  for (let v = niceMin; v <= niceMax + step * 0.5; v += step) out.push(Math.round(v));
  return out;
}

function niceNum(range: number, round: boolean): number {
  if (range <= 0) return 1;
  const exp = Math.floor(Math.log10(range));
  const frac = range / Math.pow(10, exp);
  let nice: number;
  if (round) {
    nice = frac < 1.5 ? 1 : frac < 3 ? 2 : frac < 7 ? 5 : 10;
  } else {
    nice = frac <= 1 ? 1 : frac <= 2 ? 2 : frac <= 5 ? 5 : 10;
  }
  return nice * Math.pow(10, exp);
}
