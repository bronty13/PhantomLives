/**
 * @file sfx.ts — WebAudio-synthesized sound effects + a gentle music loop.
 * No audio assets: every sound is generated, so it ships weightless and
 * identical on macOS and Windows.
 */

let ctx: AudioContext | null = null;
let soundOn = true;
let musicOn = true;

function ac(): AudioContext {
  if (!ctx) ctx = new AudioContext();
  if (ctx.state === 'suspended') void ctx.resume();
  return ctx;
}

export function setSoundEnabled(v: boolean): void {
  soundOn = v;
}
export function setMusicEnabled(v: boolean): void {
  musicOn = v;
  if (!v) stopMusic();
}
export function musicEnabled(): boolean {
  return musicOn;
}

// ---------------------------------------------------------------------------
// Primitive voices
// ---------------------------------------------------------------------------

function tone(
  freq: number,
  durMs: number,
  opts: { type?: OscillatorType; gain?: number; slide?: number; delayMs?: number } = {}
): void {
  if (!soundOn) return;
  const a = ac();
  const t0 = a.currentTime + (opts.delayMs ?? 0) / 1000;
  const osc = a.createOscillator();
  const g = a.createGain();
  osc.type = opts.type ?? 'sine';
  osc.frequency.setValueAtTime(freq, t0);
  if (opts.slide) osc.frequency.exponentialRampToValueAtTime(Math.max(30, freq + opts.slide), t0 + durMs / 1000);
  const peak = opts.gain ?? 0.12;
  g.gain.setValueAtTime(0, t0);
  g.gain.linearRampToValueAtTime(peak, t0 + 0.008);
  g.gain.exponentialRampToValueAtTime(0.0001, t0 + durMs / 1000);
  osc.connect(g).connect(a.destination);
  osc.start(t0);
  osc.stop(t0 + durMs / 1000 + 0.02);
}

function noise(durMs: number, opts: { gain?: number; lowpass?: number; delayMs?: number } = {}): void {
  if (!soundOn) return;
  const a = ac();
  const t0 = a.currentTime + (opts.delayMs ?? 0) / 1000;
  const len = Math.ceil((a.sampleRate * durMs) / 1000);
  const buf = a.createBuffer(1, len, a.sampleRate);
  const data = buf.getChannelData(0);
  for (let i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
  const src = a.createBufferSource();
  src.buffer = buf;
  const filt = a.createBiquadFilter();
  filt.type = 'lowpass';
  filt.frequency.value = opts.lowpass ?? 2200;
  const g = a.createGain();
  const peak = opts.gain ?? 0.1;
  g.gain.setValueAtTime(peak, t0);
  g.gain.exponentialRampToValueAtTime(0.0001, t0 + durMs / 1000);
  src.connect(filt).connect(g).connect(a.destination);
  src.start(t0);
}

// ---------------------------------------------------------------------------
// Game sounds
// ---------------------------------------------------------------------------

export const sfx = {
  click: (): void => tone(620, 70, { type: 'triangle', gain: 0.08 }),
  pickup: (): void => tone(440, 80, { type: 'triangle', gain: 0.09, slide: 220 }),
  place: (): void => tone(300, 80, { type: 'triangle', gain: 0.09, slide: -80 }),
  chop: (): void => {
    noise(60, { gain: 0.12, lowpass: 1400 });
    tone(180, 50, { type: 'square', gain: 0.04 });
  },
  chopDone: (): void => tone(740, 110, { type: 'triangle', gain: 0.1, slide: 200 }),
  potAdd: (): void => {
    noise(140, { gain: 0.07, lowpass: 900 });
    tone(220, 120, { gain: 0.06, slide: -60 });
  },
  cookDone: (): void => {
    tone(660, 120, { type: 'triangle', gain: 0.11 });
    tone(880, 160, { type: 'triangle', gain: 0.11, delayMs: 110 });
  },
  soupPoured: (): void => {
    noise(260, { gain: 0.09, lowpass: 1200 });
    tone(520, 180, { gain: 0.06, slide: -160 });
  },
  plateAdd: (): void => tone(520, 90, { type: 'triangle', gain: 0.09, slide: 120 }),
  burnt: (): void => {
    noise(500, { gain: 0.14, lowpass: 600 });
    tone(150, 420, { type: 'sawtooth', gain: 0.07, slide: -70 });
  },
  potCleared: (): void => noise(180, { gain: 0.08, lowpass: 1000 }),
  trash: (): void => {
    noise(150, { gain: 0.09, lowpass: 800 });
    tone(140, 130, { type: 'square', gain: 0.05, slide: -50 });
  },
  serveOk: (): void => {
    tone(523, 110, { type: 'triangle', gain: 0.12 });
    tone(659, 110, { type: 'triangle', gain: 0.12, delayMs: 90 });
    tone(784, 200, { type: 'triangle', gain: 0.12, delayMs: 180 });
  },
  serveBad: (): void => {
    tone(220, 180, { type: 'sawtooth', gain: 0.08, slide: -60 });
    tone(180, 220, { type: 'sawtooth', gain: 0.08, delayMs: 140, slide: -60 });
  },
  orderNew: (): void => tone(987, 90, { type: 'sine', gain: 0.07, slide: 120 }),
  orderExpired: (): void => {
    tone(392, 160, { type: 'square', gain: 0.06, slide: -120 });
    tone(262, 260, { type: 'square', gain: 0.06, delayMs: 140, slide: -80 });
  },
  countdown: (): void => tone(440, 120, { type: 'square', gain: 0.08 }),
  go: (): void => tone(880, 300, { type: 'square', gain: 0.1 }),
  timeLow: (): void => tone(660, 70, { type: 'square', gain: 0.05 }),
  win: (): void => {
    const notes = [523, 659, 784, 1047, 784, 1047];
    notes.forEach((n, i) => tone(n, 180, { type: 'triangle', gain: 0.12, delayMs: i * 130 }));
  },
  lose: (): void => {
    const notes = [392, 330, 262, 196];
    notes.forEach((n, i) => tone(n, 260, { type: 'triangle', gain: 0.1, delayMs: i * 200 }));
  },
  trophy: (): void => {
    const notes = [784, 988, 1175, 1568];
    notes.forEach((n, i) => tone(n, 150, { type: 'sine', gain: 0.1, delayMs: i * 90 }));
  }
};

// ---------------------------------------------------------------------------
// Music: an airy 8-bar lullaby-waltz loop, scheduled on the audio clock.
// ---------------------------------------------------------------------------

let musicTimer: number | null = null;
let musicBeat = 0;

const BASS = [131, 98, 110, 98, 131, 98, 87, 98]; // C3 G2 A2 G2 C3 G2 F2 G2
const ARP: number[][] = [
  [262, 330, 392],
  [247, 294, 392],
  [220, 262, 330],
  [247, 294, 392],
  [262, 330, 392],
  [247, 294, 392],
  [175, 220, 262],
  [196, 247, 294]
];

function musicStep(): void {
  if (!musicOn || !soundOn) return;
  const bar = musicBeat % 8;
  tone(BASS[bar], 320, { type: 'triangle', gain: 0.035 });
  const chord = ARP[bar];
  chord.forEach((n, i) => tone(n * 2, 180, { type: 'sine', gain: 0.022, delayMs: 120 + i * 120 }));
  musicBeat++;
}

export function startMusic(): void {
  if (musicTimer !== null || !musicOn) return;
  musicBeat = 0;
  musicStep();
  musicTimer = window.setInterval(musicStep, 560);
}

export function stopMusic(): void {
  if (musicTimer !== null) {
    clearInterval(musicTimer);
    musicTimer = null;
  }
}
