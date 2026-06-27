// Colors for the map (pure data, shared). Area tints show the 13 scoring
// regions; player colors mark who controls a land.

import type { AreaId } from './types'

export const AREA_COLORS: Record<AreaId, string> = {
  middle_east: '#b5651d',
  north_africa: '#c9a227',
  china: '#c0392b',
  india: '#cd6155',
  southern_europe: '#8e44ad',
  northern_europe: '#2e86c1',
  southeast_asia: '#16a085',
  eurasia: '#5d6d7e',
  north_america: '#229954',
  south_america: '#52be80',
  nippon: '#af7ac5',
  africa: '#d4ac0d',
  australia: '#dc7633',
}

export function areaColor(area: AreaId | null): string {
  return (area && AREA_COLORS[area]) || '#444'
}

/** Up to 6 player colors (3–6 players). */
export const PLAYER_COLORS = [
  '#e15554', // red
  '#4d9de0', // blue
  '#7eb74f', // green
  '#e1bc29', // gold
  '#9b5de5', // purple
  '#f15bb5', // pink
]

export function playerColor(index: number): string {
  return PLAYER_COLORS[((index % PLAYER_COLORS.length) + PLAYER_COLORS.length) % PLAYER_COLORS.length]
}
