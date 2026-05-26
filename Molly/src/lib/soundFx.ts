// Synthesized sound effects for satisfying audio feedback on user
// actions. No bundled audio assets — every sound is generated live via
// the Web Audio API. This keeps Molly offline-first and licensing-clean.
//
// All sounds are no-ops when:
//   - window / AudioContext are unavailable (SSR, vitest/jsdom)
//   - the user hasn't yet interacted with the page (browser autoplay
//     policy keeps the context suspended; resume() is best-effort)
//   - any audio node construction throws (very old WebView builds)
//
// Failure mode is silent (literally) — a sound effect that errors must
// not break the user action it was decorating.

let cachedCtx: AudioContext | null = null;

function getCtx(): AudioContext | null {
  if (typeof window === 'undefined') return null;
  if (cachedCtx) {
    if (cachedCtx.state === 'suspended') {
      void cachedCtx.resume().catch(() => {});
    }
    return cachedCtx;
  }
  const Ctor =
    window.AudioContext ??
    (window as unknown as { webkitAudioContext?: typeof AudioContext })
      .webkitAudioContext;
  if (!Ctor) return null;
  try {
    cachedCtx = new Ctor();
  } catch {
    return null;
  }
  return cachedCtx;
}

/**
 * Cash-register "cha-CHING!" — plays a layered drawer thud + mechanism
 * click + bright bell ring (E6 + E7 + G#7 harmonics with quick
 * exponential decay). Total duration ~700ms. Fire-and-forget; safe to
 * call from anywhere.
 */
export function playCashRegister(): void {
  const c = getCtx();
  if (!c) return;
  try {
    const now = c.currentTime;
    playDrawerThud(c, now);
    playMechanismClick(c, now + 0.02);
    playBellRing(c, now + 0.05);
  } catch {
    // Audio graph construction can throw in degraded WebView builds;
    // a missing ka-ching is never worth surfacing.
  }
}

function playDrawerThud(c: AudioContext, at: number): void {
  // Short low-passed noise burst that suggests a cash drawer popping
  // out — the "cha" half of "cha-ching."
  const lenSamples = Math.floor(c.sampleRate * 0.1);
  const buf = c.createBuffer(1, lenSamples, c.sampleRate);
  const data = buf.getChannelData(0);
  const decaySamples = c.sampleRate * 0.02;
  for (let i = 0; i < lenSamples; i++) {
    data[i] = (Math.random() * 2 - 1) * Math.exp(-i / decaySamples);
  }
  const src = c.createBufferSource();
  src.buffer = buf;
  const lp = c.createBiquadFilter();
  lp.type = 'lowpass';
  lp.frequency.value = 300;
  const gain = c.createGain();
  gain.gain.value = 0.35;
  src.connect(lp).connect(gain).connect(c.destination);
  src.start(at);
}

function playMechanismClick(c: AudioContext, at: number): void {
  // Tight band-passed noise transient — the metallic snap of the bell
  // hammer striking before the bell itself starts to ring.
  const lenSamples = Math.floor(c.sampleRate * 0.03);
  const buf = c.createBuffer(1, lenSamples, c.sampleRate);
  const data = buf.getChannelData(0);
  const decaySamples = c.sampleRate * 0.008;
  for (let i = 0; i < lenSamples; i++) {
    data[i] = (Math.random() * 2 - 1) * Math.exp(-i / decaySamples);
  }
  const src = c.createBufferSource();
  src.buffer = buf;
  const bp = c.createBiquadFilter();
  bp.type = 'bandpass';
  bp.frequency.value = 4000;
  bp.Q.value = 1.5;
  const gain = c.createGain();
  gain.gain.value = 0.22;
  src.connect(bp).connect(gain).connect(c.destination);
  src.start(at);
}

/**
 * Birthday countdown completion — ascending three-note bell flourish
 * (C6 → E6 → G6, a major chord arpeggio) signalling "it's the day!".
 * Celebratory and bright.
 */
export function playBirthdayChime(): void {
  const c = getCtx();
  if (!c) return;
  try {
    const now = c.currentTime;
    const notes = [1046.5, 1318.5, 1567.98]; // C6, E6, G6
    notes.forEach((freq, i) => playBellTone(c, now + i * 0.16, freq, 0.55, 0.32));
  } catch {
    /* swallow */
  }
}

/**
 * Rent-due countdown completion — two attention-getting bell tones
 * a perfect fourth apart (A5 → E5, descending). Heavier and more
 * "ding-dong" than the birthday flourish so the two countdowns stay
 * audibly distinct.
 */
export function playRentDueChime(): void {
  const c = getCtx();
  if (!c) return;
  try {
    const now = c.currentTime;
    playBellTone(c, now, 880, 0.7, 0.38);          // A5
    playBellTone(c, now + 0.32, 659.25, 0.7, 0.38); // E5
  } catch {
    /* swallow */
  }
}

/**
 * Stopwatch stop — soft single A4 bell that fades quickly. Gentle and
 * unobtrusive since Sallie's the one who pressed Stop and doesn't
 * need to be jolted.
 */
export function playStopwatchChime(): void {
  const c = getCtx();
  if (!c) return;
  try {
    const now = c.currentTime;
    playBellTone(c, now, 440, 0.45, 0.28); // A4
    playBellTone(c, now, 880, 0.45, 0.12); // A5 partial for sparkle
  } catch {
    /* swallow */
  }
}

// ---------------------------------------------------------------------------
// Tier-keyed income celebrations. Picked by `celebrateIncome(...)` based on
// the sale amount — tiny tips get a single soft "ting," whale sales get a
// full ascending fanfare. `playCashRegister()` above remains the tier-2
// default (kept as-is for backwards compat with the existing call sites).
// ---------------------------------------------------------------------------

/** Tier 1 (< $10) — single A5 sine, 200ms decay. Soft positive blip. */
export function playCashRegisterTiny(): void {
  const c = getCtx();
  if (!c) return;
  try {
    playBellTone(c, c.currentTime, 880, 0.22, 0.22); // A5
  } catch {
    /* swallow */
  }
}

/** Tier 3 ($50–$199) — brighter ka-ching: drawer + click + extra-bright
 *  4-partial bell with an added octave above the v1.18.5 register. */
export function playCashRegisterMedium(): void {
  const c = getCtx();
  if (!c) return;
  try {
    const now = c.currentTime;
    playDrawerThud(c, now);
    playMechanismClick(c, now + 0.02);
    // Bigger bell than the default — adds an octave above for sparkle.
    const partials: { freq: number; amp: number }[] = [
      { freq: 1318.5, amp: 0.34 }, // E6
      { freq: 2637.0, amp: 0.24 }, // E7
      { freq: 3322.4, amp: 0.16 }, // G#7
      { freq: 5274.0, amp: 0.08 }, // E8 — extra sparkle
    ];
    const at = now + 0.05;
    for (const { freq, amp } of partials) {
      playBellTone(c, at, freq, 0.7, amp);
    }
  } catch {
    /* swallow */
  }
}

/** Tier 4 ($200–$999) — layered double cha-ching with two overlapping
 *  bells 180ms apart, plus a stronger drawer thud. */
export function playCashRegisterBig(): void {
  const c = getCtx();
  if (!c) return;
  try {
    const now = c.currentTime;
    playDrawerThud(c, now);
    playMechanismClick(c, now + 0.02);
    // First bell — bright.
    playBellTone(c, now + 0.05, 1318.5, 0.7, 0.36); // E6
    playBellTone(c, now + 0.05, 2637.0, 0.7, 0.26); // E7
    playBellTone(c, now + 0.05, 3322.4, 0.7, 0.18); // G#7
    // Second bell, slightly higher pitch — gives a "ka-CHING-CHING".
    playMechanismClick(c, now + 0.18);
    playBellTone(c, now + 0.20, 1567.98, 0.7, 0.32); // G6
    playBellTone(c, now + 0.20, 2793.83, 0.7, 0.22); // F7
    playBellTone(c, now + 0.20, 3729.31, 0.7, 0.14); // A#7
  } catch {
    /* swallow */
  }
}

/** Tier 5 ($1000+) — mega-fanfare: drawer + click + ascending C-major
 *  arpeggio (C5→E5→G5→C6) cascade. Total ~1.5s of celebration. */
export function playCashRegisterMega(): void {
  const c = getCtx();
  if (!c) return;
  try {
    const now = c.currentTime;
    playDrawerThud(c, now);
    playMechanismClick(c, now + 0.02);
    // Big base chord stacked on the drawer thud.
    playBellTone(c, now + 0.05, 1046.5, 0.9, 0.30); // C6
    playBellTone(c, now + 0.05, 1318.5, 0.9, 0.24); // E6
    playBellTone(c, now + 0.05, 1567.98, 0.9, 0.22); // G6
    playBellTone(c, now + 0.05, 2093.0, 0.9, 0.18);  // C7 — top
    // Ascending arpeggio on top — C5, E5, G5, C6 over ~600ms.
    const arpeggio = [523.25, 659.25, 783.99, 1046.5];
    arpeggio.forEach((freq, i) => {
      playBellTone(c, now + 0.4 + i * 0.15, freq, 0.6, 0.28);
    });
    // Final triumphant high C8.
    playBellTone(c, now + 1.05, 4186.0, 0.8, 0.22);
  } catch {
    /* swallow */
  }
}

/**
 * Milestone fanfare layered on top of whichever tier sound just
 * played. Scales with how far Sallie crossed: 50% → two-note ascent,
 * 100% → full triumphant chord, 150%+ → over-the-moon cascade.
 */
export function playMilestoneFanfare(percent: number): void {
  const c = getCtx();
  if (!c) return;
  try {
    const now = c.currentTime + 0.55; // ~500ms after tier sound starts
    if (percent >= 200) {
      // Double ascending arpeggio.
      [523.25, 659.25, 783.99, 1046.5, 1318.5, 1567.98].forEach((f, i) => {
        playBellTone(c, now + i * 0.12, f, 0.5, 0.28);
      });
    } else if (percent >= 100) {
      // Big C-major triad held together.
      playBellTone(c, now, 1046.5, 0.9, 0.32); // C6
      playBellTone(c, now, 1318.5, 0.9, 0.28); // E6
      playBellTone(c, now, 1567.98, 0.9, 0.24); // G6
      playBellTone(c, now + 0.25, 2093.0, 0.9, 0.22); // C7 echo
    } else if (percent >= 75) {
      // Three rising notes — G-B-D.
      [783.99, 987.77, 1174.66].forEach((f, i) => {
        playBellTone(c, now + i * 0.18, f, 0.55, 0.30);
      });
    } else if (percent >= 50) {
      // Half-way two-note major-third ascent (E → G).
      playBellTone(c, now, 659.25, 0.55, 0.30);
      playBellTone(c, now + 0.20, 783.99, 0.55, 0.30);
    } else if (percent >= 25) {
      // Quarter-way single perfect-fifth ping (C → G chord).
      playBellTone(c, now, 783.99, 0.5, 0.30);
      playBellTone(c, now, 523.25, 0.5, 0.22);
    }
  } catch {
    /* swallow */
  }
}

/** Shared bell-tone primitive used by all three chimes. */
function playBellTone(
  c: AudioContext,
  at: number,
  freq: number,
  decaySec: number,
  peakAmp: number,
): void {
  const osc = c.createOscillator();
  osc.type = 'sine';
  osc.frequency.value = freq;
  const g = c.createGain();
  g.gain.setValueAtTime(0.0001, at);
  g.gain.linearRampToValueAtTime(peakAmp, at + 0.008);
  g.gain.exponentialRampToValueAtTime(0.0001, at + decaySec);
  osc.connect(g).connect(c.destination);
  osc.start(at);
  osc.stop(at + decaySec + 0.05);
}

function playBellRing(c: AudioContext, at: number): void {
  // Bright bell using three sine partials (E6 + E7 + G#7), each with a
  // 5ms attack and a 600ms exponential decay. The major-third on top
  // (G#7) gives the unmistakable "ching!" sparkle.
  const partials: { freq: number; amp: number }[] = [
    { freq: 1318.5, amp: 0.32 }, // E6
    { freq: 2637.0, amp: 0.22 }, // E7
    { freq: 3322.4, amp: 0.14 }, // G#7
  ];
  for (const { freq, amp } of partials) {
    const osc = c.createOscillator();
    osc.type = 'sine';
    osc.frequency.value = freq;
    const g = c.createGain();
    g.gain.setValueAtTime(0.0001, at);
    g.gain.linearRampToValueAtTime(amp, at + 0.005);
    g.gain.exponentialRampToValueAtTime(0.0001, at + 0.6);
    osc.connect(g).connect(c.destination);
    osc.start(at);
    osc.stop(at + 0.65);
  }
}
