// Combat resolution (SPEC §7, authentic AH 1993 — docs/AUTHENTIC-RULES.md §5).
// The attacker rolls `attackerDice` keeping the highest; the defender rolls
// `defenderDice` keeping the highest, +1 if a fort is present. Higher wins; an
// exact TIE is REROLLED until decisive (so the outcome is only attacker|defender).
// Because it's max-of-k on a d6 we keep the exact single-roll PMF (attacker/tie/
// defender) closed-form — the tie mass is the reroll pool, and `winProb` folds it
// in. Keeping the raw tie probability lets us later value tie-changing Events
// (Fanaticism = attacker wins ties; Fortress = defender wins ties).

import type { Rng } from './rng'

const SIDES = 6

export interface CombatContext {
  /** Leader / Elite Troops / Jihad → attacker rolls 3 dice instead of 2. */
  attackerBonus?: boolean
  /** Weaponry → +1 to the attacker's kept die. */
  attackerKeptBonus?: number
  /** Fanaticism / Jihad → the attacker WINS ties (instead of rerolling). */
  attackerWinsTies?: boolean
  /** Forest / mountain / Great Wall on the defender's border → defender rolls 2. */
  difficultTerrain?: boolean
  /** Attacking across a strait without controlling the sea → defender rolls 2. */
  strait?: boolean
  /** Landing from the sea (amphibious) → defender rolls 2 (same as terrain). */
  amphibious?: boolean
  /** Defender sits in a fort → +1 to its die (absorbs no losses; SPEC §5). */
  fort?: boolean
}

/** How an exact tie resolves: default 'reroll'; Fanaticism→'attacker', Fortress→'defender'. */
export type TieRule = 'reroll' | 'attacker' | 'defender'

/** Ties are rerolled, so a resolved combat is only attacker or defender. */
export type CombatResult = 'attacker' | 'defender'

/** Raw single-roll probabilities (sum to 1); `tie` is the reroll mass. */
export interface CombatOdds {
  attacker: number
  tie: number
  defender: number
}

/** Dice the attacker rolls (keeps highest). */
export function attackerDice(ctx: CombatContext): number {
  return ctx.attackerBonus ? 3 : 2
}

/** Dice the defender rolls (keeps highest): 2 in any difficult case, else 1. */
export function defenderDice(ctx: CombatContext): number {
  return ctx.difficultTerrain || ctx.strait || ctx.amphibious ? 2 : 1
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
 * Closed-form single-roll odds: attacker (max of `aDice`) vs defender
 * (max of `dDice`) + bonus. `tie` is the probability of an exact tie (which is
 * rerolled at resolution); use {@link winProb} for the effective win chance.
 */
export function combatOdds(aDice: number, dDice: number, defBonus = 0, atkBonus = 0): CombatOdds {
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
      const aVal = av + atkBonus
      const dVal = dv + defBonus
      const p = ap * dp
      if (aVal > dVal) attacker += p
      else if (aVal === dVal) tie += p
      else defender += p
    }
  }
  return { attacker, tie, defender }
}

/** Effective attacker win probability. Ties reroll by default (excluded); with
 *  Fanaticism ('attacker') the tie mass is won, with Fortress ('defender') it's lost. */
export function winProb(o: CombatOdds, ties: TieRule = 'reroll'): number {
  if (ties === 'attacker') return o.attacker + o.tie
  if (ties === 'defender') return o.attacker
  const decisive = o.attacker + o.defender
  return decisive > 0 ? o.attacker / decisive : 0
}

/** Single-round odds for a context (raw PMF, with attacker/fort kept-bonuses). */
export function oddsForContext(ctx: CombatContext): CombatOdds {
  return combatOdds(attackerDice(ctx), defenderDice(ctx), fortBonus(ctx), ctx.attackerKeptBonus ?? 0)
}

/** Effective attacker win probability for a context (honours Fanaticism). */
export function winProbForContext(ctx: CombatContext): number {
  return winProb(oddsForContext(ctx), ctx.attackerWinsTies ? 'attacker' : 'reroll')
}

/** Roll `n` dice through the seeded RNG and keep the highest. */
export function rollKeepHighest(rng: Rng, n: number): number {
  let best = 0
  for (let i = 0; i < n; i++) best = Math.max(best, rng.rollDie())
  return best
}

/** One decisive combat round — ties reroll by default, or go to the attacker
 *  under Fanaticism (SPEC §5). Weaponry adds to the attacker's kept die. */
export function resolveRound(rng: Rng, ctx: CombatContext): CombatResult {
  const aDice = attackerDice(ctx)
  const dDice = defenderDice(ctx)
  const atkBonus = ctx.attackerKeptBonus ?? 0
  const defBonus = fortBonus(ctx)
  for (let i = 0; i < 1000; i++) {
    const a = rollKeepHighest(rng, aDice) + atkBonus
    const d = rollKeepHighest(rng, dDice) + defBonus
    if (a > d) return 'attacker'
    if (a < d) return 'defender'
    if (ctx.attackerWinsTies) return 'attacker' // Fanaticism
    // else exact tie → reroll
  }
  return 'defender' // unreachable in practice (defender holds on pathological RNG)
}

export interface AssaultResult {
  outcome: CombatResult
  fortDestroyed: boolean
  rounds: number
}

/**
 * An assault: one decisive round (the fort gives the defender +1 but absorbs no
 * losses). The fort falls automatically when the last defending army is
 * eliminated — i.e. when the attacker wins (SPEC §5 / docs/AUTHENTIC-RULES §5).
 */
export function resolveAssault(rng: Rng, ctx: CombatContext): AssaultResult {
  const outcome = resolveRound(rng, ctx)
  return { outcome, fortDestroyed: !!ctx.fort && outcome === 'attacker', rounds: 1 }
}
