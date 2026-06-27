// Canvas rendering of the world map: area-tinted territories, adjacency edges,
// armies (owner-colored), structures (★ capital / ◆ city / ▲ monument), resource
// dots, placeable highlights for the human turn, and a hover label.

import { areaColor, playerColor } from '../shared/palette'
import { projectLand, type MapRect } from '../shared/mapProjection'
import type { BoardPiece, Land, PlayerId } from '../shared/types'

export interface MapRenderState {
  lands: Land[]
  pieces: readonly BoardPiece[]
  playerOrder: PlayerId[]
  hovered?: string | null
  placeable?: Set<string> | null
}

function hexA(hex: string, a: number): string {
  const r = parseInt(hex.slice(1, 3), 16)
  const g = parseInt(hex.slice(3, 5), 16)
  const b = parseInt(hex.slice(5, 7), 16)
  return `rgba(${r},${g},${b},${a})`
}

export function drawMap(ctx: CanvasRenderingContext2D, rect: MapRect, st: MapRenderState): void {
  const { lands, pieces } = st
  const landById = new Map(lands.map((l) => [l.id, l]))
  const colorOf = (pid: PlayerId | null): string => {
    if (pid == null) return '#8a8a8a'
    const i = st.playerOrder.indexOf(pid)
    return i >= 0 ? playerColor(i) : '#8a8a8a'
  }

  const armyOwner = new Map<string, PlayerId | null>()
  const structs = new Map<string, BoardPiece[]>()
  for (const p of pieces) {
    if (p.kind === 'army') armyOwner.set(p.land, p.owner)
    else {
      const a = structs.get(p.land) ?? []
      a.push(p)
      structs.set(p.land, a)
    }
  }

  ctx.fillStyle = '#0a0e16'
  ctx.fillRect(rect.x - 24, rect.y - 24, rect.w + 48, rect.h + 48)

  // adjacency edges (dedup by id ordering)
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

    const owner = armyOwner.get(l.id)
    if (owner != null) {
      ctx.beginPath()
      ctx.arc(p.x, p.y, r - 2.5, 0, Math.PI * 2)
      ctx.fillStyle = colorOf(owner)
      ctx.fill()
    } else if (l.hasResource && !l.barren) {
      ctx.beginPath()
      ctx.arc(p.x, p.y, 2.2, 0, Math.PI * 2)
      ctx.fillStyle = '#f5d76e'
      ctx.fill()
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
        ctx.fillStyle = colorOf(s.owner)
        ctx.fillText(glyph, p.x + r + 5 + i * 9, p.y - r + 2)
        i++
      }
    }

    if (st.placeable && st.placeable.has(l.id)) {
      ctx.beginPath()
      ctx.arc(p.x, p.y, r + 4, 0, Math.PI * 2)
      ctx.strokeStyle = '#7cfc9a'
      ctx.lineWidth = 2
      ctx.stroke()
    }
  }

  if (st.hovered) {
    const l = landById.get(st.hovered)
    const p = l && projectLand(l, rect)
    if (l && p) {
      ctx.beginPath()
      ctx.arc(p.x, p.y, 11, 0, Math.PI * 2)
      ctx.strokeStyle = '#fff'
      ctx.lineWidth = 2
      ctx.stroke()
      ctx.font = '12px sans-serif'
      ctx.textAlign = 'left'
      const tw = ctx.measureText(l.name).width
      ctx.fillStyle = 'rgba(0,0,0,0.82)'
      ctx.fillRect(p.x + 12, p.y - 23, tw + 12, 19)
      ctx.fillStyle = '#fff'
      ctx.textBaseline = 'middle'
      ctx.fillText(l.name, p.x + 18, p.y - 13)
      ctx.textAlign = 'center'
    }
  }
}
