// Epochs — core engine types. Pure data; NO Electron, Node, or DOM imports.
// See docs/SPEC.md for the authoritative rules and the meaning of each field.

export const EPOCHS = [1, 2, 3, 4, 5, 6, 7] as const
export type EpochId = (typeof EPOCHS)[number]

export type PlayerId = string
export type LandId = string
export type AreaId = string
export type SeaId = string

export type TerrainKind = 'forest' | 'mountain' | 'strait' | 'great_wall'

/** A single space on the board. `area === null` marks a Barren Land. */
export interface Land {
  id: LandId
  name: string
  area: AreaId | null
  barren: boolean
  difficultTerrain: TerrainKind[]
  hasResource: boolean
  borders: LandId[]
  seaBorders: SeaId[]
  /** Normalized world-map position (equirectangular, x,y in 0..1) for rendering. */
  x?: number
  y?: number
}

/** A colored scoring region (the 13 Areas). */
export interface AreaDef {
  id: AreaId
  name: string
  lands: LandId[]
  valueByEpoch: Record<EpochId, number>
}

/** Everything needed to build a Board: the lands, the areas, and the seas. */
export interface MapData {
  lands: Land[]
  areas: AreaDef[]
  seas: SeaId[]
}

/** Which water an empire's fleets may use. `all` = full navigation. */
export type Navigation = { all: true } | { seas: SeaId[] }

export interface EmpireCard {
  id: string
  /** OUR descriptive label — never the original card's protected art/text. */
  name: string
  epoch: EpochId
  /** 1..7 intra-epoch draw order (1 is drawn first). */
  order: number
  /** Number of armies the empire deploys. */
  strength: number
  startLand: LandId
  navigation: Navigation
  /** false => Marauder (+1 VP per structure razed). */
  hasCapital: boolean
}

// ── Events (SPEC §11) ───────────────────────────────────────────────────────
export type EventClass = 'greater' | 'lesser'

/** Structured event effect applied to the player's upcoming empire-turn. */
export type EventEffect =
  | { kind: 'leader' } // attacker rolls +1 die this turn
  | { kind: 'weaponry' } // attacker rolls +1 die this turn
  | { kind: 'reallocation'; armies: number } // fleets → extra ground armies
  | { kind: 'minor_empire'; armies: number } // a small extra force (simplified)
  | { kind: 'coins'; coins: number } // Lesser: coins, spent on forts

export interface EventCard {
  id: string
  class: EventClass
  name: string
  effect: EventEffect
}

/** A player's fixed event hand for the whole game (no refills — SPEC §11). */
export interface EventHand {
  greater: EventCard[]
  lesser: EventCard[]
}

export type StructureKind = 'capital' | 'city' | 'monument' | 'fort'
export type PieceKind = 'army' | StructureKind

export interface BoardPiece {
  land: LandId
  kind: PieceKind
  owner: PlayerId | null
  /** Armies are colored by the epoch in which they were placed. */
  epochColor: EpochId
}

/** Victory-point value of each structure when controlled (SPEC §8.3). */
export const STRUCTURE_VP: Record<StructureKind, number> = {
  capital: 2,
  city: 1,
  monument: 1,
  fort: 0,
}
