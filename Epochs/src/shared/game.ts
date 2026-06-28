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
import type { Bot, BotView, DraftView, EventChoice, EventView, FrontierKind, FrontierOption } from './bot'
import { oddsForContext, resolveAssault, type CombatContext, type CombatResult } from './combat'
import { makeEventDeck } from './data/events'
import { MINOR_EMPIRES } from './data/minorEmpires'
import { type ScoreBreakdown, scoreBreakdown } from './scoring'
import { makeRng, type Rng } from './rng'
import { EPOCHS, effectNeedsTarget } from './types'
import type {
  BoardPiece,
  EmpireCard,
  EpochId,
  EventCard,
  EventEffect,
  EventHand,
  FleetPiece,
  LandId,
  PieceKind,
  PlayerId,
  SeaId,
} from './types'
import { areaValue } from './data/areaValues'
import { isOcean } from './data/seas'

const TOTAL_MONUMENTS = 36
const MAX_ARMIES = 3 // no more than three armies may occupy a Land (original rule)
// Naval combat uses the plain dice model — no terrain, fort, or amphibious modifiers.
const NAVAL_CTX: CombatContext = {
  attackerBonus: false,
  attackerKeptBonus: 0,
  attackerWinsTies: false,
  difficultTerrain: false,
  strait: false,
  amphibious: false,
  fort: false,
}

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

/** Accumulated effects of the events a player plays this turn. */
export interface TurnEffects {
  attackerBonus: boolean // Leader → attacker rolls 3 dice
  attackerKeptBonus: number // Weaponry → +1 to each attacker die
  attackerWinsTies: boolean // Fanaticism → attacker wins ties
  bonusArmies: number // Reallocation/Minor Empire/Pop Explosion/Civil Service → extra armies
  ignoreForts: boolean // Siegecraft → forts give no defence vs your attacks
  ignoreTerrain: boolean // Surprise Attack → void difficult-terrain/amphibious defence
  minorEmpire: EmpireCard | null // Minor Empire → a second empire-turn before your main one
  foundKingdom: boolean // Kingdoms → raise a fortified city on one of your lands after expanding
  navigateAll: boolean // Ship Building / Naval Supremacy → sail every sea this turn
}

const emptyTurnEffects = (): TurnEffects => ({
  attackerBonus: false,
  attackerKeptBonus: 0,
  attackerWinsTies: false,
  bonusArmies: 0,
  ignoreForts: false,
  ignoreTerrain: false,
  minorEmpire: null,
  foundKingdom: false,
  navigateAll: false,
})

/** Keep the drawn empire, or pass (gift) it to an empire-less player. */
export type DraftChoice = { keep: true } | { passTo: PlayerId }

/** How to spend Strength: this many fleets + forts; the rest become armies. */
export type BuyChoice = { fleets: number; forts: number }

/** What the driver may pass back into `play()` when resuming a yield. */
export type PlayInput = LandId | EventChoice | DraftChoice | BuyChoice | undefined

export interface GameState {
  epoch: EpochId
  players: PlayerState[]
  pieces: BoardPiece[]
  fleets: FleetPiece[]
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
  | { type: 'startRoll'; rolls: { player: PlayerId; roll: number }[]; first: PlayerId }
  | { type: 'epochStart'; epoch: EpochId }
  | { type: 'draft'; epoch: EpochId; assignments: { player: PlayerId; empire: string }[] }
  | { type: 'turnStart'; player: PlayerId; empire: string; epoch: EpochId }
  | { type: 'awaitEvents'; player: PlayerId; empire: string; hand: EventHand }
  | { type: 'awaitEventTarget'; player: PlayerId; card: string; targets: LandId[] }
  | {
      type: 'awaitDraft'
      player: PlayerId
      epoch: EpochId
      empire: { name: string; strength: number; startLand: LandId; hasCapital: boolean; navigates: boolean }
      canPassTo: PlayerId[]
    }
  | {
      type: 'awaitBuy'
      player: PlayerId
      empire: string
      /** Strength available to spend on fleets/forts (the rest become armies). */
      budget: number
      maxFleets: number
      maxForts: number
    }
  | { type: 'eventsPlayed'; player: PlayerId; played: string[] }
  | { type: 'disaster'; player: PlayerId; card: string; land: LandId; effect: string }
  | { type: 'setup'; player: PlayerId; land: LandId; empire: string }
  | { type: 'minorEmpire'; player: PlayerId; empire: string; land: LandId }
  | { type: 'foundKingdom'; player: PlayerId; land: LandId }
  | { type: 'fleet'; player: PlayerId; sea: SeaId }
  | { type: 'navalCombat'; player: PlayerId; sea: SeaId; won: boolean }
  | { type: 'fortBuilt'; player: PlayerId; land: LandId }
  /** Human seat: pick a sea to deploy a bought fleet into (`battle` = an enemy fleet is there). */
  | { type: 'awaitFleetPlacement'; player: PlayerId; empire: string; seas: { sea: SeaId; battle: boolean }[] }
  /** Human seat: pick one of your lands to build a bought fort on. */
  | { type: 'awaitFortPlacement'; player: PlayerId; empire: string; lands: LandId[] }
  | {
      type: 'awaitPlacement'
      player: PlayerId
      empire: string
      frontier: FrontierOption[]
      remaining: number
    }
  | { type: 'placement'; player: PlayerId; land: LandId; kind: FrontierKind; outcome?: CombatResult }
  | { type: 'score'; player: PlayerId; gained: number; total: number; breakdown: ScoreBreakdown }
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
  private readonly strengthPoints = new Map<PlayerId, number>() // cumulative Empire Strength drafted
  private readonly startRolls = new Map<PlayerId, number>() // opening die roll → epoch-1 order
  private _areaSizes: Map<string, number> | null = null

  /** Non-barren land count of an Area — the Control tier needs "every land". */
  private readonly areaSize = (area: string): number => {
    if (!this._areaSizes) {
      this._areaSizes = new Map()
      for (const [id, def] of this.board.areas) {
        this._areaSizes.set(id, def.lands.filter((l) => !this.board.land(l)?.barren).length)
      }
    }
    return this._areaSizes.get(area) ?? 0
  }
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
      fleets: [],
      monumentsBuilt: 0,
      rng,
      log: [],
    }
    this.dealEvents(rng)
  }

  /** Deal one card from EACH of the 9 colour-piles to every player (SPEC §11 /
   *  original): a hand is one card of each kind — 7 Greater (boons) + 2 Lesser
   *  (disasters). Each pile holds 7, enough for up to 7 players; the rest are boxed. */
  private dealEvents(rng: Rng): void {
    const piles = makeEventDeck().map((pile) => shuffle(pile, rng))
    for (const p of this.state.players) p.hand = { greater: [], lesser: [] }
    for (const pile of piles) {
      this.state.players.forEach((p, i) => {
        const c = pile[i]
        if (!c) return
        if (c.class === 'greater') p.hand.greater.push(c)
        else p.hand.lesser.push(c)
      })
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
    // Opening roll: each player rolls a die; the LOWEST total drafts first in Epoch I
    // (the original's catch-up at the very start). Ties → seating.
    for (const p of this.state.players) this.startRolls.set(p.id, this.state.rng.rollDie())
    const first = [...this.state.players].sort((a, b) => {
      const ra = this.startRolls.get(a.id)!
      const rb = this.startRolls.get(b.id)!
      return ra - rb || this.state.players.indexOf(a) - this.state.players.indexOf(b)
    })[0].id
    yield {
      type: 'startRoll',
      rolls: this.state.players.map((p) => ({ player: p.id, roll: this.startRolls.get(p.id)! })),
      first,
    }
    this.seedSumeria() // neutral Sumerian obstacle, before Epoch I

    for (const epoch of EPOCHS) {
      this.state.epoch = epoch
      yield { type: 'epochStart', epoch }
      const order = this.drawOrder()
      const assignment = yield* this.draftGen(epoch, order)
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
        this.strengthPoints.set(pid, (this.strengthPoints.get(pid) ?? 0) + empire.strength)
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
    // Minor Empire: a full SECOND empire-turn before the main one — its own setup +
    // expansion (no event buffs). Its armies are yours, so they count at scoring.
    if (effects.minorEmpire) {
      const minor = effects.minorEmpire
      yield { type: 'minorEmpire', player: pid, empire: minor.name, land: minor.startLand }
      this.setupEmpire(pid, minor)
      yield { type: 'setup', player: pid, land: minor.startLand, empire: minor.name }
      yield* this.expandGen(pid, minor, emptyTurnEffects())
    }
    this.setupEmpire(pid, empire)
    yield { type: 'setup', player: pid, land: empire.startLand, empire: empire.name }
    yield* this.expandGen(pid, empire, effects)
    // Kingdoms: a fortified city (city + fort) rises on one of your holdings.
    if (effects.foundKingdom) {
      const land = this.bestKingdomLand(pid)
      if (land) {
        this.addPiece({ land, kind: 'city', owner: pid, epochColor: this.state.epoch })
        this.addPiece({ land, kind: 'fort', owner: pid, epochColor: this.state.epoch })
        yield { type: 'foundKingdom', player: pid, land }
      }
    }
    this.buildMonuments(pid)
    const breakdown = scoreBreakdown(
      this.state.pieces,
      this.board.areaOfFn,
      this.board.areaIds,
      this.state.epoch,
      pid,
      this.areaSize,
      this.controlledSeas(pid),
    )
    const gained = breakdown.total
    this.player(pid).vp += gained
    this.log(`E${this.state.epoch} ${pid} (${empire.name}) +${gained} → ${this.player(pid).vp}`)
    yield { type: 'score', player: pid, gained, total: this.player(pid).vp, breakdown }
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

    // ── Buy units: split Strength across fleets / forts / armies ──────────────
    // (The setup army already cost 1.) The human chooses; the bot keeps it simple
    // (one fleet if it navigates — the rule's minimum — and the rest armies).
    const navigates = 'all' in empire.navigation || empire.navigation.seas.length > 0
    const budget = Math.max(0, empire.strength - 1)
    const buy = yield* this.chooseBuy(pid, empire, navigates, budget)
    // Fleets first (they open sea-reach for the army placement that follows)…
    for (let i = 0; i < buy.fleets; i++) yield* this.placeOneFleet(pid, empire)
    let remaining = budget - buy.fleets - buy.forts + effects.bonusArmies
    while (remaining > 0) {
      const frontier = this.computeFrontier(pid, empire, effects.navigateAll)
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
      const outcome = this.resolveExpansion(pid, empire, opt, effects)
      yield { type: 'placement', player: pid, land: opt.land, kind: opt.kind, outcome }
      remaining--
    }
    // …forts last, so they can fortify any land the empire ended up holding.
    for (let i = 0; i < buy.forts; i++) yield* this.placeOneFort(pid, empire)
  }

  // ── event phase ───────────────────────────────────────────────────────────
  /** Before a turn, the player may play ≤1 Greater + ≤1 Lesser event (SPEC §11). */
  private *eventPhase(
    pid: PlayerId,
    empire: EmpireCard,
  ): Generator<GameEvent, TurnEffects, PlayInput> {
    const effects = emptyTurnEffects()
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
        board: this.board,
        pieces: this.state.pieces,
      }
      choice = this.bots.get(pid)?.chooseEvents?.(view, player.hand)
    }

    const played: string[] = []
    // Greater events are never targeted (combat / army buffs) — fold them in.
    if (choice?.greater) {
      const card = this.takeCard(player, 'greater', choice.greater)
      if (card) {
        this.foldEffect(card, effects, empire)
        played.push(card.name)
      }
    }
    // Lesser events may be a targeted disaster (aimed at an enemy Land).
    if (choice?.lesser) {
      const card = this.takeCard(player, 'lesser', choice.lesser)
      if (card && effectNeedsTarget(card.effect)) {
        const targets = this.disasterTargets(card.effect, pid)
        let target =
          choice.lesserTarget && targets.includes(choice.lesserTarget) ? choice.lesserTarget : undefined
        if (target === undefined && this.humanSeats.has(pid) && targets.length > 0) {
          const picked = (yield {
            type: 'awaitEventTarget',
            player: pid,
            card: card.name,
            targets,
          }) as PlayInput
          if (typeof picked === 'string' && targets.includes(picked)) target = picked
        }
        if (target !== undefined) {
          this.resolveDisaster(card.effect, target, pid)
          played.push(card.name)
          yield { type: 'disaster', player: pid, card: card.name, land: target, effect: card.effect.kind }
        }
      } else if (card) {
        this.foldEffect(card, effects, empire)
        played.push(card.name)
      }
    }
    if (played.length) yield { type: 'eventsPlayed', player: pid, played }
    return effects
  }

  /** Remove a chosen card from the player's hand and return it (or null). */
  private takeCard(player: PlayerState, cls: 'greater' | 'lesser', cardId: string): EventCard | null {
    const hand = cls === 'greater' ? player.hand.greater : player.hand.lesser
    const idx = hand.findIndex((c) => c.id === cardId)
    if (idx < 0) return null
    return hand.splice(idx, 1)[0]
  }

  /** Apply a targeted disaster to `land` (docs/AUTHENTIC-RULES §12). */
  private resolveDisaster(effect: EventEffect, land: LandId, pid: PlayerId): void {
    if (effect.kind === 'disaster_structure') {
      // Wreck structures: monument/city/fort destroyed; a capital is reduced to a city.
      this.state.pieces = this.state.pieces.flatMap((p) => {
        if (p.land !== land || p.kind === 'army') return [p]
        if (p.kind === 'capital') return [{ ...p, kind: 'city' as PieceKind }]
        return [] // monument / city / fort destroyed
      })
    } else if (effect.kind === 'plague') {
      // The army on the Land rolls 4 dice; any '1' eliminates it.
      this.rollPlague(land, 4)
    } else if (effect.kind === 'pestilence') {
      // Target army rolls 3 dice; each ADJACENT enemy army rolls 2 (it spreads).
      this.rollPlague(land, 3)
      for (const nb of this.board.neighbors(land)) {
        const a = this.armyOn(nb)
        if (a && a.owner !== pid) this.rollPlague(nb, 2)
      }
    } else if (effect.kind === 'famine') {
      // Every enemy army in the target's whole Area rolls 2 dice; a '1' kills.
      const area = this.board.land(land)?.area
      if (area != null) {
        for (const p of [...this.state.pieces]) {
          if (p.kind === 'army' && p.owner !== pid && this.board.land(p.land)?.area === area) {
            this.rollPlague(p.land, 2)
          }
        }
      }
    } else if (effect.kind === 'barbarians') {
      // A raid from the wastes: sack the Land — raze its top structure AND its army
      // rolls 3 dice (a 1 routs it). The raiders don't stay to hold it.
      this.state.pieces = this.state.pieces.flatMap((p) => {
        if (p.land !== land || p.kind === 'army') return [p]
        if (p.kind === 'capital') return [{ ...p, kind: 'city' as PieceKind }]
        return [] // structure razed
      })
      this.rollPlague(land, 3)
    } else if (effect.kind === 'pirates') {
      // Coastal raid: pillage the structure AND the army rolls 2 dice (a 1 routs it).
      this.state.pieces = this.state.pieces.flatMap((p) => {
        if (p.land !== land || p.kind === 'army') return [p]
        if (p.kind === 'capital') return [{ ...p, kind: 'city' as PieceKind }]
        return [] // structure razed
      })
      this.rollPlague(land, 2)
    } else if (effect.kind === 'storm_at_sea') {
      // A storm wrecks the coastal force: its army rolls 4 dice (a 1 sinks it).
      this.rollPlague(land, 4)
    }
    void pid
  }

  /** The army on `land` rolls `dice` d6; any '1' eliminates it. */
  private rollPlague(land: LandId, dice: number): void {
    // Each army in the stack rolls `dice` d6; any '1' eliminates THAT army.
    const armies = this.armiesOn(land)
    for (let a = 0; a < armies; a++) {
      let killed = false
      for (let i = 0; i < dice; i++) if (this.state.rng.rollDie() === 1) killed = true
      if (killed) this.removeOneArmyOn(land)
    }
  }

  /** Enemy Lands a disaster may legally strike (honours the terrain restriction). */
  private disasterTargets(effect: EventEffect, pid: PlayerId): LandId[] {
    const out = new Set<LandId>()
    for (const p of this.state.pieces) {
      if (p.owner == null || p.owner === pid) continue // aim at opponents
      const land = this.board.land(p.land)
      if (!land) continue
      if (effect.kind === 'disaster_structure') {
        if (p.kind === 'army') continue // needs a structure to wreck
        if (effect.terrain === 'coastal' && land.seaBorders.length === 0) continue
        if (effect.terrain === 'mountain' && !land.difficultTerrain.includes('mountain')) continue
        out.add(p.land)
      } else if (effect.kind === 'plague' || effect.kind === 'pestilence' || effect.kind === 'famine') {
        if (p.kind === 'army') out.add(p.land) // any enemy army is a legal aim point
      } else if (effect.kind === 'barbarians') {
        // Erupts from the wastes: only enemy lands that border a barren Land.
        if (p.kind !== 'army') continue
        if (this.board.neighbors(p.land).some((nb) => this.board.land(nb)?.barren)) out.add(p.land)
      } else if (effect.kind === 'pirates' || effect.kind === 'storm_at_sea') {
        // From the sea: only coastal enemy lands (those bordering a sea).
        if (p.kind === 'army' && land.seaBorders.length > 0) out.add(p.land)
      }
    }
    return [...out]
  }

  private foldEffect(card: EventCard, effects: TurnEffects, empire: EmpireCard): void {
    switch (card.effect.kind) {
      case 'leader':
        effects.attackerBonus = true // attacker rolls 3 dice
        break
      case 'weaponry':
        effects.attackerKeptBonus += 1 // +1 to each attacker die
        break
      case 'fanaticism':
        effects.attackerWinsTies = true // attacker wins ties
        break
      case 'siegecraft':
        effects.ignoreForts = true // forts give no defence vs your attacks
        break
      case 'surprise_attack':
        effects.ignoreTerrain = true // void difficult-terrain/amphibious defence
        break
      case 'reallocation':
        effects.bonusArmies += card.effect.armies
        break
      case 'minor_empire':
        effects.minorEmpire = MINOR_EMPIRES[this.state.epoch] // summoned before the main turn
        break
      case 'extra_armies':
        if (!card.effect.needsCapital || empire.hasCapital) effects.bonusArmies += card.effect.armies
        break
      case 'found_kingdom':
        effects.foundKingdom = true // a fortified city rises after the expansion phase
        break
      case 'ship_building':
        effects.navigateAll = true // sail every sea this turn
        break
      case 'naval_supremacy':
        effects.navigateAll = true // sail every sea …
        effects.ignoreTerrain = true // … and your sea-borne landings ignore terrain/amphibious
        break
    }
  }

  // ── phases ──────────────────────────────────────────────────────────────
  /** Lowest VP first; tie-break by previous epoch's empire order, then the opening
   *  roll (higher first), then seating. In epoch 1 (all tied) the roll decides. */
  private drawOrder(): PlayerId[] {
    return [...this.state.players]
      .map((p, i) => ({ p, i }))
      .sort((a, b) => {
        // fewest cumulative Empire Strength drafts first (catch-up); …
        const sa = this.strengthPoints.get(a.p.id) ?? 0
        const sb = this.strengthPoints.get(b.p.id) ?? 0
        if (sa !== sb) return sa - sb
        if (a.p.vp !== b.p.vp) return b.p.vp - a.p.vp // … ties → highest VP first; …
        const ao = this.prevEmpireOrder.get(a.p.id) ?? 0
        const bo = this.prevEmpireOrder.get(b.p.id) ?? 0
        if (ao !== bo) return ao - bo // … then lowest prior-epoch card number; …
        const ra = this.startRolls.get(a.p.id) ?? 0
        const rb = this.startRolls.get(b.p.id) ?? 0
        if (ra !== rb) return ra - rb // … then the LOWEST opening roll (epoch 1).
        return a.i - b.i
      })
      .map((x) => x.p.id)
  }

  /** Keep/Pass draft (catch-up order): each drafter draws a RANDOM empire (face-down)
   *  and may KEEP it or PASS (gift) it to a player who has none yet — then draws again.
   *  Human seats decide via `awaitDraft`; bots via `chooseDraft`. Surplus players
   *  (fewer empires than players) sit out — run()'s `if (!empire) continue` handles it. */
  private *draftGen(
    epoch: EpochId,
    order: PlayerId[],
  ): Generator<GameEvent, Map<PlayerId, EmpireCard>, PlayInput> {
    const pool = shuffle([...(this.empiresByEpoch.get(epoch) ?? [])], this.state.rng)
    const assign = new Map<PlayerId, EmpireCard>()
    for (const pid of order) {
      while (!assign.has(pid) && pool.length > 0) {
        const top = pool[0]
        const canPassTo = order.filter((p) => p !== pid && !assign.has(p))
        let choice: DraftChoice
        if (this.humanSeats.has(pid) && canPassTo.length > 0) {
          choice = (yield {
            type: 'awaitDraft',
            player: pid,
            epoch,
            empire: {
              name: top.name,
              strength: top.strength,
              startLand: top.startLand,
              hasCapital: top.hasCapital,
              navigates: 'all' in top.navigation || top.navigation.seas.length > 0,
            },
            canPassTo,
          }) as DraftChoice
        } else {
          const view: DraftView = {
            epoch,
            player: pid,
            standings: this.state.players.map((p) => ({ id: p.id, vp: p.vp })),
            drawn: top,
            remaining: pool,
            canPassTo,
          }
          choice = this.bots.get(pid)?.chooseDraft?.(view) ?? { keep: true }
        }
        // Pass only if a valid empire-less recipient was named; otherwise keep.
        if ('passTo' in choice && canPassTo.includes(choice.passTo)) {
          assign.set(choice.passTo, pool.shift()!) // gift it away; pid draws again
        } else {
          assign.set(pid, pool.shift()!)
        }
      }
    }
    return assign
  }

  /** Seed the neutral Sumerians: four white armies spreading out from Lower Tigris at
   *  game start (the original's pre-game obstacle). Owner `null` → they score for no
   *  one and must be conquered like any defender. */
  private seedSumeria(): void {
    const start: LandId = 'lower_tigris'
    if (!this.board.land(start)) return
    const placed = new Set<LandId>()
    const queue: LandId[] = [start]
    while (placed.size < 4 && queue.length) {
      const land = queue.shift()!
      if (placed.has(land) || this.board.isBarren(land) || !this.board.land(land) || this.armyOn(land)) continue
      this.addPiece({ land, kind: 'army', owner: null, epochColor: 1 })
      placed.add(land)
      for (const nb of this.board.neighbors(land)) if (!placed.has(nb)) queue.push(nb)
    }
  }

  private setupEmpire(pid: PlayerId, empire: EmpireCard): void {
    const start = empire.startLand
    this.retreatFromStart(start) // an occupying army RETREATS (it isn't simply destroyed)
    this.removeFortOn(start)
    this.onOccupy(start, pid, empire) // sack/pillage + transfer any structures
    if (empire.hasCapital) {
      this.addPiece({ land: start, kind: 'capital', owner: pid, epochColor: this.state.epoch })
    }
    this.addPiece({ land: start, kind: 'army', owner: pid, epochColor: this.state.epoch })
  }

  /** When a new empire's Start Land is occupied, its armies don't fight — they retreat
   *  (one at a time) to an adjacent Land holding the same owner's same-colour army with
   *  room (≤3, never overseas). Any army with nowhere to go is eliminated. (Original rule.) */
  private retreatFromStart(start: LandId): void {
    const army = this.armyOn(start)
    if (!army) return
    const { owner, epochColor } = army
    let count = this.armiesOn(start)
    while (count > 0) {
      const dest = this.board.neighbors(start).find(
        (nb) =>
          !this.board.isBarren(nb) &&
          this.armiesOn(nb) < MAX_ARMIES &&
          this.state.pieces.some(
            (p) => p.land === nb && p.kind === 'army' && p.owner === owner && p.epochColor === epochColor,
          ),
      )
      this.removeOneArmyOn(start)
      if (dest) this.addPiece({ land: dest, kind: 'army', owner, epochColor }) // else eliminated
      count--
    }
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
  private computeFrontier(pid: PlayerId, empire: EmpireCard, navigateAll = false): FrontierOption[] {
    const epoch = this.state.epoch
    const occupied = new Set<LandId>()
    for (const p of this.state.pieces) {
      if (p.owner === pid && p.kind === 'army' && p.epochColor === epoch) occupied.add(p.land)
    }

    const reachable = new Set<LandId>()
    const landAdjacent = new Set<LandId>()
    for (const land of occupied) {
      reachable.add(land) // our own holding — reinforce it (if not yet at MAX_ARMIES)
      landAdjacent.add(land)
      for (const nb of this.board.neighbors(land)) {
        if (this.board.isBarren(nb)) continue
        reachable.add(nb)
        landAdjacent.add(nb)
      }
    }
    const nav = empire.navigation
    const navSeas = navigateAll || 'all' in nav ? this.board.seas : nav.seas
    for (const sea of navSeas) {
      // sea-reach requires a fleet in that Sea (Ship Building / Naval Supremacy bypass it)
      if (!navigateAll && !this.playerHasFleetIn(sea, pid)) continue
      for (const l of this.board.landsOnSea(sea)) {
        if (!this.board.isBarren(l)) reachable.add(l)
      }
    }

    const options: FrontierOption[] = []
    for (const land of reachable) {
      const army = this.armyOn(land)
      const amphibious = !landAdjacent.has(land)
      let kind: FrontierKind
      let odds: FrontierOption['odds']
      let defenders: number | undefined
      if (!army) {
        kind = 'empty'
      } else if (army.owner === pid && army.epochColor === epoch) {
        if (this.armiesOn(land) >= MAX_ARMIES) continue // stack full
        kind = 'own_reinforce'
      } else if (army.owner === pid) {
        kind = 'own_old' // our older-epoch army → free replace
      } else {
        kind = 'enemy'
        defenders = this.armiesOn(land)
        odds = oddsForContext(this.combatContext(land, amphibious)) // per-round (pre-events)
      }
      options.push({ land, kind, amphibious, odds, defenders })
    }
    return options
  }

  private combatContext(
    land: LandId,
    amphibious: boolean,
    effects?: TurnEffects,
  ): CombatContext {
    const terrain = this.board.land(land)?.difficultTerrain ?? []
    const fort = this.state.pieces.some((p) => p.land === land && p.kind === 'fort')
    const ignoreTerrain = effects?.ignoreTerrain ?? false // Surprise Attack
    return {
      attackerBonus: effects?.attackerBonus ?? false,
      attackerKeptBonus: effects?.attackerKeptBonus ?? 0,
      attackerWinsTies: effects?.attackerWinsTies ?? false,
      difficultTerrain:
        !ignoreTerrain &&
        (terrain.includes('forest') ||
          terrain.includes('mountain') ||
          terrain.includes('great_wall')),
      strait: !ignoreTerrain && terrain.includes('strait') && !amphibious,
      amphibious: amphibious && !ignoreTerrain,
      fort: fort && !(effects?.ignoreForts ?? false), // Siegecraft
    }
  }

  /** Returns the combat outcome for an enemy target, else undefined. */
  private resolveExpansion(
    pid: PlayerId,
    empire: EmpireCard,
    opt: FrontierOption,
    effects: TurnEffects,
  ): CombatResult | undefined {
    const land = opt.land
    const epoch = this.state.epoch
    if (opt.kind === 'empty') {
      this.onOccupy(land, pid, empire)
      this.addPiece({ land, kind: 'army', owner: pid, epochColor: epoch })
      return undefined
    }
    if (opt.kind === 'own_reinforce') {
      this.addPiece({ land, kind: 'army', owner: pid, epochColor: epoch }) // stack up to MAX_ARMIES
      return undefined
    }
    if (opt.kind === 'own_old') {
      this.removeArmyOn(land) // replace the older-epoch stack with one fresh army
      this.onOccupy(land, pid, empire)
      this.addPiece({ land, kind: 'army', owner: pid, epochColor: epoch })
      return undefined
    }
    // enemy — a multi-round assault: the placed army must win one round per defending
    // army; it is repelled on the first round it loses. A fort adds +1 EVERY round and
    // falls only when the last defender is eliminated (it suffers no losses itself).
    const ctx = this.combatContext(land, opt.amphibious, effects)
    let defenders = this.armiesOn(land)
    while (defenders > 0) {
      const res = resolveAssault(this.state.rng, ctx)
      if (res.outcome === 'attacker') {
        this.removeOneArmyOn(land) // one defending army falls
        defenders -= 1
      } else {
        return 'defender' // attacking army repelled; the stack (and its fort) hold
      }
    }
    // every defender eliminated → the land is conquered
    this.removeFortOn(land)
    this.onOccupy(land, pid, empire) // sack/pillage + structure transfer
    this.addPiece({ land, kind: 'army', owner: pid, epochColor: epoch })
    return 'attacker'
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

    // Build order: Capital land, then a City land, then a held Resource land (orig).
    for (const kind of ['capital', 'city'] as const) {
      const open = controlledLands(kind).find((l) => !hasMonument(l))
      if (open) return open
    }
    const resourceLand = controlledLands('army').find(
      (l) => !hasMonument(l) && !!this.board.land(l)?.hasResource,
    )
    if (resourceLand) return resourceLand
    // no eligible land (every capital/city/resource land already has a monument)
    return null
  }

  /** A plain holding (current-epoch army, no city/capital/fort) to raise into a
   *  fortified city for the Kingdoms event; null if every holding is already built up. */
  private bestKingdomLand(pid: PlayerId): LandId | null {
    const built = (l: LandId): boolean =>
      this.state.pieces.some(
        (p) => p.land === l && (p.kind === 'city' || p.kind === 'capital' || p.kind === 'fort'),
      )
    return (
      this.state.pieces
        .filter((p) => p.kind === 'army' && p.owner === pid && p.epochColor === this.state.epoch && !built(p.land))
        .map((p) => p.land)
        .sort()[0] ?? null
    )
  }

  // ── piece helpers ─────────────────────────────────────────────────────────
  private addPiece(p: BoardPiece): void {
    this.state.pieces.push(p)
  }

  private armyOn(land: LandId): BoardPiece | undefined {
    return this.state.pieces.find((p) => p.land === land && p.kind === 'army')
  }

  /** Does `pid` have a fleet in `sea`? (Fleets persist across epochs.) */
  private playerHasFleetIn(sea: SeaId, pid: PlayerId): boolean {
    return this.state.fleets.some((f) => f.sea === sea && f.owner === pid)
  }

  /** Sink one fleet in `sea` that is not `pid`'s (a naval-combat loss for the defender). */
  private removeOneEnemyFleet(sea: SeaId, pid: PlayerId): void {
    const i = this.state.fleets.findIndex((f) => f.sea === sea && f.owner !== pid)
    if (i >= 0) this.state.fleets.splice(i, 1)
  }

  /** Distinct enclosed Seas `pid` controls with a fleet (each scores +1; oceans don't). */
  private controlledSeas(pid: PlayerId): number {
    const seas = new Set<SeaId>()
    for (const f of this.state.fleets) if (f.owner === pid && !isOcean(f.sea)) seas.add(f.sea)
    return seas.size
  }

  /** Decide the fleet/fort split. The human chooses via `awaitBuy`; the bot builds one
   *  fleet if it navigates (the rule's minimum) and no forts. */
  private *chooseBuy(
    pid: PlayerId,
    empire: EmpireCard,
    navigates: boolean,
    budget: number,
  ): Generator<GameEvent, BuyChoice, PlayInput> {
    if (budget <= 0) return { fleets: 0, forts: 0 }
    // Cap fleets at what can actually be PLACED — navigable seas reachable from the
    // empire's homeland — so you can never buy a fleet with nowhere to go.
    const maxFleets = navigates ? Math.min(budget, this.placeableSeas(pid, empire).length) : 0
    const maxForts = budget
    if (this.humanSeats.has(pid)) {
      const choice = (yield {
        type: 'awaitBuy',
        player: pid,
        empire: empire.name,
        budget,
        maxFleets,
        maxForts,
      }) as BuyChoice | undefined
      // Building a fleet is OPTIONAL (the rules never force one — navigation is an
      // ability, used only if you choose to cross a sea this turn).
      const fleets = Math.max(0, Math.min(maxFleets, choice?.fleets ?? 0))
      const forts = Math.max(0, Math.min(maxForts - fleets, choice?.forts ?? 0))
      return { fleets, forts: Math.min(forts, budget - fleets) }
    }
    // The bot builds one fleet when it can navigate — a strategic choice, not a rule.
    return { fleets: navigates && maxFleets >= 1 ? 1 : 0, forts: 0 }
  }

  /** Deploy one fleet into the empire's best navigable sea (with naval combat). */
  /** Seas a fleet may be deployed into now: navigable, bordering a land the empire
   *  holds, and either with room (<2 fleets) or holding an enemy fleet to battle. */
  private placeableSeas(pid: PlayerId, empire: EmpireCard): { sea: SeaId; battle: boolean }[] {
    const navSeas = 'all' in empire.navigation ? this.board.seas : empire.navigation.seas
    const occupied = this.currentLands(pid)
    const out: { sea: SeaId; battle: boolean }[] = []
    for (const sea of navSeas) {
      if (!this.board.landsOnSea(sea).some((l) => occupied.has(l))) continue
      const enemy = !isOcean(sea) && this.state.fleets.some((f) => f.sea === sea && f.owner !== pid)
      const total = this.state.fleets.filter((f) => f.sea === sea).length
      if (enemy) out.push({ sea, battle: true })
      else if (total < 2) out.push({ sea, battle: false })
    }
    return out
  }

  /** Deploy one bought fleet — the human picks the sea (battling an enemy fleet there
   *  if present); the bot takes the highest-value reachable sea. */
  private *placeOneFleet(pid: PlayerId, empire: EmpireCard): Generator<GameEvent, void, PlayInput> {
    const opts = this.placeableSeas(pid, empire)
    if (opts.length === 0) return // nowhere to place — the fleet is forfeit
    let sea: SeaId
    if (this.humanSeats.has(pid)) {
      const pick = (yield {
        type: 'awaitFleetPlacement',
        player: pid,
        empire: empire.name,
        seas: opts,
      }) as SeaId | undefined
      sea = pick && opts.some((o) => o.sea === pick) ? pick : opts[0].sea
    } else {
      const navSeas = 'all' in empire.navigation ? this.board.seas : empire.navigation.seas
      sea = this.bestFleetSea(navSeas, this.currentLands(pid)) ?? opts[0].sea
    }
    yield* this.deployFleetAt(pid, sea)
  }

  /** Resolve a fleet arriving in a specific sea — naval combat if an enemy holds it. */
  private *deployFleetAt(pid: PlayerId, sea: SeaId): Generator<GameEvent, void, PlayInput> {
    const enemyFleets = isOcean(sea)
      ? 0
      : this.state.fleets.filter((f) => f.sea === sea && f.owner !== pid).length
    if (enemyFleets > 0) {
      let defenders = enemyFleets
      while (defenders > 0) {
        const res = resolveAssault(this.state.rng, NAVAL_CTX)
        if (res.outcome === 'attacker') {
          this.removeOneEnemyFleet(sea, pid)
          defenders -= 1
        } else break
      }
      const won = defenders === 0
      if (won) this.state.fleets.push({ sea, owner: pid, epochColor: this.state.epoch })
      yield { type: 'navalCombat', player: pid, sea, won }
    } else if (this.state.fleets.filter((f) => f.sea === sea).length < 2) {
      this.state.fleets.push({ sea, owner: pid, epochColor: this.state.epoch }) // ≤2 per body
      yield { type: 'fleet', player: pid, sea }
    }
  }

  /** Place one bought fort — the human picks the land; the bot takes its seat, else
   *  its highest-value holding. */
  private *placeOneFort(pid: PlayerId, empire: EmpireCard): Generator<GameEvent, void, PlayInput> {
    const hasFort = (l: LandId): boolean =>
      this.state.pieces.some((p) => p.land === l && p.kind === 'fort')
    const lands = [...this.currentLands(pid)].filter((l) => !hasFort(l))
    if (lands.length === 0) return // nowhere to fortify — forfeit
    let land: LandId
    if (this.humanSeats.has(pid)) {
      const pick = (yield {
        type: 'awaitFortPlacement',
        player: pid,
        empire: empire.name,
        lands,
      }) as LandId | undefined
      land = pick && lands.includes(pick) ? pick : this.bestFortLand(pid, lands)
    } else {
      land = this.bestFortLand(pid, lands)
    }
    this.addPiece({ land, kind: 'fort', owner: pid, epochColor: this.state.epoch })
    yield { type: 'fortBuilt', player: pid, land }
  }

  private bestFortLand(pid: PlayerId, lands: LandId[]): LandId {
    const capLand = this.state.pieces.find((p) => p.owner === pid && p.kind === 'capital')?.land
    if (capLand && lands.includes(capLand)) return capLand
    return lands
      .slice()
      .sort(
        (a, b) =>
          areaValue(this.board.land(b)?.area ?? '', this.state.epoch) -
          areaValue(this.board.land(a)?.area ?? '', this.state.epoch),
      )[0]
  }

  /** Lands `pid` holds with a current-epoch army. */
  private currentLands(pid: PlayerId): Set<LandId> {
    const out = new Set<LandId>()
    for (const p of this.state.pieces) {
      if (p.owner === pid && p.kind === 'army' && p.epochColor === this.state.epoch) out.add(p.land)
    }
    return out
  }

  /** Best navigable sea to deploy a fleet into: one that borders a land the empire
   *  already holds, valued by the (mostly overseas) non-barren coast it would unlock. */
  private bestFleetSea(navSeas: SeaId[], occupied: Set<LandId>): SeaId | null {
    let best: SeaId | null = null
    let bestVal = -1
    for (const sea of navSeas) {
      const coast = this.board.landsOnSea(sea)
      if (!coast.some((l) => occupied.has(l))) continue // must touch an occupied land
      let val = 0
      for (const l of coast) {
        const land = this.board.land(l)
        if (land && !land.barren && !occupied.has(l)) val += areaValue(land.area ?? '', this.state.epoch) + 1
      }
      if (val > bestVal) {
        bestVal = val
        best = sea
      }
    }
    return best
  }

  /** Number of armies stacked on a land (0–3). */
  private armiesOn(land: LandId): number {
    let n = 0
    for (const p of this.state.pieces) if (p.land === land && p.kind === 'army') n++
    return n
  }

  /** Remove ONE army from a land (a single combat / disaster loss). */
  private removeOneArmyOn(land: LandId): void {
    const i = this.state.pieces.findIndex((p) => p.land === land && p.kind === 'army')
    if (i >= 0) this.state.pieces.splice(i, 1)
  }

  /** Remove EVERY army from a land (setup clears the Start Land). */
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
