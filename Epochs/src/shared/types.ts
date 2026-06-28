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
/** Where a structure-wrecking disaster may strike (docs/AUTHENTIC-RULES §12). */
export type DisasterTerrain = 'coastal' | 'mountain' | 'any' // Flood / Volcano / Fire

export type EventEffect =
  | { kind: 'leader' } // attacker rolls 3 dice this turn
  | { kind: 'weaponry' } // +1 to each attacker die this turn
  | { kind: 'fanaticism' } // attacker wins all ties this turn
  | { kind: 'reallocation'; armies: number } // fleets → extra ground armies
  | { kind: 'minor_empire' } // summon this epoch's Minor Empire: a second empire-turn
  | { kind: 'siegecraft' } // forts have no effect vs your attacks this turn
  | { kind: 'surprise_attack' } // void difficult-terrain / amphibious defence this turn
  | { kind: 'extra_armies'; armies: number; needsCapital: boolean } // Pop Explosion / Civil Service
  | { kind: 'found_kingdom' } // Kingdoms: raise a fortified city (city + fort) on one of your lands
  | { kind: 'ship_building' } // navigate ALL seas this turn (reach any coast)
  | { kind: 'naval_supremacy' } // navigate all seas AND your sea-borne landings ignore terrain
  // ── targeted disasters (played BEFORE turn, aimed at an enemy Land) ──
  | { kind: 'disaster_structure'; terrain: DisasterTerrain } // Flood/Volcano/Fire: wreck structures
  | { kind: 'plague' } // the target Land's army rolls 4 dice; a '1' eliminates it
  | { kind: 'pestilence' } // target army rolls 3 dice; each adjacent enemy army rolls 2 — '1' kills
  | { kind: 'famine' } // every enemy army in the target's Area rolls 2 dice; a '1' kills
  | { kind: 'barbarians' } // a raid from the wastes: sack an enemy Land bordering a barren one
  | { kind: 'pirates' } // raid a COASTAL enemy Land: raze its structure + its army rolls 2 dice
  | { kind: 'storm_at_sea' } // a COASTAL enemy Land's army rolls 4 dice; a '1' wrecks it

/** True for effects that must be aimed at a target Land. */
export function effectNeedsTarget(e: EventEffect): boolean {
  return (
    e.kind === 'disaster_structure' ||
    e.kind === 'plague' ||
    e.kind === 'pestilence' ||
    e.kind === 'famine' ||
    e.kind === 'barbarians' ||
    e.kind === 'pirates' ||
    e.kind === 'storm_at_sea'
  )
}

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

/** A fleet occupies a Sea (not a Land). Up to two fleets may share a Sea; a fleet
 *  lets the owning empire's armies land on any coast of that Sea, and (for true Seas)
 *  scores +1 at controlling it. Fleets belong to the player across empires. */
export interface FleetPiece {
  sea: SeaId
  owner: PlayerId
  epochColor: EpochId
}

/** Victory-point value of each structure when controlled (SPEC §8.3). */
export const STRUCTURE_VP: Record<StructureKind, number> = {
  capital: 2,
  city: 1,
  monument: 1,
  fort: 0,
}
