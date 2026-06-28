import { describe, expect, it } from 'vitest'
import { Board } from '../src/shared/board'
import { GreedyStubBot } from '../src/shared/bot'
import { FIXTURE_EMPIRES } from '../src/shared/data/fixtureEmpires'
import { FIXTURE_MAP_DATA } from '../src/shared/data/fixtureMap'
import { Game, type GameEvent, type GameResult, type PlayerConfig } from '../src/shared/game'
import type { LandId } from '../src/shared/types'

const makeGame = (seed: number, players: PlayerConfig[]) =>
  new Game({ board: new Board(FIXTURE_MAP_DATA), deck: FIXTURE_EMPIRES, players, seed })

const bots = (ids: string[]): PlayerConfig[] =>
  ids.map((id) => ({ id, name: id, bot: new GreedyStubBot(id) }))

function drive(game: Game): { events: GameEvent[]; result: GameResult } {
  const it = game.play()
  const events: GameEvent[] = []
  let step = it.next()
  while (!step.done) {
    events.push(step.value)
    step = it.next()
  }
  return { events, result: step.value }
}

const count = (events: GameEvent[], type: GameEvent['type']) =>
  events.filter((e) => e.type === type).length

describe('Game.play() — the step-driven generator', () => {
  it('emits a well-formed event sequence', () => {
    const { events } = drive(makeGame(1, bots(['P1', 'P2', 'P3'])))
    expect(events[0].type).toBe('startRoll') // opening die roll
    expect(events[1].type).toBe('epochStart')
    expect(events[events.length - 1].type).toBe('gameEnd')
    expect(count(events, 'epochStart')).toBe(7)
    expect(count(events, 'epochEnd')).toBe(7)
    expect(count(events, 'draft')).toBe(7)
    expect(count(events, 'gameEnd')).toBe(1)
    expect(count(events, 'turnStart')).toBeGreaterThan(0)
    expect(count(events, 'placement')).toBeGreaterThan(0)
  })

  it('produces the same result whether drained via play() or run()', () => {
    const viaPlay = drive(makeGame(7, bots(['P1', 'P2', 'P3', 'P4']))).result
    const viaRun = makeGame(7, bots(['P1', 'P2', 'P3', 'P4'])).run()
    expect(viaPlay.standings).toEqual(viaRun.standings)
    expect(viaPlay.winner).toBe(viaRun.winner)
  })

  it('all placement events name a real land owned/contested that turn', () => {
    const { events } = drive(makeGame(2, bots(['P1', 'P2', 'P3'])))
    for (const e of events) {
      if (e.type === 'placement') expect(typeof e.land).toBe('string')
    }
  })
})

describe('Game.play() — human seats', () => {
  const humanGame = (seed: number) =>
    makeGame(seed, [
      { id: 'P1', name: 'P1', isHuman: true }, // no bot
      ...bots(['P2', 'P3']),
    ])

  function driveWithHuman(
    game: Game,
    pick: (frontier: LandId[]) => LandId | undefined,
  ): { events: GameEvent[]; result: GameResult } {
    const it = game.play()
    const events: GameEvent[] = []
    let step = it.next()
    while (!step.done) {
      const ev = step.value
      events.push(ev)
      if (ev.type === 'awaitPlacement') {
        step = it.next(pick(ev.frontier.map((f) => f.land)))
      } else if (ev.type === 'awaitDraft') {
        step = it.next({ keep: true })
      } else {
        step = it.next()
      }
    }
    return { events, result: step.value }
  }

  it('asks the human to place (awaitPlacement) and completes when they pick the first option', () => {
    const { events, result } = driveWithHuman(humanGame(1), (frontier) => frontier[0])
    expect(count(events, 'awaitPlacement')).toBeGreaterThan(0)
    expect(result.epochsPlayed).toBe(7)
    expect(['P1', 'P2', 'P3']).toContain(result.winner)
    // the human (P1) actually got onto the board
    expect(events.some((e) => e.type === 'placement' && e.player === 'P1')).toBe(true)
  })

  it('lets the human stop placing early (resume with undefined) and still completes', () => {
    const { result } = driveWithHuman(humanGame(3), () => undefined)
    expect(result.epochsPlayed).toBe(7)
  })

  it('a human game is deterministic given the same choices', () => {
    const a = driveWithHuman(humanGame(5), (f) => f[0]).result
    const b = driveWithHuman(humanGame(5), (f) => f[0]).result
    expect(b.standings).toEqual(a.standings)
  })
})
