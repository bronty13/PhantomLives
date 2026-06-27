// Colors for the map (pure data, shared). Area tints show the 13 scoring
// regions; player colors mark who controls a land.

import type { AreaId } from './types'

// Muted, desaturated EARTH tones — regions read as terrain background, NOT as
// player ownership. Player pieces (below) stay vivid so ownership pops on a
// different visual channel than geography. (Kept distinct from PLAYER_COLORS.)
export const AREA_COLORS: Record<AreaId, string> = {
  middle_east: '#8a6d3b',
  north_africa: '#9b8a52',
  china: '#9c5a52',
  india: '#a06a5c',
  southern_europe: '#6e5a7a',
  northern_europe: '#5a6e85',
  southeast_asia: '#4a7a6e',
  eurasia: '#6a6e78',
  north_america: '#5e7a54',
  south_america: '#74804e',
  nippon: '#7a6a82',
  africa: '#93824e',
  australia: '#9c6a4e',
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
