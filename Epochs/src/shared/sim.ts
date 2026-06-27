// Headless game runner + tournament harness — plays full Epochs games with no
// UI, for AI tuning and balance studies. Pure engine; safe to import anywhere.

import { Board } from './board'
import { GreedyStubBot, RandomBot, type Bot } from './bot'
import { HeuristicBot, type Difficulty } from './heuristicBot'
import { WORLD_MAP_DATA } from './data/board'
import { WORLD_EMPIRES } from './data/empires'
import { Game, type GameResult, type PlayerConfig } from './game'
import { makeRng } from './rng'
import type { EmpireCard, MapData } from './types'

/** Builds a bot for a seat. `seed` lets stochastic bots vary per game. */
export type BotFactory = (name: string, seed: number) => Bot

export const heuristic =
  (difficulty: Difficulty = 'hard'): BotFactory =>
  (name) =>
    new HeuristicBot({ name, difficulty })

export const greedy: BotFactory = (name) => new GreedyStubBot(name)

export const random: BotFactory = (_name, seed) => {
  const rng = makeRng((seed ^ 0x9e3779b9) >>> 0)
  return new RandomBot((n) => rng.nextInt(n))
}

export interface MatchOptions {
  /** Override the map (defaults to the full world). */
  mapData?: MapData
  /** Override the empire deck (defaults to the full 49-empire roster). */
  deck?: EmpireCard[]
}

/** Run one full game with the given per-seat bot factories (world map by default). */
export function runMatch(
  seed: number,
  factories: BotFactory[],
  opts: MatchOptions = {},
): GameResult {
  const board = new Board(opts.mapData ?? WORLD_MAP_DATA)
  const deck = opts.deck ?? WORLD_EMPIRES
  const players: PlayerConfig[] = factories.map((make, i) => ({
    id: `P${i + 1}`,
    name: `P${i + 1}`,
    bot: make(`P${i + 1}`, seed + i * 1009),
  }))
  return new Game({ board, deck, players, seed }).run()
}

export interface HeadlessOptions {
  seed?: number
  players?: number
  difficulty?: Difficulty
}

/** Run one full fixture game with `players` HeuristicBots (default medium). */
export function runHeadlessGame(opts: HeadlessOptions = {}): GameResult {
  const seed = opts.seed ?? 1
  const n = opts.players ?? 4
  const make = heuristic(opts.difficulty ?? 'medium')
  return runMatch(seed, Array.from({ length: n }, () => make))
}

export interface MatchupResult {
  games: number
  wins: number
  winRate: number
}

/**
 * Win rate of the bot seated at `seatIndex` (default 0) across `seeds`,
 * playing the given factory line-up.
 */
export function tournament(
  factories: BotFactory[],
  seeds: number[],
  seatIndex = 0,
): MatchupResult {
  let wins = 0
  for (const seed of seeds) {
    if (runMatch(seed, factories).winner === `P${seatIndex + 1}`) wins++
  }
  return { games: seeds.length, wins, winRate: wins / seeds.length }
}

/** Inclusive integer range [a, b]. */
export function seeds(a: number, b: number): number[] {
  return Array.from({ length: b - a + 1 }, (_, i) => a + i)
}

/** Pretty one-block summary of a finished game. */
export function formatResult(r: GameResult): string {
  const lines = [`Winner: ${r.winner}  (epochs played: ${r.epochsPlayed})`]
  for (const s of r.standings) {
    lines.push(`  ${s.name.padEnd(10)} ${String(s.vp).padStart(4)} VP`)
  }
  return lines.join('\n')
}
