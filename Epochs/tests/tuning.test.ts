// Self-play AI tuning harness (env-guarded — does NOT run in the normal suite).
// Run: `TUNE=1 npx vitest run tests/tuning.test.ts`
// Coordinate-descent search over the key HeuristicWeights, scoring each config by
// its seat-averaged 2-player win rate vs the current DEFAULT on the world board.
// Read the printed BEST config and bake it into heuristicBot.ts.

import { describe, it } from 'vitest'
import type { BotFactory } from '../src/shared/sim'
import { seeds, tournament } from '../src/shared/sim'
import { DEFAULT_WEIGHTS, HeuristicBot, type HeuristicWeights } from '../src/shared/heuristicBot'

const runIf = process.env.TUNE ? it : it.skip
const S2 = seeds(1, 40) // 40 seeds × 2 seatings = 80 games per evaluation

const botOf =
  (w: HeuristicWeights): BotFactory =>
  (name) =>
    new HeuristicBot({ name, weights: w })

const refBot: BotFactory = (name) => new HeuristicBot({ name, weights: DEFAULT_WEIGHTS })

/** Seat-averaged 2-player win rate of `w` vs the DEFAULT reference. */
function strength(w: HeuristicWeights): number {
  const hero = botOf(w)
  let total = 0
  for (const seat of [0, 1]) {
    const lineup = seat === 0 ? [hero, refBot] : [refBot, hero]
    total += tournament(lineup, S2, seat).winRate
  }
  return total / 2
}

// 4-player check: `w` vs 3 DEFAULT, hero seat rotated (chance = 25%).
function strength4(w: HeuristicWeights): number {
  const hero = botOf(w)
  let total = 0
  for (let seat = 0; seat < 4; seat++) {
    const lineup: BotFactory[] = [refBot, refBot, refBot]
    lineup.splice(seat, 0, hero)
    total += tournament(lineup, seeds(1, 24), seat).winRate
  }
  return total / 4
}

const GRID: Partial<Record<keyof HeuristicWeights, number[]>> = {
  rhoBase: [0.5, 0.6, 0.68, 0.74, 0.8],
  denialBase: [0.35, 0.5, 0.65, 0.8],
  riskAversion: [0.3, 0.45, 0.6, 0.75],
  terrainRetention: [0.3, 0.6, 0.9],
  threatPenalty: [0.05, 0.1, 0.15],
  structDurability: [0.1, 0.2, 0.3],
  monumentWeight: [0.6, 0.9, 1.2],
  denialLeaderBonus: [0.5, 1.0, 1.5],
  selfBias: [0.9, 1.0, 1.1],
}

describe('AI self-play tuning', () => {
  runIf(
    'coordinate-descent search for the strength peak',
    () => {
      let best: HeuristicWeights = { ...DEFAULT_WEIGHTS }
      let bestScore = strength(best) // ~0.5 vs itself
      // eslint-disable-next-line no-console
      console.log(`\nbaseline (DEFAULT vs DEFAULT) s2=${bestScore.toFixed(3)}`)

      for (let pass = 0; pass < 2; pass++) {
        for (const key of Object.keys(GRID) as (keyof HeuristicWeights)[]) {
          let localBest = best[key]
          let localScore = bestScore
          for (const v of GRID[key] as number[]) {
            const score = strength({ ...best, [key]: v })
            if (score > localScore) {
              localScore = score
              localBest = v
            }
          }
          best = { ...best, [key]: localBest }
          bestScore = localScore
          // eslint-disable-next-line no-console
          console.log(`pass ${pass} ${key} → ${localBest}  (s2=${localScore.toFixed(3)})`)
        }
      }

      // eslint-disable-next-line no-console
      console.log(`\nBEST s2=${strength(best).toFixed(3)}  s4=${strength4(best).toFixed(3)}`)
      // eslint-disable-next-line no-console
      console.log('BEST = ' + JSON.stringify(best, null, 2))
    },
    600_000,
  )
})
