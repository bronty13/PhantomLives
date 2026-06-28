import { describe, expect, it } from 'vitest'
import type { BoardPiece, EpochId, PlayerId, StructureKind } from '../src/shared/types'
import { fixtureAreaOf } from '../src/shared/data/fixtureMap'
import {
  areaTier,
  armiesByPlayerInArea,
  scoreAllAreasForPlayer,
  scoreArea,
  scoreBreakdown,
  scoreEmpireTurn,
  scoreStructuresForPlayer,
} from '../src/shared/scoring'

const army = (land: string, owner: PlayerId, epoch: EpochId = 1): BoardPiece => ({
  land,
  kind: 'army',
  owner,
  epochColor: epoch,
})

const struct = (
  land: string,
  kind: StructureKind,
  owner: PlayerId,
  epoch: EpochId = 1,
): BoardPiece => ({ land, kind, owner, epochColor: epoch })

describe('areaTier (SPEC §9.1 — lands held vs the Area size)', () => {
  it('none when the player holds no lands', () => {
    expect(areaTier(0, [3], 5)).toBe('none')
  })

  it('presence at ≥1 land, even when out-landed', () => {
    expect(areaTier(1, [], 5)).toBe('presence')
    expect(areaTier(1, [5], 5)).toBe('presence')
  })

  it('dominance needs ≥3 lands AND strictly more than every rival', () => {
    expect(areaTier(3, [1], 6)).toBe('dominance')
    expect(areaTier(2, [1], 6)).toBe('presence') // 2 lands is no longer enough
    expect(areaTier(3, [3], 6)).toBe('presence') // tie ≠ dominance
    expect(areaTier(4, [3, 1], 6)).toBe('dominance')
  })

  it('control means holding EVERY land in the Area', () => {
    expect(areaTier(3, [], 3)).toBe('control') // own == size
    expect(areaTier(5, [], 5)).toBe('control')
    expect(areaTier(2, [], 2)).toBe('control') // small area: holding both is control
    expect(areaTier(3, [], 5)).toBe('dominance') // 3 of 5, no rival → dominance, not control
  })
})

describe('scoreArea (base × tier multiplier)', () => {
  it('uses the per-epoch VP table and the tier multiplier (Area size 4)', () => {
    // Middle East base: epoch I = 2, epoch III = 3
    expect(scoreArea('middle_east', 1, 1, [], 4)).toBe(2) // presence ×1
    expect(scoreArea('middle_east', 1, 3, [1], 4)).toBe(4) // dominance ×2 (≥3, > rival)
    expect(scoreArea('middle_east', 1, 4, [], 4)).toBe(6) // control ×3 (all 4 lands)
    expect(scoreArea('middle_east', 3, 4, [], 4)).toBe(9) // control ×3 of base 3
  })

  it('scores zero where an area has no value that epoch', () => {
    // Northern Europe does not score in epoch I (base 0)
    expect(scoreArea('northern_europe', 1, 5, [], 8)).toBe(0)
  })
})

describe('armiesByPlayerInArea (fixture map)', () => {
  it('counts only armies in the named area, per owner', () => {
    const pieces: BoardPiece[] = [
      army('mesopotamia', 'P1'),
      army('levant', 'P1'),
      army('persia', 'P2'),
      army('egypt', 'P1'), // north_africa — not middle_east
      struct('mesopotamia', 'capital', 'P1'), // not an army
    ]
    const counts = armiesByPlayerInArea(pieces, fixtureAreaOf, 'middle_east')
    expect(counts.get('P1')).toBe(2)
    expect(counts.get('P2')).toBe(1)
  })
})

describe('scoreStructuresForPlayer (SPEC §8.3)', () => {
  it('capital 2, city 1, monument 1, fort 0; only the player’s own', () => {
    const pieces: BoardPiece[] = [
      struct('mesopotamia', 'capital', 'P1'),
      struct('levant', 'city', 'P1'),
      struct('egypt', 'monument', 'P1'),
      struct('persia', 'fort', 'P1'),
      struct('greece', 'capital', 'P2'), // other player
    ]
    expect(scoreStructuresForPlayer(pieces, 'P1')).toBe(4) // 2+1+1+0
    expect(scoreStructuresForPlayer(pieces, 'P2')).toBe(2)
  })
})

describe('scoreAllAreasForPlayer + scoreEmpireTurn (integration)', () => {
  const board: BoardPiece[] = [
    // P1 controls Middle East (3 armies, no rival) and has presence in N. Africa
    army('mesopotamia', 'P1'),
    army('levant', 'P1'),
    army('persia', 'P1'),
    army('egypt', 'P1'),
    // P2 contests nothing in those areas this turn
    army('greece', 'P2'),
    // P1 structures
    struct('mesopotamia', 'capital', 'P1'),
  ]
  const areas = ['middle_east', 'north_africa', 'southern_europe']
  // fixture Area sizes (non-barren lands): ME=4, N.Africa=3, S.Europe=2
  const areaSize = (a: string): number =>
    ({ middle_east: 4, north_africa: 3, southern_europe: 2 })[a] ?? 0

  it('sums area control across areas for the active player', () => {
    // epoch I: Middle East 3 of 4 lands, no rival → DOMINANCE ×2 of base 2 = 4;
    // North Africa 1 land → presence ×1 of base 1 = 1.
    const areaVp = scoreAllAreasForPlayer(board, fixtureAreaOf, areas, 1, 'P1', areaSize)
    expect(areaVp).toBe(5)
  })

  it('full empire-turn score = area control + structures', () => {
    // 5 (areas) + 2 (capital) = 7
    expect(scoreEmpireTurn(board, fixtureAreaOf, areas, 1, 'P1', areaSize)).toBe(7)
  })

  it('control needs EVERY land; a rival drops it to dominance', () => {
    // P1 holds all 4 Middle East lands → control ×3 of base 2 = 6; +N.Africa presence 1
    const allFour = [...board, army('anatolia', 'P1')]
    expect(scoreAllAreasForPlayer(allFour, fixtureAreaOf, areas, 1, 'P1', areaSize)).toBe(7)
    // a rival on anatolia → P1 holds 3 of 4 → dominance ×2 = 4; +1 = 5
    const contested = [...board, army('anatolia', 'P2')]
    expect(scoreAllAreasForPlayer(contested, fixtureAreaOf, areas, 1, 'P1', areaSize)).toBe(5)
  })

  it('adds +1 per controlled enclosed sea (oceans excluded)', () => {
    const bd = scoreBreakdown(board, fixtureAreaOf, areas, 1, 'P1', areaSize, 2)
    expect(bd.seaVp).toBe(2)
    expect(bd.total).toBe(bd.areaVp + bd.structureVp + 2)
    // and scoreEmpireTurn includes it
    expect(scoreEmpireTurn(board, fixtureAreaOf, areas, 1, 'P1', areaSize, 2)).toBe(bd.total)
  })

  it('scoreBreakdown decomposes the score into per-Area tiers + structures', () => {
    const bd = scoreBreakdown(board, fixtureAreaOf, areas, 1, 'P1', areaSize)
    expect(bd.total).toBe(scoreEmpireTurn(board, fixtureAreaOf, areas, 1, 'P1', areaSize)) // 7
    expect(bd.areaVp + bd.structureVp).toBe(bd.total)
    expect(bd.structureVp).toBe(2)
    expect(bd.structures).toEqual({ capital: 1, city: 0, monument: 0 })
    // best-scoring Area first: Middle East dominance (4), then North Africa presence (1)
    expect(bd.areas.map((a) => [a.area, a.tier, a.vp])).toEqual([
      ['middle_east', 'dominance', 4],
      ['north_africa', 'presence', 1],
    ])
  })
})
