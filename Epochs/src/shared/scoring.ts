// Area-control + structure scoring (SPEC §9). An empire scores the HIGHEST tier
// it reaches in each Area (presence / dominance / control), multiplied by that
// Area's per-epoch base value, plus VP for the structures it controls.

import type { AreaId, BoardPiece, EpochId, LandId, PlayerId } from './types'
import { STRUCTURE_VP } from './types'
import { areaValue } from './data/areaValues'

export type Tier = 'none' | 'presence' | 'dominance' | 'control'

export const TIER_MULTIPLIER: Record<Tier, number> = {
  none: 0,
  presence: 1,
  dominance: 2,
  control: 3,
}

/**
 * Tier for a player in one Area given their own army count and every rival's
 * count in that Area (SPEC §9.1):
 *   control   — own ≥ 3 AND no rival has any army
 *   dominance — own ≥ 2 AND own > every rival
 *   presence  — own ≥ 1
 */
export function areaTier(own: number, rivalCounts: number[]): Tier {
  const maxRival = rivalCounts.length ? Math.max(...rivalCounts) : 0
  const anyRival = maxRival > 0
  if (own >= 3 && !anyRival) return 'control'
  if (own >= 2 && own > maxRival) return 'dominance'
  if (own >= 1) return 'presence'
  return 'none'
}

/** VP scored in one Area: base value × tier multiplier. */
export function scoreArea(
  area: AreaId,
  epoch: EpochId,
  own: number,
  rivalCounts: number[],
): number {
  return areaValue(area, epoch) * TIER_MULTIPLIER[areaTier(own, rivalCounts)]
}

/** Count each player's armies in a given Area, using a land→area resolver. */
export function armiesByPlayerInArea(
  pieces: BoardPiece[],
  areaOf: (land: LandId) => AreaId | null,
  area: AreaId,
): Map<PlayerId, number> {
  const counts = new Map<PlayerId, number>()
  for (const p of pieces) {
    if (p.kind !== 'army' || p.owner == null) continue
    if (areaOf(p.land) !== area) continue
    counts.set(p.owner, (counts.get(p.owner) ?? 0) + 1)
  }
  return counts
}

/** Score one Area for one player from a precomputed per-player army count map. */
export function scoreAreaForPlayer(
  area: AreaId,
  epoch: EpochId,
  player: PlayerId,
  counts: Map<PlayerId, number>,
): number {
  const own = counts.get(player) ?? 0
  const rivals: number[] = []
  for (const [id, c] of counts) if (id !== player) rivals.push(c)
  return scoreArea(area, epoch, own, rivals)
}

/** Total area-control VP for a player across the given Areas. */
export function scoreAllAreasForPlayer(
  pieces: BoardPiece[],
  areaOf: (land: LandId) => AreaId | null,
  areas: AreaId[],
  epoch: EpochId,
  player: PlayerId,
): number {
  let total = 0
  for (const area of areas) {
    const counts = armiesByPlayerInArea(pieces, areaOf, area)
    total += scoreAreaForPlayer(area, epoch, player, counts)
  }
  return total
}

/** VP from every structure a player controls (capital 2, city 1, monument 1). */
export function scoreStructuresForPlayer(
  pieces: BoardPiece[],
  player: PlayerId,
): number {
  let vp = 0
  for (const p of pieces) {
    if (p.owner !== player) continue
    if (p.kind === 'army') continue
    vp += STRUCTURE_VP[p.kind]
  }
  return vp
}

/** Full empire-turn score: area control + structures (SPEC §9). */
export function scoreEmpireTurn(
  pieces: BoardPiece[],
  areaOf: (land: LandId) => AreaId | null,
  areas: AreaId[],
  epoch: EpochId,
  player: PlayerId,
): number {
  return (
    scoreAllAreasForPlayer(pieces, areaOf, areas, epoch, player) +
    scoreStructuresForPlayer(pieces, player)
  )
}
