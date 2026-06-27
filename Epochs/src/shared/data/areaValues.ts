// The Victory-Point table: base (presence) value of each of the 13 Areas per
// epoch (SPEC §9.3). Dominance doubles and Control triples these (SPEC §9.1).
// AUTHENTIC data transcribed from the physical board's Victory Point Table
// (owner's scan, 2026-06-27) — replaces the earlier partly-invented values.

import type { AreaId, EpochId } from '../types'

/** [epoch1, epoch2, epoch3, epoch4, epoch5, epoch6, epoch7] */
export type EpochTuple = [number, number, number, number, number, number, number]

export const AREA_NAMES: Record<AreaId, string> = {
  middle_east: 'Middle East',
  north_africa: 'North Africa',
  china: 'China',
  india: 'India',
  southern_europe: 'Southern Europe',
  northern_europe: 'Northern Europe',
  southeast_asia: 'South-East Asia',
  eurasia: 'Eurasia',
  north_america: 'North America',
  south_america: 'South America',
  nippon: 'Nippon',
  africa: 'Sub-Saharan Africa',
  australia: 'Australasia',
}

export const AREA_VALUES: Record<AreaId, EpochTuple> = {
  //                  I  II III IV  V  VI VII
  middle_east:      [ 2, 3, 3, 3, 2, 2, 1 ],
  north_africa:     [ 1, 2, 2, 2, 2, 2, 1 ],
  china:            [ 1, 2, 3, 3, 3, 3, 3 ],
  india:            [ 1, 2, 3, 3, 3, 3, 3 ],
  southern_europe:  [ 0, 2, 3, 3, 3, 2, 2 ],
  northern_europe:  [ 0, 0, 1, 2, 2, 2, 4 ],
  southeast_asia:   [ 0, 0, 1, 2, 2, 2, 2 ],
  eurasia:          [ 0, 0, 0, 0, 1, 1, 2 ],
  north_america:    [ 0, 0, 0, 0, 1, 1, 3 ],
  south_america:    [ 0, 0, 0, 0, 0, 2, 2 ],
  nippon:           [ 0, 0, 0, 0, 0, 1, 2 ],
  africa:           [ 0, 0, 0, 0, 0, 1, 2 ],
  australia:        [ 0, 0, 0, 0, 0, 0, 1 ],
}

/** Base (presence) VP value of an area in a given epoch; 0 if it doesn't score. */
export function areaValue(area: AreaId, epoch: EpochId): number {
  const t = AREA_VALUES[area]
  return t ? t[epoch - 1] : 0
}

/** The same row as a Record keyed by epoch (handy for building AreaDef). */
export function valueByEpoch(area: AreaId): Record<EpochId, number> {
  const t = AREA_VALUES[area] ?? [0, 0, 0, 0, 0, 0, 0]
  return { 1: t[0], 2: t[1], 3: t[2], 4: t[3], 5: t[4], 6: t[5], 7: t[6] }
}
