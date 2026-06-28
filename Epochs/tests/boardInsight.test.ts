import { describe, expect, it } from 'vitest'
import { areaControl, placementInfo, type PlacementCtx } from '../src/shared/boardInsight'
import { Board } from '../src/shared/board'
import { combatOdds } from '../src/shared/combat'
import { FIXTURE_MAP_DATA } from '../src/shared/data/fixtureMap'
import type { BoardPiece, EpochId, PieceKind, PlayerId } from '../src/shared/types'

const board = new Board(FIXTURE_MAP_DATA)
const army = (land: string, owner: PlayerId, epoch: EpochId = 1): BoardPiece => ({
  land,
  kind: 'army',
  owner,
  epochColor: epoch,
})
const struct = (land: string, kind: PieceKind, owner: PlayerId): BoardPiece => ({
  land,
  kind,
  owner,
  epochColor: 1,
})
const ctx = (pieces: BoardPiece[], extra: Partial<PlacementCtx> = {}): PlacementCtx => ({
  board,
  pieces,
  epoch: 1,
  player: 'P1',
  empireHasCapital: true,
  ...extra,
})

describe('placementInfo', () => {
  it('settling an empty scoring land shows presence + VP gain', () => {
    const lines = placementInfo('mesopotamia', 'empty', undefined, false, ctx([]))
    expect(lines[0]).toMatch(/Settle/)
    expect(lines.join(' ')).toMatch(/\+2 VP/) // Middle East ×2 epoch I: none→presence
  })

  it('attacking an enemy capital shows odds + the capture', () => {
    const pieces = [army('levant', 'P2'), struct('levant', 'capital', 'P2')]
    const lines = placementInfo('levant', 'enemy', combatOdds(2, 1), false, ctx(pieces))
    expect(lines[0]).toMatch(/Attack:.*win/)
    expect(lines.join(' ')).toMatch(/Captures enemy capital/)
  })

  it('own_old reclaim shows no new ground', () => {
    const lines = placementInfo('mesopotamia', 'own_old', undefined, false, ctx([army('mesopotamia', 'P1', 1)]))
    expect(lines[0]).toMatch(/Reclaim/)
    expect(lines.join(' ')).toMatch(/no new ground/)
  })

  it('amphibious enemy notes the defender advantage', () => {
    const lines = placementInfo('greece', 'enemy', combatOdds(2, 3), true, ctx([army('greece', 'P2')]))
    expect(lines.join(' ')).toMatch(/Amphibious/)
  })

  it('a Marauder notes the raze bonus', () => {
    const pieces = [army('levant', 'P2'), struct('levant', 'city', 'P2')]
    const lines = placementInfo('levant', 'enemy', combatOdds(2, 1), false, ctx(pieces, { empireHasCapital: false }))
    expect(lines.join(' ')).toMatch(/Marauder/)
  })
})

describe('areaControl', () => {
  it('identifies the leader, tier, and banked VP of each scoring region', () => {
    // 3 of Middle East's 4 lands, no rival → DOMINANCE (control now needs all 4)
    const pieces = [army('mesopotamia', 'P1'), army('levant', 'P1'), army('persia', 'P1')]
    const me = areaControl(board, pieces, 1).find((r) => r.areaId === 'middle_east')!
    expect(me.leaderId).toBe('P1')
    expect(me.tier).toBe('dominance')
    expect(me.bankVP).toBe(me.value * 2) // dominance = ×2
    // holding all 4 lands → control ×3
    const all = [...pieces, army('anatolia', 'P1')]
    const me2 = areaControl(board, all, 1).find((r) => r.areaId === 'middle_east')!
    expect(me2.tier).toBe('control')
    expect(me2.bankVP).toBe(me2.value * 3)
  })

  it('marks contested when two players tie for the lead', () => {
    const pieces = [army('mesopotamia', 'P1'), army('levant', 'P2')]
    const me = areaControl(board, pieces, 1).find((r) => r.areaId === 'middle_east')!
    expect(me.contested).toBe(true)
  })

  it('only returns regions that score this epoch', () => {
    for (const r of areaControl(board, [], 1)) expect(r.value).toBeGreaterThan(0)
  })
})
