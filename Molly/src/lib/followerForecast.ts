// Pure forecast + trend math for daily follower tracking.
//
// Kept in TS (not Rust) so it's fast to iterate and unit-testable like
// rotationRule.ts / cadence.ts. The Rust layer only stores raw snapshots;
// all the "where is she headed" math lives here.
//
// Input is the SPARSE logged series (only days Sallie actually logged,
// oldest-first) from `list_logged_follower_history`. We convert each date
// to an integer day-index (timezone-safe, via Date.UTC) so skipped days
// weight correctly: a 7-day gap is Δx=7, keeping growth-per-day honest.

export type LoggedPoint = { date: string; count: number };

export type ForecastStatus =
  | 'insufficient' // < 2 logged points
  | 'no-goal' // goal not set — trend only
  | 'reached' // already at/past goal
  | 'flat-or-declining' // slope <= 0 and goal not reached
  | 'on-track' // climbing toward a goal, ETA known
  | 'far-off'; // climbing but ETA > 5y away

export interface ForecastResult {
  status: ForecastStatus;
  /** Followers/day from least-squares regression. null when insufficient. */
  slopePerDay: number | null;
  /** Friendly average over the window (latest − firstInWindow) / spanDays. */
  avgPerDay: number | null;
  /** Total change across the regression window. */
  windowDelta: number | null;
  /** Latest logged value (the projection anchor). */
  latestCount: number | null;
  /** Whole days from `today` to crossing the goal (ceil). null when N/A. */
  daysToGoal: number | null;
  /** YYYY-MM-DD ETA to the goal. null when N/A. */
  etaDate: string | null;
  /** When already past goal: how far past. */
  surplus: number | null;
  /** Cute, always-kind one-liner for the forecast card. */
  message: string;
}

export const FORECAST_WINDOW = 14; // last N logged points feed the regression
const FLAT_EPS = 0.5; // |slope| below this reads as "steady" in copy
const FAR_OFF_DAYS = 1825; // ~5 years — don't show a 2034 date

/** Whole days between two YYYY-MM-DD strings (b − a), timezone-safe. */
export function daysBetween(a: string, b: string): number {
  const pa = parseIsoDate(a);
  const pb = parseIsoDate(b);
  if (pa == null || pb == null) return 0;
  return Math.round((pb - pa) / 86_400_000);
}

function parseIsoDate(iso: string): number | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!m) return null;
  return Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
}

/** Add `n` whole days to a YYYY-MM-DD string, returning YYYY-MM-DD. */
export function addDays(iso: string, n: number): string {
  const base = parseIsoDate(iso);
  if (base == null) return iso;
  const d = new Date(base + n * 86_400_000);
  const y = d.getUTCFullYear();
  const mo = String(d.getUTCMonth() + 1).padStart(2, '0');
  const da = String(d.getUTCDate()).padStart(2, '0');
  return `${y}-${mo}-${da}`;
}

/**
 * Forecast where the follower count is heading.
 *
 * @param series   sparse logged points, oldest-first
 * @param goal     target follower count; 0 / negative = no goal
 * @param today    YYYY-MM-DD anchor for ETA arithmetic
 */
export function forecast(series: LoggedPoint[], goal: number, today: string): ForecastResult {
  const base: ForecastResult = {
    status: 'insufficient',
    slopePerDay: null,
    avgPerDay: null,
    windowDelta: null,
    latestCount: series.length ? series[series.length - 1].count : null,
    daysToGoal: null,
    etaDate: null,
    surplus: null,
    message: "Log a couple more days and I'll start predicting your glow-up! ✨",
  };

  if (series.length < 2) return base;

  // Regression over the last FORECAST_WINDOW logged points.
  const window = series.slice(-FORECAST_WINDOW);
  const x0 = window[0].date;
  const xs = window.map((p) => daysBetween(x0, p.date));
  const ys = window.map((p) => p.count);
  const n = window.length;

  const Sx = xs.reduce((a, b) => a + b, 0);
  const Sy = ys.reduce((a, b) => a + b, 0);
  const Sxx = xs.reduce((a, b) => a + b * b, 0);
  const Sxy = xs.reduce((a, x, i) => a + x * ys[i], 0);
  const denom = n * Sxx - Sx * Sx;

  if (denom === 0) return base; // all points same day — shouldn't happen with distinct dates

  const slope = (n * Sxy - Sx * Sy) / denom;
  const latest = ys[ys.length - 1];
  const spanDays = xs[xs.length - 1] - xs[0];
  const windowDelta = ys[ys.length - 1] - ys[0];
  const avgPerDay = spanDays > 0 ? windowDelta / spanDays : 0;

  const common = {
    slopePerDay: slope,
    avgPerDay,
    windowDelta,
    latestCount: latest,
  };

  // Already at/past the goal.
  if (goal > 0 && latest >= goal) {
    const surplus = latest - goal;
    return {
      ...base,
      ...common,
      status: 'reached',
      surplus,
      message: surplus > 0
        ? `You smashed it — ${fmtFollowers(surplus)} past your goal! 👑`
        : 'Goal reached — you absolute star! 🌟',
    };
  }

  // No goal: show the trend, no ETA.
  if (goal <= 0) {
    return { ...base, ...common, status: 'no-goal', message: trendCopy(slope, windowDelta) };
  }

  // Flat or declining (and goal still ahead): never alarming, never an ETA.
  if (slope <= 0) {
    return {
      ...base,
      ...common,
      status: 'flat-or-declining',
      message: Math.abs(slope) < FLAT_EPS
        ? 'Holding steady 💪 — consistency is its own superpower.'
        : 'A lil dip — happens to everyone, you’ve got this 💖',
    };
  }

  // Climbing toward a goal.
  const daysToGoal = Math.ceil((goal - latest) / slope);
  if (daysToGoal > FAR_OFF_DAYS) {
    return {
      ...base,
      ...common,
      status: 'far-off',
      message: 'Steady climb — keep stacking those days and the goal gets closer! 🌱',
    };
  }
  const etaDate = addDays(today, daysToGoal);
  return {
    ...base,
    ...common,
    status: 'on-track',
    daysToGoal,
    etaDate,
    message: `At +${fmtFollowers(Math.round(slope))}/day you’ll hit ${fmtFollowers(goal)} around ${prettyDate(etaDate)} ✨`,
  };
}

function trendCopy(slope: number, windowDelta: number): string {
  if (Math.abs(slope) < FLAT_EPS) return 'Holding steady 💪';
  if (slope > 0) return `Trending up — +${fmtFollowers(Math.round(windowDelta))} lately! 📈💖`;
  return 'A gentle dip lately — every climb has them 🌸';
}

/** "Jun 3, 2026" style. */
export function prettyDate(iso: string): string {
  const t = parseIsoDate(iso);
  if (t == null) return iso;
  const d = new Date(t);
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return `${months[d.getUTCMonth()]} ${d.getUTCDate()}, ${d.getUTCFullYear()}`;
}

/**
 * Compact follower formatting: 9,842 · 12.3k · 1.2M. Full exact value
 * belongs in a `title`/tooltip. Negative inputs keep their sign.
 */
export function fmtFollowers(n: number): string {
  const neg = n < 0;
  const a = Math.abs(n);
  let s: string;
  if (a < 10_000) s = a.toLocaleString('en-US');
  else if (a < 1_000_000) s = trimZero((a / 1000).toFixed(1)) + 'k';
  else s = trimZero((a / 1_000_000).toFixed(2)) + 'M';
  return neg ? `-${s}` : s;
}

function trimZero(s: string): string {
  // 12.0 → 12 ; 1.20 → 1.2 ; 1.00 → 1
  return s.replace(/\.0+$/, '').replace(/(\.\d*?)0+$/, '$1');
}
