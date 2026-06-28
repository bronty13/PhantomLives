// Procedural sound effects via WebAudio — no audio files; every SFX is a few
// oscillator / noise blips with short envelopes, kept subtle. The AudioContext is
// created lazily and resumes on the first user gesture (autoplay policy). A persisted
// mute toggle (`epochs-muted`) gates everything. Math.random here is fine — this is
// the renderer, not the deterministic engine.

let ctx: AudioContext | null = null
let muted = (() => {
  try {
    return localStorage.getItem('epochs-muted') === '1'
  } catch {
    return false
  }
})()

function ac(): AudioContext | null {
  if (muted) return null
  if (!ctx) {
    try {
      ctx = new AudioContext()
    } catch {
      return null
    }
  }
  if (ctx.state === 'suspended') void ctx.resume()
  return ctx
}

/** A tone with a fast attack + exponential decay; optional pitch slide. */
function blip(freq: number, dur: number, type: OscillatorType = 'sine', gain = 0.15, slideTo?: number): void {
  const a = ac()
  if (!a) return
  const t = a.currentTime
  const osc = a.createOscillator()
  const g = a.createGain()
  osc.type = type
  osc.frequency.setValueAtTime(freq, t)
  if (slideTo) osc.frequency.exponentialRampToValueAtTime(slideTo, t + dur)
  g.gain.setValueAtTime(0.0001, t)
  g.gain.linearRampToValueAtTime(gain, t + 0.006)
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur)
  osc.connect(g)
  g.connect(a.destination)
  osc.start(t)
  osc.stop(t + dur + 0.02)
}

/** A band-passed decaying noise burst — clashes, splashes. */
function noise(dur: number, gain = 0.12, center = 1200): void {
  const a = ac()
  if (!a) return
  const t = a.currentTime
  const buf = a.createBuffer(1, Math.max(1, Math.floor(a.sampleRate * dur)), a.sampleRate)
  const data = buf.getChannelData(0)
  for (let i = 0; i < data.length; i++) data[i] = (Math.random() * 2 - 1) * (1 - i / data.length)
  const src = a.createBufferSource()
  src.buffer = buf
  const filt = a.createBiquadFilter()
  filt.type = 'bandpass'
  filt.frequency.value = center
  const g = a.createGain()
  g.gain.value = gain
  src.connect(filt)
  filt.connect(g)
  g.connect(a.destination)
  src.start(t)
}

export const Sound = {
  get muted(): boolean {
    return muted
  },
  toggle(): boolean {
    muted = !muted
    try {
      localStorage.setItem('epochs-muted', muted ? '1' : '0')
    } catch {
      /* ignore */
    }
    if (!muted) blip(660, 0.07, 'sine', 0.12) // little confirmation chirp
    return muted
  },
  place(): void {
    blip(420, 0.07, 'triangle', 0.09)
  },
  clash(): void {
    noise(0.12, 0.14, 900)
    blip(160, 0.1, 'sawtooth', 0.08)
  },
  conquer(): void {
    blip(330, 0.09, 'square', 0.09)
    window.setTimeout(() => blip(494, 0.13, 'square', 0.09), 70)
  },
  score(): void {
    blip(620, 0.12, 'sine', 0.1, 880)
  },
  fleet(): void {
    noise(0.28, 0.07, 600) // watery whoosh
  },
  roll(): void {
    blip(740, 0.045, 'square', 0.07)
  },
  victory(): void {
    ;[523, 659, 784, 1047].forEach((f, i) => window.setTimeout(() => blip(f, 0.24, 'triangle', 0.12), i * 115))
  },
}
