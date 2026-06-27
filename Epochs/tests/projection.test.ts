import { describe, expect, it } from 'vitest'
import { nearestLand, project, projectLand, type MapRect } from '../src/shared/mapProjection'
import type { Land } from '../src/shared/types'

const rect: MapRect = { x: 100, y: 50, w: 800, h: 400 }

const land = (id: string, x?: number, y?: number): Land => ({
  id,
  name: id,
  area: 'middle_east',
  barren: false,
  difficultTerrain: [],
  hasResource: false,
  borders: [],
  seaBorders: [],
  x,
  y,
})

describe('project', () => {
  it('maps the corners and center of the unit square into the rect', () => {
    expect(project(0, 0, rect)).toEqual({ x: 100, y: 50 })
    expect(project(1, 1, rect)).toEqual({ x: 900, y: 450 })
    expect(project(0.5, 0.5, rect)).toEqual({ x: 500, y: 250 })
  })

  it('projectLand returns null when a land has no coordinates', () => {
    expect(projectLand(land('x'), rect)).toBeNull()
    expect(projectLand(land('y', 0.5, 0.5), rect)).toEqual({ x: 500, y: 250 })
  })
})

describe('nearestLand', () => {
  const lands = [land('a', 0.25, 0.25), land('b', 0.75, 0.75), land('nocoord')]

  it('returns the closest land within maxDist', () => {
    // 'a' projects to (300, 150)
    expect(nearestLand(lands, rect, 305, 155, 20)?.id).toBe('a')
    // 'b' projects to (700, 350)
    expect(nearestLand(lands, rect, 690, 360, 30)?.id).toBe('b')
  })

  it('returns null when nothing is within maxDist', () => {
    expect(nearestLand(lands, rect, 500, 250, 10)).toBeNull()
  })

  it('ignores lands without coordinates', () => {
    expect(nearestLand([land('nocoord')], rect, 100, 100, 50)).toBeNull()
  })
})
