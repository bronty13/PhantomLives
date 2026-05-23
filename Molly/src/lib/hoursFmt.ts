// Phase 15 PR2 — Hours formatting helpers, extracted from
// views/Reddit/HoursSection.tsx so they can be unit-tested without
// pulling React into the harness.

/** Format milliseconds as "HH:MM:SS" (zero-padded). Negative inputs
 *  are treated as zero. Hours can roll past 99 — caller's problem. */
export function fmtClock(ms: number): string {
  const safe = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(safe / 3600);
  const m = Math.floor((safe % 3600) / 60);
  const s = safe % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}

/** Format milliseconds as "Xh Ym" or "Ym" (if under an hour).
 *  Floors to whole minutes — partial minutes don't count yet,
 *  because seeing "59m" turn to "1h 0m" after a single second feels
 *  more honest than seeing "1h" pop instantly at the rollover. */
export function fmtHM(ms: number): string {
  const m = Math.floor(Math.max(0, ms) / 60_000);
  const h = Math.floor(m / 60);
  return h ? `${h}h ${m % 60}m` : `${m}m`;
}
