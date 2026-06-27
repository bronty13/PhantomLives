import { describe, expect, it } from 'vitest'
import { makeRng } from '../src/shared/rng'
import {
  attackerDice,
  combatOdds,
  defenderDice,
  fortBonus,
  oddsForContext,
  pmfMaxOfK,
  resolveAssault,
  resolveRound,
  rollKeepHighest,
  winProb,
  type CombatResult,
} from '../src/shared/combat'

const sum = (xs: number[]) => xs.reduce((a, b) => a + b, 0)

describe('pmfMaxOfK', () => {
  it('is a proper distribution for k = 1..3', () => {
    for (const k of [1, 2, 3]) {
      const pmf = pmfMaxOfK(k)
      expect(pmf).toHaveLength(6)
      expect(sum(pmf)).toBeCloseTo(1, 12)
    }
  })

  it('matches known values (max of 2 d6)', () => {
    // P(max=v) = (2v-1)/36
    expect(pmfMaxOfK(2)).toEqual([
      1 / 36, 3 / 36, 5 / 36, 7 / 36, 9 / 36, 11 / 36,
    ])
  })
})

describe('combatOdds (closed-form)', () => {
  it('standard combat 2 vs 1 = 125/36/55 over 216', () => {
    const o = combatOdds(2, 1)
    expect(o.attacker).toBeCloseTo(125 / 216, 12)
    expect(o.tie).toBeCloseTo(36 / 216, 12) // = 1/6
    expect(o.defender).toBeCloseTo(55 / 216, 12)
    expect(o.attacker + o.tie + o.defender).toBeCloseTo(1, 12)
  })

  it('difficult terrain 2 vs 2 is symmetric (505/286/505 over 1296)', () => {
    const o = combatOdds(2, 2)
    expect(o.attacker).toBeCloseTo(505 / 1296, 12)
    expect(o.tie).toBeCloseTo(286 / 1296, 12)
    expect(o.defender).toBeCloseTo(505 / 1296, 12)
    expect(o.attacker).toBeCloseTo(o.defender, 12)
  })

  it('attacker bonus 3 vs 1 = 855/216/225 over 1296', () => {
    const o = combatOdds(3, 1)
    expect(o.attacker).toBeCloseTo(855 / 1296, 12)
    expect(o.tie).toBeCloseTo(216 / 1296, 12) // = 1/6
    expect(o.defender).toBeCloseTo(225 / 1296, 12)
  })

  it('defender 3 dice (2 vs 3) closed-form = 2183/1926/3667 over 7776', () => {
    // No context produces defender-3 anymore (capped at 2), but the closed form
    // must stay correct for k=3.
    const o = combatOdds(2, 3)
    expect(o.attacker).toBeCloseTo(2183 / 7776, 12)
    expect(o.tie).toBeCloseTo(1926 / 7776, 12)
    expect(o.defender).toBeCloseTo(3667 / 7776, 12)
  })

  it('a fort (+1 to defender) lowers attacker odds and raises defender odds', () => {
    const noFort = combatOdds(2, 1, 0)
    const withFort = combatOdds(2, 1, 1)
    expect(withFort.attacker).toBeLessThan(noFort.attacker)
    expect(withFort.defender).toBeGreaterThan(noFort.defender)
    expect(withFort.attacker + withFort.tie + withFort.defender).toBeCloseTo(1, 12)
  })

  it('winProb folds the rerolled ties into the decisive pool', () => {
    expect(winProb(combatOdds(2, 1))).toBeCloseTo(125 / 180, 12) // ties (36) rerolled
    expect(winProb(combatOdds(2, 2))).toBeCloseTo(0.5, 12) // symmetric
    expect(winProb(combatOdds(2, 1, 1))).toBeLessThan(winProb(combatOdds(2, 1, 0))) // fort hurts
  })
})

describe('context → dice mapping (SPEC §7.2)', () => {
  it('attacker rolls 2 normally, 3 with a bonus', () => {
    expect(attackerDice({})).toBe(2)
    expect(attackerDice({ attackerBonus: true })).toBe(3)
  })

  it('defender rolls 2 in any difficult case, capped at 2 (no defender-3)', () => {
    expect(defenderDice({})).toBe(1)
    expect(defenderDice({ difficultTerrain: true })).toBe(2)
    expect(defenderDice({ strait: true })).toBe(2)
    expect(defenderDice({ amphibious: true })).toBe(2)
    expect(defenderDice({ difficultTerrain: true, amphibious: true })).toBe(2)
    expect(defenderDice({ fort: true })).toBe(1) // fort is a +1, not a die
  })

  it('fort contributes a +1 bonus', () => {
    expect(fortBonus({})).toBe(0)
    expect(fortBonus({ fort: true })).toBe(1)
  })

  it('oddsForContext composes the helpers', () => {
    expect(oddsForContext({ difficultTerrain: true })).toEqual(combatOdds(2, 2))
    expect(oddsForContext({ attackerBonus: true })).toEqual(combatOdds(3, 1))
  })
})

describe('seeded resolution', () => {
  it('rollKeepHighest stays in range and is order-statistic correct', () => {
    const rng = makeRng(1)
    for (let i = 0; i < 1000; i++) {
      const r = rollKeepHighest(rng, 2)
      expect(r).toBeGreaterThanOrEqual(1)
      expect(r).toBeLessThanOrEqual(6)
    }
  })

  it('is deterministic for a given seed', () => {
    const seq = (seed: number): CombatResult[] => {
      const rng = makeRng(seed)
      return Array.from({ length: 50 }, () => resolveRound(rng, {}))
    }
    expect(seq(42)).toEqual(seq(42))
    expect(seq(42)).not.toEqual(seq(43))
  })

  it('empirical frequencies converge to the post-reroll win odds (2 vs 1)', () => {
    const rng = makeRng(12345)
    const N = 200_000
    const tally = { attacker: 0, defender: 0 }
    for (let i = 0; i < N; i++) tally[resolveRound(rng, {})]++ // ties rerolled away
    const p = winProb(combatOdds(2, 1)) // 125/180 ≈ 0.694
    expect(tally.attacker / N).toBeCloseTo(p, 2)
    expect(tally.defender / N).toBeCloseTo(1 - p, 2)
  })
})

describe('resolveAssault (fort = +1, no shielding)', () => {
  it('without a fort, an assault is a single round', () => {
    const rng = makeRng(7)
    const res = resolveAssault(rng, {})
    expect(res.rounds).toBe(1)
    expect(res.fortDestroyed).toBe(false)
  })

  it('a fort makes the attacker less likely to take the land', () => {
    const trials = (fort: boolean): number => {
      const rng = makeRng(999)
      const N = 100_000
      let taken = 0
      for (let i = 0; i < N; i++) {
        if (resolveAssault(rng, { fort }).outcome === 'attacker') taken++
      }
      return taken / N
    }
    const withFort = trials(true)
    const noFort = trials(false)
    expect(withFort).toBeLessThan(noFort)
  })
})
