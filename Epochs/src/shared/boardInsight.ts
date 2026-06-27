// Pure board-insight helpers for the UI (no DOM) — reuse the ENGINE's own
// scoring so the numbers a player sees match how the engine actually scores.

import type { Board } from './board'
import type { FrontierKind } from './bot'
import { winProb, type CombatOdds } from './combat'
import { AREA_NAMES, areaValue } from './data/areaValues'
import { areaTier, armiesByPlayerInArea, TIER_MULTIPLIER, type Tier } from './scoring'
import type { AreaId, BoardPiece, EpochId, LandId, PlayerId } from './types'

const pct = (x: number): string => `${Math.round(x * 100)}%`

function armyOwnerOn(pieces: readonly BoardPiece[], land: LandId): PlayerId | null {
  for (const p of pieces) if (p.land === land && p.kind === 'army') return p.owner
  return null
}

export interface PlacementCtx {
  board: Board
  pieces: readonly BoardPiece[]
  epoch: EpochId
  player: PlayerId
  empireHasCapital: boolean
}

/** Human-readable preview lines for placing an army on `land` (SPEC §9 scoring). */
export function placementInfo(
  land: LandId,
  kind: FrontierKind,
  odds: CombatOdds | undefined,
  amphibious: boolean,
  ctx: PlacementCtx,
): string[] {
  const lines: string[] = []
  if (kind === 'empty') lines.push('Settle — gain presence')
  else if (kind === 'own_old') lines.push('Reclaim your old army')
  else {
    const o = odds ?? { attacker: 0, tie: 0, defender: 1 }
    const win = winProb(o)
    lines.push(`Attack: ${pct(win)} win · ${pct(1 - win)} hold`)
    if (amphibious) lines.push('Amphibious — defender rolls 2 dice')
  }

  const area = ctx.board.areaOf(land)
  if (area) {
    const value = areaValue(area, ctx.epoch)
    if (value > 0) {
      const counts = armiesByPlayerInArea(ctx.pieces as BoardPiece[], ctx.board.areaOfFn, area)
      const own = counts.get(ctx.player) ?? 0
      const rivalsNow: number[] = []
      for (const [id, c] of counts) if (id !== ctx.player) rivalsNow.push(c)
      const tierNow = areaTier(own, rivalsNow)
      const name = AREA_NAMES[area] ?? area
      if (kind === 'own_old') {
        lines.push(`${name} (×${value}): no new ground`)
      } else {
        let tierAfter: Tier
        if (kind === 'empty') {
          tierAfter = areaTier(own + 1, rivalsNow)
        } else {
          const defender = armyOwnerOn(ctx.pieces, land)
          const after = new Map(counts)
          after.set(ctx.player, own + 1)
          if (defender && defender !== ctx.player) {
            after.set(defender, (after.get(defender) ?? 1) - 1)
          }
          const rivalsAfter: number[] = []
          for (const [id, c] of after) if (id !== ctx.player) rivalsAfter.push(c)
          tierAfter = areaTier(own + 1, rivalsAfter)
        }
        const gain = (TIER_MULTIPLIER[tierAfter] - TIER_MULTIPLIER[tierNow]) * value
        lines.push(
          gain > 0
            ? `${name} (×${value}): ${tierNow}→${tierAfter}, +${gain} VP`
            : `${name} (×${value}): ${tierNow} this epoch`,
        )
      }
    }
  }

  if (kind === 'enemy') {
    for (const p of ctx.pieces) {
      if (p.land !== land || p.owner === ctx.player) continue
      if (p.kind === 'capital') lines.push('Captures enemy capital → your city (+2/epoch denied)')
      else if (p.kind === 'city') lines.push('Razes enemy city')
      else if (p.kind === 'monument') lines.push('Takes enemy monument')
    }
    if (!ctx.empireHasCapital) lines.push('+1 VP per razed structure (Marauder)')
  }
  return lines
}

export interface AreaControlRow {
  areaId: AreaId
  name: string
  value: number
  leaderId: PlayerId | null
  leaderCount: number
  tier: Tier
  bankVP: number
  contested: boolean
}

/** Who leads each scoring region this epoch (areas that don't score are skipped). */
export function areaControl(
  board: Board,
  pieces: readonly BoardPiece[],
  epoch: EpochId,
): AreaControlRow[] {
  const rows: AreaControlRow[] = []
  for (const areaId of board.areaIds) {
    const value = areaValue(areaId, epoch)
    if (value === 0) continue
    const counts = armiesByPlayerInArea(pieces as BoardPiece[], board.areaOfFn, areaId)
    let leaderId: PlayerId | null = null
    let leaderCount = 0
    let contested = false
    for (const [id, c] of counts) {
      if (c > leaderCount) {
        leaderCount = c
        leaderId = id
        contested = false
      } else if (c === leaderCount && c > 0) {
        contested = true
      }
    }
    const rivals: number[] = []
    for (const [id, c] of counts) if (id !== leaderId) rivals.push(c)
    const tier: Tier = leaderId ? areaTier(leaderCount, rivals) : 'none'
    rows.push({
      areaId,
      name: AREA_NAMES[areaId] ?? areaId,
      value,
      leaderId,
      leaderCount,
      tier,
      bankVP: value * TIER_MULTIPLIER[tier],
      contested,
    })
  }
  return rows.sort((a, b) => b.value - a.value)
}
