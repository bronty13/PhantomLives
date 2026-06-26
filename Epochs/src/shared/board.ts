// A queryable wrapper over a MapData (lands + areas + seas). Precomputes the
// sea→lands index so the engine can ask "which lands border this sea?" cheaply.
// Pure data; no Electron/DOM. The fixture board and (later) the real board both
// just supply a MapData.

import type { AreaDef, AreaId, Land, LandId, MapData, SeaId } from './types'

export class Board {
  readonly lands: Map<LandId, Land>
  readonly areas: Map<AreaId, AreaDef>
  readonly seas: SeaId[]
  private readonly seaToLands: Map<SeaId, LandId[]>

  constructor(data: MapData) {
    this.lands = new Map(data.lands.map((l) => [l.id, l]))
    this.areas = new Map(data.areas.map((a) => [a.id, a]))
    this.seas = [...data.seas]
    this.seaToLands = new Map()
    for (const l of data.lands) {
      for (const s of l.seaBorders) {
        const arr = this.seaToLands.get(s) ?? []
        arr.push(l.id)
        this.seaToLands.set(s, arr)
      }
    }
  }

  land(id: LandId): Land | undefined {
    return this.lands.get(id)
  }

  areaOf(id: LandId): AreaId | null {
    return this.lands.get(id)?.area ?? null
  }

  /** Bound resolver, handy to pass to scoring functions. */
  readonly areaOfFn = (id: LandId): AreaId | null => this.areaOf(id)

  isBarren(id: LandId): boolean {
    return this.lands.get(id)?.barren ?? false
  }

  neighbors(id: LandId): LandId[] {
    return this.lands.get(id)?.borders ?? []
  }

  landsOnSea(sea: SeaId): LandId[] {
    return this.seaToLands.get(sea) ?? []
  }

  get areaIds(): AreaId[] {
    return [...this.areas.keys()]
  }

  get allLandIds(): LandId[] {
    return [...this.lands.keys()]
  }
}
