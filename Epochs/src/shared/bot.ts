// The AI seam. The engine computes the legal expansion frontier and hands it to
// a Bot, which picks one target land (or null to stop). This keeps board/rules
// internals out of the bot and lets us swap strategies freely (SPEC §15).
//
// GreedyStubBot is a placeholder, not the real heuristic AI: it scores each
// option by this-epoch area value, resource bonus, and (for attacks) win
// probability, and takes the best. Good enough to produce sane-looking games;
// the tunable weighted-scoring bot replaces it later.

import type { CombatOdds } from './combat'
import type { Board } from './board'
import { areaValue } from './data/areaValues'
import type { BoardPiece, EmpireCard, EpochId, EventHand, LandId, PlayerId } from './types'

export type FrontierKind = 'empty' | 'own_old' | 'enemy'

export interface FrontierOption {
  land: LandId
  kind: FrontierKind
  /** True when the land is reachable only across water (amphibious landing). */
  amphibious: boolean
  /** Single-round combat odds, present only for `enemy` targets. */
  odds?: CombatOdds
}

export interface BotView {
  board: Board
  player: PlayerId
  epoch: EpochId
  empire: EmpireCard
  /** Live board snapshot — rebuilt by the engine on every placement. */
  pieces: readonly BoardPiece[]
  /** Current visible VP per player (excludes hidden pre-eminence). */
  standings: readonly { id: PlayerId; vp: number }[]
  /** Monuments already on the board (0 once the 36-cap is hit). */
  monumentsBuilt: number
  /** Game seed — drives deterministic tie-break jitter (never Math.random). */
  seed: number
  /** Armies left to place this turn. */
  armiesRemaining: number
}

/** Context a bot sees when deciding which events to play before its turn. */
export interface EventView {
  epoch: EpochId
  empire: EmpireCard
  player: PlayerId
  standings: readonly { id: PlayerId; vp: number }[]
  /** Board + live pieces, so a bot can aim a targeted event (e.g. a disaster). */
  board: Board
  pieces: readonly BoardPiece[]
}

/** Which event cards (by id) to play this turn — at most one of each class.
 *  A targeted card (disaster) carries its target Land id. */
export interface EventChoice {
  greater?: string
  lesser?: string
  greaterTarget?: LandId
  lesserTarget?: LandId
}

export interface Bot {
  readonly name: string
  /** Choose a frontier land to expand into, or null to stop expanding. */
  chooseExpansion(view: BotView, frontier: FrontierOption[]): LandId | null
  /** Optionally play events before the turn (default: play none). */
  chooseEvents?(view: EventView, hand: EventHand): EventChoice
}

export class GreedyStubBot implements Bot {
  readonly name: string

  constructor(name = 'Greedy') {
    this.name = name
  }

  chooseExpansion(view: BotView, frontier: FrontierOption[]): LandId | null {
    if (frontier.length === 0) return null
    let best = frontier[0]
    let bestScore = -Infinity
    for (const opt of frontier) {
      const base = areaValue(view.board.areaOf(opt.land) ?? '', view.epoch)
      const resource = view.board.land(opt.land)?.hasResource ? 0.5 : 0
      let score: number
      if (opt.kind === 'empty') {
        score = base + resource + 1 // free, secures presence
      } else if (opt.kind === 'own_old') {
        score = base + resource + 1.5 // free reclaim of our own ground
      } else {
        const p = opt.odds?.attacker ?? 0
        score = base * p + resource * p - (1 - p) * 0.5 // risk-discounted
      }
      if (score > bestScore) {
        bestScore = score
        best = opt
      }
    }
    return best.land
  }
}

/** Picks a uniformly random frontier option from its own (separate) RNG. */
export class RandomBot implements Bot {
  readonly name = 'Random'
  constructor(private readonly pick: (n: number) => number) {}

  chooseExpansion(_view: BotView, frontier: FrontierOption[]): LandId | null {
    if (frontier.length === 0) return null
    return frontier[this.pick(frontier.length)].land
  }
}
