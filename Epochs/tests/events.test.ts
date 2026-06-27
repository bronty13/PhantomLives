import { describe, expect, it } from 'vitest'
import { Board } from '../src/shared/board'
import { WORLD_MAP_DATA } from '../src/shared/data/board'
import { WORLD_EMPIRES } from '../src/shared/data/empires'
import { makeEventDeck } from '../src/shared/data/events'
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
  it('has enough Greater for 6 players (>= 18); Lesser empty pending the rebuild', () => {
    expect(deck.greater.length).toBeGreaterThanOrEqual(18)
    expect(deck.lesser.length).toBe(0) // authentic 9-pile deck rebuilt in task #29
  })
  it('Greater cards are the implemented kinds; no Coins (wrong-edition, removed)', () => {
    for (const c of deck.greater) {
      expect(['leader', 'weaponry', 'fanaticism', 'reallocation', 'minor_empire']).toContain(
        c.effect.kind,
      )
    }
    expect(deck.lesser).toHaveLength(0)
  })
})

describe('dealing hands', () => {
  it('gives each player 3 Greater (Lesser empty for now), no shared cards (SPEC §11)', () => {
    const game = worldGame(1, hardBots(['P1', 'P2', 'P3', 'P4']))
    const seen = new Set<string>()
    for (const p of game.state.players) {
      expect(p.hand.greater).toHaveLength(3)
      expect(p.hand.lesser).toHaveLength(0)
      for (const c of [...p.hand.greater, ...p.hand.lesser]) {
        expect(seen.has(c.id), `duplicate card ${c.id}`).toBe(false)
        seen.add(c.id)
      }
    }
  })
})

describe('events in a full game', () => {
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
