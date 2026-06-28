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

describe('areaTier (SPEC §9.1)', () => {
  it('none when the player has no armies', () => {
    expect(areaTier(0, [3])).toBe('none')
  })

  it('presence at ≥1 army, even when out-armied', () => {
    expect(areaTier(1, [])).toBe('presence')
    expect(areaTier(1, [5])).toBe('presence')
  })

  it('dominance at ≥2 and strictly more than every rival', () => {
    expect(areaTier(2, [1])).toBe('dominance')
    expect(areaTier(2, [2])).toBe('presence') // tie ≠ dominance
    expect(areaTier(4, [3, 1])).toBe('dominance')
  })

  it('control at ≥3 with no rival present at all', () => {
    expect(areaTier(3, [])).toBe('control')
    expect(areaTier(5, [0, 0])).toBe('control')
    expect(areaTier(3, [1])).toBe('dominance') // a rival blocks control
    expect(areaTier(3, [3])).toBe('presence')
  })
})

describe('scoreArea (base × tier multiplier)', () => {
  it('uses the per-epoch VP table and the tier multiplier', () => {
    // Middle East base: epoch I = 2, epoch III = 3
    expect(scoreArea('middle_east', 1, 1, [])).toBe(2) // presence ×1
    expect(scoreArea('middle_east', 1, 2, [1])).toBe(4) // dominance ×2
    expect(scoreArea('middle_east', 1, 3, [])).toBe(6) // control ×3
    expect(scoreArea('middle_east', 3, 3, [])).toBe(9) // control ×3 of base 3
  })

  it('scores zero where an area has no value that epoch', () => {
    // Northern Europe does not score in epoch I (base 0)
    expect(scoreArea('northern_europe', 1, 5, [])).toBe(0)
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

  it('sums area control across areas for the active player', () => {
    // epoch I: Middle East control ×3 of base 2 = 6; North Africa presence ×1 of base 1 = 1
    const areaVp = scoreAllAreasForPlayer(board, fixtureAreaOf, areas, 1, 'P1')
    expect(areaVp).toBe(7)
  })

  it('full empire-turn score = area control + structures', () => {
    // 7 (areas) + 2 (capital) = 9
    expect(scoreEmpireTurn(board, fixtureAreaOf, areas, 1, 'P1')).toBe(9)
  })

  it('a rival in the area downgrades control to dominance', () => {
    const contested = [...board, army('anatolia', 'P2')]
    // Middle East: P1 has 3, P2 has 1 → dominance ×2 of base 2 = 4; N.Africa presence 1
    const areaVp = scoreAllAreasForPlayer(contested, fixtureAreaOf, areas, 1, 'P1')
    expect(areaVp).toBe(5)
  })

  it('scoreBreakdown decomposes the score into per-Area tiers + structures', () => {
    const bd = scoreBreakdown(board, fixtureAreaOf, areas, 1, 'P1')
    expect(bd.total).toBe(scoreEmpireTurn(board, fixtureAreaOf, areas, 1, 'P1')) // 9
    expect(bd.areaVp + bd.structureVp).toBe(bd.total)
    expect(bd.structureVp).toBe(2)
    expect(bd.structures).toEqual({ capital: 1, city: 0, monument: 0 })
    // best-scoring Area first: Middle East control (6), then North Africa presence (1)
    expect(bd.areas.map((a) => [a.area, a.tier, a.vp])).toEqual([
      ['middle_east', 'control', 6],
      ['north_africa', 'presence', 1],
    ])
  })
})
