// Voronoi tessellation by half-plane clipping — original generated art for the
// antique map. Each site (a territory centroid) gets the polygon of points
// closest to it; coastal sites round toward the ocean so continents read as
// hand-drawn landmasses. Pure (no DOM); cached by the renderer per layout.

export interface VSite {
  id: string
  x: number // pixel coords
  y: number
  coastal: boolean // round this cell toward the ocean
}

export type Cell = [number, number][]

function clipHalf(poly: Cell, mx: number, my: number, nx: number, ny: number): Cell {
  const out: Cell = []
  const side = (p: [number, number]): number => (p[0] - mx) * nx + (p[1] - my) * ny
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i]
    const b = poly[(i + 1) % poly.length]
    const da = side(a)
    const db = side(b)
    if (da <= 1e-9) out.push(a)
    if (da <= 1e-9 !== (db <= 1e-9)) {
      const t = da / (da - db)
      out.push([a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])])
    }
  }
  return out
}

/** Median nearest-neighbour spacing — a good basis for the coastline radius. */
export function medianSpacing(sites: VSite[]): number {
  if (sites.length < 2) return 0
  const nn = sites.map((a) => {
    let best = Infinity
    for (const b of sites) {
      if (b === a) continue
      best = Math.min(best, Math.hypot(a.x - b.x, a.y - b.y))
    }
    return best
  })
  nn.sort((p, q) => p - q)
  return nn[Math.floor(nn.length / 2)]
}

/** Voronoi cell per site id; coastal sites are trimmed to a disc of `radius`. */
export function voronoiCells(sites: VSite[], radius: number): Map<string, Cell> {
  const cells = new Map<string, Cell>()
  if (sites.length === 0) return cells
  let minX = Infinity
  let minY = Infinity
  let maxX = -Infinity
  let maxY = -Infinity
  for (const s of sites) {
    minX = Math.min(minX, s.x)
    minY = Math.min(minY, s.y)
    maxX = Math.max(maxX, s.x)
    maxY = Math.max(maxY, s.y)
  }
  const m = radius * 2
  for (const s of sites) {
    let poly: Cell = [
      [minX - m, minY - m],
      [maxX + m, minY - m],
      [maxX + m, maxY + m],
      [minX - m, maxY + m],
    ]
    for (const o of sites) {
      if (o === s) continue
      poly = clipHalf(poly, (s.x + o.x) / 2, (s.y + o.y) / 2, o.x - s.x, o.y - s.y)
      if (poly.length < 3) break
    }
    // Only round the COASTLINE: land-locked territories keep their full cell and
    // interlock into solid continents; coastal ones trim to a disc.
    if (s.coastal) {
      for (let k = 0; k < 18 && poly.length >= 3; k++) {
        const ang = (k / 18) * 2 * Math.PI
        poly = clipHalf(
          poly,
          s.x + Math.cos(ang) * radius,
          s.y + Math.sin(ang) * radius,
          Math.cos(ang),
          Math.sin(ang),
        )
      }
    }
    if (poly.length >= 3) cells.set(s.id, poly)
  }
  return cells
}
