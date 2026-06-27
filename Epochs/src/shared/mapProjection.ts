// Pure map projection + hit-testing (no DOM) — shared by the renderer and tests.
// Territory positions are normalized (x,y in 0..1, equirectangular); a MapRect
// maps them into pixel space.

import type { Land } from './types'

export interface MapRect {
  x: number
  y: number
  w: number
  h: number
}

export interface Point {
  x: number
  y: number
}

/** Project a normalized (nx, ny) into the pixel rect. */
export function project(nx: number, ny: number, rect: MapRect): Point {
  return { x: rect.x + nx * rect.w, y: rect.y + ny * rect.h }
}

/** Project a land's centroid (returns null if it has no coordinates). */
export function projectLand(land: Land, rect: MapRect): Point | null {
  if (land.x == null || land.y == null) return null
  return project(land.x, land.y, rect)
}

/** The land whose centroid is nearest to (px, py), within `maxDist` px, or null. */
export function nearestLand(
  lands: readonly Land[],
  rect: MapRect,
  px: number,
  py: number,
  maxDist: number,
): Land | null {
  let best: Land | null = null
  let bestD = maxDist * maxDist
  for (const l of lands) {
    const p = projectLand(l, rect)
    if (!p) continue
    const dx = p.x - px
    const dy = p.y - py
    const d = dx * dx + dy * dy
    if (d <= bestD) {
      bestD = d
      best = l
    }
  }
  return best
}
