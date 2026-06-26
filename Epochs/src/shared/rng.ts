// Seeded, deterministic RNG (mulberry32). The engine NEVER calls Math.random();
// all randomness flows through here so games replay identically (SPEC §13).

export interface Rng {
  /** Uniform float in [0, 1). */
  nextFloat(): number
  /** Integer in [0, maxExclusive). */
  nextInt(maxExclusive: number): number
  /** A six-sided die roll in [1, 6]. */
  rollDie(): number
  /** Current internal state (for serialization / debugging). */
  state(): number
}

export function makeRng(seed: number): Rng {
  let a = seed >>> 0
  function nextFloat(): number {
    a |= 0
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
  return {
    nextFloat,
    nextInt(maxExclusive: number): number {
      return Math.floor(nextFloat() * maxExclusive)
    },
    rollDie(): number {
      return 1 + Math.floor(nextFloat() * 6)
    },
    state(): number {
      return a >>> 0
    },
  }
}
