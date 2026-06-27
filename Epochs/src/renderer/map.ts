// The board scan (public/board.jpg) IS the map — it carries the real geography,
// region colours, terrain, and territory labels. drawMap renders it as the
// basemap, then draws only the LIVE game layer on top: army counters, structures,
// the active-empire ring, placeable rings, and a hover tooltip (anim.ts overlays
// the effects). A CALIBRATION mode instead draws a normalized coordinate grid, for
// registering territories onto the scan (flip CALIBRATION true to re-register).

import type { FrontierKind } from '../shared/bot'
import type { CombatOdds } from '../shared/combat'
import { playerColor } from '../shared/palette'
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

// Median nearest-neighbour spacing of the projected territories → counter size.
function landSpacing(lands: Land[], rect: MapRect): number {
  const pts: { x: number; y: number }[] = []
  for (const l of lands) {
    const p = projectLand(l, rect)
    if (p) pts.push(p)
  }
  if (pts.length < 2) return 40
  const nn = pts.map((a) => {
    let best = Infinity
    for (const o of pts) {
      if (o === a) continue
      best = Math.min(best, Math.hypot(a.x - o.x, a.y - o.y))
    }
    return best
  })
  nn.sort((p, q) => p - q)
  return nn[Math.floor(nn.length / 2)]
}

// ── the board scan basemap ──────────────────────────────────────────────────
// public/board.jpg is the photographed physical board, drawn into `rect` (framed
// to the board's aspect in main.ts). Every land's normalized (x,y) is a fraction
// of THIS image, so projectLand drops each piece exactly on its province.
const boardImg = typeof Image !== 'undefined' ? new Image() : null
let boardReady = false
if (boardImg) {
  boardImg.onload = () => {
    boardReady = true
  }
  boardImg.src = 'board.jpg'
}

// Flip true to re-register territories (draws the scan + a coordinate grid, no
// game layer) — read each centroid off the grid into scripts/coords.json.
const CALIBRATION: boolean = false

function drawCalibrationGrid(ctx: CanvasRenderingContext2D, rect: MapRect): void {
  ctx.save()
  ctx.font = '10px ui-monospace, Menlo, monospace'
  ctx.textAlign = 'left'
  ctx.textBaseline = 'top'
  for (let i = 0; i <= 20; i++) {
    const f = i / 20
    const major = i % 2 === 0
    const x = rect.x + f * rect.w
    const y = rect.y + f * rect.h
    ctx.strokeStyle = major ? 'rgba(15,15,25,0.55)' : 'rgba(15,15,25,0.22)'
    ctx.lineWidth = major ? 1 : 0.5
    ctx.beginPath()
    ctx.moveTo(x, rect.y)
    ctx.lineTo(x, rect.y + rect.h)
    ctx.stroke()
    ctx.beginPath()
    ctx.moveTo(rect.x, y)
    ctx.lineTo(rect.x + rect.w, y)
    ctx.stroke()
    if (major) {
      ctx.fillStyle = 'rgba(255,255,255,0.9)'
      ctx.fillText(f.toFixed(2), x + 2, rect.y + 2)
      ctx.fillText(f.toFixed(2), rect.x + 2, y + 1)
    }
  }
  ctx.fillStyle = 'rgba(255,235,180,0.95)'
  ctx.font = '13px ui-monospace, monospace'
  ctx.fillText('CALIBRATION — registering territories to the board scan', rect.x + 6, rect.y + rect.h - 18)
  ctx.restore()
}

export function drawMap(ctx: CanvasRenderingContext2D, rect: MapRect, st: MapRenderState): void {
  const { lands, pieces } = st
  const vw = st.viewW ?? rect.x * 2 + rect.w
  const vh = st.viewH ?? rect.y * 2 + rect.h

  // ── backdrop + board-scan basemap ─────────────────────────────────────────
  ctx.fillStyle = '#0c0a08'
  ctx.fillRect(0, 0, vw, vh)
  if (boardReady && boardImg) ctx.drawImage(boardImg, rect.x, rect.y, rect.w, rect.h)
  if (CALIBRATION) {
    drawCalibrationGrid(ctx, rect)
    return
  }

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

  const R = clamp(landSpacing(lands, rect) * 0.18, 7, 16)

  // ── live game layer: army counters + structures + placeable rings ─────────
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
      ctx.strokeStyle = 'rgba(24,16,8,0.85)'
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
      ctx.font = `${Math.round(R * 1.25)}px Georgia, serif`
      let i = 0
      for (const s of ss) {
        const glyph =
          s.kind === 'capital' ? '★' : s.kind === 'city' ? '◆' : s.kind === 'monument' ? '▲' : s.kind === 'fort' ? '▮' : ''
        if (!glyph) continue
        const gx = p.x + (army ? R + 4 : 0) + i * (R + 1)
        const gy = army ? p.y - R - 2 : p.y
        ctx.lineWidth = 3
        ctx.strokeStyle = 'rgba(245,238,222,0.92)'
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

  // ── hover ring + tooltip ──────────────────────────────────────────────────
  if (st.hovered) {
    const l = landById.get(st.hovered)
    const p = l && projectLand(l, rect)
    if (l && p) {
      ctx.beginPath()
      ctx.arc(p.x, p.y, R + 4, 0, Math.PI * 2)
      ctx.strokeStyle = '#fff'
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
}

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, rad: number): void {
  const r = Math.min(rad, w / 2, h / 2)
  ctx.moveTo(x + r, y)
  ctx.arcTo(x + w, y, x + w, y + h, r)
  ctx.arcTo(x + w, y + h, x, y + h, r)
  ctx.arcTo(x, y + h, x, y, r)
  ctx.arcTo(x, y, x + w, y, r)
}
