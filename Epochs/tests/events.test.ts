import { describe, expect, it } from 'vitest'
import { Board } from '../src/shared/board'
import { WORLD_MAP_DATA } from '../src/shared/data/board'
import { WORLD_EMPIRES } from '../src/shared/data/empires'
import { describeEffect, makeEventDeck } from '../src/shared/data/events'
import type { EventEffect } from '../src/shared/types'
import { Game, type GameEvent, type PlayerConfig } from '../src/shared/game'
import { HeuristicBot } from '../src/shared/heuristicBot'

const worldGame = (seed: number, players: PlayerConfig[]) =>
  new Game({ board: new Board(WORLD_MAP_DATA), deck: WORLD_EMPIRES, players, seed })

const hardBots = (ids: string[]): PlayerConfig[] =>
  ids.map((id) => ({ id, name: id, bot: new HeuristicBot({ name: id, difficulty: 'hard' }) }))

function drive(game: Game): GameEvent[] {
  const it = game.play()
  const events: GameEvent[] = []
  let step = it.next()
  while (!step.done) {
    events.push(step.value)
    step = it.next()
  }
  return events
}

describe('event deck', () => {
  const deck = makeEventDeck()
  it('has enough Greater (>= 18) + Lesser disasters (>= 12) for 6 players', () => {
    expect(deck.greater.length).toBeGreaterThanOrEqual(18)
    expect(deck.lesser.length).toBeGreaterThanOrEqual(12)
  })
  it('Greater are the implemented boon kinds; Lesser are targeted disasters', () => {
    const greaterKinds = [
      'leader', 'weaponry', 'fanaticism', 'reallocation', 'minor_empire',
      'siegecraft', 'surprise_attack', 'extra_armies',
    ]
    for (const c of deck.greater) {
      expect(greaterKinds).toContain(c.effect.kind)
    }
    for (const c of deck.lesser) {
      expect(['disaster_structure', 'plague', 'pestilence', 'famine']).toContain(c.effect.kind)
    }
  })
})

describe('dealing hands', () => {
  it('gives each player 3 Greater + 2 Lesser disasters, no shared cards (SPEC §11)', () => {
    const game = worldGame(1, hardBots(['P1', 'P2', 'P3', 'P4']))
    const seen = new Set<string>()
    for (const p of game.state.players) {
      expect(p.hand.greater).toHaveLength(3)
      expect(p.hand.lesser).toHaveLength(2)
      for (const c of [...p.hand.greater, ...p.hand.lesser]) {
        expect(seen.has(c.id), `duplicate card ${c.id}`).toBe(false)
        seen.add(c.id)
      }
    }
  })
})

describe('events in a full game', () => {
  it('disasters fire during AI games (the bot aims them at opponents)', () => {
    let fired = false
    for (const seed of [1, 2, 3, 4, 5]) {
      const game = worldGame(seed, hardBots(['P1', 'P2', 'P3', 'P4']))
      if (drive(game).some((e) => e.type === 'disaster')) {
        fired = true
        break
      }
    }
    expect(fired).toBe(true)
  })

  it('the AI plays Greater events during a full game', () => {
    const game = worldGame(1, hardBots(['P1', 'P2', 'P3', 'P4']))
    const events = drive(game)
    expect(events.some((e) => e.type === 'eventsPlayed')).toBe(true)
    // (Forts no longer come from Coins — that was a wrong-edition mechanic;
    // fort-building returns with the build phase + Engineering events, task #29/32.)
  })

  it('never plays more cards than were dealt (finite hand, no refills)', () => {
    const game = worldGame(2, hardBots(['P1', 'P2', 'P3', 'P4']))
    let played = 0
    for (const e of drive(game)) if (e.type === 'eventsPlayed') played += e.played.length
    expect(played).toBeLessThanOrEqual(4 * 10)
    for (const p of game.state.players) {
      expect(p.hand.greater.length + p.hand.lesser.length).toBeLessThanOrEqual(10)
    }
  })

  it('places at most one fort per land', () => {
    const game = worldGame(3, hardBots(['P1', 'P2', 'P3', 'P4']))
    drive(game)
    const perLand = new Map<string, number>()
    for (const p of game.state.pieces) {
      if (p.kind !== 'fort') continue
      perLand.set(p.land, (perLand.get(p.land) ?? 0) + 1)
    }
    for (const [, n] of perLand) expect(n).toBeLessThanOrEqual(1)
  })
})

describe('human event play', () => {
  it('consumes the chosen card from the hand', () => {
    const players: PlayerConfig[] = [
      { id: 'P1', name: 'P1', isHuman: true },
      ...hardBots(['P2', 'P3']),
    ]
    const game = worldGame(5, players)
    const before = game.state.players[0].hand.greater.length

    const it = game.play()
    let playedId: string | undefined
    let firstHuman = true
    let step = it.next()
    while (!step.done) {
      const ev = step.value
      if (ev.type === 'awaitEvents') {
        if (firstHuman && ev.hand.greater[0]) {
          firstHuman = false
          playedId = ev.hand.greater[0].id
          step = it.next({ greater: playedId })
        } else {
          step = it.next(undefined) // skip later event phases
        }
      } else if (ev.type === 'awaitPlacement') {
        step = it.next(ev.frontier[0]?.land)
      } else {
        step = it.next()
      }
    }

    expect(playedId).toBeDefined()
    expect(game.state.players[0].hand.greater.some((c) => c.id === playedId)).toBe(false)
    expect(game.state.players[0].hand.greater).toHaveLength(before - 1)
  })
})

describe('describeEffect (event card text for the panel)', () => {
  const kinds: EventEffect[] = [
    { kind: 'leader' },
    { kind: 'weaponry' },
    { kind: 'fanaticism' },
    { kind: 'reallocation', armies: 3 },
    { kind: 'minor_empire', armies: 4 },
    { kind: 'siegecraft' },
    { kind: 'surprise_attack' },
    { kind: 'extra_armies', armies: 2, needsCapital: false },
    { kind: 'extra_armies', armies: 2, needsCapital: true },
    { kind: 'disaster_structure', terrain: 'mountain' },
    { kind: 'plague' },
    { kind: 'pestilence' },
    { kind: 'famine' },
  ]
  it('gives non-empty text + a valid timing for every effect kind', () => {
    for (const e of kinds) {
      const d = describeEffect(e)
      expect(d.text.length).toBeGreaterThan(10)
      expect(d.timing === 'during' || d.timing === 'before').toBe(true)
    }
  })
  it('combat boons play during the turn; disasters play before it', () => {
    expect(describeEffect({ kind: 'fanaticism' }).timing).toBe('during')
    expect(describeEffect({ kind: 'leader' }).timing).toBe('during')
    expect(describeEffect({ kind: 'plague' }).timing).toBe('before')
    expect(describeEffect({ kind: 'disaster_structure', terrain: 'any' }).timing).toBe('before')
  })
  it('interpolates the army count', () => {
    expect(describeEffect({ kind: 'reallocation', armies: 5 }).text).toContain('5')
  })
  it('capital-gated vs free extra armies read differently', () => {
    const free = describeEffect({ kind: 'extra_armies', armies: 2, needsCapital: false }).text
    const cap = describeEffect({ kind: 'extra_armies', armies: 2, needsCapital: true }).text
    expect(free).not.toBe(cap)
    expect(cap.toLowerCase()).toContain('capital')
  })
})

describe('event deck — the new Greater boons are present', () => {
  it('includes siegecraft, surprise_attack, and both extra_armies variants', () => {
    const { greater } = makeEventDeck()
    const kinds = new Set(greater.map((c) => c.effect.kind))
    for (const k of ['siegecraft', 'surprise_attack', 'extra_armies']) expect(kinds.has(k as never)).toBe(true)
    const capGated = greater.filter((c) => c.effect.kind === 'extra_armies' && c.effect.needsCapital)
    const free = greater.filter((c) => c.effect.kind === 'extra_armies' && !c.effect.needsCapital)
    expect(capGated.length).toBeGreaterThan(0)
    expect(free.length).toBeGreaterThan(0)
  })
})
