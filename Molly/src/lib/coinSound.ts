// v1.21.0 — synthesised "ching" for piggy-bank coin drops.
//
// Web Audio API tone, no external asset. Two short overlapping bell-like
// partials with quick exponential decay. Total ~250ms. Designed to feel
// rewarding without being annoying when Sallie taps +1 repeatedly.
//
// Two flavours:
//   - playCoin()  — soft single ching on every +1
//   - playGoalHit() — slightly fuller chord when a daily goal flips green

let ctxRef: AudioContext | null = null;
let muted = false;

function ctx(): AudioContext | null {
  if (muted) return null;
  if (typeof window === 'undefined') return null;
  if (!ctxRef) {
    const Ctor = (window as any).AudioContext || (window as any).webkitAudioContext;
    if (!Ctor) return null;
    try { ctxRef = new Ctor(); }
    catch { return null; }
  }
  // Safari/WKWebView starts contexts suspended until a user gesture.
  // The +1 button click is the gesture; resume is safe & idempotent.
  if (ctxRef && ctxRef.state === 'suspended') {
    ctxRef.resume().catch(() => {});
  }
  return ctxRef;
}

function tone(c: AudioContext, freq: number, when: number, dur: number, gain = 0.18) {
  const osc = c.createOscillator();
  const g = c.createGain();
  osc.type = 'triangle';
  osc.frequency.setValueAtTime(freq, when);
  g.gain.setValueAtTime(0, when);
  g.gain.linearRampToValueAtTime(gain, when + 0.005);
  g.gain.exponentialRampToValueAtTime(0.0001, when + dur);
  osc.connect(g).connect(c.destination);
  osc.start(when);
  osc.stop(when + dur + 0.02);
}

export function playCoin(): void {
  const c = ctx();
  if (!c) return;
  const t = c.currentTime;
  tone(c, 1320, t,         0.18);            // E6
  tone(c, 1760, t + 0.015, 0.16, 0.10);      // A6 — sparkle
}

export function playGoalHit(): void {
  const c = ctx();
  if (!c) return;
  const t = c.currentTime;
  // Major arpeggio C6-E6-G6, ascending, slightly louder.
  tone(c, 1046, t,        0.22, 0.22);
  tone(c, 1318, t + 0.08, 0.22, 0.20);
  tone(c, 1568, t + 0.16, 0.30, 0.22);
}

export function setCoinSoundMuted(v: boolean): void {
  muted = v;
}
export function isCoinSoundMuted(): boolean {
  return muted;
}
