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
 * Tier for a player in one Area, by the number of LANDS they hold there vs every
 * rival, and the Area's size (its non-barren land count) — SPEC §9.1 / original:
 *   control   — holds EVERY land in the Area
 *   dominance — holds ≥ 3 lands AND more than every rival
 *   presence  — holds ≥ 1 land
 */
export function areaTier(own: number, rivalCounts: number[], areaSize: number): Tier {
  const maxRival = rivalCounts.length ? Math.max(...rivalCounts) : 0
  if (areaSize > 0 && own >= areaSize) return 'control' // every land (implies no rival)
  if (own >= 3 && own > maxRival) return 'dominance'
  if (own >= 1) return 'presence'
  return 'none'
}

/** VP scored in one Area: base value × tier multiplier. */
export function scoreArea(
  area: AreaId,
  epoch: EpochId,
  own: number,
  rivalCounts: number[],
  areaSize: number,
): number {
  return areaValue(area, epoch) * TIER_MULTIPLIER[areaTier(own, rivalCounts, areaSize)]
}

/** Count the distinct LANDS each player holds in an Area (army stacks count once). */
export function armiesByPlayerInArea(
  pieces: BoardPiece[],
  areaOf: (land: LandId) => AreaId | null,
  area: AreaId,
): Map<PlayerId, number> {
  const landsByPlayer = new Map<PlayerId, Set<LandId>>()
  for (const p of pieces) {
    if (p.kind !== 'army' || p.owner == null) continue
    if (areaOf(p.land) !== area) continue
    let s = landsByPlayer.get(p.owner)
    if (!s) {
      s = new Set()
      landsByPlayer.set(p.owner, s)
    }
    s.add(p.land)
  }
  const counts = new Map<PlayerId, number>()
  for (const [pid, s] of landsByPlayer) counts.set(pid, s.size)
  return counts
}

/** Score one Area for one player from a precomputed per-player land-count map. */
export function scoreAreaForPlayer(
  area: AreaId,
  epoch: EpochId,
  player: PlayerId,
  counts: Map<PlayerId, number>,
  areaSize: number,
): number {
  const own = counts.get(player) ?? 0
  const rivals: number[] = []
  for (const [id, c] of counts) if (id !== player) rivals.push(c)
  return scoreArea(area, epoch, own, rivals, areaSize)
}

/** Total area-control VP for a player across the given Areas. `areaSize` resolves
 *  each Area's non-barren land count (for the Control tier). */
export function scoreAllAreasForPlayer(
  pieces: BoardPiece[],
  areaOf: (land: LandId) => AreaId | null,
  areas: AreaId[],
  epoch: EpochId,
  player: PlayerId,
  areaSize: (area: AreaId) => number,
): number {
  let total = 0
  for (const area of areas) {
    const counts = armiesByPlayerInArea(pieces, areaOf, area)
    total += scoreAreaForPlayer(area, epoch, player, counts, areaSize(area))
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

/** One Area's contribution to a player's score this epoch. */
export interface AreaScore {
  area: AreaId
  tier: Tier
  base: number
  own: number
  vp: number
}

/** A transparent breakdown of an empire-turn score (SPEC §9) — every Area the player
 *  has presence in (with its tier), the structure tally, and the total. The Marauder
 *  raze-bonus is scored separately at raze time, so it isn't part of this. */
export interface ScoreBreakdown {
  areas: AreaScore[] // only Areas where the player has ≥1 army, best-scoring first
  structures: { capital: number; city: number; monument: number }
  structureVp: number
  areaVp: number
  total: number
}

export function scoreBreakdown(
  pieces: BoardPiece[],
  areaOf: (land: LandId) => AreaId | null,
  areas: AreaId[],
  epoch: EpochId,
  player: PlayerId,
  areaSize: (area: AreaId) => number,
): ScoreBreakdown {
  const areaScores: AreaScore[] = []
  let areaVp = 0
  for (const area of areas) {
    const counts = armiesByPlayerInArea(pieces, areaOf, area)
    const own = counts.get(player) ?? 0
    if (own === 0) continue
    const rivals: number[] = []
    for (const [id, c] of counts) if (id !== player) rivals.push(c)
    const tier = areaTier(own, rivals, areaSize(area))
    const base = areaValue(area, epoch)
    const vp = base * TIER_MULTIPLIER[tier]
    areaScores.push({ area, tier, base, own, vp })
    areaVp += vp
  }
  areaScores.sort((a, b) => b.vp - a.vp)

  let capital = 0
  let city = 0
  let monument = 0
  for (const p of pieces) {
    if (p.owner !== player) continue
    if (p.kind === 'capital') capital++
    else if (p.kind === 'city') city++
    else if (p.kind === 'monument') monument++
  }
  const structureVp =
    capital * STRUCTURE_VP.capital + city * STRUCTURE_VP.city + monument * STRUCTURE_VP.monument

  return {
    areas: areaScores,
    structures: { capital, city, monument },
    structureVp,
    areaVp,
    total: areaVp + structureVp,
  }
}

/** Full empire-turn score: area control + structures (SPEC §9). */
export function scoreEmpireTurn(
  pieces: BoardPiece[],
  areaOf: (land: LandId) => AreaId | null,
  areas: AreaId[],
  epoch: EpochId,
  player: PlayerId,
  areaSize: (area: AreaId) => number,
): number {
  return scoreBreakdown(pieces, areaOf, areas, epoch, player, areaSize).total
}
