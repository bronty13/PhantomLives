// The rulebook's worked "Sample Game" (pages 7–12) as a deterministic oracle.
//
// The sample game walks a 4-player Epoch I (Hera/Zeus/Apollo/Hermes) plus a late
// Persia tally, pinning down EXACT dice and EXACT Victory-Point breakdowns. We encode
// those facts (uncopyrightable game data, like a transcribed chess game) and assert our
// engine reproduces them. This is the ground-truth check that settles disputes the
// clause-level audit could only guess at — most importantly the combat dice model.

import { describe, expect, it } from 'vitest'
import type { Rng } from '../src/shared/rng'
import { combatOdds, resolveAssault, winProb } from '../src/shared/combat'
import { areaValue } from '../src/shared/data/areaValues'
import { scoreArea, scoreStructuresForPlayer } from '../src/shared/scoring'
import type { BoardPiece, EpochId, PlayerId, StructureKind } from '../src/shared/types'

/** An Rng that returns a fixed sequence of die faces — lets us replay the book's rolls. */
function scriptedRng(dice: number[]): Rng {
  let i = 0
  return {
    nextFloat: () => 0,
    nextInt: () => 0,
    rollDie: () => {
      if (i >= dice.length) throw new Error(`combat consumed more than the ${dice.length} scripted dice`)
      return dice[i++]
    },
    state: () => i,
  }
}

describe('Sample game §combat — Hera assaults Zeus’s fortified Nile Delta (steps 12–13)', () => {
  it('reproduces the book exactly: tie on round 1, defender wins the reroll', () => {
    // Round 1 — attacker rolls 6,1 (keeps 6); defender rolls 5, +1 fort = 6 → TIE → reroll.
    // Round 2 — attacker rolls 6,6 (keeps 6); defender rolls 6, +1 fort = 7 → DEFENDER wins.
    const rng = scriptedRng([6, 1, 5, /* reroll */ 6, 6, 6])
    const res = resolveAssault(rng, { fort: true })
    expect(res.outcome).toBe('defender') // Hera is repelled, loses the attacking army
    expect(res.fortDestroyed).toBe(false) // the fort that wins its defence survives
    expect(rng.state()).toBe(6) // consumed exactly the 6 dice the book rolled (2+1 ×2 rounds)
  })

  it('the closed-form odds agree it is a defender-favoured fight (attacker 2 vs defender 1 +fort)', () => {
    const odds = combatOdds(2, 1, 1) // attacker 2 dice, defender 1 die, +1 fort
    expect(winProb(odds)).toBeLessThan(0.5)
  })
})

describe('Sample game §VP table — base Area values the book prints', () => {
  // The sample game states these exact base values in its scoring tallies.
  it('matches the printed per-epoch base values for the three Areas in play', () => {
    expect(areaValue('north_africa', 1)).toBe(1) // step 6: N. Africa Dominance "base 1 doubled"
    expect(areaValue('north_africa', 2)).toBe(2) // step 19: N. Africa Presence = 2
    expect(areaValue('middle_east', 1)).toBe(2) // steps 10/16: Middle East "base 2"
    expect(areaValue('middle_east', 2)).toBe(3) // step 19: Middle East Control of base 3
    expect(areaValue('southern_europe', 1)).toBe(0) // step 10: Crete/S. Europe "base value 0 in Epoch I"
    expect(areaValue('southern_europe', 2)).toBe(2) // step 19: S. Europe Dominance of base 2
  })
})

describe('Sample game §Area scoring — each tally’s per-Area points', () => {
  // scoreArea(area, epoch, own, rivalCounts, areaSize). We force each tier the book
  // names (presence / dominance / control) and assert the exact VP it prints.
  const SIZE = 6 // a comfortably-large Area so own<size means "not control"

  it('Zeus/Egypt E1 — Dominance of North Africa = 2 (base 1 ×2)', () => {
    expect(scoreArea('north_africa', 1, 3, [1], SIZE)).toBe(2)
  })
  it('Apollo/Minoans E1 — Presence in the Middle East = 2 (base 2 ×1)', () => {
    expect(scoreArea('middle_east', 1, 1, [2], SIZE)).toBe(2)
  })
  it('Apollo/Minoans E1 — Crete/S. Europe scores 0 (base 0 in Epoch I)', () => {
    expect(scoreArea('southern_europe', 1, 1, [], SIZE)).toBe(0)
  })
  it('Hera/Babylonia E1 — Dominance of the Middle East = 4 (base 2 ×2)', () => {
    expect(scoreArea('middle_east', 1, 3, [1], SIZE)).toBe(4)
  })
  it('Hera/Persia E2 — Control of the Middle East = 9 (base 3 ×3)', () => {
    expect(scoreArea('middle_east', 2, SIZE, [], SIZE)).toBe(9) // own == size → control
  })
  it('Hera/Persia E2 — Dominance of Southern Europe = 4 (base 2 ×2)', () => {
    expect(scoreArea('southern_europe', 2, 3, [1], SIZE)).toBe(4)
  })
  it('Hera/Persia E2 — Presence in North Africa = 2 (base 2 ×1)', () => {
    expect(scoreArea('north_africa', 2, 1, [], SIZE)).toBe(2)
  })
})

describe('Sample game §structures — capital/city/monument point values', () => {
  const struct = (land: string, kind: StructureKind, owner: PlayerId, epoch: EpochId = 1): BoardPiece => ({
    land,
    kind,
    owner,
    epochColor: epoch,
  })
  it('Hera/Persia E2 structures = 7 (capital 2 + 3 cities + 2 monuments)', () => {
    const pieces: BoardPiece[] = [
      struct('a', 'capital', 'P1'),
      struct('b', 'city', 'P1'),
      struct('c', 'city', 'P1'),
      struct('d', 'city', 'P1'),
      struct('e', 'monument', 'P1'),
      struct('f', 'monument', 'P1'),
    ]
    expect(scoreStructuresForPlayer(pieces, 'P1')).toBe(7)
  })
})

describe('Sample game §turn totals — the book’s per-turn VP add up under our scoring', () => {
  const SIZE = 6
  it('Zeus/Egypt E1 = 5 (Capital 2 + N. Africa Dominance 2 + 1 Sea)', () => {
    const cap = 2
    const area = scoreArea('north_africa', 1, 3, [1], SIZE) // 2
    const sea = 1
    expect(cap + area + sea).toBe(5)
  })
  it('Apollo/Minoans E1 = 5 (Capital 2 + Middle East Presence 2 + 1 Sea)', () => {
    expect(2 + scoreArea('middle_east', 1, 1, [2], SIZE) + 1).toBe(5)
  })
  it('Hera/Babylonia E1 = 7 (Capital 2 + Monument 1 + Middle East Dominance 4)', () => {
    expect(2 + 1 + scoreArea('middle_east', 1, 3, [1], SIZE)).toBe(7)
  })
  it('Hera/Persia E2 = 22 (Cap 2 + 3 Cities + 2 Monuments + N.Af Presence + S.Eu Dominance + ME Control)', () => {
    const structures = 2 + 3 + 2 // capital + 3 cities + 2 monuments
    const nAfrica = scoreArea('north_africa', 2, 1, [], SIZE) // 2 (presence)
    const sEurope = scoreArea('southern_europe', 2, 3, [1], SIZE) // 4 (dominance)
    const mEast = scoreArea('middle_east', 2, SIZE, [], SIZE) // 9 (control)
    expect(structures + nAfrica + sEurope + mEast).toBe(22)
  })
})
