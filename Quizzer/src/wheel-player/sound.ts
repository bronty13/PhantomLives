// Synthesized wheel sounds via the Web Audio API — no asset files, so the deployed
// wheel stays lean and works offline. iOS requires a user gesture before audio can
// start, so unlockAudio() must be called from the Spin click handler.

type AudioCtor = typeof AudioContext;

let ctx: AudioContext | null = null;

function context(): AudioContext | null {
  try {
    if (!ctx) {
      const Ctor: AudioCtor | undefined =
        window.AudioContext ?? (window as unknown as { webkitAudioContext?: AudioCtor }).webkitAudioContext;
      if (!Ctor) return null;
      ctx = new Ctor();
    }
    if (ctx.state === 'suspended') void ctx.resume();
    return ctx;
  } catch {
    return null;
  }
}

/** Call from a user gesture (the Spin tap) so audio is unlocked on iOS/Safari. */
export function unlockAudio(): void {
  context();
}

/** A short peg "click" as the wheel passes a sector boundary. */
export function playTick(intensity = 1): void {
  const c = context();
  if (!c) return;
  try {
    const osc = c.createOscillator();
    const gain = c.createGain();
    osc.type = 'square';
    osc.frequency.value = 720 + 260 * Math.max(0, Math.min(1, intensity));
    osc.connect(gain);
    gain.connect(c.destination);
    const t = c.currentTime;
    const vol = 0.05 * Math.max(0.2, Math.min(1, intensity));
    gain.gain.setValueAtTime(vol, t);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.05);
    osc.start(t);
    osc.stop(t + 0.06);
  } catch {
    /* ignore — audio is a nicety, never a hard failure */
  }
}

/** A short rising arpeggio when the wheel stops on a result. */
export function playChime(): void {
  const c = context();
  if (!c) return;
  try {
    const notes = [523.25, 659.25, 783.99, 1046.5]; // C5 E5 G5 C6
    notes.forEach((freq, i) => {
      const osc = c.createOscillator();
      const gain = c.createGain();
      osc.type = 'triangle';
      osc.frequency.value = freq;
      osc.connect(gain);
      gain.connect(c.destination);
      const t = c.currentTime + i * 0.12;
      gain.gain.setValueAtTime(0.0001, t);
      gain.gain.exponentialRampToValueAtTime(0.16, t + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.42);
      osc.start(t);
      osc.stop(t + 0.45);
    });
  } catch {
    /* ignore */
  }
}
