// The game-loop engine (SPEC §3): runs a full 7-epoch game over a Board + an
// empire deck + per-player Bots, deterministically from a seed. Ties together
// combat (combat.ts) and scoring (scoring.ts).
//
// MODELING DECISIONS made here for the playable v0.2 (each flagged in SPEC §16,
// to verify against the manual / 1997 oracle later):
//  - Area scoring counts ALL of a player's armies (any epoch), not just the
//    current-epoch color. Monument building counts only the ACTIVE empire's
//    (current-epoch) armies, per the manual's "Active Empire's armies" wording.
//  - The empire DRAFT is simplified to "lowest-VP player gets the strongest
//    available empire" (captures the catch-up intent without the keep/pass deck).
//  - Events are NOT yet modeled (no hands dealt) — pure expansion + combat.
//  - Fort assaults use combat.ts::resolveAssault's documented interpretation.

import { Board } from './board'
import type { Bot, BotView, EventChoice, EventView, FrontierKind, FrontierOption } from './bot'
import { oddsForContext, resolveAssault, type CombatContext, type CombatResult } from './combat'
import { makeEventDeck } from './data/events'
import { scoreEmpireTurn } from './scoring'
import { makeRng, type Rng } from './rng'
import { EPOCHS } from './types'
import type {
  BoardPiece,
  EmpireCard,
  EpochId,
  EventCard,
  EventHand,
  LandId,
  PlayerId,
} from './types'

const TOTAL_MONUMENTS = 36

export interface PlayerConfig {
  id: PlayerId
  name: string
  /** The AI for this seat. Omit (with `isHuman`) for a human player. */
  bot?: Bot
  isHuman?: boolean
}

export interface PlayerState {
  id: PlayerId
  name: string
  vp: number
  hand: EventHand // fixed for the whole game (SPEC §11)
}

/** Accumulated effects of the events a player plays before its turn. */
export interface TurnEffects {
  attackerBonus: boolean // Leader/Weaponry → attacker +1 die
  bonusArmies: number // Reallocation/Minor Empire → extra armies
}

/** What the driver may pass back into `play()` when resuming a yield. */
export type PlayInput = LandId | EventChoice | undefined

export interface GameState {
  epoch: EpochId
  players: PlayerState[]
  pieces: BoardPiece[]
  monumentsBuilt: number
  rng: Rng
  log: string[]
}

export interface GameResult {
  standings: { id: PlayerId; name: string; vp: number }[]
  winner: PlayerId
  epochsPlayed: number
  log: string[]
}

/**
 * Events emitted by {@link Game.play} as the game advances, so a UI can animate
 * step-by-step. On `awaitPlacement` (a human seat's expansion) the driver must
 * resume the generator with the chosen LandId (or `undefined` to stop placing).
 */
export type GameEvent =
  | { type: 'epochStart'; epoch: EpochId }
  | { type: 'draft'; epoch: EpochId; assignments: { player: PlayerId; empire: string }[] }
  | { type: 'turnStart'; player: PlayerId; empire: string; epoch: EpochId }
  | { type: 'awaitEvents'; player: PlayerId; empire: string; hand: EventHand }
  | { type: 'eventsPlayed'; player: PlayerId; played: string[] }
  | { type: 'setup'; player: PlayerId; land: LandId; empire: string }
  | {
      type: 'awaitPlacement'
      player: PlayerId
      empire: string
      frontier: FrontierOption[]
      remaining: number
    }
  | { type: 'placement'; player: PlayerId; land: LandId; kind: FrontierKind; outcome?: CombatResult }
  | { type: 'score'; player: PlayerId; gained: number; total: number }
  | { type: 'turnEnd'; player: PlayerId }
  | { type: 'epochEnd'; epoch: EpochId }
  | { type: 'gameEnd'; result: GameResult }

function shuffle<T>(xs: T[], rng: Rng): T[] {
  const a = [...xs]
  for (let i = a.length - 1; i > 0; i--) {
    const j = rng.nextInt(i + 1)
    ;[a[i], a[j]] = [a[j], a[i]]
  }
  return a
}

export interface CaptureOutcome {
  pieces: BoardPiece[]
  /** Number of ENEMY structures razed (drives the Marauder bonus). */
  razed: number
}

/**
 * Pure sack/pillage + structure transfer for when `pid` occupies `land`
 * (SPEC §8.1). Only ENEMY structures are affected — the occupier's OWN
 * capital/city are left intact (this is the guard whose absence corrupted VP
 * on `own_old` re-occupation). Returns a NEW pieces array (no mutation).
 *   - enemy capital → city now controlled by `pid` (razed)
 *   - enemy city    → sacked / removed (razed)
 *   - any monument  → transfers to `pid`
 *   - own structures, armies, forts → untouched
 */
export function applyCapture(
  pieces: BoardPiece[],
  land: LandId,
  pid: PlayerId,
): CaptureOutcome {
  let razed = 0
  const out: BoardPiece[] = []
  for (const p of pieces) {
    if (p.land !== land) {
      out.push(p)
      continue
    }
    if (p.kind === 'capital' && p.owner !== pid) {
      out.push({ ...p, kind: 'city', owner: pid })
      razed++
    } else if (p.kind === 'city' && p.owner !== pid) {
      razed++ // enemy city sacked → dropped
    } else if (p.kind === 'monument') {
      out.push({ ...p, owner: pid })
    } else {
      out.push(p) // own capital/city, army, or fort — untouched here
    }
  }
  return { pieces: out, razed }
}

export class Game {
  readonly board: Board
  readonly state: GameState
  private readonly empiresByEpoch: Map<EpochId, EmpireCard[]>
  private readonly bots: Map<PlayerId, Bot>
  private readonly prevEmpireOrder = new Map<PlayerId, number>()
  private readonly seed: number
  private readonly humanSeats: Set<PlayerId>

  constructor(opts: {
    board: Board
    deck: EmpireCard[]
    players: PlayerConfig[]
    seed: number
  }) {
    this.seed = opts.seed
    this.board = opts.board
    this.bots = new Map(
      opts.players.filter((p) => p.bot).map((p) => [p.id, p.bot as Bot]),
    )
    this.humanSeats = new Set(opts.players.filter((p) => p.isHuman).map((p) => p.id))
    this.empiresByEpoch = new Map(EPOCHS.map((e) => [e, [] as EmpireCard[]]))
    for (const card of opts.deck) this.empiresByEpoch.get(card.epoch)?.push(card)

    const rng = makeRng(opts.seed)
    this.state = {
      epoch: 1,
      players: opts.players.map((p) => ({
        id: p.id,
        name: p.name,
        vp: 0,
        hand: { greater: [], lesser: [] },
      })),
      pieces: [],
      monumentsBuilt: 0,
      rng,
      log: [],
    }
    this.dealEvents(rng)
  }

  /** Deal each player a fixed hand of 3 Greater + 7 Lesser events (SPEC §11). */
  private dealEvents(rng: Rng): void {
    const deck = makeEventDeck()
    const greater = shuffle(deck.greater, rng)
    const lesser = shuffle(deck.lesser, rng)
    let gi = 0
    let li = 0
    for (const p of this.state.players) {
      p.hand = { greater: greater.slice(gi, gi + 3), lesser: lesser.slice(li, li + 7) }
      gi += 3
      li += 7
    }
  }

  // ── public entry ────────────────────────────────────────────────────────
  /** Play the whole game to completion (all-bot; drains {@link play}). */
  run(): GameResult {
    const it = this.play()
    let step = it.next()
    while (!step.done) step = it.next()
    return step.value
  }

  /**
   * Step-driven game loop. Yields a GameEvent after each action; for a human
   * seat's expansion it yields `awaitPlacement` and must be resumed via
   * `.next(landId)` (or `.next(undefined)` to stop placing). `run()` drains it.
   */
  *play(): Generator<GameEvent, GameResult, PlayInput> {
    for (const epoch of EPOCHS) {
      this.state.epoch = epoch
      yield { type: 'epochStart', epoch }
      const order = this.drawOrder()
      const assignment = this.draft(epoch, order)
      yield {
        type: 'draft',
        epoch,
        assignments: order
          .filter((pid) => assignment.has(pid))
          .map((pid) => ({ player: pid, empire: assignment.get(pid)!.name })),
      }
      for (const pid of order) {
        const empire = assignment.get(pid)
        if (!empire) continue
        yield* this.playEmpireTurnGen(pid, empire)
        this.prevEmpireOrder.set(pid, empire.order)
      }
      yield { type: 'epochEnd', epoch }
    }
    const result = this.finalize()
    yield { type: 'gameEnd', result }
    return result
  }

  private *playEmpireTurnGen(
    pid: PlayerId,
    empire: EmpireCard,
  ): Generator<GameEvent, void, PlayInput> {
    yield { type: 'turnStart', player: pid, empire: empire.name, epoch: this.state.epoch }
    const effects = yield* this.eventPhase(pid, empire)
    this.setupEmpire(pid, empire)
    yield { type: 'setup', player: pid, land: empire.startLand, empire: empire.name }
    yield* this.expandGen(pid, empire, effects)
    this.buildMonuments(pid)
    const gained = scoreEmpireTurn(
      this.state.pieces,
      this.board.areaOfFn,
      this.board.areaIds,
      this.state.epoch,
      pid,
    )
    this.player(pid).vp += gained
    this.log(`E${this.state.epoch} ${pid} (${empire.name}) +${gained} → ${this.player(pid).vp}`)
    yield { type: 'score', player: pid, gained, total: this.player(pid).vp }
    yield { type: 'turnEnd', player: pid }
  }

  private *expandGen(
    pid: PlayerId,
    empire: EmpireCard,
    effects: TurnEffects,
  ): Generator<GameEvent, void, PlayInput> {
    const bot = this.bots.get(pid)
    const isHuman = this.humanSeats.has(pid)
    if (!bot && !isHuman) return
    let remaining = empire.strength - 1 + effects.bonusArmies // first army placed at setup
    while (remaining > 0) {
      const frontier = this.computeFrontier(pid, empire)
      if (frontier.length === 0) break
      let targetId: LandId | undefined
      if (isHuman) {
        targetId = (yield {
          type: 'awaitPlacement',
          player: pid,
          empire: empire.name,
          frontier,
          remaining,
        }) as LandId | undefined
        if (targetId == null) break // human chose to stop placing
      } else {
        // Rebuild the view each iteration: state.pieces is reassigned on every
        // mutation, so a captured snapshot would go stale.
        const view: BotView = {
          board: this.board,
          player: pid,
          epoch: this.state.epoch,
          empire,
          pieces: this.state.pieces,
          standings: this.state.players.map((p) => ({ id: p.id, vp: p.vp })),
          monumentsBuilt: this.state.monumentsBuilt,
          seed: this.seed,
          armiesRemaining: remaining,
        }
        targetId = bot!.chooseExpansion(view, frontier) ?? undefined
        if (targetId == null) break
      }
      const opt = frontier.find((f) => f.land === targetId)
      if (!opt) break // invalid choice — stop placing
      const outcome = this.resolveExpansion(pid, empire, opt, effects.attackerBonus)
      yield { type: 'placement', player: pid, land: opt.land, kind: opt.kind, outcome }
      remaining--
    }
  }

  // ── event phase ───────────────────────────────────────────────────────────
  /** Before a turn, the player may play ≤1 Greater + ≤1 Lesser event (SPEC §11). */
  private *eventPhase(
    pid: PlayerId,
    empire: EmpireCard,
  ): Generator<GameEvent, TurnEffects, PlayInput> {
    const effects: TurnEffects = { attackerBonus: false, bonusArmies: 0 }
    const player = this.player(pid)
    if (player.hand.greater.length === 0 && player.hand.lesser.length === 0) return effects

    let choice: EventChoice | undefined
    if (this.humanSeats.has(pid)) {
      choice = (yield {
        type: 'awaitEvents',
        player: pid,
        empire: empire.name,
        hand: { greater: [...player.hand.greater], lesser: [...player.hand.lesser] },
      }) as EventChoice | undefined
    } else {
      const view: EventView = {
        epoch: this.state.epoch,
        empire,
        player: pid,
        standings: this.state.players.map((p) => ({ id: p.id, vp: p.vp })),
      }
      choice = this.bots.get(pid)?.chooseEvents?.(view, player.hand)
    }

    const played: string[] = []
    if (choice?.greater) this.applyEvent(player, 'greater', choice.greater, effects, played)
    if (choice?.lesser) this.applyEvent(player, 'lesser', choice.lesser, effects, played)
    if (played.length) yield { type: 'eventsPlayed', player: pid, played }
    return effects
  }

  /** Remove a chosen card from the hand and fold its effect into `effects`. */
  private applyEvent(
    player: PlayerState,
    cls: 'greater' | 'lesser',
    cardId: string,
    effects: TurnEffects,
    played: string[],
  ): void {
    const hand = cls === 'greater' ? player.hand.greater : player.hand.lesser
    const idx = hand.findIndex((c) => c.id === cardId)
    if (idx < 0) return // not in hand — ignore
    const [card] = hand.splice(idx, 1)
    this.foldEffect(card, effects)
    played.push(card.name)
  }

  private foldEffect(card: EventCard, effects: TurnEffects): void {
    switch (card.effect.kind) {
      case 'leader':
      case 'weaponry':
        effects.attackerBonus = true
        break
      case 'reallocation':
      case 'minor_empire':
        effects.bonusArmies += card.effect.armies
        break
    }
  }

  // ── phases ──────────────────────────────────────────────────────────────
  /** Lowest VP first; tie-break by previous epoch's empire order, then seating. */
  private drawOrder(): PlayerId[] {
    return [...this.state.players]
      .map((p, i) => ({ p, i }))
      .sort((a, b) => {
        if (a.p.vp !== b.p.vp) return a.p.vp - b.p.vp
        const ao = this.prevEmpireOrder.get(a.p.id) ?? 0
        const bo = this.prevEmpireOrder.get(b.p.id) ?? 0
        if (ao !== bo) return ao - bo
        return a.i - b.i
      })
      .map((x) => x.p.id)
  }

  /** Simplified catch-up draft: strongest available empire to the first drawer. */
  private draft(epoch: EpochId, order: PlayerId[]): Map<PlayerId, EmpireCard> {
    const pool = [...(this.empiresByEpoch.get(epoch) ?? [])].sort(
      (a, b) => b.strength - a.strength,
    )
    const assign = new Map<PlayerId, EmpireCard>()
    // Each empire is drafted at most once; surplus players (more players than
    // empires this epoch) sit out — run()'s `if (!empire) continue` handles it.
    order.forEach((pid, i) => {
      if (i < pool.length) assign.set(pid, pool[i])
    })
    return assign
  }

  private setupEmpire(pid: PlayerId, empire: EmpireCard): void {
    const start = empire.startLand
    this.removeArmyOn(start)
    this.removeFortOn(start)
    this.onOccupy(start, pid, empire) // sack/pillage + transfer any structures
    if (empire.hasCapital) {
      this.addPiece({ land: start, kind: 'capital', owner: pid, epochColor: this.state.epoch })
    }
    this.addPiece({ land: start, kind: 'army', owner: pid, epochColor: this.state.epoch })
  }

  private buildMonuments(pid: PlayerId): void {
    let resourceLands = 0
    for (const p of this.state.pieces) {
      if (p.owner === pid && p.kind === 'army' && p.epochColor === this.state.epoch) {
        if (this.board.land(p.land)?.hasResource) resourceLands++
      }
    }
    let toBuild = Math.floor(resourceLands / 2)
    while (toBuild > 0 && this.state.monumentsBuilt < TOTAL_MONUMENTS) {
      const target = this.monumentPlacement(pid)
      if (!target) break
      this.addPiece({ land: target, kind: 'monument', owner: pid, epochColor: this.state.epoch })
      this.state.monumentsBuilt++
      toBuild--
    }
  }

  private finalize(): GameResult {
    const standings = [...this.state.players]
      .map((p) => ({ id: p.id, name: p.name, vp: p.vp }))
      .sort((a, b) => b.vp - a.vp)
    return {
      standings,
      winner: standings[0].id,
      epochsPlayed: EPOCHS.length,
      log: this.state.log,
    }
  }

  // ── expansion mechanics ───────────────────────────────────────────────────
  private computeFrontier(pid: PlayerId, empire: EmpireCard): FrontierOption[] {
    const epoch = this.state.epoch
    const occupied = new Set<LandId>()
    for (const p of this.state.pieces) {
      if (p.owner === pid && p.kind === 'army' && p.epochColor === epoch) occupied.add(p.land)
    }

    const reachable = new Set<LandId>()
    const landAdjacent = new Set<LandId>()
    for (const land of occupied) {
      for (const nb of this.board.neighbors(land)) {
        if (this.board.isBarren(nb)) continue
        reachable.add(nb)
        landAdjacent.add(nb)
      }
    }
    const nav = empire.navigation
    const navSeas = 'all' in nav ? this.board.seas : nav.seas
    for (const sea of navSeas) {
      for (const l of this.board.landsOnSea(sea)) {
        if (!this.board.isBarren(l)) reachable.add(l)
      }
    }

    const options: FrontierOption[] = []
    for (const land of reachable) {
      const army = this.armyOn(land)
      if (army && army.owner === pid && army.epochColor === epoch) continue // already ours
      const amphibious = !landAdjacent.has(land)
      let kind: FrontierKind
      let odds: FrontierOption['odds']
      if (!army) {
        kind = 'empty'
      } else if (army.owner === pid) {
        kind = 'own_old' // our older-epoch army → free replace
      } else {
        kind = 'enemy'
        odds = oddsForContext(this.combatContext(land, amphibious, false))
      }
      options.push({ land, kind, amphibious, odds })
    }
    return options
  }

  private combatContext(land: LandId, amphibious: boolean, attackerBonus: boolean): CombatContext {
    const terrain = this.board.land(land)?.difficultTerrain ?? []
    const fort = this.state.pieces.some((p) => p.land === land && p.kind === 'fort')
    return {
      attackerBonus,
      difficultTerrain:
        terrain.includes('forest') ||
        terrain.includes('mountain') ||
        terrain.includes('great_wall'),
      strait: terrain.includes('strait') && !amphibious,
      amphibious,
      fort,
    }
  }

  /** Returns the combat outcome for an enemy target, else undefined. */
  private resolveExpansion(
    pid: PlayerId,
    empire: EmpireCard,
    opt: FrontierOption,
    attackerBonus: boolean,
  ): CombatResult | undefined {
    const land = opt.land
    const epoch = this.state.epoch
    if (opt.kind === 'empty') {
      this.onOccupy(land, pid, empire)
      this.addPiece({ land, kind: 'army', owner: pid, epochColor: epoch })
      return undefined
    }
    if (opt.kind === 'own_old') {
      this.removeArmyOn(land)
      this.onOccupy(land, pid, empire)
      this.addPiece({ land, kind: 'army', owner: pid, epochColor: epoch })
      return undefined
    }
    // enemy
    const ctx = this.combatContext(land, opt.amphibious, attackerBonus)
    const res = resolveAssault(this.state.rng, ctx)
    if (res.fortDestroyed) this.removeFortOn(land) // fort fell with the army
    if (res.outcome === 'attacker') {
      this.removeArmyOn(land) // defender removed
      this.removeFortOn(land) // any surviving fort falls with the land
      this.onOccupy(land, pid, empire) // sack/pillage + structure transfer
      this.addPiece({ land, kind: 'army', owner: pid, epochColor: epoch })
    }
    // 'defender': attacker army consumed, board unchanged (ties are rerolled)
    return res.outcome
  }

  /** Apply sack/pillage + structure transfer when `pid` takes `land`. */
  private onOccupy(land: LandId, pid: PlayerId, empire: EmpireCard): void {
    const { pieces, razed } = applyCapture(this.state.pieces, land, pid)
    this.state.pieces = pieces
    if (!empire.hasCapital && razed > 0) {
      this.player(pid).vp += razed // Marauder bonus, enemy structures only (SPEC §5)
    }
  }

  private monumentPlacement(pid: PlayerId): LandId | null {
    const controlledLands = (kind: 'capital' | 'city' | 'army'): LandId[] =>
      this.state.pieces
        .filter(
          (p) =>
            p.owner === pid &&
            p.kind === kind &&
            (kind !== 'army' || p.epochColor === this.state.epoch),
        )
        .map((p) => p.land)

    const hasMonument = (land: LandId): boolean =>
      this.state.pieces.some((p) => p.land === land && p.kind === 'monument')

    for (const kind of ['capital', 'city', 'army'] as const) {
      const lands = controlledLands(kind)
      const open = lands.find((l) => !hasMonument(l))
      if (open) return open
    }
    // every controlled land already carries a monument → unplaceable, so it
    // isn't built (SPEC §8.2 — one monument per land)
    return null
  }

  // ── piece helpers ─────────────────────────────────────────────────────────
  private addPiece(p: BoardPiece): void {
    this.state.pieces.push(p)
  }

  private armyOn(land: LandId): BoardPiece | undefined {
    return this.state.pieces.find((p) => p.land === land && p.kind === 'army')
  }

  private removeArmyOn(land: LandId): void {
    this.state.pieces = this.state.pieces.filter(
      (p) => !(p.land === land && p.kind === 'army'),
    )
  }

  private removeFortOn(land: LandId): void {
    this.state.pieces = this.state.pieces.filter(
      (p) => !(p.land === land && p.kind === 'fort'),
    )
  }

  private player(pid: PlayerId): PlayerState {
    const p = this.state.players.find((x) => x.id === pid)
    if (!p) throw new Error(`unknown player ${pid}`)
    return p
  }

  private log(msg: string): void {
    this.state.log.push(msg)
  }
}
