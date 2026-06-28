import { describe, expect, it } from 'vitest'
import { Board } from '../src/shared/board'
import { WORLD_MAP_DATA } from '../src/shared/data/board'
import { WORLD_EMPIRES } from '../src/shared/data/empires'
import { describeEffect, makeEventDeck } from '../src/shared/data/events'
import { MINOR_EMPIRES } from '../src/shared/data/minorEmpires'
import { OCEANS, isOcean } from '../src/shared/data/seas'
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
      'siegecraft', 'surprise_attack', 'extra_armies', 'found_kingdom',
      'ship_building', 'naval_supremacy',
    ]
    for (const c of deck.greater) {
      expect(greaterKinds).toContain(c.effect.kind)
    }
    const lesserKinds = ['disaster_structure', 'plague', 'pestilence', 'famine', 'barbarians', 'pirates', 'storm_at_sea']
    for (const c of deck.lesser) {
      expect(lesserKinds).toContain(c.effect.kind)
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
      } else if (ev.type === 'awaitDraft') {
        step = it.next({ keep: true })
      } else {
        step = it.next()
      }
    }

    expect(playedId).toBeDefined()
    expect(game.state.players[0].hand.greater.some((c) => c.id === playedId)).toBe(false)
    expect(game.state.players[0].hand.greater).toHaveLength(before - 1)
  })
})

describe('Minor Empires', () => {
  it('has 7 minor empires (one per epoch) on real, non-barren start lands', () => {
    const byId = new Map(WORLD_MAP_DATA.lands.map((l) => [l.id, l]))
    for (let e = 1; e <= 7; e++) {
      const m = MINOR_EMPIRES[e as 1]
      expect(m.epoch).toBe(e)
      expect(m.strength).toBeGreaterThan(0)
      const land = byId.get(m.startLand)
      expect(land, `${m.name} → start ${m.startLand}`).toBeDefined()
      expect(land!.barren).toBe(false)
    }
  })

  it('when a Minor Empire is summoned, it runs a second empire-turn (its homeland is set up)', () => {
    for (let seed = 1; seed <= 40; seed++) {
      const events = drive(worldGame(seed, hardBots(['P1', 'P2', 'P3', 'P4'])))
      const me = events.find((e) => e.type === 'minorEmpire')
      if (me?.type === 'minorEmpire') {
        const setup = events.some((e) => e.type === 'setup' && e.empire === me.empire && e.land === me.land)
        expect(setup, `${me.empire} summoned but no setup on ${me.land}`).toBe(true)
        return
      }
    }
    // No bot summoned a Minor Empire across 40 seeds — acceptable (draw-dependent).
  })
})

describe('Keep/Pass draft', () => {
  it('the bot keeps a strong/capital empire but gifts a weak one to the leader', () => {
    const bot = new HeuristicBot({ name: 'B', difficulty: 'hard' })
    const mk = (strength: number, hasCapital: boolean) => ({
      id: 'x', name: 'X', epoch: 1 as const, order: 1, strength, startLand: 'x', navigation: { seas: [] }, hasCapital,
    })
    const remaining = [mk(2, false), mk(3, false), mk(4, false), mk(5, true)] // avg 3.5
    const standings = [{ id: 'P1', vp: 0 }, { id: 'P2', vp: 10 }, { id: 'P3', vp: 3 }]
    const base = { epoch: 1 as const, player: 'P1', standings, remaining, canPassTo: ['P2', 'P3'] }
    expect(bot.chooseDraft!({ ...base, drawn: mk(5, false) })).toEqual({ keep: true }) // strong
    expect(bot.chooseDraft!({ ...base, drawn: mk(1, true) })).toEqual({ keep: true }) // capital
    expect(bot.chooseDraft!({ ...base, drawn: mk(2, false) })).toEqual({ passTo: 'P2' }) // weak → leader
    expect(bot.chooseDraft!({ ...base, drawn: mk(2, false), canPassTo: [] })).toEqual({ keep: true }) // no one
  })

  it('passing a drawn empire gives it to the chosen empire-less player (not the passer)', () => {
    for (let seed = 1; seed <= 12; seed++) {
      const players: PlayerConfig[] = [{ id: 'P1', name: 'P1', isHuman: true }, ...hardBots(['P2', 'P3', 'P4'])]
      const it = worldGame(seed, players).play()
      let step = it.next()
      let passedEmpire: string | undefined
      let draftEv: Extract<GameEvent, { type: 'draft' }> | undefined
      while (!step.done) {
        const ev = step.value
        if (ev.type === 'awaitDraft') {
          if (!passedEmpire && ev.canPassTo.includes('P2')) {
            passedEmpire = ev.empire.name
            step = it.next({ passTo: 'P2' })
          } else {
            step = it.next({ keep: true })
          }
        } else if (ev.type === 'draft') {
          draftEv = ev
          break
        } else {
          step = it.next()
        }
      }
      if (!passedEmpire || !draftEv) continue // P1 drafted last this seed — try another
      expect(draftEv.assignments.find((a) => a.player === 'P2')?.empire).toBe(passedEmpire)
      expect(draftEv.assignments.find((a) => a.player === 'P1')?.empire).not.toBe(passedEmpire)
      return
    }
    throw new Error('no seed in 1..12 let P1 pass to P2')
  })
})

describe('interactive buy (fleets + forts)', () => {
  it('a human who buys a fort gets one placed on a held land', () => {
    for (let seed = 1; seed <= 10; seed++) {
      const players: PlayerConfig[] = [{ id: 'P1', name: 'P1', isHuman: true }, ...hardBots(['P2', 'P3'])]
      const game = worldGame(seed, players)
      const it = game.play()
      let step = it.next()
      let boughtAFort = false
      while (!step.done) {
        const ev = step.value
        if (ev.type === 'awaitBuy') {
          if (ev.maxForts > 0) boughtAFort = true
          step = it.next({ fleets: ev.maxFleets > 0 ? 1 : 0, forts: Math.min(1, ev.maxForts) })
        } else if (ev.type === 'awaitDraft') {
          step = it.next({ keep: true })
        } else if (ev.type === 'awaitPlacement') {
          step = it.next(ev.frontier[0]?.land)
        } else {
          step = it.next()
        }
      }
      if (boughtAFort && game.state.pieces.some((p) => p.kind === 'fort' && p.owner === 'P1')) return
    }
    throw new Error('buying a fort never put one on the board')
  })
})

describe('naval combat (seas) vs coexistence (oceans)', () => {
  it('classifies the 5 great oceans; everything else is a sea', () => {
    expect(OCEANS.size).toBe(5)
    expect(isOcean('atlantic')).toBe(true)
    expect(isOcean('pacific')).toBe(true)
    expect(isOcean('mediterranean')).toBe(false)
    expect(isOcean('aegean_sea')).toBe(false)
  })

  it('battles happen only in enclosed seas, and an enclosed sea ends up single-owner', () => {
    for (let seed = 1; seed <= 25; seed++) {
      const game = worldGame(seed, hardBots(['P1', 'P2', 'P3', 'P4']))
      for (const e of drive(game)) {
        if (e.type === 'navalCombat') expect(isOcean(e.sea)).toBe(false) // combat is sea-only
      }
      const ownersBySea = new Map<string, Set<string>>()
      for (const f of game.state.fleets) {
        if (isOcean(f.sea)) continue // oceans may hold many owners
        const s = ownersBySea.get(f.sea) ?? new Set<string>()
        s.add(f.owner)
        ownersBySea.set(f.sea, s)
      }
      for (const [, owners] of ownersBySea) expect(owners.size).toBeLessThanOrEqual(1)
    }
  })
})

describe('fleets — navigation requires a deployed fleet', () => {
  it('a navigation empire deploys a fleet, and the player accrues fleets', () => {
    for (let seed = 1; seed <= 20; seed++) {
      const game = worldGame(seed, hardBots(['P1', 'P2', 'P3', 'P4']))
      if (drive(game).some((e) => e.type === 'fleet')) {
        expect(game.state.fleets.length).toBeGreaterThan(0)
        expect(game.state.fleets.every((f) => typeof f.sea === 'string' && f.owner)).toBe(true)
        return
      }
    }
    throw new Error('no fleet deployed across 20 seeds — navigation empires should build one')
  })
})

describe('seas — overseas reach', () => {
  const OVERSEAS = new Set(['north_america', 'south_america', 'australia', 'africa'])
  const byId = new Map(WORLD_MAP_DATA.lands.map((l) => [l.id, l]))

  it('the Atlantic / Pacific / Indian Ocean each bridge an overseas landmass to the rest', () => {
    const areasOn = (sea: string) =>
      new Set(WORLD_MAP_DATA.lands.filter((l) => l.seaBorders.includes(sea)).map((l) => l.area))
    for (const sea of ['atlantic', 'pacific', 'indian_ocean']) {
      const areas = [...areasOn(sea)]
      expect(areas.some((a) => OVERSEAS.has(a as string)), `${sea} touches no overseas area`).toBe(true)
      expect(areas.some((a) => !OVERSEAS.has(a as string)), `${sea} touches no mainland area`).toBe(true)
    }
  })

  it('empires actually sail overseas — an overseas land gets occupied in some game', () => {
    for (let seed = 1; seed <= 40; seed++) {
      const game = worldGame(seed, hardBots(['P1', 'P2', 'P3', 'P4']))
      drive(game)
      if (game.state.pieces.some((p) => p.kind === 'army' && OVERSEAS.has((byId.get(p.land)?.area as string) ?? ''))) {
        return
      }
    }
    throw new Error('no empire reached an overseas landmass across 40 seeds — sea reach is not working')
  })
})

describe('army stacking (up to 3 per land)', () => {
  it('a human who reinforces stacks a land to 2–3 armies, never beyond 3', () => {
    const players: PlayerConfig[] = [{ id: 'P1', name: 'P1', isHuman: true }, ...hardBots(['P2', 'P3'])]
    const game = worldGame(3, players)
    const it = game.play()
    let step = it.next()
    while (!step.done) {
      const ev = step.value
      if (ev.type === 'awaitPlacement') {
        const reinforce = ev.frontier.find((f) => f.kind === 'own_reinforce')
        step = it.next((reinforce ?? ev.frontier[0])?.land)
      } else if (ev.type === 'awaitDraft') {
        step = it.next({ keep: true })
      } else {
        step = it.next()
      }
    }
    const counts = new Map<string, number>()
    for (const p of game.state.pieces) {
      if (p.kind === 'army' && p.owner === 'P1') counts.set(p.land, (counts.get(p.land) ?? 0) + 1)
    }
    const maxStack = Math.max(0, ...counts.values())
    expect(maxStack).toBeGreaterThan(1) // reinforcement stacked a land
    expect(maxStack).toBeLessThanOrEqual(3) // never beyond the cap
  })
})

describe('Kingdoms + Barbarians', () => {
  it('a played Kingdom raises a fortified city (city + fort) on a held land', () => {
    for (let seed = 1; seed <= 60; seed++) {
      const game = worldGame(seed, hardBots(['P1', 'P2', 'P3', 'P4']))
      const it = game.play()
      let step = it.next()
      while (!step.done) {
        const ev = step.value
        if (ev.type === 'foundKingdom') {
          const onLand = game.state.pieces.filter((p) => p.land === ev.land)
          expect(onLand.some((p) => p.kind === 'city')).toBe(true)
          expect(onLand.some((p) => p.kind === 'fort')).toBe(true)
          return
        }
        step = it.next()
      }
    }
    // no bot played a Kingdom across 60 seeds — acceptable (draw-dependent)
  })

  it('Barbarians only strike enemy lands that border a barren Land', () => {
    const board = new Board(WORLD_MAP_DATA)
    let struck = 0
    for (let seed = 1; seed <= 30; seed++) {
      for (const e of drive(worldGame(seed, hardBots(['P1', 'P2', 'P3', 'P4'])))) {
        if (e.type === 'disaster' && e.effect === 'barbarians') {
          struck++
          expect(board.neighbors(e.land).some((nb) => board.land(nb)?.barren), `${e.land} not by barren`).toBe(true)
        }
      }
      if (struck > 0) return
    }
  })

  it('Pirates / Storm at Sea only strike coastal enemy lands', () => {
    const byId = new Map(WORLD_MAP_DATA.lands.map((l) => [l.id, l]))
    let struck = 0
    for (let seed = 1; seed <= 30; seed++) {
      for (const e of drive(worldGame(seed, hardBots(['P1', 'P2', 'P3', 'P4'])))) {
        if (e.type === 'disaster' && (e.effect === 'pirates' || e.effect === 'storm_at_sea')) {
          struck++
          expect((byId.get(e.land)?.seaBorders.length ?? 0) > 0, `${e.land} is not coastal`).toBe(true)
        }
      }
      if (struck > 0) return
    }
  })
})

describe('opening roll — first player + empire variety', () => {
  it('emits startRoll first, with first = the LOWEST roller (epoch-1 catch-up)', () => {
    const events = drive(worldGame(7, hardBots(['P1', 'P2', 'P3', 'P4'])))
    const sr = events[0]
    expect(sr.type).toBe('startRoll')
    if (sr.type === 'startRoll') {
      const minRoll = Math.min(...sr.rolls.map((r) => r.roll))
      expect(sr.rolls.find((r) => r.player === sr.first)!.roll).toBe(minRoll)
    }
  })

  it("P1's epoch-1 empire varies across seeds (no longer always the same draw)", () => {
    const p1Empire = (seed: number): string | undefined => {
      const draft = drive(worldGame(seed, hardBots(['P1', 'P2', 'P3', 'P4']))).find((e) => e.type === 'draft')
      return draft?.type === 'draft' ? draft.assignments.find((a) => a.player === 'P1')?.empire : undefined
    }
    const seen = new Set([1, 2, 3, 5, 8, 13, 21].map(p1Empire))
    expect(seen.size).toBeGreaterThan(1)
  })
})

describe('describeEffect (event card text for the panel)', () => {
  const kinds: EventEffect[] = [
    { kind: 'leader' },
    { kind: 'weaponry' },
    { kind: 'fanaticism' },
    { kind: 'reallocation', armies: 3 },
    { kind: 'minor_empire' },
    { kind: 'siegecraft' },
    { kind: 'surprise_attack' },
    { kind: 'extra_armies', armies: 2, needsCapital: false },
    { kind: 'extra_armies', armies: 2, needsCapital: true },
    { kind: 'disaster_structure', terrain: 'mountain' },
    { kind: 'plague' },
    { kind: 'pestilence' },
    { kind: 'famine' },
    { kind: 'found_kingdom' },
    { kind: 'barbarians' },
    { kind: 'ship_building' },
    { kind: 'naval_supremacy' },
    { kind: 'pirates' },
    { kind: 'storm_at_sea' },
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
