// A small, hand-built fixture map so the engine and tests run end-to-end BEFORE
// the full 102-land board is transcribed (SPEC §14). NOT the real board — a
// coherent Mediterranean-ish slice across three real Areas. Borders are kept
// symmetric. Replace with src/shared/data/board.ts when real data lands.

import type { AreaDef, Land, LandId, SeaId } from '../types'
import { AREA_NAMES, valueByEpoch } from './areaValues'

export const FIXTURE_SEAS: SeaId[] = ['eastern_med', 'western_med', 'black_sea']

function land(
  id: LandId,
  name: string,
  area: string,
  opts: Partial<Land> = {},
): Land {
  return {
    id,
    name,
    area,
    barren: false,
    difficultTerrain: [],
    hasResource: false,
    borders: [],
    seaBorders: [],
    ...opts,
  }
}

export const FIXTURE_LANDS: Land[] = [
  land('mesopotamia', 'Mesopotamia', 'middle_east', {
    hasResource: true,
    borders: ['levant', 'persia', 'anatolia'],
  }),
  land('levant', 'Levant', 'middle_east', {
    borders: ['mesopotamia', 'egypt', 'anatolia'],
    seaBorders: ['eastern_med'],
  }),
  land('persia', 'Persia', 'middle_east', {
    difficultTerrain: ['mountain'],
    borders: ['mesopotamia'],
  }),
  land('anatolia', 'Anatolia', 'middle_east', {
    borders: ['mesopotamia', 'levant', 'greece'],
    seaBorders: ['eastern_med', 'black_sea'],
  }),
  land('egypt', 'Egypt', 'north_africa', {
    hasResource: true,
    borders: ['levant', 'libya'],
    seaBorders: ['eastern_med'],
  }),
  land('libya', 'Libya', 'north_africa', {
    borders: ['egypt', 'carthage'],
  }),
  land('carthage', 'Carthage', 'north_africa', {
    borders: ['libya'],
    seaBorders: ['western_med'],
  }),
  land('greece', 'Greece', 'southern_europe', {
    hasResource: true,
    // attacking INTO greece from anatolia crosses a strait (defender +dice)
    difficultTerrain: ['strait', 'mountain'],
    borders: ['anatolia'],
    seaBorders: ['eastern_med', 'western_med'],
  }),
  land('italy', 'Italy', 'southern_europe', {
    borders: [],
    seaBorders: ['western_med'],
  }),
]

const LANDS_BY_AREA = new Map<string, LandId[]>()
for (const l of FIXTURE_LANDS) {
  if (l.area == null) continue
  const list = LANDS_BY_AREA.get(l.area) ?? []
  list.push(l.id)
  LANDS_BY_AREA.set(l.area, list)
}

/** Area definitions for the fixture (real VP values, fixture land membership). */
export const FIXTURE_AREAS: AreaDef[] = [...LANDS_BY_AREA.keys()].map((id) => ({
  id,
  name: AREA_NAMES[id] ?? id,
  lands: LANDS_BY_AREA.get(id) ?? [],
  valueByEpoch: valueByEpoch(id),
}))

const AREA_OF = new Map<LandId, string>(
  FIXTURE_LANDS.map((l) => [l.id, l.area ?? '']),
)

/** Resolve a fixture land to its Area id (or null for barren/unknown). */
export function fixtureAreaOf(landId: LandId): string | null {
  return AREA_OF.get(landId) ?? null
}
