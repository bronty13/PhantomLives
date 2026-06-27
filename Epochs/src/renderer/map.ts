// Canvas rendering of the world map (the STATIC base layer; anim.ts overlays it).
// Reads like a real map: blue ocean, soft area-colored CONTINENT silhouettes
// (overlapping discs fuse same-region territories into landmasses), brighter
// territory nodes, owner-colored armies, structures (★/◆/▲/▮), an active-empire
// ring, per-kind placeable rings, territory labels, and a multi-line tooltip.

import type { FrontierKind } from '../shared/bot'
import type { CombatOdds } from '../shared/combat'
import { areaColor, BARREN_COLOR, playerColor } from '../shared/palette'
import { projectLand, type MapRect } from '../shared/mapProjection'
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
  /** Full canvas size in CSS px, so ocean fills the view (rect may overflow it). */
  viewW?: number
  viewH?: number
}

function hexA(hex: string, a: number): string {
  const r = parseInt(hex.slice(1, 3), 16)
  const g = parseInt(hex.slice(3, 5), 16)
  const b = parseInt(hex.slice(5, 7), 16)
  return `rgba(${r},${g},${b},${a})`
}

/** Lighten a #rrggbb toward white by t (0..1). */
function lighten(hex: string, t: number): string {
  const c = (i: number) => {
    const v = parseInt(hex.slice(i, i + 2), 16)
    return Math.round(v + (255 - v) * t)
  }
  return `rgb(${c(1)},${c(3)},${c(5)})`
}

/** Ring color for a placeable land: settle green, reclaim blue, attack by odds. */
function placeColor(e: PlaceableEntry): string {
  if (e.kind === 'empty') return '#7cfc9a'
  if (e.kind === 'own_old') return '#4d9de0'
  const p = e.odds?.attacker ?? 0
  return p >= 0.6 ? '#9ccc65' : p >= 0.35 ? '#e1bc29' : '#e15554'
}

const clamp = (v: number, lo: number, hi: number): number => Math.max(lo, Math.min(hi, v))

export function drawMap(ctx: CanvasRenderingContext2D, rect: MapRect, st: MapRenderState): void {
  const { lands, pieces } = st
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

  const R = clamp(rect.w * 0.0085, 5, 11)
  const BLOB = R * 3.2
  const showLabels = rect.w > 700

  // ── ocean (fills the whole view; rect may overflow it after bbox-fit) ────
  const vw = st.viewW ?? rect.x * 2 + rect.w
  const vh = st.viewH ?? rect.y * 2 + rect.h
  const grad = ctx.createLinearGradient(0, 0, 0, vh)
  grad.addColorStop(0, '#10314e')
  grad.addColorStop(1, '#0a2236')
  ctx.fillStyle = grad
  ctx.fillRect(0, 0, vw, vh)

  // ── continent silhouettes (overlapping soft discs fuse into landmasses) ──
  ctx.save()
  ctx.beginPath()
  ctx.rect(0, 0, vw, vh)
  ctx.clip()
  for (const l of lands) {
    const p = projectLand(l, rect)
    if (!p) continue
    ctx.beginPath()
    ctx.arc(p.x, p.y, l.barren ? BLOB * 0.7 : BLOB, 0, Math.PI * 2)
    ctx.fillStyle = hexA(l.barren ? BARREN_COLOR : areaColor(l.area), 0.42)
    ctx.fill()
  }
  ctx.restore()

  // ── adjacency edges ──────────────────────────────────────────────────────
  ctx.strokeStyle = 'rgba(225,232,245,0.22)'
  ctx.lineWidth = 1
  ctx.beginPath()
  for (const l of lands) {
    const a = projectLand(l, rect)
    if (!a) continue
    for (const nbId of l.borders) {
      if (nbId <= l.id) continue
      const nb = landById.get(nbId)
      const b = nb && projectLand(nb, rect)
      if (!b) continue
      ctx.moveTo(a.x, a.y)
      ctx.lineTo(b.x, b.y)
    }
  }
  ctx.stroke()

  // ── territory nodes ──────────────────────────────────────────────────────
  ctx.textAlign = 'center'
  ctx.textBaseline = 'middle'
  for (const l of lands) {
    const p = projectLand(l, rect)
    if (!p) continue
    const r = l.barren ? R * 0.62 : R
    const base = l.barren ? BARREN_COLOR : areaColor(l.area)
    ctx.beginPath()
    ctx.arc(p.x, p.y, r, 0, Math.PI * 2)
    ctx.fillStyle = lighten(base, 0.34)
    ctx.fill()
    ctx.lineWidth = 1.4
    ctx.strokeStyle = hexA(base, 0.95)
    ctx.stroke()

    const army = armyAt.get(l.id)
    if (army) {
      ctx.beginPath()
      ctx.arc(p.x, p.y, r - 2.4, 0, Math.PI * 2)
      ctx.fillStyle = colorOf(army.owner)
      ctx.fill()
    } else if (l.hasResource && !l.barren) {
      ctx.beginPath()
      ctx.arc(p.x, p.y, r * 0.55, 0, Math.PI * 2)
      ctx.strokeStyle = '#f5d76e'
      ctx.lineWidth = 1.5
      ctx.stroke()
    }

    if (
      army &&
      st.activePlayer &&
      army.owner === st.activePlayer &&
      army.epochColor === st.currentEpoch
    ) {
      ctx.beginPath()
      ctx.arc(p.x, p.y, r + 2.6, 0, Math.PI * 2)
      ctx.strokeStyle = 'rgba(255,255,255,0.9)'
      ctx.lineWidth = 1.6
      ctx.stroke()
    }

    const ss = structs.get(l.id)
    if (ss && ss.length) {
      ctx.font = `${Math.round(R * 1.3)}px sans-serif`
      let i = 0
      for (const s of ss) {
        const glyph =
          s.kind === 'capital'
            ? '★'
            : s.kind === 'city'
              ? '◆'
              : s.kind === 'monument'
                ? '▲'
                : s.kind === 'fort'
                  ? '▮'
                  : ''
        if (!glyph) continue
        const gx = p.x + r + 4 + i * (R + 1)
        const gy = p.y - r + 1
        ctx.lineWidth = 3
        ctx.strokeStyle = 'rgba(6,12,22,0.92)'
        ctx.strokeText(glyph, gx, gy)
        ctx.fillStyle = colorOf(s.owner)
        ctx.fillText(glyph, gx, gy)
        i++
      }
    }

    const pe = st.placeable?.get(l.id)
    if (pe) {
      ctx.beginPath()
      if (pe.amphibious) ctx.setLineDash([3, 3])
      ctx.arc(p.x, p.y, r + 4, 0, Math.PI * 2)
      ctx.strokeStyle = placeColor(pe)
      ctx.lineWidth = 2
      ctx.stroke()
      ctx.setLineDash([])
    }
  }

  // ── territory labels (collision-culled so dense regions don't smear) ─────
  if (showLabels) {
    ctx.font = '8.5px sans-serif'
    ctx.textBaseline = 'top'
    const placed: { x0: number; y0: number; x1: number; y1: number }[] = []
    for (const l of lands) {
      const p = projectLand(l, rect)
      if (!p) continue
      const r = l.barren ? R * 0.62 : R
      const w = ctx.measureText(l.name).width
      const x0 = p.x - w / 2
      const x1 = p.x + w / 2
      const y0 = p.y + r + 1.5
      const y1 = y0 + 10
      let clash = false
      for (const b of placed) {
        if (x0 < b.x1 && x1 > b.x0 && y0 < b.y1 && y1 > b.y0) {
          clash = true
          break
        }
      }
      if (clash) continue
      placed.push({ x0, y0, x1, y1 })
      ctx.lineWidth = 2.5
      ctx.strokeStyle = 'rgba(6,12,22,0.85)'
      ctx.strokeText(l.name, p.x, y0)
      ctx.fillStyle = l.barren ? 'rgba(210,205,190,0.75)' : 'rgba(236,240,248,0.92)'
      ctx.fillText(l.name, p.x, y0)
    }
    ctx.textBaseline = 'middle'
  }

  // ── hover tooltip (multi-line) ───────────────────────────────────────────
  if (st.hovered) {
    const l = landById.get(st.hovered)
    const p = l && projectLand(l, rect)
    if (l && p) {
      ctx.beginPath()
      ctx.arc(p.x, p.y, R + 2.5, 0, Math.PI * 2)
      ctx.strokeStyle = '#fff'
      ctx.lineWidth = 2
      ctx.stroke()

      const lines = st.tooltipLines && st.tooltipLines.length ? st.tooltipLines : [l.name]
      ctx.font = '12px sans-serif'
      const lh = 16
      const pad = 7
      const w = Math.max(...lines.map((s) => ctx.measureText(s).width)) + pad * 2
      const h = lines.length * lh + pad * 2 - 4
      let bx = p.x + 14
      let by = p.y - h / 2
      if (bx + w > rect.x + rect.w) bx = p.x - 14 - w
      if (by < rect.y) by = rect.y
      if (by + h > rect.y + rect.h) by = rect.y + rect.h - h

      ctx.fillStyle = 'rgba(8,11,18,0.94)'
      ctx.fillRect(bx, by, w, h)
      ctx.strokeStyle = 'rgba(179,136,255,0.55)'
      ctx.lineWidth = 1
      ctx.strokeRect(bx, by, w, h)
      ctx.textAlign = 'left'
      ctx.textBaseline = 'middle'
      lines.forEach((s, i) => {
        ctx.fillStyle = i === 0 ? '#ffffff' : '#cbd2e0'
        ctx.fillText(s, bx + pad, by + pad + i * lh + lh / 2 - 2)
      })
      ctx.textAlign = 'center'
    }
  }
}
