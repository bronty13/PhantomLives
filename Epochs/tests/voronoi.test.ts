import { describe, expect, it } from 'vitest'
import { medianSpacing, voronoiCells, type VSite } from '../src/shared/voronoi'

const grid = (n: number): VSite[] => {
  const s: VSite[] = []
  for (let i = 0; i < n; i++) {
    for (let j = 0; j < n; j++) {
      s.push({ id: `${i}_${j}`, x: i * 40, y: j * 40, coastal: i === 0 || j === 0 || i === n - 1 || j === n - 1 })
    }
  }
  return s
}

describe('voronoi tessellation', () => {
  it('produces a valid polygon (>= 3 verts) for each site', () => {
    const sites = grid(5)
    const cells = voronoiCells(sites, medianSpacing(sites) * 2)
    expect(cells.size).toBe(sites.length)
    for (const [, c] of cells) expect(c.length).toBeGreaterThanOrEqual(3)
  })

  it('an interior cell sits around its own site', () => {
    const sites = grid(5)
    const r = medianSpacing(sites) * 2
    const cells = voronoiCells(sites, r)
    const site = sites.find((s) => s.id === '2_2')!
    const c = cells.get('2_2')!
    const cx = c.reduce((a, p) => a + p[0], 0) / c.length
    const cy = c.reduce((a, p) => a + p[1], 0) / c.length
    expect(Math.hypot(cx - site.x, cy - site.y)).toBeLessThan(r)
  })

  it('medianSpacing is the grid step for a regular grid', () => {
    expect(medianSpacing(grid(5))).toBeCloseTo(40, 6)
  })
})
