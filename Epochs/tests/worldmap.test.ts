import { describe, expect, it } from 'vitest'
import { Board } from '../src/shared/board'
import { HeuristicBot } from '../src/shared/heuristicBot'
import { WORLD_AREAS, WORLD_LANDS, WORLD_MAP_DATA, WORLD_SEAS } from '../src/shared/data/board'
import { WORLD_EMPIRES } from '../src/shared/data/empires'
import { Game, type PlayerConfig } from '../src/shared/game'
import type { LandId } from '../src/shared/types'

const byId = new Map(WORLD_LANDS.map((l) => [l.id, l]))
const seaSet = new Set(WORLD_SEAS)
const TERRAINS = new Set(['forest', 'mountain', 'strait', 'great_wall'])

describe('world map — structure', () => {
  it('has the expected scale (100 lands, 13 areas, 8 barren, 18 resource)', () => {
    // The complete board: re-registered to the full scan incl. South America's 6
    // (all 13 areas). Sardinia dropped as a phantom read.
    expect(WORLD_LANDS).toHaveLength(100)
    expect(WORLD_AREAS).toHaveLength(13)
    expect(WORLD_LANDS.filter((l) => l.barren)).toHaveLength(8)
    expect(WORLD_LANDS.filter((l) => l.hasResource)).toHaveLength(18)
  })

  it('has unique land ids and valid areas', () => {
    expect(new Set(WORLD_LANDS.map((l) => l.id)).size).toBe(WORLD_LANDS.length)
    const areaIds = new Set(WORLD_AREAS.map((a) => a.id))
    for (const l of WORLD_LANDS) expect(areaIds.has(l.area as string)).toBe(true)
  })

  it('every area has lands', () => {
    for (const a of WORLD_AREAS) expect(a.lands.length).toBeGreaterThan(0)
  })

  it('land adjacency is symmetric, has no self-loops, and targets exist', () => {
    for (const l of WORLD_LANDS) {
      for (const b of l.borders) {
        expect(b).not.toBe(l.id) // no self-loop
        const other = byId.get(b)
        expect(other, `${l.id} → missing neighbor ${b}`).toBeDefined()
        expect(other!.borders, `${l.id}↔${b} not symmetric`).toContain(l.id)
      }
    }
  })

  it('all seaBorders and difficultTerrain values are valid', () => {
    for (const l of WORLD_LANDS) {
      for (const s of l.seaBorders) expect(seaSet.has(s)).toBe(true)
      for (const t of l.difficultTerrain) expect(TERRAINS.has(t)).toBe(true)
    }
  })

  it('the Old-World mainland is one connected component (Americas are a separate overseas landmass)', () => {
    // adjacency = land borders + shared-sea links
    const adj = new Map<LandId, Set<LandId>>(WORLD_LANDS.map((l) => [l.id, new Set(l.borders)]))
    const bySea = new Map<string, LandId[]>()
    for (const l of WORLD_LANDS) for (const s of l.seaBorders) {
      if (!bySea.has(s)) bySea.set(s, [])
      bySea.get(s)!.push(l.id)
    }
    for (const mem of bySea.values()) for (const a of mem) for (const b of mem) if (a !== b) adj.get(a)!.add(b)

    // The Americas are reachable only by sea (navigation TBD), so they're an
    // expected separate component. Assert the OLD-WORLD mainland is fully connected.
    const OVERSEAS = new Set(['north_america', 'south_america', 'australia', 'africa'])
    const byId = new Map(WORLD_LANDS.map((l) => [l.id, l]))
    const onMainland = (id: LandId): boolean => {
      const l = byId.get(id)!
      return !l.barren && !OVERSEAS.has(l.area as string)
    }
    const mainland = WORLD_LANDS.filter((l) => onMainland(l.id)).map((l) => l.id)
    const seen = new Set<LandId>([mainland[0]])
    const stack = [mainland[0]]
    while (stack.length) {
      const c = stack.pop()!
      for (const n of adj.get(c)!) if (onMainland(n) && !seen.has(n)) {
        seen.add(n)
        stack.push(n)
      }
    }
    expect(seen.size).toBe(mainland.length)
  })
})

describe('world empires', () => {
  it('has 49 empires, exactly 7 per epoch', () => {
    expect(WORLD_EMPIRES).toHaveLength(49)
    for (let e = 1; e <= 7; e++) {
      expect(WORLD_EMPIRES.filter((c) => c.epoch === e)).toHaveLength(7)
    }
  })

  it('every empire starts on a real, non-barren land and sails valid seas', () => {
    for (const c of WORLD_EMPIRES) {
      const land = byId.get(c.startLand)
      expect(land, `${c.name} → missing start land ${c.startLand}`).toBeDefined()
      expect(land!.barren, `${c.name} starts on barren ${c.startLand}`).toBe(false)
      if (!('all' in c.navigation)) {
        for (const s of c.navigation.seas) expect(seaSet.has(s)).toBe(true)
      }
    }
  })
})

describe('a full game on the real world map', () => {
  const play = (seed: number) => {
    const board = new Board(WORLD_MAP_DATA)
    const players: PlayerConfig[] = ['P1', 'P2', 'P3', 'P4'].map((id) => ({
      id,
      name: id,
      bot: new HeuristicBot({ name: id, difficulty: 'medium' }),
    }))
    const game = new Game({ board, deck: WORLD_EMPIRES, players, seed })
    const result = game.run()
    return { game, result }
  }

  it('completes with a ranked winner and respects board invariants', () => {
    const { game, result } = play(1)
    expect(result.epochsPlayed).toBe(7)
    expect(result.standings[0].vp).toBeGreaterThan(0)

    const armiesPerLand = new Map<LandId, number>()
    const monumentsPerLand = new Map<LandId, number>()
    for (const p of game.state.pieces) {
      if (p.kind === 'army') {
        armiesPerLand.set(p.land, (armiesPerLand.get(p.land) ?? 0) + 1)
        expect(byId.get(p.land)!.barren, `army on barren ${p.land}`).toBe(false)
      } else if (p.kind === 'monument') {
        monumentsPerLand.set(p.land, (monumentsPerLand.get(p.land) ?? 0) + 1)
      }
    }
    for (const [, n] of armiesPerLand) expect(n).toBeLessThanOrEqual(3) // up to 3 armies stack
    for (const [, n] of monumentsPerLand) expect(n).toBeLessThanOrEqual(1)
  })

  it('is deterministic from the seed', () => {
    expect(play(3).result.standings).toEqual(play(3).result.standings)
  })
})
