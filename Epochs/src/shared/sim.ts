// Headless game runner — plays a full Epochs game with no UI, for testing,
// AI tuning, and balance studies. Pure engine; safe to import anywhere.

import { Board } from './board'
import { GreedyStubBot } from './bot'
import { FIXTURE_EMPIRES } from './data/fixtureEmpires'
import { FIXTURE_MAP_DATA } from './data/fixtureMap'
import { Game, type GameResult, type PlayerConfig } from './game'

export interface HeadlessOptions {
  seed?: number
  players?: number
}

/** Run one full fixture game with `players` GreedyStubBots from a seed. */
export function runHeadlessGame(opts: HeadlessOptions = {}): GameResult {
  const seed = opts.seed ?? 1
  const n = opts.players ?? 4
  const board = new Board(FIXTURE_MAP_DATA)
  const players: PlayerConfig[] = Array.from({ length: n }, (_, i) => ({
    id: `P${i + 1}`,
    name: `Player ${i + 1}`,
    bot: new GreedyStubBot(`Greedy${i + 1}`),
  }))
  return new Game({ board, deck: FIXTURE_EMPIRES, players, seed }).run()
}

/** Pretty one-block summary of a finished game. */
export function formatResult(r: GameResult): string {
  const lines = [`Winner: ${r.winner}  (epochs played: ${r.epochsPlayed})`]
  for (const s of r.standings) {
    lines.push(
      `  ${s.name.padEnd(10)} ${String(s.vp).padStart(4)} VP  ` +
        `pre-eminence=[${s.preeminence.join(',')}]`,
    )
  }
  return lines.join('\n')
}
