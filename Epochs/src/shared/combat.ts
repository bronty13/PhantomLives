// Combat resolution (SPEC §7). The system is closed-form: attacker rolls
// `attackerDice` keeping the highest; defender rolls `defenderDice` keeping the
// highest, +1 if a fort is present. Higher wins; a TIE removes BOTH (land
// vacant). Because it's max-of-k on a d6, we can compute exact odds with no
// simulation — which is what makes strong heuristic AI tractable (SPEC §15).

import type { Rng } from './rng'

const SIDES = 6

export interface CombatContext {
  /** Leader / Weaponry / Event bonus → attacker rolls 3 dice instead of 2. */
  attackerBonus?: boolean
  /** Forest / mountain / Great Wall on the attacked land → defender rolls 2. */
  difficultTerrain?: boolean
  /** Attacking across a strait → defender rolls 3 (overrides terrain). */
  strait?: boolean
  /** Landing from the sea (amphibious) → defender rolls 3. */
  amphibious?: boolean
  /** Defender sits in a fort → +1 and the fort shields the army (SPEC §7.4). */
  fort?: boolean
}

export type CombatResult = 'attacker' | 'tie' | 'defender'

export interface CombatOdds {
  attacker: number
  tie: number
  defender: number
}

/** Dice the attacker rolls (keeps highest). */
export function attackerDice(ctx: CombatContext): number {
  return ctx.attackerBonus ? 3 : 2
}

/** Dice the defender rolls (keeps highest); take the max applicable bonus. */
export function defenderDice(ctx: CombatContext): number {
  let n = 1
  if (ctx.difficultTerrain) n = Math.max(n, 2)
  if (ctx.strait || ctx.amphibious) n = Math.max(n, 3)
  return n
}

/** Flat bonus added to the defender's kept value when a fort is present. */
export function fortBonus(ctx: CombatContext): number {
  return ctx.fort ? 1 : 0
}

/** PMF of "max of k d6": index i holds P(max === i+1), for i in 0..5. */
export function pmfMaxOfK(k: number, sides = SIDES): number[] {
  const denom = Math.pow(sides, k)
  const out: number[] = []
  for (let v = 1; v <= sides; v++) {
    out.push((Math.pow(v, k) - Math.pow(v - 1, k)) / denom)
  }
  return out
}

/**
 * Closed-form odds: attacker (max of `aDice`) vs defender (max of `dDice`) + bonus.
 * Single-round only — the fort's multi-round shielding is handled in
 * {@link resolveAssault}.
 */
export function combatOdds(aDice: number, dDice: number, bonus = 0): CombatOdds {
  const atk = pmfMaxOfK(aDice)
  const def = pmfMaxOfK(dDice)
  let attacker = 0
  let tie = 0
  let defender = 0
  for (let av = 1; av <= SIDES; av++) {
    const ap = atk[av - 1]
    if (ap === 0) continue
    for (let dv = 1; dv <= SIDES; dv++) {
      const dp = def[dv - 1]
      if (dp === 0) continue
      const dVal = dv + bonus
      const p = ap * dp
      if (av > dVal) attacker += p
      else if (av === dVal) tie += p
      else defender += p
    }
  }
  return { attacker, tie, defender }
}

/** Single-round odds for a context (ignores fort multi-round shielding). */
export function oddsForContext(ctx: CombatContext): CombatOdds {
  return combatOdds(attackerDice(ctx), defenderDice(ctx), fortBonus(ctx))
}

/** Roll `n` dice through the seeded RNG and keep the highest. */
export function rollKeepHighest(rng: Rng, n: number): number {
  let best = 0
  for (let i = 0; i < n; i++) best = Math.max(best, rng.rollDie())
  return best
}

/** One combat round (no fort shielding sequence). */
export function resolveRound(rng: Rng, ctx: CombatContext): CombatResult {
  const a = rollKeepHighest(rng, attackerDice(ctx))
  const d = rollKeepHighest(rng, defenderDice(ctx)) + fortBonus(ctx)
  if (a > d) return 'attacker'
  if (a === d) return 'tie'
  return 'defender'
}

export interface AssaultResult {
  outcome: CombatResult
  fortDestroyed: boolean
  rounds: number
}

/**
 * Full assault including fort shielding (SPEC §7.4, INTERPRETATION — verify
 * against the manual, §16): while a fort stands, the defender gets +1; the
 * first non-defender-win result destroys the fort (not the army) and the
 * attacker refights without it. A defender win repels the assault with the fort
 * intact.
 */
export function resolveAssault(rng: Rng, ctx: CombatContext): AssaultResult {
  let rounds = 0
  let fortDestroyed = false

  if (ctx.fort) {
    rounds++
    const r = resolveRound(rng, { ...ctx, fort: true })
    if (r === 'defender') {
      return { outcome: 'defender', fortDestroyed: false, rounds }
    }
    // attacker win or tie → the fort absorbs the blow; refight without it
    fortDestroyed = true
  }

  rounds++
  const r = resolveRound(rng, { ...ctx, fort: false })
  return { outcome: r, fortDestroyed, rounds }
}
