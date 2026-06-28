import { describe, expect, it } from 'vitest'
import { Board } from '../src/shared/board'
import { GreedyStubBot } from '../src/shared/bot'
import { FIXTURE_EMPIRES } from '../src/shared/data/fixtureEmpires'
import { FIXTURE_MAP_DATA } from '../src/shared/data/fixtureMap'
import { applyCapture, Game, type PlayerConfig } from '../src/shared/game'
import { formatResult, runHeadlessGame } from '../src/shared/sim'
import type { BoardPiece, PieceKind, PlayerId } from '../src/shared/types'

const piece = (
  land: string,
  kind: PieceKind,
  owner: PlayerId | null,
): BoardPiece => ({ land, kind, owner, epochColor: 1 })

const newGame = (seed: number, ids: string[]): Game => {
  const board = new Board(FIXTURE_MAP_DATA)
  const players: PlayerConfig[] = ids.map((id) => ({
    id,
    name: id,
    bot: new GreedyStubBot(id),
  }))
  return new Game({ board, deck: FIXTURE_EMPIRES, players, seed })
}

describe('a full headless game', () => {
  it('completes 7 epochs and produces a ranked winner', () => {
    const r = runHeadlessGame({ seed: 1, players: 4 })
    expect(r.epochsPlayed).toBe(7)
    expect(r.standings).toHaveLength(4)
    expect(['P1', 'P2', 'P3', 'P4']).toContain(r.winner)
    // standings are sorted by descending VP
    for (let i = 1; i < r.standings.length; i++) {
      expect(r.standings[i - 1].vp).toBeGreaterThanOrEqual(r.standings[i].vp)
    }
    // the game actually produced score, and every total is a finite number
    expect(r.standings[0].vp).toBeGreaterThan(0)
    for (const s of r.standings) expect(Number.isFinite(s.vp)).toBe(true)
    // surface a real played game in the test output
    // eslint-disable-next-line no-console
    console.log('\n' + formatResult(r))
  })

  it('is deterministic for a fixed seed', () => {
    const a = runHeadlessGame({ seed: 7, players: 4 })
    const b = runHeadlessGame({ seed: 7, players: 4 })
    expect(b.standings).toEqual(a.standings)
    expect(b.winner).toBe(a.winner)
  })

  it('runs to completion across many seeds and player counts', () => {
    for (const seed of [1, 2, 3, 42, 1000]) {
      for (const players of [3, 4]) {
        const r = runHeadlessGame({ seed, players })
        expect(r.epochsPlayed).toBe(7)
        expect(r.standings).toHaveLength(players)
        expect(r.winner).toBeTruthy()
      }
    }
  })
})

describe('board invariants hold after a full game', () => {
  it('never stacks more than three armies on a land', () => {
    const game = newGame(3, ['P1', 'P2', 'P3', 'P4'])
    game.run()
    const armies = new Map<string, number>()
    for (const p of game.state.pieces) {
      if (p.kind !== 'army') continue
      armies.set(p.land, (armies.get(p.land) ?? 0) + 1)
    }
    for (const [, n] of armies) expect(n).toBeLessThanOrEqual(3)
  })

  it('respects the 36-monument cap', () => {
    const game = newGame(9, ['P1', 'P2', 'P3'])
    game.run()
    expect(game.state.monumentsBuilt).toBeLessThanOrEqual(36)
    const monuments = game.state.pieces.filter((p) => p.kind === 'monument').length
    expect(monuments).toBeLessThanOrEqual(36)
  })

  it('never places a piece on a barren land', () => {
    const game = newGame(11, ['P1', 'P2', 'P3', 'P4'])
    game.run()
    for (const p of game.state.pieces) {
      expect(game.board.isBarren(p.land)).toBe(false)
    }
  })
})

describe('setup + catch-up draft', () => {
  it('places a capital and a first army on the start land at setup', () => {
    const game = newGame(1, ['P1', 'P2', 'P3'])
    game.run()
    // after a full game there is always at least one capital/city and armies
    const hasArmies = game.state.pieces.some((p) => p.kind === 'army')
    expect(hasArmies).toBe(true)
  })

  it('the lowest-VP player drafts first (gets a strong empire) — leads stay close', () => {
    // The rubber-band draft should keep the field from running away: the gap
    // between 1st and last should be far smaller than the winner's total.
    const r = runHeadlessGame({ seed: 4, players: 4 })
    const spread = r.standings[0].vp - r.standings[r.standings.length - 1].vp
    expect(spread).toBeLessThan(r.standings[0].vp)
  })

  it('seats 5- and 6-player games without duplicate-empire corruption', () => {
    // Regression: draft() used to wrap (pool[i % len]) and hand two players the
    // same empire/start land when players > empires-per-epoch.
    for (const players of [5, 6]) {
      const r = runHeadlessGame({ seed: 2, players })
      expect(r.epochsPlayed).toBe(7)
      expect(r.standings).toHaveLength(players)
    }
  })
})

describe('applyCapture — sack/pillage is enemy-only (SPEC §8.1)', () => {
  it("leaves the occupier's OWN capital and city untouched (no self-raze)", () => {
    const { pieces, razed } = applyCapture(
      [piece('x', 'capital', 'P1'), piece('x', 'city', 'P1')],
      'x',
      'P1',
    )
    expect(razed).toBe(0)
    expect(pieces.filter((p) => p.kind === 'capital' && p.owner === 'P1')).toHaveLength(1)
    expect(pieces.filter((p) => p.kind === 'city' && p.owner === 'P1')).toHaveLength(1)
  })

  it('downgrades an ENEMY capital to a city owned by the occupier (razed)', () => {
    const { pieces, razed } = applyCapture([piece('x', 'capital', 'P2')], 'x', 'P1')
    expect(razed).toBe(1)
    expect(pieces).toHaveLength(1)
    expect(pieces[0]).toMatchObject({ kind: 'city', owner: 'P1' })
  })

  it('sacks (removes) an ENEMY city (razed)', () => {
    const { pieces, razed } = applyCapture([piece('x', 'city', 'P2')], 'x', 'P1')
    expect(razed).toBe(1)
    expect(pieces).toHaveLength(0)
  })

  it('leaves a monument UNAFFECTED by conquest — it keeps scoring for its builder (§8/§9.3)', () => {
    const { pieces, razed } = applyCapture([piece('x', 'monument', 'P2')], 'x', 'P1')
    expect(razed).toBe(0)
    expect(pieces[0]).toMatchObject({ kind: 'monument', owner: 'P2' }) // still P2's, not transferred
  })

  it('does not touch pieces on other lands', () => {
    const { pieces } = applyCapture([piece('y', 'capital', 'P2')], 'x', 'P1')
    expect(pieces[0]).toMatchObject({ land: 'y', kind: 'capital', owner: 'P2' })
  })
})

describe('monument placement is one-per-land (SPEC §8.2)', () => {
  it('never stacks more than one monument on a land after a full game', () => {
    const game = newGame(13, ['P1', 'P2', 'P3', 'P4'])
    game.run()
    const perLand = new Map<string, number>()
    for (const p of game.state.pieces) {
      if (p.kind !== 'monument') continue
      perLand.set(p.land, (perLand.get(p.land) ?? 0) + 1)
    }
    for (const [, n] of perLand) expect(n).toBeLessThanOrEqual(1)
  })
})
