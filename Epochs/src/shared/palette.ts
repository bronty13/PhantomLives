// Colors for the map (pure data, shared). Area tints show the 13 scoring
// regions; player colors mark who controls a land.

import type { AreaId } from './types'

// Earthy LAND tones — each of the 13 regions reads as a distinct landmass over
// the blue ocean. Northern areas lean green/khaki (never ocean-blue) so land vs
// sea never confuses. Player pieces (below) stay vivid and sit ON TOP, so
// ownership pops on a brightness/size channel distinct from these region tints.
export const AREA_COLORS: Record<AreaId, string> = {
  middle_east: '#c19a4e',
  north_africa: '#cbb15e',
  china: '#c2604f',
  india: '#cc8150',
  southern_europe: '#8f76a8',
  northern_europe: '#6f9472',
  southeast_asia: '#4fa386',
  eurasia: '#a39a6e',
  north_america: '#74a458',
  south_america: '#9aa450',
  nippon: '#a87290',
  africa: '#c0a154',
  australia: '#c0764e',
}

/** Sandy tan for Barren lands (deserts/tundra) — distinct from ocean and regions. */
export const BARREN_COLOR = '#9c8f6e'

export function areaColor(area: AreaId | null): string {
  return (area && AREA_COLORS[area]) || BARREN_COLOR
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
