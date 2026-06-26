import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { Board } from '../src/shared/board'
import type { BotView, FrontierOption } from '../src/shared/bot'
import { combatOdds } from '../src/shared/combat'
import { FIXTURE_MAP_DATA } from '../src/shared/data/fixtureMap'
import { HeuristicBot, hash01 } from '../src/shared/heuristicBot'
import type { BoardPiece, EmpireCard, EpochId, PieceKind, PlayerId } from '../src/shared/types'

const board = new Board(FIXTURE_MAP_DATA)

const empire = (hasCapital = true): EmpireCard => ({
  id: 'e',
  name: 'E',
  epoch: 1,
  order: 1,
  strength: 5,
  startLand: 'mesopotamia',
  navigation: { seas: [] },
  hasCapital,
})

const army = (land: string, owner: PlayerId, epoch: EpochId = 1): BoardPiece => ({
  land,
  kind: 'army',
  owner,
  epochColor: epoch,
})
const struct = (land: string, kind: PieceKind, owner: PlayerId, epoch: EpochId = 1): BoardPiece => ({
  land,
  kind,
  owner,
  epochColor: epoch,
})

function view(opts: Partial<BotView> = {}): BotView {
  return {
    board,
    player: 'P1',
    epoch: 1,
    empire: empire(),
    pieces: [],
    standings: [
      { id: 'P1', vp: 0 },
      { id: 'P2', vp: 0 },
    ],
    monumentsBuilt: 0,
    seed: 1,
    armiesRemaining: 3,
    ...opts,
  }
}

describe('HeuristicBot decision logic', () => {
  it('fixes the own_old bug: a tier-gaining empty land beats refreshing owned ground', () => {
    const bot = new HeuristicBot({ difficulty: 'hard' })
    const frontier: FrontierOption[] = [
      { land: 'italy', kind: 'own_old', amphibious: false }, // ~0 marginal value
      { land: 'levant', kind: 'empty', amphibious: false }, // presence in Middle East
    ]
    expect(bot.chooseExpansion(view(), frontier)).toBe('levant')
  })

  it('values own_old ONLY for monument refresh (resource land > non-resource land)', () => {
    const bot = new HeuristicBot({ difficulty: 'hard' })
    const frontier: FrontierOption[] = [
      { land: 'italy', kind: 'own_old', amphibious: false }, // not a resource land
      { land: 'mesopotamia', kind: 'own_old', amphibious: false }, // resource land
    ]
    expect(bot.chooseExpansion(view(), frontier)).toBe('mesopotamia')
  })

  it('captures an enemy capital (esp. the leader’s) over an equal empty land', () => {
    const bot = new HeuristicBot({ difficulty: 'hard' })
    const pieces: BoardPiece[] = [
      army('persia', 'P1'), // P1 already present in Middle East
      army('levant', 'P2'), // P2 defends Levant…
      struct('levant', 'capital', 'P2'), // …which holds P2's capital
    ]
    const frontier: FrontierOption[] = [
      { land: 'levant', kind: 'enemy', amphibious: false, odds: combatOdds(2, 1) },
      { land: 'anatolia', kind: 'empty', amphibious: false },
    ]
    const v = view({
      pieces,
      standings: [
        { id: 'P1', vp: 0 },
        { id: 'P2', vp: 8 }, // P2 is the leader → denial weighted up
      ],
    })
    expect(bot.chooseExpansion(v, frontier)).toBe('levant')
  })

  it('is deterministic: identical inputs → identical choice', () => {
    const bot = new HeuristicBot({ difficulty: 'medium' })
    const frontier: FrontierOption[] = [
      { land: 'levant', kind: 'empty', amphibious: false },
      { land: 'anatolia', kind: 'empty', amphibious: false },
      { land: 'egypt', kind: 'empty', amphibious: false },
    ]
    const a = bot.chooseExpansion(view({ seed: 99 }), frontier)
    const b = bot.chooseExpansion(view({ seed: 99 }), frontier)
    expect(b).toBe(a)
  })

  it('only returns a land in the frontier, and null only when it is empty', () => {
    const bot = new HeuristicBot({ difficulty: 'hard' })
    expect(bot.chooseExpansion(view(), [])).toBeNull()
    const frontier: FrontierOption[] = [
      { land: 'levant', kind: 'empty', amphibious: false },
      { land: 'persia', kind: 'empty', amphibious: false },
    ]
    const choice = bot.chooseExpansion(view(), frontier)
    expect(['levant', 'persia']).toContain(choice)
  })

  it('uses no nondeterministic sources (no Math.random, no engine rng)', () => {
    const src = readFileSync('src/shared/heuristicBot.ts', 'utf8')
    expect(src).not.toContain('Math.random(') // a call (the words appear in comments)
    expect(src).not.toMatch(/\brng\b/)
  })
})

describe('hash01', () => {
  it('is in [0,1), deterministic, and varies with inputs', () => {
    const a = hash01(1, 'P1', 1, 'levant')
    expect(a).toBeGreaterThanOrEqual(0)
    expect(a).toBeLessThan(1)
    expect(hash01(1, 'P1', 1, 'levant')).toBe(a)
    expect(hash01(1, 'P1', 1, 'anatolia')).not.toBe(a)
    expect(hash01(2, 'P1', 1, 'levant')).not.toBe(a)
  })
})
