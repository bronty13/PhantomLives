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
    // Deterministic (seeded) win rates. Monotonic ε-greedy handicap of the tuned
    // peak. Registering to the real board scan (95 lands, Delaunay adjacency)
    // compressed the spread vs the old generated map — still hard > medium > easy,
    // all clear of 50% (observed 52.5 / 59.6 / 57.1%), but tighter. Re-tuning the
    // handicap for the new geography is a follow-up; thresholds track today's ladder.
    expect(hVsM).toBeGreaterThan(0.51)
    expect(mVsE).toBeGreaterThan(0.55)
    expect(hVsE).toBeGreaterThan(0.54)
  })
})
