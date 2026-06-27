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
import { playerColor } from '../shared/palette'
import { drawMap } from './map'

const ROMAN = ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII']
const lands = WORLD_MAP_DATA.lands

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
  private placeable: Set<string> | null = null
  private pending: AwaitEvent | null = null
  private pendingEvents: AwaitEventsEvent | null = null
  private eventSel: { greater?: string; lesser?: string } = {}
  private auto = false
  private speed = 320
  private timer: ReturnType<typeof setTimeout> | null = null
  private over = false

  private opts: NewGameOpts = { players: 4, difficulty: 'medium', humanSeat: 0, seed: 1 }
  private playerOrder: string[] = []
  private status = ''
  private currentEpoch = 1
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
    if (this.auto && !this.pending && !this.pendingEvents && !this.over) {
      this.timer = setTimeout(() => this.advance(), this.speed)
    }
  }

  private handle(ev: GameEvent): void {
    switch (ev.type) {
      case 'epochStart':
        this.currentEpoch = ev.epoch
        this.pushLog(`— Epoch ${ROMAN[ev.epoch]} —`)
        break
      case 'turnStart':
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
      case 'awaitPlacement':
        this.pending = ev
        this.placeable = new Set(ev.frontier.map((f) => f.land))
        this.status = `Your turn — ${ev.empire}: place an army (${ev.remaining} left). Click a highlighted land, or End Turn.`
        break
      case 'placement':
        if (this.pending && ev.player === this.pending.player) {
          this.pending = null
          this.placeable = null
        }
        break
      case 'score':
        this.pushLog(`${this.nameOf(ev.player)} scored +${ev.gained} → ${ev.total}`)
        break
      case 'preeminence':
        if (ev.player) this.pushLog(`★ pre-eminence → ${this.nameOf(ev.player)}`)
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
    this.hideEventPanel()
    if (this.timer) clearTimeout(this.timer)
    const win = result.standings[0]
    this.status = `Game over — winner: ${this.nameOf(win.id)} (${win.vp} VP)`
    this.pushLog(`=== ${this.nameOf(win.id)} wins with ${win.vp} VP ===`)
    this.renderFinal(result)
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
    if (l && this.placeable?.has(l.id)) this.advance(l.id)
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
    const dpr = window.devicePixelRatio || 1
    const cw = this.canvas.clientWidth
    const ch = this.canvas.clientHeight
    if (this.canvas.width !== cw * dpr || this.canvas.height !== ch * dpr) {
      this.canvas.width = cw * dpr
      this.canvas.height = ch * dpr
    }
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    const pad = 26
    this.rect = { x: pad, y: pad, w: cw - 2 * pad, h: ch - 2 * pad }

    drawMap(this.ctx, this.rect, {
      lands,
      pieces: this.game.state.pieces,
      playerOrder: this.playerOrder,
      hovered: this.hovered,
      placeable: this.placeable,
    })
    this.renderSidebar()
  }

  private renderSidebar(): void {
    const epochEl = this.root.querySelector('#epoch')!
    epochEl.textContent = `Epoch ${ROMAN[this.currentEpoch]} / VII`
    this.root.querySelector('#status')!.textContent = this.status

    const players = this.game.state.players
    const sb = this.root.querySelector('#scoreboard')!
    sb.innerHTML = [...players]
      .map((p, i) => ({ p, i }))
      .sort((a, b) => b.p.vp - a.p.vp)
      .map(
        ({ p, i }) =>
          `<div class="score"><span class="dot" style="background:${playerColor(i)}"></span>` +
          `<span class="pname">${esc(p.name)}</span><span class="pvp">${p.vp}</span></div>`,
      )
      .join('')

    const logEl = this.root.querySelector('#log')!
    logEl.innerHTML = this.log.slice(-80).map((l) => `<div>${esc(l)}</div>`).join('')
    logEl.scrollTop = logEl.scrollHeight

    const endBtn = this.root.querySelector('#end-turn') as HTMLButtonElement
    endBtn.disabled = !this.pending
  }

  private renderFinal(result: GameResult): void {
    const sb = this.root.querySelector('#scoreboard')!
    sb.innerHTML = result.standings
      .map((s) => {
        const i = this.playerOrder.indexOf(s.id)
        return (
          `<div class="score"><span class="dot" style="background:${playerColor(i)}"></span>` +
          `<span class="pname">${esc(s.name)}</span><span class="pvp">${s.vp}</span></div>`
        )
      })
      .join('')
    this.root.querySelector('#status')!.textContent = this.status
    this.root.querySelector('#log')!.scrollTop = 1e9
  }

  // ── controls ──────────────────────────────────────────────────────────────
  private wireControls(): void {
    const q = <T extends HTMLElement>(s: string) => this.root.querySelector(s) as T
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
    <div class="hud"><span id="epoch">Epoch I / VII</span></div>
  </header>
  <div class="body">
    <div class="mapwrap"><canvas id="map"></canvas><div id="event-panel" class="event-panel hidden"></div></div>
    <aside class="sidebar">
      <div class="status" id="status"></div>
      <section>
        <h2>Standings</h2>
        <div id="scoreboard"></div>
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
        <div class="muted">Big dots = territories, tinted by region; filled = controlled by a player.</div>
      </section>
      <section><h2>Log</h2><div id="log" class="log"></div></section>
    </aside>
  </div>
</div>
`

const app = document.getElementById('app')
if (app) new GameUI(app)
