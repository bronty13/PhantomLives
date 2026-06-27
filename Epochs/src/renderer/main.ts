// Epochs — interactive world-map UI. Drives the engine's step generator, renders
// the board on a Canvas, and lets you watch the AI or play a seat yourself.
import './style.css'
import { Board } from '../shared/board'
import { WORLD_MAP_DATA } from '../shared/data/board'
import { WORLD_EMPIRES } from '../shared/data/empires'
import {
  Game,
  type GameEvent,
  type GameResult,
  type PlayInput,
  type PlayerConfig,
} from '../shared/game'
import { HeuristicBot, type Difficulty } from '../shared/heuristicBot'
import { nearestLand, type MapRect } from '../shared/mapProjection'
import { areaColor, playerColor } from '../shared/palette'
import { areaControl, placementInfo } from '../shared/boardInsight'
import type { EpochId, Land, PlayerId } from '../shared/types'
import { drawMap, type PlaceableEntry } from './map'
import { drawFx, fxDone, type Fx } from './anim'

const ROMAN = ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII']
const lands = WORLD_MAP_DATA.lands
const LAND_BY_ID = new Map<string, Land>(lands.map((l) => [l.id, l]))
const MAP_BOUNDS = ((): { minX: number; minY: number; maxX: number; maxY: number } => {
  let minX = 1
  let minY = 1
  let maxX = 0
  let maxY = 0
  for (const l of lands) {
    if (l.x == null || l.y == null) continue
    minX = Math.min(minX, l.x)
    maxX = Math.max(maxX, l.x)
    minY = Math.min(minY, l.y)
    maxY = Math.max(maxY, l.y)
  }
  return { minX, minY, maxX, maxY }
})()

type AwaitEvent = Extract<GameEvent, { type: 'awaitPlacement' }>
type AwaitEventsEvent = Extract<GameEvent, { type: 'awaitEvents' }>

interface NewGameOpts {
  players: number
  difficulty: Difficulty
  humanSeat: number // 0 = all AI, else 1-based seat the human plays
  seed: number
}

class GameUI {
  private game!: Game
  private iter!: Generator<GameEvent, GameResult, PlayInput>
  private readonly canvas: HTMLCanvasElement
  private readonly ctx: CanvasRenderingContext2D
  private rect: MapRect = { x: 0, y: 0, w: 0, h: 0 }

  private hovered: string | null = null
  private placeable: Map<string, PlaceableEntry> | null = null
  private pending: AwaitEvent | null = null
  private pendingEvents: AwaitEventsEvent | null = null
  private eventSel: { greater?: string; lesser?: string } = {}
  private auto = false
  private speed = 320
  private timer: ReturnType<typeof setTimeout> | null = null
  private over = false
  private helpOpen = false

  private fx: Fx[] = []
  private rafId: number | null = null
  private activePlayer: PlayerId | null = null
  private attackOdds: number | null = null // win% of the human's pending attack (clash float)

  private opts: NewGameOpts = { players: 4, difficulty: 'medium', humanSeat: 0, seed: 1 }
  private playerOrder: string[] = []
  private status = ''
  private currentEpoch: EpochId = 1
  private log: string[] = []

  constructor(private readonly root: HTMLElement) {
    root.innerHTML = TEMPLATE
    this.canvas = root.querySelector('#map') as HTMLCanvasElement
    this.ctx = this.canvas.getContext('2d') as CanvasRenderingContext2D
    this.wireControls()
    this.canvas.addEventListener('mousemove', (e) => this.onMove(e))
    this.canvas.addEventListener('mouseleave', () => { this.hovered = null; this.render() })
    this.canvas.addEventListener('click', (e) => this.onClick(e))
    window.addEventListener('resize', () => this.render())
    this.newGame()
    this.showHelp() // first-run onboarding (pauses until dismissed)
  }

  private showHelp(): void {
    this.helpOpen = true
    if (this.timer) clearTimeout(this.timer)
    this.timer = null
    ;(this.root.querySelector('#help') as HTMLElement).classList.remove('hidden')
  }

  private hideHelp(): void {
    this.helpOpen = false
    ;(this.root.querySelector('#help') as HTMLElement).classList.add('hidden')
    this.scheduleNext()
  }

  // The original scanned rulebook + sample game, bundled into the build (the
  // owner's own scans). Pages are probed sequentially until one is missing.
  private openRulebook(): void {
    this.helpOpen = true
    if (this.timer) clearTimeout(this.timer)
    this.timer = null
    const el = this.root.querySelector('#rulebook') as HTMLElement
    const box = el.querySelector('.rb-pages') as HTMLElement
    if (!box.dataset.loaded) {
      box.dataset.loaded = '1'
      const tryPage = (n: number): void => {
        const img = new Image()
        img.alt = `Rulebook page ${n}`
        img.className = 'rb-page'
        img.onload = (): void => {
          box.appendChild(img)
          tryPage(n + 1)
        }
        img.onerror = (): void => {
          if (n === 1) {
            box.innerHTML =
              '<p class="muted" style="padding:20px">The original rulebook scans aren’t bundled on this machine. They live in <code>src/renderer/public/rulebook/</code> (git-ignored) and are packaged into the local build.</p>'
          }
        }
        img.src = `rulebook/page-${String(n).padStart(2, '0')}.jpg`
      }
      tryPage(1)
    }
    el.classList.remove('hidden')
  }

  private closeRulebook(): void {
    this.helpOpen = false
    ;(this.root.querySelector('#rulebook') as HTMLElement).classList.add('hidden')
    this.scheduleNext()
  }

  // ── lifecycle ──────────────────────────────────────────────────────────
  private newGame(): void {
    if (this.timer) clearTimeout(this.timer)
    const { players, difficulty, humanSeat, seed } = this.opts
    const configs: PlayerConfig[] = []
    for (let i = 0; i < players; i++) {
      const seat = i + 1
      const human = seat === humanSeat
      configs.push({
        id: `P${seat}`,
        name: human ? `You (P${seat})` : `P${seat}`,
        isHuman: human,
        bot: human ? undefined : new HeuristicBot({ name: `P${seat}`, difficulty }),
      })
    }
    this.game = new Game({ board: new Board(WORLD_MAP_DATA), deck: WORLD_EMPIRES, players: configs, seed })
    this.iter = this.game.play()
    this.playerOrder = configs.map((c) => c.id)
    this.over = false
    this.pending = null
    this.placeable = null
    this.pendingEvents = null
    this.eventSel = {}
    this.hideEventPanel()
    if (this.rafId != null) cancelAnimationFrame(this.rafId)
    this.rafId = null
    this.fx = []
    this.activePlayer = null
    this.attackOdds = null
    ;(this.root.querySelector('#gameover') as HTMLElement | null)?.classList.add('hidden')
    this.log = []
    this.status = humanSeat ? `You are P${humanSeat}.` : 'Watching the AI.'
    this.auto = true // auto-play; it pauses for the human's own decisions
    this.render()
    this.scheduleNext()
  }

  private advance(input?: PlayInput): void {
    if (this.over) return
    const step = this.iter.next(input)
    if (step.done) {
      this.onEnd(step.value)
      return
    }
    this.handle(step.value)
    this.render()
    this.scheduleNext()
  }

  private scheduleNext(): void {
    if (this.timer) clearTimeout(this.timer)
    this.timer = null
    if (this.auto && !this.pending && !this.pendingEvents && !this.over && !this.helpOpen) {
      // dwell at least `speed`, but long enough for any running animation to finish
      const now = performance.now()
      const pend = this.fx.reduce((m, f) => Math.max(m, f.start + f.dur - now), 0)
      this.timer = setTimeout(() => this.advance(), Math.max(this.speed, pend))
    }
  }

  private handle(ev: GameEvent): void {
    const now = performance.now()
    switch (ev.type) {
      case 'epochStart':
        this.currentEpoch = ev.epoch
        this.pushLog(`— Epoch ${ROMAN[ev.epoch]} —`)
        break
      case 'turnStart':
        this.activePlayer = ev.player
        this.status = `Epoch ${ROMAN[ev.epoch]}: ${ev.empire} (${this.nameOf(ev.player)})`
        break
      case 'awaitEvents':
        this.pendingEvents = ev
        this.eventSel = {}
        this.status = `Your turn — ${ev.empire}: play events? (optional)`
        this.showEventPanel(ev)
        break
      case 'eventsPlayed':
        this.pushLog(`${this.nameOf(ev.player)} played ${ev.played.join(', ')}`)
        break
      case 'setup':
        this.fx.push({ kind: 'spawn', land: ev.land, color: this.colorOf(ev.player), start: now, dur: 260 })
        this.startLoop()
        break
      case 'awaitPlacement':
        this.pending = ev
        this.activePlayer = ev.player
        this.placeable = new Map(
          ev.frontier.map((f) => [f.land, { kind: f.kind, odds: f.odds, amphibious: f.amphibious }]),
        )
        this.status = `Your turn — ${ev.empire}: place an army (${ev.remaining} left).`
        break
      case 'placement': {
        if (ev.outcome) {
          const color = ev.outcome === 'attacker' ? '#7cfc9a' : '#e15554'
          const text = this.attackOdds != null ? `${Math.round(this.attackOdds * 100)}%` : undefined
          this.fx.push({ kind: 'clash', land: ev.land, color, start: now, dur: 380, text })
          const verb = ev.outcome === 'attacker' ? 'WON' : 'REPELLED'
          this.pushLog(`${this.nameOf(ev.player)} attacked ${this.landName(ev.land)} — ${verb}`)
        } else {
          this.fx.push({ kind: 'spawn', land: ev.land, color: this.colorOf(ev.player), start: now, dur: 260 })
        }
        this.startLoop()
        this.attackOdds = null
        if (this.pending && ev.player === this.pending.player) {
          this.pending = null
          this.placeable = null
        }
        break
      }
      case 'score': {
        this.pushLog(`${this.nameOf(ev.player)} scored +${ev.gained} → ${ev.total}`)
        if (ev.gained > 0) {
          let sx = 0
          let sy = 0
          let n = 0
          for (const p of this.game.state.pieces) {
            if (p.owner !== ev.player || p.kind !== 'army' || p.epochColor !== this.currentEpoch) continue
            const l = LAND_BY_ID.get(p.land)
            if (l?.x != null && l?.y != null) {
              sx += l.x
              sy += l.y
              n++
            }
          }
          if (n > 0) {
            this.fx.push({ kind: 'score', nx: sx / n, ny: sy / n, color: this.colorOf(ev.player), start: now, dur: 1100, text: `+${ev.gained}` })
            this.startLoop()
          }
        }
        break
      }
      case 'preeminence':
        if (ev.player) this.pushLog(`★ pre-eminence → ${this.nameOf(ev.player)}`)
        break
      case 'turnEnd':
        this.activePlayer = null
        break
      default:
        break
    }
  }

  private onEnd(result: GameResult): void {
    this.over = true
    this.pending = null
    this.placeable = null
    this.pendingEvents = null
    this.activePlayer = null
    this.hideEventPanel()
    if (this.timer) clearTimeout(this.timer)
    const win = result.standings[0]
    this.status = `Game over — ${this.nameOf(win.id)} wins (${win.vp} VP)`
    this.pushLog(`=== ${this.nameOf(win.id)} wins with ${win.vp} VP ===`)
    this.render()
    this.renderGameOver(result)
  }

  // ── input ──────────────────────────────────────────────────────────────
  private onMove(e: MouseEvent): void {
    const { px, py } = this.toCanvas(e)
    const l = nearestLand(lands, this.rect, px, py, 14)
    const id = l ? l.id : null
    if (id !== this.hovered) {
      this.hovered = id
      this.render()
    }
  }

  private onClick(e: MouseEvent): void {
    if (!this.pending) return
    const { px, py } = this.toCanvas(e)
    const l = nearestLand(lands, this.rect, px, py, 14)
    if (l && this.placeable?.has(l.id)) {
      const opt = this.pending.frontier.find((f) => f.land === l.id)
      this.attackOdds = opt?.kind === 'enemy' ? (opt.odds?.attacker ?? null) : null
      this.advance(l.id)
    }
  }

  // ── event panel (human's event phase) ──────────────────────────────────
  private showEventPanel(ev: AwaitEventsEvent): void {
    const panel = this.root.querySelector('#event-panel') as HTMLElement
    const chip = (c: { id: string; name: string }, cls: string) =>
      `<button class="evt" data-cls="${cls}" data-id="${c.id}">${esc(c.name)}</button>`
    panel.innerHTML = `
      <div class="evt-box">
        <h3>${esc(ev.empire)} — play events? <span class="muted">(optional, ≤1 each)</span></h3>
        <div class="evt-group"><span>Greater</span>${
          ev.hand.greater.map((c) => chip(c, 'greater')).join('') || '<em>none</em>'
        }</div>
        <div class="evt-group"><span>Lesser</span>${
          ev.hand.lesser.map((c) => chip(c, 'lesser')).join('') || '<em>none</em>'
        }</div>
        <div class="evt-actions"><button id="evt-skip">Skip</button><button id="evt-play" class="primary">Play Selected</button></div>
      </div>`
    panel.classList.remove('hidden')
    panel.querySelectorAll('.evt').forEach((el) => {
      el.addEventListener('click', () => {
        const cls = (el as HTMLElement).dataset.cls as 'greater' | 'lesser'
        const id = (el as HTMLElement).dataset.id as string
        if (this.eventSel[cls] === id) delete this.eventSel[cls]
        else this.eventSel[cls] = id
        panel
          .querySelectorAll(`.evt[data-cls="${cls}"]`)
          .forEach((e) => e.classList.toggle('sel', (e as HTMLElement).dataset.id === this.eventSel[cls]))
      })
    })
    ;(panel.querySelector('#evt-skip') as HTMLButtonElement).onclick = () => this.resolveEvents(undefined)
    ;(panel.querySelector('#evt-play') as HTMLButtonElement).onclick = () => this.resolveEvents({ ...this.eventSel })
  }

  private resolveEvents(choice: { greater?: string; lesser?: string } | undefined): void {
    this.pendingEvents = null
    this.hideEventPanel()
    this.advance(choice)
    this.drainToInteractive()
  }

  /**
   * When stepping manually (auto off), progress through the non-interactive
   * yields (eventsPlayed, setup, …) to the player's next decision so the human
   * isn't parked on a stale, non-actionable state. (Auto mode drains via the
   * timer, so this is a no-op there.)
   */
  private drainToInteractive(): void {
    while (!this.auto && !this.over && !this.pending && !this.pendingEvents) {
      this.advance()
    }
  }

  private hideEventPanel(): void {
    const panel = this.root.querySelector('#event-panel') as HTMLElement | null
    if (panel) {
      panel.classList.add('hidden')
      panel.innerHTML = ''
    }
  }

  private toCanvas(e: MouseEvent): { px: number; py: number } {
    const b = this.canvas.getBoundingClientRect()
    return { px: e.clientX - b.left, py: e.clientY - b.top }
  }

  // ── rendering ────────────────────────────────────────────────────────────
  private render(): void {
    this.resize()
    this.drawScene(performance.now())
    this.renderSidebar()
    if (this.fx.length) this.startLoop()
  }

  private resize(): void {
    const dpr = window.devicePixelRatio || 1
    const cw = this.canvas.clientWidth
    const ch = this.canvas.clientHeight
    if (this.canvas.width !== cw * dpr || this.canvas.height !== ch * dpr) {
      this.canvas.width = cw * dpr
      this.canvas.height = ch * dpr
    }
    // Fit the view to where territories actually are (their bbox + margin), with
    // the equirectangular correction that one x-unit spans twice the longitude of
    // a y-unit. rect still maps the full 0..1 domain, but is sized/offset so the
    // populated bbox fills the canvas (rect overflows it — that's fine).
    const b = MAP_BOUNDS
    const bw = b.maxX - b.minX
    const bh = b.maxY - b.minY
    const m = 0.05
    const minX = b.minX - bw * m
    const maxX = b.maxX + bw * m
    const minY = b.minY - bh * m
    const maxY = b.maxY + bh * m
    const dw = maxX - minX
    const dh = maxY - minY
    const pad = 6
    const s = Math.min((cw - 2 * pad) / (dw * 2), (ch - 2 * pad) / dh)
    const rw = 2 * s
    const rh = s
    this.rect = {
      x: (cw - dw * rw) / 2 - minX * rw,
      y: (ch - dh * rh) / 2 - minY * rh,
      w: rw,
      h: rh,
    }
  }

  private drawScene(now: number): void {
    const dpr = window.devicePixelRatio || 1
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    drawMap(this.ctx, this.rect, {
      lands,
      pieces: this.game.state.pieces,
      playerOrder: this.playerOrder,
      currentEpoch: this.currentEpoch,
      activePlayer: this.activePlayer,
      hovered: this.hovered,
      placeable: this.placeable,
      tooltipLines: this.tooltipLines(),
      viewW: this.canvas.clientWidth,
      viewH: this.canvas.clientHeight,
    })
    for (const fx of this.fx) drawFx(this.ctx, this.rect, fx, now, LAND_BY_ID)
  }

  private startLoop(): void {
    if (this.rafId != null) return
    this.rafId = requestAnimationFrame(this.frame)
  }

  // Self-stopping animation loop (no idle rAF). Effects are render-only.
  private frame = (now: number): void => {
    this.fx = this.fx.filter((f) => !fxDone(f, now))
    this.drawScene(now)
    if (this.fx.length) this.rafId = requestAnimationFrame(this.frame)
    else this.rafId = null
  }

  /** Tooltip lines for the hovered land: rich placement info on your turn, else null. */
  private tooltipLines(): string[] | null {
    if (!this.hovered || !this.pending) return null
    const opt = this.pending.frontier.find((f) => f.land === this.hovered)
    if (!opt) return null
    const empire = WORLD_EMPIRES.find(
      (e) => e.name === this.pending!.empire && e.epoch === this.currentEpoch,
    )
    return placementInfo(opt.land, opt.kind, opt.odds, opt.amphibious, {
      board: this.game.board,
      pieces: this.game.state.pieces,
      epoch: this.currentEpoch,
      player: this.pending.player,
      empireHasCapital: empire?.hasCapital ?? true,
    })
  }

  private renderSidebar(): void {
    const epochEl = this.root.querySelector('#epoch')!
    epochEl.textContent = `Epoch ${ROMAN[this.currentEpoch]} / VII`
    const statusEl = this.root.querySelector('#status') as HTMLElement
    statusEl.textContent = this.status
    statusEl.style.borderLeft = this.activePlayer
      ? `4px solid ${this.colorOf(this.activePlayer)}`
      : '4px solid transparent'

    const players = this.game.state.players
    const maxVp = Math.max(1, ...players.map((p) => p.vp))
    const sb = this.root.querySelector('#scoreboard')!
    sb.innerHTML = [...players]
      .map((p, i) => ({ p, i }))
      .sort((a, b) => b.p.vp - a.p.vp)
      .map(
        ({ p, i }) =>
          `<div class="score${p.id === this.activePlayer ? ' active' : ''}">` +
          `<span class="dot" style="background:${playerColor(i)}"></span>` +
          `<span class="pname">${esc(p.name)}</span><span class="pvp">${p.vp}</span>` +
          `<div class="bar" style="width:${Math.round((100 * p.vp) / maxVp)}%;background:${playerColor(i)}"></div></div>`,
      )
      .join('')

    this.renderAreaControl()

    const logEl = this.root.querySelector('#log')!
    logEl.innerHTML = this.log.slice(-80).map((l) => `<div>${esc(l)}</div>`).join('')
    logEl.scrollTop = logEl.scrollHeight

    const endBtn = this.root.querySelector('#end-turn') as HTMLButtonElement
    endBtn.disabled = !this.pending
  }

  private renderAreaControl(): void {
    const el = this.root.querySelector('#areas')
    if (!el) return
    const rows = areaControl(this.game.board, this.game.state.pieces, this.currentEpoch)
    el.innerHTML = rows
      .map((r) => {
        const dot = r.leaderId
          ? `<span class="dot" style="background:${this.colorOf(r.leaderId)}"></span>`
          : `<span class="dot empty"></span>`
        return (
          `<div class="area${r.leaderId === this.activePlayer ? ' active' : ''}">` +
          `<span class="swatch" style="background:${areaColor(r.areaId)}"></span>` +
          `<span class="aname">${esc(r.name)}</span><span class="aval">×${r.value}</span>` +
          `${dot}<span class="atier${r.contested ? ' contested' : ''}">${r.leaderId ? r.tier : '—'}</span>` +
          `<span class="abank">${r.bankVP}</span></div>`
        )
      })
      .join('')
  }

  private renderGameOver(result: GameResult): void {
    const el = this.root.querySelector('#gameover') as HTMLElement
    const rows = result.standings
      .map((s, rank) => {
        const i = this.playerOrder.indexOf(s.id)
        const base = s.vp - s.preeminence.reduce((a, b) => a + b, 0)
        const chips = s.preeminence.map((v) => `<span class="pre-chip" data-v="${v}">◇</span>`).join('')
        return (
          `<div class="go-row${rank === 0 ? ' winner' : ''}">` +
          `<span class="dot" style="background:${playerColor(i)}"></span>` +
          `<span class="go-name">${rank === 0 ? '👑 ' : ''}${esc(s.name)}</span>` +
          `<span class="go-pre">${chips}</span><span class="go-vp">${base}</span></div>`
        )
      })
      .join('')
    el.innerHTML =
      `<div class="evt-box"><h3>Game over — ${esc(this.nameOf(result.winner))} wins</h3>` +
      `<div class="go-list">${rows}</div>` +
      `<div class="muted">hidden pre-eminence markers revealed →</div>` +
      `<div class="evt-actions"><button id="go-again" class="primary">Play Again</button></div></div>`
    el.classList.remove('hidden')
    ;(el.querySelector('#go-again') as HTMLButtonElement).onclick = () => {
      el.classList.add('hidden')
      this.newGame()
    }
    const chipEls = [...el.querySelectorAll('.pre-chip')] as HTMLElement[]
    chipEls.forEach((chip, k) => {
      setTimeout(() => {
        chip.classList.add('flip')
        chip.textContent = chip.dataset.v ?? ''
        const vpEl = chip.closest('.go-row')?.querySelector('.go-vp') as HTMLElement | null
        if (vpEl) {
          vpEl.textContent = String(
            parseInt(vpEl.textContent || '0', 10) + parseInt(chip.dataset.v || '0', 10),
          )
        }
      }, 400 + k * 150)
    })
  }

  // ── controls ──────────────────────────────────────────────────────────────
  private wireControls(): void {
    const q = <T extends HTMLElement>(s: string) => this.root.querySelector(s) as T
    q<HTMLButtonElement>('#help-btn').onclick = () => this.showHelp()
    q<HTMLButtonElement>('#help-close').onclick = () => this.hideHelp()
    q<HTMLButtonElement>('#rulebook-btn').onclick = () => this.openRulebook()
    q<HTMLButtonElement>('#rb-close').onclick = () => this.closeRulebook()
    q<HTMLButtonElement>('#step').onclick = () => {
      this.auto = false
      this.syncAuto()
      if (!this.pending && !this.pendingEvents) this.advance()
    }
    q<HTMLButtonElement>('#auto').onclick = () => {
      this.auto = !this.auto
      this.syncAuto()
      this.scheduleNext()
    }
    q<HTMLButtonElement>('#end-turn').onclick = () => {
      if (this.pending) this.advance(undefined) // stop placing this turn
    }
    q<HTMLButtonElement>('#newgame').onclick = () => {
      this.opts = {
        players: parseInt(q<HTMLSelectElement>('#players').value, 10),
        difficulty: q<HTMLSelectElement>('#difficulty').value as Difficulty,
        humanSeat: q<HTMLInputElement>('#human').checked ? 1 : 0,
        seed: parseInt(q<HTMLInputElement>('#seed').value, 10) || 1,
      }
      this.newGame()
    }
    const sp = q<HTMLInputElement>('#speed')
    sp.oninput = () => {
      this.speed = 720 - parseInt(sp.value, 10) // slider right = faster
    }
    this.speed = 720 - parseInt(sp.value, 10)
  }

  private syncAuto(): void {
    const b = this.root.querySelector('#auto') as HTMLButtonElement
    b.textContent = this.auto ? '⏸ Pause' : '▶ Auto'
    b.classList.toggle('on', this.auto)
  }

  // ── helpers ────────────────────────────────────────────────────────────
  private nameOf(id: string): string {
    return this.game.state.players.find((p) => p.id === id)?.name ?? id
  }
  private colorOf(id: PlayerId): string {
    return playerColor(this.playerOrder.indexOf(id))
  }
  private landName(land: string): string {
    return LAND_BY_ID.get(land)?.name ?? land
  }
  private pushLog(s: string): void {
    this.log.push(s)
  }
}

function esc(s: string): string {
  return s.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c] as string)
}

const TEMPLATE = `
<div class="app">
  <header class="topbar">
    <h1>Epochs</h1>
    <div class="hud"><span id="epoch">Epoch I / VII</span><button id="help-btn" class="help-btn">? How to play</button><button id="rulebook-btn" class="help-btn">📖 Rulebook</button></div>
  </header>
  <div class="body">
    <div class="mapwrap"><canvas id="map"></canvas><div id="event-panel" class="event-panel hidden"></div><div id="gameover" class="event-panel hidden"></div>
      <div id="rulebook" class="event-panel hidden"><div class="evt-box rb-box"><div class="rb-head"><h3>Original Rulebook &amp; Sample Game</h3><button id="rb-close">Close</button></div><div class="rb-pages"></div></div></div>
      <div id="help" class="event-panel hidden">
        <div class="evt-box help-box">
          <h3>How to play Epochs</h3>
          <div class="help-body">
            <p class="help-lead">Lead a succession of empires across <b>seven epochs</b> of history. Whoever has the most <b>Victory Points (VP)</b> at the end wins.</p>
            <h4>A turn</h4>
            <p>Each epoch every player commands <b>one empire</b> of that era. You may play a couple of <b>event cards</b>, then place your armies one at a time — spreading from your homeland into bordering lands (or across seas you can sail) — and then you <b>score</b>. Empires die off between epochs; your VP carry on.</p>
            <h4>Scoring — the heart of it</h4>
            <p>You earn VP for controlling the colored <b>regions</b>:</p>
            <ul>
              <li><b>Presence</b> (≥1 army in a region) = the region's value</li>
              <li><b>Dominance</b> (≥2 armies and more than anyone else) = <b>×2</b></li>
              <li><b>Control</b> (≥3 and no rival there) = <b>×3</b></li>
            </ul>
            <p>Plus <b>★ capital</b> = 2, <b>◆ city</b> = 1, <b>▲ monument</b> = 1 each turn you hold them. A region's value changes by epoch — watch the <b>Regions</b> panel for what's worth fighting over now.</p>
            <h4>Combat</h4>
            <p>To take an enemy land you attack: roll <b>2 dice, keep the higher</b>, vs the defender's <b>1</b> — higher wins, an exact <b>tie is rerolled</b>. Mountains, forests, the Great Wall, straits and sea-landings make the <b>defender roll 2 dice</b> (keep higher); a <b>▮ fort</b> adds +1 to the defender. On your turn, <b>hover</b> a target to see the exact win odds.</p>
            <h4>It stays close</h4>
            <p>The player in <b>last place drafts first</b> each epoch and gets first pick of the strongest new empire — so leads don't run away. And each epoch's leader secretly draws a hidden <b>pre-eminence</b> bonus, revealed only at the very end.</p>
            <h4>Events</h4>
            <p>You hold a fixed hand of cards for the <i>whole game</i> (no refills): <b>Leaders / Weaponry</b> (stronger attacks), <b>bonus armies</b>, or <b>Coins</b> (build forts). Spend them wisely — up to one of each before a turn.</p>
            <h4>Watch or play</h4>
            <p>By default you <b>watch the AI</b>. To take a seat, tick <b>“I play (seat 1)”</b> and press <b>New Game</b>. On your turn, click a highlighted land to place an army — <span class="hk g">●</span> settle · <span class="hk b">●</span> reclaim · <span class="hk r">●</span> attack (ring color = your odds). Use <b>Step</b> / <b>Auto</b> and the speed slider to control playback; <b>End Turn</b> stops placing early.</p>
          </div>
          <div class="evt-actions"><button id="help-close" class="primary">Got it — start</button></div>
        </div>
      </div>
    </div>
    <aside class="sidebar">
      <div class="status" id="status"></div>
      <section>
        <h2>Standings</h2>
        <div id="scoreboard"></div>
      </section>
      <section>
        <h2>Regions (this epoch)</h2>
        <div id="areas"></div>
      </section>
      <section class="controls">
        <h2>Game</h2>
        <div class="row"><button id="step">Step</button><button id="auto" class="on">⏸ Pause</button><button id="end-turn" disabled>End Turn</button></div>
        <label class="row">Speed <input type="range" id="speed" min="60" max="660" value="400" /></label>
        <div class="row">
          <label>Players <select id="players"><option>3</option><option selected>4</option><option>5</option><option>6</option></select></label>
          <label>AI <select id="difficulty"><option>easy</option><option selected>medium</option><option>hard</option></select></label>
        </div>
        <div class="row"><label><input type="checkbox" id="human" /> I play (seat 1)</label><label>Seed <input type="number" id="seed" value="1" min="1" style="width:64px" /></label></div>
        <div class="row"><button id="newgame" class="primary">New Game</button></div>
      </section>
      <section class="legend">
        <h2>Legend</h2>
        <div>★ capital&nbsp; ◆ city&nbsp; ▲ monument&nbsp; ▮ fort&nbsp; <span class="res">●</span> resource</div>
        <div class="muted">On your turn: <span style="color:#7cfc9a">○</span> settle · <span style="color:#4d9de0">○</span> reclaim · <span style="color:#e15554">○</span> attack (ring color = odds)</div>
        <div class="muted">Big dots = territories, tinted by region; filled = controlled by a player.</div>
      </section>
      <section><h2>Log</h2><div id="log" class="log"></div></section>
    </aside>
  </div>
</div>
`

const app = document.getElementById('app')
if (app) new GameUI(app)
