// Antique PARCHMENT map (original generated art on the real geography): an ocean
// ground, Voronoi territories tinted by region with sepia coastlines, ridgeline
// mountains, forest stipple, calligraphic labels, a compass rose — then the live
// game layer on top: army counters, structures, the active-empire ring, placeable
// rings, hover, and (via anim.ts) effects. The Voronoi tessellation is cached per
// layout so the per-frame cost stays low.

import type { FrontierKind } from '../shared/bot'
import type { CombatOdds } from '../shared/combat'
import { areaParchment, PARCHMENT_BARREN, playerColor } from '../shared/palette'
import { projectLand, type MapRect } from '../shared/mapProjection'
import { medianSpacing, voronoiCells, type Cell, type VSite } from '../shared/voronoi'
import type { BoardPiece, EpochId, Land, PlayerId } from '../shared/types'

export interface PlaceableEntry {
  kind: FrontierKind
  odds?: CombatOdds
  amphibious: boolean
}

export interface MapRenderState {
  lands: Land[]
  pieces: readonly BoardPiece[]
  playerOrder: PlayerId[]
  currentEpoch: EpochId
  activePlayer?: PlayerId | null
  hovered?: string | null
  placeable?: Map<string, PlaceableEntry> | null
  tooltipLines?: string[] | null
  viewW?: number
  viewH?: number
}

function placeColor(e: PlaceableEntry): string {
  if (e.kind === 'empty') return '#2f7d3f'
  if (e.kind === 'own_old') return '#3b6ea5'
  const p = e.odds?.attacker ?? 0
  return p >= 0.6 ? '#5a8a2f' : p >= 0.35 ? '#b8881f' : '#a83232'
}

const clamp = (v: number, lo: number, hi: number): number => Math.max(lo, Math.min(hi, v))

// ── cached Voronoi tessellation (recomputed only when the layout changes) ──
let cache: { key: string; cells: Map<string, Cell>; r: number } | null = null
function tessellate(lands: Land[], rect: MapRect): { cells: Map<string, Cell>; r: number } {
  const key = `${rect.x.toFixed(1)},${rect.y.toFixed(1)},${rect.w.toFixed(1)},${rect.h.toFixed(1)},${lands.length}`
  if (cache && cache.key === key) return cache
  const sites: VSite[] = []
  for (const l of lands) {
    const p = projectLand(l, rect)
    if (p) sites.push({ id: l.id, x: p.x, y: p.y, coastal: l.seaBorders.length > 0 || l.barren })
  }
  const r = medianSpacing(sites) * 2.05
  cache = { key, cells: voronoiCells(sites, r), r }
  return cache
}

function fillCell(ctx: CanvasRenderingContext2D, cell: Cell): void {
  ctx.beginPath()
  ctx.moveTo(cell[0][0], cell[0][1])
  for (let i = 1; i < cell.length; i++) ctx.lineTo(cell[i][0], cell[i][1])
  ctx.closePath()
}

export function drawMap(ctx: CanvasRenderingContext2D, rect: MapRect, st: MapRenderState): void {
  const { lands, pieces } = st
  const vw = st.viewW ?? rect.x * 2 + rect.w
  const vh = st.viewH ?? rect.y * 2 + rect.h
  const landById = new Map(lands.map((l) => [l.id, l]))
  const colorOf = (pid: PlayerId | null): string => {
    if (pid == null) return '#8a8a8a'
    const i = st.playerOrder.indexOf(pid)
    return i >= 0 ? playerColor(i) : '#8a8a8a'
  }
  const armyAt = new Map<string, BoardPiece>()
  const structs = new Map<string, BoardPiece[]>()
  for (const p of pieces) {
    if (p.kind === 'army') armyAt.set(p.land, p)
    else {
      const a = structs.get(p.land) ?? []
      a.push(p)
      structs.set(p.land, a)
    }
  }

  const { cells, r: spacing } = tessellate(lands, rect)
  const R = clamp(spacing * 0.18, 7, 16)

  // ── ocean ground ──────────────────────────────────────────────────────────
  const ocean = ctx.createRadialGradient(vw / 2, vh * 0.45, vh * 0.2, vw / 2, vh / 2, vh * 0.85)
  ocean.addColorStop(0, '#bcd4cf')
  ocean.addColorStop(1, '#9bbcbf')
  ctx.fillStyle = ocean
  ctx.fillRect(0, 0, vw, vh)

  // ── territories (parchment, tinted by region; sepia coastlines) ───────────
  for (const l of lands) {
    const cell = cells.get(l.id)
    if (!cell) continue
    fillCell(ctx, cell)
    ctx.fillStyle = l.barren ? PARCHMENT_BARREN : areaParchment(l.area)
    ctx.fill()
    ctx.lineWidth = 1.1
    ctx.strokeStyle = 'rgba(107,79,42,0.6)'
    ctx.stroke()
  }

  // ── terrain: ridgeline mountains, forest stipple, resource rings ──────────
  ctx.lineCap = 'round'
  for (const l of lands) {
    const p = projectLand(l, rect)
    if (!p) continue
    const t = l.difficultTerrain
    if (t.includes('mountain') || t.includes('great_wall')) {
      ctx.strokeStyle = '#5a4326'
      ctx.lineWidth = 2
      const w = R * 0.7
      for (let i = -1; i <= 1; i++) {
        const cx = p.x + i * w * 1.4
        ctx.beginPath()
        ctx.moveTo(cx - w, p.y + w * 0.5)
        ctx.lineTo(cx, p.y - w * 0.7)
        ctx.lineTo(cx + w, p.y + w * 0.5)
        ctx.stroke()
      }
    } else if (t.includes('forest')) {
      ctx.fillStyle = '#3f6b34'
      for (let i = 0; i < 7; i++) {
        ctx.beginPath()
        ctx.arc(p.x + ((i % 3) - 1) * 9, p.y + (Math.floor(i / 3) - 1) * 8, 1.8, 0, Math.PI * 2)
        ctx.fill()
      }
    }
    if (l.hasResource && !l.barren && !armyAt.has(l.id)) {
      ctx.beginPath()
      ctx.arc(p.x, p.y + R + 4, 3, 0, Math.PI * 2)
      ctx.strokeStyle = '#7a5a1f'
      ctx.lineWidth = 1.6
      ctx.stroke()
    }
  }

  // ── territory labels (calligraphic italic, collision-culled) ──────────────
  if (rect.w > 600) {
    ctx.font = "italic 11px Georgia, 'Times New Roman', serif"
    ctx.textAlign = 'center'
    ctx.textBaseline = 'alphabetic'
    const placed: { x0: number; y0: number; x1: number; y1: number }[] = []
    for (const l of lands) {
      const p = projectLand(l, rect)
      if (!p || armyAt.has(l.id)) continue
      const w = ctx.measureText(l.name).width
      const x0 = p.x - w / 2
      const y0 = p.y - 6
      if (placed.some((b) => x0 < b.x1 && x0 + w > b.x0 && y0 < b.y1 && y0 + 12 > b.y0)) continue
      placed.push({ x0, y0, x1: x0 + w, y1: y0 + 12 })
      ctx.lineWidth = 2.4
      ctx.strokeStyle = 'rgba(232,217,176,0.85)'
      ctx.strokeText(l.name, p.x, p.y)
      ctx.fillStyle = l.barren ? '#6a5a3a' : '#2f4524'
      ctx.fillText(l.name, p.x, p.y)
    }
  }

  // ── live game layer: army counters + structures ──────────────────────────
  ctx.textAlign = 'center'
  ctx.textBaseline = 'middle'
  for (const l of lands) {
    const p = projectLand(l, rect)
    if (!p) continue
    const army = armyAt.get(l.id)
    if (army) {
      const cs = R * 1.7
      const live = army.owner === st.activePlayer && army.epochColor === st.currentEpoch
      if (live) {
        ctx.beginPath()
        roundRect(ctx, p.x - cs / 2 - 2.5, p.y - cs / 2 - 2.5, cs + 5, cs + 5, 4)
        ctx.strokeStyle = 'rgba(255,255,255,0.9)'
        ctx.lineWidth = 2
        ctx.stroke()
      }
      ctx.beginPath()
      roundRect(ctx, p.x - cs / 2, p.y - cs / 2, cs, cs, 3)
      ctx.fillStyle = colorOf(army.owner)
      ctx.fill()
      ctx.strokeStyle = 'rgba(24,16,8,0.75)'
      ctx.lineWidth = 1.4
      ctx.stroke()
      // crossed-swords emblem
      ctx.strokeStyle = 'rgba(255,255,255,0.7)'
      ctx.lineWidth = 1.3
      const e = cs * 0.26
      ctx.beginPath()
      ctx.moveTo(p.x - e, p.y - e)
      ctx.lineTo(p.x + e, p.y + e)
      ctx.moveTo(p.x + e, p.y - e)
      ctx.lineTo(p.x - e, p.y + e)
      ctx.stroke()
    }
    const ss = structs.get(l.id)
    if (ss && ss.length) {
      ctx.font = `${Math.round(R * 1.2)}px Georgia, serif`
      let i = 0
      for (const s of ss) {
        const glyph =
          s.kind === 'capital' ? '★' : s.kind === 'city' ? '◆' : s.kind === 'monument' ? '▲' : s.kind === 'fort' ? '▮' : ''
        if (!glyph) continue
        const gx = p.x + (army ? R + 4 : 0) + i * (R + 1)
        const gy = army ? p.y - R - 2 : p.y
        ctx.lineWidth = 3
        ctx.strokeStyle = 'rgba(40,28,12,0.85)'
        ctx.strokeText(glyph, gx, gy)
        ctx.fillStyle = colorOf(s.owner)
        ctx.fillText(glyph, gx, gy)
        i++
      }
    }
    const pe = st.placeable?.get(l.id)
    if (pe) {
      ctx.beginPath()
      if (pe.amphibious) ctx.setLineDash([4, 3])
      ctx.arc(p.x, p.y, R + 5, 0, Math.PI * 2)
      ctx.strokeStyle = placeColor(pe)
      ctx.lineWidth = 2.5
      ctx.stroke()
      ctx.setLineDash([])
    }
  }

  drawCompass(ctx, vw * 0.5, vh * 0.13, Math.min(34, vh * 0.05))

  // ── hover tooltip ─────────────────────────────────────────────────────────
  if (st.hovered) {
    const l = landById.get(st.hovered)
    const p = l && projectLand(l, rect)
    if (l && p) {
      ctx.beginPath()
      ctx.arc(p.x, p.y, R + 4, 0, Math.PI * 2)
      ctx.strokeStyle = '#3a2c12'
      ctx.lineWidth = 2
      ctx.stroke()
      const lines = st.tooltipLines && st.tooltipLines.length ? st.tooltipLines : [l.name]
      ctx.font = '12px Georgia, serif'
      const lh = 16
      const pad = 8
      const w = Math.max(...lines.map((sline) => ctx.measureText(sline).width)) + pad * 2
      const h = lines.length * lh + pad * 2 - 4
      let bx = p.x + 16
      let by = p.y - h / 2
      if (bx + w > vw) bx = p.x - 16 - w
      by = clamp(by, 4, vh - h - 4)
      ctx.fillStyle = 'rgba(243,229,196,0.97)'
      ctx.beginPath()
      roundRect(ctx, bx, by, w, h, 6)
      ctx.fill()
      ctx.strokeStyle = '#7a5a2a'
      ctx.lineWidth = 1.2
      ctx.stroke()
      ctx.textAlign = 'left'
      ctx.textBaseline = 'middle'
      lines.forEach((sline, i) => {
        ctx.fillStyle = i === 0 ? '#2c2012' : '#5a4a2a'
        ctx.fillText(sline, bx + pad, by + pad + i * lh + lh / 2 - 2)
      })
      ctx.textAlign = 'center'
    }
  }

  // ── burnt edge frame ──────────────────────────────────────────────────────
  ctx.strokeStyle = 'rgba(58,44,18,0.4)'
  ctx.lineWidth = 10
  ctx.strokeRect(5, 5, vw - 10, vh - 10)
}

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, rad: number): void {
  const r = Math.min(rad, w / 2, h / 2)
  ctx.moveTo(x + r, y)
  ctx.arcTo(x + w, y, x + w, y + h, r)
  ctx.arcTo(x + w, y + h, x, y + h, r)
  ctx.arcTo(x, y + h, x, y, r)
  ctx.arcTo(x, y, x + w, y, r)
}

function drawCompass(ctx: CanvasRenderingContext2D, cx: number, cy: number, rad: number): void {
  ctx.save()
  ctx.translate(cx, cy)
  ctx.beginPath()
  ctx.arc(0, 0, rad, 0, Math.PI * 2)
  ctx.fillStyle = 'rgba(232,217,176,0.85)'
  ctx.fill()
  ctx.strokeStyle = '#7a5a2a'
  ctx.lineWidth = 2
  ctx.stroke()
  for (let k = 0; k < 8; k++) {
    const a = (k / 8) * 2 * Math.PI
    const len = k % 2 === 0 ? rad : rad * 0.5
    ctx.beginPath()
    ctx.moveTo(0, 0)
    ctx.lineTo(Math.cos(a) * len, Math.sin(a) * len)
    ctx.strokeStyle = k % 2 === 0 ? '#8a3a2a' : '#9a7a3a'
    ctx.lineWidth = k % 2 === 0 ? 3 : 1.5
    ctx.stroke()
  }
  ctx.beginPath()
  ctx.arc(0, 0, rad * 0.16, 0, Math.PI * 2)
  ctx.fillStyle = '#c8a23a'
  ctx.fill()
  ctx.restore()
}
