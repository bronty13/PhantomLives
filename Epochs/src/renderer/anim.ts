// A tiny requestAnimationFrame effects layer drawn OVER the static map. Effects
// are pure presentation — they are NEVER fed back into Game.play(), so the engine
// stays deterministic. The loop (in GameUI) is self-stopping: no idle rAF.

import { project, projectLand, type MapRect } from '../shared/mapProjection'
import type { Land } from '../shared/types'

export interface Fx {
  kind: 'spawn' | 'clash' | 'score'
  land?: string // anchor by land id (spawn / clash)
  nx?: number // anchor by normalized point (score), 0..1
  ny?: number
  color: string
  start: number
  dur: number
  text?: string
}

const easeOut = (t: number): number => 1 - (1 - t) * (1 - t)

export function fxDone(fx: Fx, now: number): boolean {
  return now - fx.start >= fx.dur
}

export function drawFx(
  ctx: CanvasRenderingContext2D,
  rect: MapRect,
  fx: Fx,
  now: number,
  landById: Map<string, Land>,
): void {
  const t = Math.min(1, Math.max(0, (now - fx.start) / fx.dur))

  if (fx.kind === 'score') {
    if (fx.nx == null || fx.ny == null) return
    const p = project(fx.nx, fx.ny, rect)
    ctx.font = 'bold 14px sans-serif'
    ctx.textAlign = 'center'
    ctx.globalAlpha = 1 - t
    ctx.fillStyle = fx.color
    ctx.fillText(fx.text ?? '', p.x, p.y - 14 - t * 24)
    ctx.globalAlpha = 1
    return
  }

  const land = fx.land ? landById.get(fx.land) : undefined
  const p = land && projectLand(land, rect)
  if (!p || !land) return
  const r0 = land.barren ? 4 : 8

  if (fx.kind === 'spawn') {
    const r = r0 + easeOut(t) * 11
    ctx.beginPath()
    ctx.arc(p.x, p.y, r, 0, Math.PI * 2)
    ctx.strokeStyle = fx.color
    ctx.globalAlpha = 1 - t
    ctx.lineWidth = 2
    ctx.stroke()
    ctx.globalAlpha = 1
    return
  }

  // clash
  const r = r0 + 4 + easeOut(t) * 13
  ctx.globalAlpha = 1 - t
  ctx.strokeStyle = fx.color
  ctx.beginPath()
  ctx.arc(p.x, p.y, r, 0, Math.PI * 2)
  ctx.lineWidth = 2.5
  ctx.stroke()
  const s = r0 + 6
  ctx.lineWidth = 2
  ctx.beginPath()
  ctx.moveTo(p.x - s, p.y - s)
  ctx.lineTo(p.x + s, p.y + s)
  ctx.moveTo(p.x + s, p.y - s)
  ctx.lineTo(p.x - s, p.y + s)
  ctx.stroke()
  ctx.globalAlpha = 1
  if (fx.text) {
    ctx.font = 'bold 12px sans-serif'
    ctx.textAlign = 'center'
    ctx.fillStyle = fx.color
    ctx.globalAlpha = 1 - t
    ctx.fillText(fx.text, p.x, p.y - r - 4)
    ctx.globalAlpha = 1
  }
}
