// HeuristicBot — the real AI (replaces GreedyStubBot). It scores every frontier
// placement by its marginal, survival-discounted, relative expected VP and
// returns the argmax. Design from the AI design-panel synthesis; see docs/SPEC.md
// §15. Pure + deterministic: all jitter flows through a seeded hash, never
// Math.random and never the engine RNG (SPEC §13).
//
// Core ideas:
//  - ENGINE PARITY: value a move as scoring.scoreArea(after) − scoreArea(before),
//    summed over remaining epochs and discounted by a board-aware survival factor
//    `rho`, so the bot can never value a move differently from how the engine
//    actually scores it.
//  - own_old (re-occupying your own land) has EXACTLY ZERO marginal area value
//    (the old army already counted) — its only worth is refreshing a current-epoch
//    army onto a resource land for monuments. (This is the GreedyStubBot bug.)
//  - DENIAL: removing an enemy army / razing a capital is valued via the same
//    parity math from the victim's perspective, weighted toward the leader.
//  - RISK: enemy attacks are folded by closed-form (win/tie/loss) odds and must
//    beat the best safe placement (opportunity cost).

import type { Bot, BotView, DraftDecision, DraftView, EventChoice, EventView, FrontierOption } from './bot'
import { combatOdds, winProb } from './combat'
import { areaValue } from './data/areaValues'
import { scoreArea } from './scoring'
import { effectNeedsTarget } from './types'
import type { AreaId, BoardPiece, EpochId, EventEffect, EventHand, LandId, PlayerId } from './types'

export interface HeuristicWeights {
  rhoBase: number
  rhoMin: number
  terrainRetention: number
  threatPenalty: number
  structDurability: number
  selfBias: number
  monumentWeight: number
  structWeight: number
  marauderBonus: number
  denialBase: number
  denialLeaderBonus: number
  denialCatchup: number
  denyPhaseEarly: number
  denyPhaseLate: number
  riskAversion: number
  armyFloor: number
  expansionTempo: number
  ownTempo: number
  tieEps: number
  minWinProb: number
  /** ε-greedy skill dial: prob. of a (deterministic-pseudo)random move. The
   *  difficulty axis — scale-independent and strictly monotonic (0 = best). */
  randomMoveProb: number
}

// Tuned by self-play (tests/tuning.test.ts): the strength peak on the real
// world board. Notably riskAversion is HIGH (don't fling armies into bad
// attacks) and denialBase is LOW (grow yourself before spiting opponents) —
// this config beats the pre-tuning default ~77% head-to-head.
export const DEFAULT_WEIGHTS: HeuristicWeights = {
  rhoBase: 0.74,
  rhoMin: 0.4,
  terrainRetention: 0.6,
  threatPenalty: 0.05,
  structDurability: 0.15,
  selfBias: 0.9,
  monumentWeight: 0.6,
  structWeight: 1.0,
  marauderBonus: 1.0,
  denialBase: 0.35,
  denialLeaderBonus: 1.0,
  denialCatchup: 0.04,
  denyPhaseEarly: 0.5,
  denyPhaseLate: 1.3,
  riskAversion: 0.75,
  armyFloor: 0.25,
  expansionTempo: 0.05,
  ownTempo: 0.01,
  tieEps: 0.01,
  minWinProb: 0.0,
  randomMoveProb: 0.0,
}

export type Difficulty = 'easy' | 'medium' | 'hard'

/** Difficulty maps onto a few weights so a stronger bot is SHARPER, not luckier:
 *  foresight (rhoBase), opponent-awareness (denialBase), and noise (tieEps). */
export function difficultyWeights(d: Difficulty): HeuristicWeights {
  // Difficulty = MONOTONIC HANDICAPS of the tuned peak (DEFAULT). `hard` is the
  // peak with no jitter; lower tiers turn its advantages DOWN — less foresight
  // (rhoBase), more noise (tieEps), more timidity (minWinProb), and (easy)
  // opponent-blind (denialBase 0). So hard > medium > easy by construction.
  const overlays: Record<Difficulty, Partial<HeuristicWeights>> = {
    // Pure random-move handicap — monotonic by construction. (The old `easy`
    // overlay added timidity/opponent-blindness, but "timid" plays SAFE and
    // scored ~even with medium; plain extra noise is a cleaner, ordered weakening.)
    easy: { randomMoveProb: 0.7 },
    medium: { randomMoveProb: 0.38 },
    hard: { randomMoveProb: 0.0 },
  }
  return { ...DEFAULT_WEIGHTS, ...overlays[d] }
}

const clamp = (x: number, lo: number, hi: number): number => Math.max(lo, Math.min(hi, x))

/** Deterministic [0,1) hash of the move key — seeded jitter, no Math.random. */
export function hash01(seed: number, player: string, epoch: number, land: string): number {
  let h = (2166136261 ^ seed) >>> 0
  const key = `${player}|${epoch}|${land}`
  for (let i = 0; i < key.length; i++) {
    h ^= key.charCodeAt(i)
    h = Math.imul(h, 16777619)
  }
  h = (h + 0x6d2b79f5) | 0
  let t = Math.imul(h ^ (h >>> 15), 1 | h)
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296
}

// Post-reroll probability the defender HOLDS on flat terrain (1 − attacker win).
const DEFENSE_BASELINE = 1 - winProb(combatOdds(2, 1))

export interface HeuristicBotOptions {
  name?: string
  difficulty?: Difficulty
  weights?: Partial<HeuristicWeights>
}

export class HeuristicBot implements Bot {
  readonly name: string
  private readonly w: HeuristicWeights

  constructor(opts: HeuristicBotOptions = {}) {
    const base = opts.difficulty ? difficultyWeights(opts.difficulty) : DEFAULT_WEIGHTS
    this.w = { ...base, ...(opts.weights ?? {}) }
    this.name = opts.name ?? `Heuristic-${opts.difficulty ?? 'default'}`
  }

  /**
   * Draft policy: keep a decent empire; gift a weak, capital-less one to the
   * strongest rival who still has none (deny them — they'd otherwise draw something
   * stronger), then draw again. Capitals and at/above-average strength are kept.
   */
  chooseDraft(view: DraftView): DraftDecision {
    const { drawn, remaining, canPassTo, standings, player } = view
    if (canPassTo.length === 0) return { keep: true } // no one to gift it to
    const avg = remaining.reduce((s, e) => s + e.strength, 0) / Math.max(1, remaining.length)
    if (drawn.hasCapital || drawn.strength >= avg) return { keep: true }
    const vp = (p: PlayerId): number => standings.find((s) => s.id === p)?.vp ?? 0
    const target = [...canPassTo].sort((a, b) => vp(b) - vp(a) || (a < b ? -1 : 1))[0]
    void player
    return { passTo: target }
  }

  /**
   * Event policy: spend the finite hand on strong empires so it lasts the game.
   * A strong empire presses the attack (Leader → 3 dice, Weaponry → +1/die,
   * Fanaticism → win ties); a weak one bulks up (Reallocation/Minor Empire →
   * armies). See SPEC §11/§15.
   */
  chooseEvents(view: EventView, hand: EventHand): EventChoice {
    const choice: EventChoice = {}
    const s = view.empire.strength

    if (hand.greater.length > 0) {
      if (s >= 7) {
        const combat = hand.greater.find(
          (c) =>
            c.effect.kind === 'leader' ||
            c.effect.kind === 'weaponry' ||
            c.effect.kind === 'fanaticism' ||
            c.effect.kind === 'siegecraft' ||
            c.effect.kind === 'surprise_attack' ||
            c.effect.kind === 'naval_supremacy',
        )
        choice.greater = (combat ?? hand.greater[0]).id
      } else if (s <= 4 && view.epoch >= 2) {
        const armies = hand.greater.find(
          (c) =>
            c.effect.kind === 'reallocation' ||
            c.effect.kind === 'minor_empire' ||
            c.effect.kind === 'extra_armies' ||
            c.effect.kind === 'found_kingdom' ||
            c.effect.kind === 'ship_building',
        )
        if (armies) choice.greater = armies.id
      }
    }

    // Lesser: aim a disaster at an opponent's most valuable legal target.
    const disaster = hand.lesser.find((c) => effectNeedsTarget(c.effect))
    if (disaster) {
      const target = this.bestDisasterTarget(view, disaster.effect)
      if (target) {
        choice.lesser = disaster.id
        choice.lesserTarget = target
      }
    }
    return choice
  }

  /** Best enemy Land to strike with a disaster (capital/city first; rich areas). */
  private bestDisasterTarget(view: EventView, effect: EventEffect): LandId | null {
    let best: LandId | null = null
    let bestScore = 0
    for (const p of view.pieces) {
      if (p.owner == null || p.owner === view.player) continue
      const land = view.board.land(p.land)
      if (!land) continue
      let score = 0
      if (effect.kind === 'disaster_structure') {
        if (p.kind === 'army') continue
        if (effect.terrain === 'coastal' && land.seaBorders.length === 0) continue
        if (effect.terrain === 'mountain' && !land.difficultTerrain.includes('mountain')) continue
        score = (p.kind === 'capital' ? 5 : p.kind === 'city' ? 3 : 2) + areaValue(land.area ?? '', view.epoch) * 0.5
      } else if (effect.kind === 'plague') {
        if (p.kind !== 'army') continue
        score = 1 + areaValue(land.area ?? '', view.epoch)
      } else if (effect.kind === 'pestilence') {
        if (p.kind !== 'army') continue
        // value the spread — aim where adjacent enemy armies cluster
        const adjEnemies = view.board
          .neighbors(p.land)
          .filter((nb) =>
            view.pieces.some((q) => q.land === nb && q.kind === 'army' && q.owner != null && q.owner !== view.player),
          ).length
        score = 1 + adjEnemies * 1.5 + areaValue(land.area ?? '', view.epoch) * 0.5
      } else if (effect.kind === 'famine') {
        if (p.kind !== 'army') continue
        // value the whole region — aim at the enemy's most-armied Area
        const areaArmies = view.pieces.filter(
          (q) =>
            q.kind === 'army' &&
            q.owner != null &&
            q.owner !== view.player &&
            view.board.land(q.land)?.area === land.area,
        ).length
        score = areaArmies + areaValue(land.area ?? '', view.epoch)
      } else if (effect.kind === 'barbarians') {
        if (p.kind !== 'army') continue
        // only enemy lands bordering a barren one are legal; value the sack (structures + rout)
        if (!view.board.neighbors(p.land).some((nb) => view.board.land(nb)?.barren)) continue
        const struct = view.pieces.filter((q) => q.land === p.land && q.kind !== 'army').length
        score = 1 + struct * 2 + areaValue(land.area ?? '', view.epoch) * 0.5
      } else if (effect.kind === 'pirates' || effect.kind === 'storm_at_sea') {
        if (p.kind !== 'army' || land.seaBorders.length === 0) continue // coastal only
        const struct =
          effect.kind === 'pirates'
            ? view.pieces.filter((q) => q.land === p.land && q.kind !== 'army').length
            : 0
        score = 1 + struct * 2 + areaValue(land.area ?? '', view.epoch) * 0.5
      }
      if (score > bestScore) {
        bestScore = score
        best = p.land
      }
    }
    return best
  }

  chooseExpansion(view: BotView, frontier: FrontierOption[]): LandId | null {
    if (frontier.length === 0) return null
    const w = this.w
    const { board, player: me, epoch: E } = view
    const remainingEpochs = 7 - E

    // ── precompute from the live board snapshot ───────────────────────────
    const armyOwner = new Map<LandId, PlayerId>()
    const structuresByLand = new Map<LandId, BoardPiece[]>()
    const areaCount = new Map<AreaId, Map<PlayerId, number>>()
    for (const p of view.pieces) {
      if (p.kind === 'army') {
        if (p.owner) armyOwner.set(p.land, p.owner)
        const a = board.areaOf(p.land)
        if (a && p.owner) {
          let m = areaCount.get(a)
          if (!m) {
            m = new Map()
            areaCount.set(a, m)
          }
          m.set(p.owner, (m.get(p.owner) ?? 0) + 1)
        }
      } else {
        const arr = structuresByLand.get(p.land) ?? []
        arr.push(p)
        structuresByLand.set(p.land, arr)
      }
    }

    const vpOf = (id: PlayerId): number =>
      view.standings.find((s) => s.id === id)?.vp ?? 0
    const myVp = vpOf(me)
    let leaderId: PlayerId | null = null
    let leaderVp = -Infinity
    for (const s of view.standings) {
      if (s.id === me) continue
      if (s.vp > leaderVp) {
        leaderVp = s.vp
        leaderId = s.id
      }
    }
    const phi = w.denyPhaseEarly + (w.denyPhaseLate - w.denyPhaseEarly) * ((E - 1) / 6)
    const wDeny = (d: PlayerId): number =>
      w.denialBase *
      phi *
      (1 + w.denialLeaderBonus * (d === leaderId ? 1 : 0) + w.denialCatchup * Math.max(0, vpOf(d) - myVp))

    // ── board-aware survival retention on land L ──────────────────────────
    const adjEnemy = (land: LandId): number => {
      let n = 0
      for (const nb of board.neighbors(land)) {
        const o = armyOwner.get(nb)
        if (o && o !== me) n++
      }
      return n
    }
    const retention = (land: LandId): { rhoArea: number; rhoStr: number } => {
      const terrain = board.land(land)?.difficultTerrain ?? []
      const defDice =
        terrain.includes('forest') || terrain.includes('mountain') || terrain.includes('great_wall')
          ? 2
          : 1
      const hold = 1 - winProb(combatOdds(2, defDice))
      const rhoArea = clamp(
        w.rhoBase + w.terrainRetention * (hold - DEFENSE_BASELINE) - w.threatPenalty * adjEnemy(land),
        w.rhoMin,
        0.98,
      )
      const rhoStr = clamp(rhoArea + w.structDurability, w.rhoMin, 0.98)
      return { rhoArea, rhoStr }
    }
    const famStruct = (rhoStr: number): number => {
      let total = 0
      let p = 1
      for (let k = 0; k <= remainingEpochs; k++) {
        total += p
        p *= rhoStr
      }
      return total
    }

    // ── engine-parity area value over the horizon ─────────────────────────
    const areaSizeOf = (area: AreaId): number => {
      const def = view.board.areas.get(area)
      return def ? def.lands.filter((l) => !view.board.land(l)?.barren).length : 0
    }
    const fwdScore = (
      area: AreaId,
      rho: number,
      perspective: PlayerId,
      counts: Map<PlayerId, number>,
    ): number => {
      const own = counts.get(perspective) ?? 0
      const rivals: number[] = []
      for (const [id, c] of counts) if (id !== perspective) rivals.push(c)
      const aSize = areaSizeOf(area)
      let total = 0
      let weight = 1
      for (let k = 0; k <= remainingEpochs; k++) {
        total += weight * scoreArea(area, (E + k) as EpochId, own, rivals, aSize)
        weight *= rho
      }
      return total
    }
    const adjusted = (
      base: Map<PlayerId, number>,
      deltas: Array<[PlayerId, number]>,
    ): Map<PlayerId, number> => {
      const m = new Map(base)
      for (const [id, d] of deltas) m.set(id, (m.get(id) ?? 0) + d)
      return m
    }
    const EMPTY_COUNTS = new Map<PlayerId, number>()
    const baseCounts = (area: AreaId | null): Map<PlayerId, number> =>
      (area && areaCount.get(area)) || EMPTY_COUNTS

    // ── structures captured by occupying L (applyCapture semantics) ───────
    const structureTerms = (
      land: LandId,
      fam: number,
    ): { selfStruct: number; denyStruct: number; razed: number } => {
      let selfStruct = 0
      let denyStruct = 0
      let razed = 0
      for (const s of structuresByLand.get(land) ?? []) {
        if (s.owner == null || s.owner === me) continue
        const wd = wDeny(s.owner)
        if (s.kind === 'capital') {
          selfStruct += w.structWeight * fam * 1 // flips to a city I bank
          denyStruct += wd * fam * 2
          razed++
        } else if (s.kind === 'city') {
          denyStruct += wd * fam * 1 // sacked
          razed++
        } else if (s.kind === 'monument') {
          selfStruct += w.structWeight * fam * 1 // transfers to me
          denyStruct += wd * fam * 1
        }
      }
      return { selfStruct, denyStruct, razed }
    }

    const monMargin = (land: LandId, fam: number): number =>
      board.land(land)?.hasResource && view.monumentsBuilt < 36
        ? w.monumentWeight * 0.5 * fam
        : 0

    const isMarauder = !view.empire.hasCapital

    // ── per-kind option scoring ───────────────────────────────────────────
    const scoreEmpty = (opt: FrontierOption): number => {
      const land = opt.land
      const area = board.areaOf(land)
      const { rhoArea, rhoStr } = retention(land)
      const fam = famStruct(rhoStr)
      const base = baseCounts(area)
      const selfArea = area
        ? w.selfBias * (fwdScore(area, rhoArea, me, adjusted(base, [[me, 1]])) - fwdScore(area, rhoArea, me, base))
        : 0
      const { selfStruct, denyStruct, razed } = structureTerms(land, fam)
      const maraud = isMarauder ? w.marauderBonus * razed : 0
      return (
        selfArea +
        w.selfBias * (selfStruct + monMargin(land, fam)) +
        maraud +
        denyStruct +
        w.expansionTempo
      )
    }

    const scoreOwnOld = (opt: FrontierOption): number => {
      // No body added → area value is exactly 0; only a resource refresh matters.
      const { rhoStr } = retention(opt.land)
      return w.selfBias * monMargin(opt.land, famStruct(rhoStr)) + w.ownTempo
    }

    const scoreEnemy = (opt: FrontierOption, bestPeaceful: number): number => {
      const land = opt.land
      const area = board.areaOf(land)
      const d = armyOwner.get(land)
      const odds = opt.odds ?? combatOdds(2, 1)
      const { rhoArea, rhoStr } = retention(land)
      const fam = famStruct(rhoStr)
      const base = baseCounts(area)

      // WIN: I occupy (me +1) and the defender loses an army (d −1).
      let selfAreaWin = 0
      let denialWin = 0
      if (area && d) {
        const winMap = adjusted(base, [
          [me, 1],
          [d, -1],
        ])
        selfAreaWin = w.selfBias * (fwdScore(area, rhoArea, me, winMap) - fwdScore(area, rhoArea, me, base))
        denialWin = wDeny(d) * (fwdScore(area, rhoArea, d, base) - fwdScore(area, rhoArea, d, winMap))
      }
      const { selfStruct, denyStruct, razed } = structureTerms(land, fam)
      const maraud = isMarauder ? w.marauderBonus * razed : 0
      const win =
        selfAreaWin + w.selfBias * (selfStruct + monMargin(land, fam)) + maraud + denyStruct + denialWin

      // A single army must win one round per defender to conquer; it dies on the
      // first round it loses. So P(conquer) = P(round)^defenders. Win → `win` (the land
      // flips, land-based); lose → a wasted army.
      const p = winProb(odds) ** (opt.defenders ?? 1)
      const oppCost = Math.max(w.armyFloor, bestPeaceful)
      let s = p * win - w.riskAversion * (1 - p) * oppCost
      if (p < w.minWinProb) s -= 1e6 // timid skip (low difficulty)
      return s
    }

    // ── two passes: peaceful first (sets opportunity cost), then attacks ──
    const score = new Map<LandId, number>()
    let bestPeaceful = 0
    for (const opt of frontier) {
      if (opt.kind === 'empty') {
        const s = scoreEmpty(opt)
        score.set(opt.land, s)
        if (s > bestPeaceful) bestPeaceful = s
      } else if (opt.kind === 'own_old') {
        const s = scoreOwnOld(opt)
        score.set(opt.land, s)
        if (s > bestPeaceful) bestPeaceful = s
      }
    }
    for (const opt of frontier) {
      if (opt.kind === 'enemy') score.set(opt.land, scoreEnemy(opt, bestPeaceful))
    }

    // ── ε-greedy: occasionally play a deterministic-pseudorandom move ──────
    if (w.randomMoveProb > 0) {
      const salt = `${frontier.length}:${view.armiesRemaining}`
      if (hash01(view.seed, me, E, `rm:${salt}`) < w.randomMoveProb) {
        const idx = Math.floor(hash01(view.seed, me, E, `rp:${salt}`) * frontier.length)
        return frontier[Math.min(idx, frontier.length - 1)].land
      }
    }

    // ── deterministic argmax with seeded jitter ───────────────────────────
    let bestLand = frontier[0].land
    let bestScore = -Infinity
    for (const opt of frontier) {
      const jitter = w.tieEps * (hash01(view.seed, me, E, opt.land) - 0.5)
      const s = (score.get(opt.land) ?? -Infinity) + jitter
      if (s > bestScore) {
        bestScore = s
        bestLand = opt.land
      }
    }
    return bestLand
  }
}
