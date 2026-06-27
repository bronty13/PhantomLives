import { describe, expect, it } from 'vitest'
import type { BotFactory } from '../src/shared/sim'
import { greedy, heuristic, random, seeds, tournament } from '../src/shared/sim'

const S = seeds(1, 120)

/**
 * Win rate of `hero` against a fixed `field` of opponents, AVERAGED over every
 * seat the hero can occupy — controls for first-mover / draft-order seat bias.
 */
function vsField(hero: BotFactory, field: BotFactory[], seedList = S): number {
  const n = field.length + 1
  let total = 0
  for (let seat = 0; seat < n; seat++) {
    const lineup = [...field]
    lineup.splice(seat, 0, hero)
    total += tournament(lineup, seedList, seat).winRate
  }
  return total / n
}

const pct = (x: number) => `${(x * 100).toFixed(1)}%`

describe('AI strength (seat-averaged headless tournaments)', () => {
  it('HeuristicBot(hard) decisively beats the baseline bots', () => {
    const hVsG = vsField(heuristic('hard'), [greedy])
    const hVsR = vsField(heuristic('hard'), [random])
    const hVs3G = vsField(heuristic('hard'), [greedy, greedy, greedy])
    // eslint-disable-next-line no-console
    console.log(
      `\n  hard vs greedy (2p): ${pct(hVsG)}` +
        `\n  hard vs random (2p): ${pct(hVsR)}` +
        `\n  hard vs 3×greedy (4p): ${pct(hVs3G)}  (chance=25%)`,
    )
    expect(hVsG).toBeGreaterThan(0.75) // ~100% observed
    expect(hVsR).toBeGreaterThan(0.75) // ~91% observed
    expect(hVs3G).toBeGreaterThan(0.4) // ~56% observed, well above 25% chance
  })

  it('difficulty is monotonic: hard > medium > easy', () => {
    const hVsM = vsField(heuristic('hard'), [heuristic('medium')])
    const mVsE = vsField(heuristic('medium'), [heuristic('easy')])
    const hVsE = vsField(heuristic('hard'), [heuristic('easy')])
    // eslint-disable-next-line no-console
    console.log(
      `\n  hard vs medium (2p): ${pct(hVsM)}` +
        `\n  medium vs easy (2p): ${pct(mVsE)}` +
        `\n  hard vs easy (2p): ${pct(hVsE)}`,
    )
    // Deterministic (seeded) win rates, clean monotonic ladder: hard > medium > easy.
    // Re-tuned to a PURE random-move handicap (easy 0.42 / medium 0.20 / hard 0.0)
    // after the old `easy` timidity overlay scored ~even with medium on the new board
    // + richer events. Observed 56.7 / 61.3 / 62.9%.
    expect(hVsM).toBeGreaterThan(0.53)
    expect(mVsE).toBeGreaterThan(0.57)
    expect(hVsE).toBeGreaterThan(0.58)
  })
})
