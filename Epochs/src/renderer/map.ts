// Canvas rendering of the world map (the STATIC base layer; anim.ts overlays it).
// Area-tinted territories, adjacency edges, armies (owner-colored), structures
// (★/◆/▲/▮), resource dots, an active-empire ring, per-kind placeable rings, and
// a multi-line hover tooltip.

import type { FrontierKind } from '../shared/bot'
import type { CombatOdds } from '../shared/combat'
import { areaColor, playerColor } from '../shared/palette'
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
}

function hexA(hex: string, a: number): string {
  const r = parseInt(hex.slice(1, 3), 16)
  const g = parseInt(hex.slice(3, 5), 16)
  const b = parseInt(hex.slice(5, 7), 16)
  return `rgba(${r},${g},${b},${a})`
}

/** Ring color for a placeable land: settle green, reclaim blue, attack by odds. */
function placeColor(e: PlaceableEntry): string {
  if (e.kind === 'empty') return '#7cfc9a'
  if (e.kind === 'own_old') return '#4d9de0'
  const p = e.odds?.attacker ?? 0
  return p >= 0.6 ? '#9ccc65' : p >= 0.35 ? '#e1bc29' : '#e15554'
}

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

  ctx.fillStyle = '#0a0e16'
  ctx.fillRect(rect.x - 24, rect.y - 24, rect.w + 48, rect.h + 48)

  // adjacency edges
  ctx.strokeStyle = 'rgba(120,140,170,0.12)'
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

  // lands
  ctx.textAlign = 'center'
  ctx.textBaseline = 'middle'
  for (const l of lands) {
    const p = projectLand(l, rect)
    if (!p) continue
    const r = l.barren ? 4 : 8
    ctx.beginPath()
    ctx.arc(p.x, p.y, r, 0, Math.PI * 2)
    ctx.fillStyle = l.barren ? 'rgba(60,66,80,0.5)' : hexA(areaColor(l.area), 0.3)
    ctx.fill()
    ctx.lineWidth = 1.5
    ctx.strokeStyle = l.barren ? 'rgba(90,96,110,0.6)' : hexA(areaColor(l.area), 0.75)
    ctx.stroke()

    const army = armyAt.get(l.id)
    if (army) {
      ctx.beginPath()
      ctx.arc(p.x, p.y, r - 2.5, 0, Math.PI * 2)
      ctx.fillStyle = colorOf(army.owner)
      ctx.fill()
    } else if (l.hasResource && !l.barren) {
      ctx.beginPath()
      ctx.arc(p.x, p.y, 2.2, 0, Math.PI * 2)
      ctx.fillStyle = '#f5d76e'
      ctx.fill()
    }

    // active-empire "live army" ring
    if (
      army &&
      st.activePlayer &&
      army.owner === st.activePlayer &&
      army.epochColor === st.currentEpoch
    ) {
      ctx.beginPath()
      ctx.arc(p.x, p.y, r + 2.5, 0, Math.PI * 2)
      ctx.strokeStyle = 'rgba(255,255,255,0.85)'
      ctx.lineWidth = 1.5
      ctx.stroke()
    }

    const ss = structs.get(l.id)
    if (ss && ss.length) {
      ctx.font = '11px sans-serif'
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
        const gx = p.x + r + 5 + i * 9
        const gy = p.y - r + 2
        ctx.lineWidth = 3
        ctx.strokeStyle = 'rgba(8,11,18,0.9)'
        ctx.strokeText(glyph, gx, gy) // halo for legibility
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

  // hover tooltip (multi-line)
  if (st.hovered) {
    const l = landById.get(st.hovered)
    const p = l && projectLand(l, rect)
    if (l && p) {
      ctx.beginPath()
      ctx.arc(p.x, p.y, 11, 0, Math.PI * 2)
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

      ctx.fillStyle = 'rgba(8,11,18,0.93)'
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
