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
import type { EmpireCard, EpochId, LandId, PlayerId } from './types'

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
}

export interface Bot {
  readonly name: string
  /** Choose a frontier land to expand into, or null to stop expanding. */
  chooseExpansion(view: BotView, frontier: FrontierOption[]): LandId | null
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
