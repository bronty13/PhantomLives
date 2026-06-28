// Epochs — interactive world-map UI. Drives the engine's step generator, renders
// the board on a Canvas, and lets you watch the AI or play a seat yourself.
import './style.css'
import { Board } from '../shared/board'
import { WORLD_MAP_DATA } from '../shared/data/board'
import { WORLD_EMPIRES } from '../shared/data/empires'
import {
  type DraftChoice,
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
import { AREA_NAMES, AREA_VALUES } from '../shared/data/areaValues'
import { scoreBreakdown } from '../shared/scoring'
import type { AreaId } from '../shared/types'
import { RULEBOOK } from './rulebook'
import { describeEffect } from '../shared/data/events'
import type { EmpireCard, EpochId, EventCard, Land, PlayerId } from '../shared/types'
import { drawMap, type PlaceableEntry } from './map'
import { drawFx, fxDone, type Fx } from './anim'

const ROMAN = ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII']
// Rough historical span per epoch (I & II match the original; the rest are
// reasonable eras) — flavour for the empire-rises splash.
const EPOCH_ERA = ['', '3000–1900 BC', '1900–950 BC', '950 BC – AD 1', 'AD 1 – 700', 'AD 700 – 1300', 'AD 1300 – 1700', 'AD 1700 – 2000']
const lands = WORLD_MAP_DATA.lands
const LAND_BY_ID = new Map<string, Land>(lands.map((l) => [l.id, l]))
const AREA_SIZE = new Map<string, number>() // non-barren land count per Area (Control tier)
for (const l of lands) if (!l.barren && l.area) AREA_SIZE.set(l.area, (AREA_SIZE.get(l.area) ?? 0) + 1)
// The board scan (art/board-crop.jpg → public/board.jpg) is the map. Land
// coordinates are normalized fractions of THIS image, so the view rect is framed
// to the image's aspect ratio (letterboxed) and projectLand maps straight onto it.
const BOARD_ASPECT = 2600 / 1795

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
  private pendingTarget: { card: string; targets: string[] } | null = null
  private pendingDraft: Extract<GameEvent, { type: 'awaitDraft' }> | null = null
  private pendingIntro: { player: PlayerId; empire: string; epoch: EpochId } | null = null
  private pendingRoll: { rolls: { player: PlayerId; roll: number }[]; first: PlayerId } | null = null
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
  private lastSeed = 0 // seed last auto-filled into #seed (to detect a user-typed override)
  private readonly randomSeed = (): number => Math.floor(Math.random() * 1_000_000) + 1

  private opts: NewGameOpts = { players: 4, difficulty: 'medium', humanSeat: 1, seed: 1 }
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
    // First game gets a random seed too (so it isn't always the same draw).
    this.lastSeed = this.randomSeed()
    this.opts.seed = this.lastSeed
    ;(root.querySelector('#seed') as HTMLInputElement).value = String(this.lastSeed)
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

  private rbTab: 'rules' | 'classic' = 'rules'

  // Rulebook: DEFAULT is our own-words Epochs rules (RULEBOOK); the "Classic" tab shows
  // the owner's own scanned pages, bundled into the local build (git-ignored, never
  // committed). Pages are probed sequentially until one is missing.
  private openRulebook(): void {
    this.helpOpen = true
    if (this.timer) clearTimeout(this.timer)
    this.timer = null
    const el = this.root.querySelector('#rulebook') as HTMLElement
    const nav = el.querySelector('.rb-nav') as HTMLElement
    if (!nav.dataset.loaded) {
      nav.dataset.loaded = '1'
      nav.innerHTML = RULEBOOK.map(
        (s) => `<button class="rb-navi" data-sec="${s.id}">${esc(s.title)}</button>`,
      ).join('')
      nav.querySelectorAll<HTMLButtonElement>('.rb-navi').forEach((b) => {
        b.onclick = (): void => this.showRuleSection(b.dataset.sec ?? '')
      })
      this.showRuleSection(RULEBOOK[0].id)
    }
    this.loadClassicPages()
    this.setRbTab(this.rbTab)
    el.classList.remove('hidden')
  }

  private showRuleSection(id: string): void {
    const s = RULEBOOK.find((x) => x.id === id)
    if (!s) return
    const el = this.root.querySelector('#rulebook') as HTMLElement
    ;(el.querySelector('.rb-content') as HTMLElement).innerHTML = `<h2>${esc(s.title)}</h2>${s.body}`
    el.querySelectorAll<HTMLButtonElement>('.rb-navi').forEach((b) =>
      b.classList.toggle('on', b.dataset.sec === id),
    )
    ;(el.querySelector('.rb-content') as HTMLElement).scrollTop = 0
  }

  private setRbTab(tab: 'rules' | 'classic'): void {
    this.rbTab = tab
    const el = this.root.querySelector('#rulebook') as HTMLElement
    ;(el.querySelector('.rb-rules') as HTMLElement).classList.toggle('hidden', tab !== 'rules')
    ;(el.querySelector('.rb-pages') as HTMLElement).classList.toggle('hidden', tab !== 'classic')
    ;(el.querySelector('#rb-tab-rules') as HTMLElement).classList.toggle('on', tab === 'rules')
    ;(el.querySelector('#rb-tab-classic') as HTMLElement).classList.toggle('on', tab === 'classic')
  }

  private loadClassicPages(): void {
    const box = this.root.querySelector('#rulebook .rb-pages') as HTMLElement
    if (box.dataset.loaded) return
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
    this.pendingTarget = null
    this.pendingIntro = null
    this.pendingRoll = null
    this.pendingDraft = null
    this.eventSel = {}
    this.hideEventPanel()
    ;(this.root.querySelector('#epoch-intro') as HTMLElement | null)?.classList.add('hidden')
    ;(this.root.querySelector('#start-roll') as HTMLElement | null)?.classList.add('hidden')
    ;(this.root.querySelector('#draft-panel') as HTMLElement | null)?.classList.add('hidden')
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
    if (
      this.auto &&
      !this.pending &&
      !this.pendingEvents &&
      !this.pendingTarget &&
      !this.pendingIntro &&
      !this.pendingRoll &&
      !this.pendingDraft &&
      !this.over &&
      !this.helpOpen
    ) {
      // dwell at least `speed`, but long enough for any running animation to finish
      const now = performance.now()
      const pend = this.fx.reduce((m, f) => Math.max(m, f.start + f.dur - now), 0)
      this.timer = setTimeout(() => this.advance(), Math.max(this.speed, pend))
    }
  }

  private handle(ev: GameEvent): void {
    const now = performance.now()
    switch (ev.type) {
      case 'startRoll':
        this.pendingRoll = { rolls: ev.rolls, first: ev.first }
        this.pushLog(`${this.nameOf(ev.first)} rolls lowest — drafts first`)
        this.showStartRoll()
        break
      case 'epochStart':
        this.currentEpoch = ev.epoch
        this.pushLog(`— Epoch ${ROMAN[ev.epoch]} —`)
        break
      case 'turnStart':
        this.activePlayer = ev.player
        this.status = `Epoch ${ROMAN[ev.epoch]}: ${ev.empire} (${this.nameOf(ev.player)})`
        // Your empire rises — pause on the dramatic intro card (AI turns roll on).
        if (this.opts.humanSeat && ev.player === `P${this.opts.humanSeat}`) {
          this.pendingIntro = { player: ev.player, empire: ev.empire, epoch: ev.epoch }
          this.showEpochIntro()
        }
        break
      case 'awaitDraft':
        this.pendingDraft = ev
        this.status = `Epoch ${ROMAN[ev.epoch]} draft — keep ${ev.empire.name}, or pass it to a player with no empire`
        this.showDraftPanel(ev)
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
      case 'awaitEventTarget':
        // Human seat aiming a disaster: highlight the legal target lands.
        this.pendingTarget = { card: ev.card, targets: ev.targets }
        this.placeable = new Map(
          ev.targets.map((t) => [t, { kind: 'enemy' as const, amphibious: false }]),
        )
        this.status = `${ev.card}: click a target land (highlighted).`
        break
      case 'disaster': {
        const what =
          ev.effect === 'plague' || ev.effect === 'pestilence'
            ? 'plague'
            : ev.effect === 'famine'
              ? 'famine'
              : ev.effect === 'barbarians'
                ? 'sacked'
                : ev.effect === 'pirates'
                  ? 'raided'
                  : ev.effect === 'storm_at_sea'
                    ? 'wrecked'
                    : 'razed'
        this.pushLog(`☄ ${ev.card} struck ${this.landName(ev.land)} — ${what}`)
        this.fx.push({ kind: 'clash', land: ev.land, color: '#e8801c', start: now, dur: 560, text: ev.card })
        this.startLoop()
        break
      }
      case 'minorEmpire':
        this.status = `${this.nameOf(ev.player)}'s Minor Empire — the ${ev.empire} rise in ${this.landName(ev.land)}`
        this.pushLog(`🏛 ${this.nameOf(ev.player)} summons a Minor Empire: ${ev.empire} (${this.landName(ev.land)})`)
        break
      case 'foundKingdom':
        this.pushLog(`🏰 ${this.nameOf(ev.player)} raised a fortified kingdom at ${this.landName(ev.land)}`)
        this.fx.push({ kind: 'spawn', land: ev.land, color: this.colorOf(ev.player), start: now, dur: 320 })
        this.startLoop()
        break
      case 'fleet':
        this.pushLog(`⛵ ${this.nameOf(ev.player)} launched a fleet in the ${this.seaName(ev.sea)}`)
        break
      case 'navalCombat':
        this.pushLog(
          ev.won
            ? `⚓ ${this.nameOf(ev.player)} won a sea battle in the ${this.seaName(ev.sea)}`
            : `⚓ ${this.nameOf(ev.player)} was repulsed at sea in the ${this.seaName(ev.sea)}`,
        )
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
        const bd = ev.breakdown
        const bits = bd.areas
          .filter((a) => a.vp > 0)
          .slice(0, 4)
          .map((a) => `${AREA_NAMES[a.area] ?? a.area}${a.tier === 'control' ? ' ×3' : a.tier === 'dominance' ? ' ×2' : ''} (${a.vp})`)
        if (bd.structureVp > 0) bits.push(`+${bd.structureVp} structures`)
        this.pushLog(`${this.nameOf(ev.player)} scored +${ev.gained} → ${ev.total}${bits.length ? ' — ' + bits.join(', ') : ''}`)
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
    const { px, py } = this.toCanvas(e)
    const l = nearestLand(lands, this.rect, px, py, 14)
    if (!l) return
    // Aiming a disaster: click one of the highlighted target lands.
    if (this.pendingTarget) {
      if (this.pendingTarget.targets.includes(l.id)) {
        this.pendingTarget = null
        this.placeable = null
        this.advance(l.id)
      }
      return
    }
    if (!this.pending) return
    if (this.placeable?.has(l.id)) {
      const opt = this.pending.frontier.find((f) => f.land === l.id)
      this.attackOdds = opt?.kind === 'enemy' ? (opt.odds?.attacker ?? null) : null
      this.advance(l.id)
    }
  }

  // ── event panel (human's event phase) ──────────────────────────────────
  private showEventPanel(ev: AwaitEventsEvent): void {
    const panel = this.root.querySelector('#event-panel') as HTMLElement
    const cardHtml = (c: EventCard, cls: string): string => {
      const d = describeEffect(c.effect)
      const when = d.timing === 'before' ? 'Play before turn · aim at an enemy land' : 'Play during your turn'
      return (
        `<button class="evt-card" data-cls="${cls}" data-id="${c.id}">` +
        `<div class="evt-card-name">${esc(c.name)}</div>` +
        `<div class="evt-card-meta">Epochs I–VII · ${when}</div>` +
        `<div class="evt-card-text">${esc(d.text)}</div></button>`
      )
    }
    const section = (label: string, sub: string, cards: EventCard[], cls: string): string =>
      `<div class="evt-section"><div class="evt-section-h">${label}<span>${sub}</span></div>` +
      `<div class="evt-cards">${cards.map((c) => cardHtml(c, cls)).join('') || '<em class="evt-none">— none drawn —</em>'}</div></div>`
    panel.innerHTML = `
      <div class="evt-box intro-box evt-box-wide">
        <div class="intro-epoch">Events — ${esc(ev.empire)}<span>play up to one of each, or skip</span></div>
        <div class="evt-body">
          ${section('Greater', 'a boon for your campaign', ev.hand.greater, 'greater')}
          ${section('Lesser', 'a disaster to unleash', ev.hand.lesser, 'lesser')}
        </div>
        <div class="evt-actions"><button id="evt-skip">Skip events</button><button id="evt-play" class="primary">Play selected ▶</button></div>
      </div>`
    panel.classList.remove('hidden')
    panel.querySelectorAll('.evt-card').forEach((el) => {
      el.addEventListener('click', () => {
        const cls = (el as HTMLElement).dataset.cls as 'greater' | 'lesser'
        const id = (el as HTMLElement).dataset.id as string
        if (this.eventSel[cls] === id) delete this.eventSel[cls]
        else this.eventSel[cls] = id
        panel
          .querySelectorAll(`.evt-card[data-cls="${cls}"]`)
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
    while (!this.auto && !this.over && !this.pending && !this.pendingEvents && !this.pendingTarget && !this.pendingIntro && !this.pendingRoll && !this.pendingDraft) {
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

  private empireCard(name: string, epoch: EpochId): EmpireCard | undefined {
    return WORLD_EMPIRES.find((e) => e.epoch === epoch && e.name === name)
  }

  // The empire-rises splash: a parchment card announcing your new empire each
  // epoch (homeland, strength, capital, navigation). Pauses until you Proceed.
  private showEpochIntro(): void {
    const intro = this.pendingIntro
    if (!intro) return
    if (this.timer) clearTimeout(this.timer)
    this.timer = null
    const card = this.empireCard(intro.empire, intro.epoch)
    const home = card ? this.landName(card.startLand) : '—'
    const nav = !card
      ? '—'
      : 'all' in card.navigation
        ? 'Worldwide seas'
        : card.navigation.seas.length
          ? card.navigation.seas.map((s) => s.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())).join(', ')
          : 'No navigation'
    const cap = card?.hasCapital ? 'Fortified capital' : 'No capital'
    const el = this.root.querySelector('#epoch-intro') as HTMLElement
    el.innerHTML =
      `<div class="evt-box intro-box">` +
      `<div class="intro-epoch">Epoch ${ROMAN[intro.epoch]}<span>${EPOCH_ERA[intro.epoch]}</span></div>` +
      `<div class="intro-seal" style="background:${this.colorOf(intro.player)}">${esc(intro.empire.slice(0, 1))}</div>` +
      `<h2 class="intro-name">${esc(intro.empire)}</h2>` +
      `<p class="intro-sub">rises in ${esc(home)} — ${this.nameOf(intro.player)}</p>` +
      `<div class="intro-rows">` +
      `<div><span>Homeland</span><b>${esc(home)}</b></div>` +
      `<div><span>Strength</span><b>${card?.strength ?? '—'}</b></div>` +
      `<div><span>Capital</span><b>${cap}</b></div>` +
      `<div><span>Navigation</span><b>${esc(nav)}</b></div>` +
      `</div>` +
      `<div class="evt-actions"><button id="intro-proceed" class="primary">Take command ▶</button></div>` +
      `</div>`
    el.classList.remove('hidden')
    ;(el.querySelector('#intro-proceed') as HTMLButtonElement).onclick = () => this.hideEpochIntro()
  }

  private hideEpochIntro(): void {
    this.pendingIntro = null
    ;(this.root.querySelector('#epoch-intro') as HTMLElement).classList.add('hidden')
    this.render()
    this.drainToInteractive()
    this.scheduleNext()
  }

  // The opening die-roll splash: each player rolls; the LOWEST drafts first.
  private showStartRoll(): void {
    const r = this.pendingRoll
    if (!r) return
    if (this.timer) clearTimeout(this.timer)
    this.timer = null
    const dice = r.rolls
      .map((d) => {
        const win = d.player === r.first
        return (
          `<div class="roll-die${win ? ' win' : ''}">` +
          `<div class="roll-face" style="border-color:${this.colorOf(d.player)}">${d.roll}</div>` +
          `<div class="roll-name"><span class="dot" style="background:${this.colorOf(d.player)}"></span>${esc(this.nameOf(d.player))}</div></div>`
        )
      })
      .join('')
    const el = this.root.querySelector('#start-roll') as HTMLElement
    el.innerHTML =
      `<div class="evt-box intro-box roll-box">` +
      `<div class="intro-epoch">Opening Roll<span>lowest die drafts first</span></div>` +
      `<div class="roll-dice">${dice}</div>` +
      `<p class="intro-sub"><b>${esc(this.nameOf(r.first))}</b> drafts first</p>` +
      `<div class="evt-actions"><button id="roll-begin" class="primary">Begin ▶</button></div>` +
      `</div>`
    el.classList.remove('hidden')
    ;(el.querySelector('#roll-begin') as HTMLButtonElement).onclick = () => this.hideStartRoll()
    this.timer = setTimeout(() => this.hideStartRoll(), 2800) // auto-advance to keep the opening flowing
  }

  private hideStartRoll(): void {
    if (!this.pendingRoll) return
    this.pendingRoll = null
    if (this.timer) clearTimeout(this.timer)
    this.timer = null
    ;(this.root.querySelector('#start-roll') as HTMLElement).classList.add('hidden')
    this.render()
    this.drainToInteractive()
    this.scheduleNext()
  }

  // Keep/Pass draft: you drew an empire — keep it, or gift it to an empire-less player.
  private showDraftPanel(ev: Extract<GameEvent, { type: 'awaitDraft' }>): void {
    const e = ev.empire
    const tags = [`Strength ${e.strength}`, e.hasCapital ? 'Capital' : 'No capital', e.navigates ? 'Seafaring' : 'Landlocked']
      .map((t) => `<span class="draft-tag">${esc(t)}</span>`)
      .join('')
    const passBtns = ev.canPassTo
      .map(
        (p) =>
          `<button class="pass-btn" data-pass="${esc(p)}"><span class="dot" style="background:${this.colorOf(p)}"></span>${esc(this.nameOf(p))}</button>`,
      )
      .join('')
    const el = this.root.querySelector('#draft-panel') as HTMLElement
    el.innerHTML =
      `<div class="evt-box intro-box draft-box">` +
      `<div class="intro-epoch">Epoch ${ROMAN[ev.epoch]} — Draft<span>you drew an empire</span></div>` +
      `<div class="draft-empire"><div class="draft-name">${esc(e.name)}</div><div class="draft-tags">${tags}</div>` +
      `<div class="draft-home">Homeland — ${esc(this.landName(e.startLand))}</div></div>` +
      `<div class="draft-actions"><button id="draft-keep" class="primary">Keep ${esc(e.name)}</button></div>` +
      (passBtns
        ? `<div class="draft-pass"><span class="draft-pass-label">…or pass it to a player with no empire:</span><div class="pass-row">${passBtns}</div></div>`
        : '') +
      `</div>`
    el.classList.remove('hidden')
    ;(el.querySelector('#draft-keep') as HTMLButtonElement).onclick = () => this.resolveDraft({ keep: true })
    el.querySelectorAll<HTMLButtonElement>('.pass-btn').forEach((b) => {
      b.onclick = () => this.resolveDraft({ passTo: b.dataset.pass! })
    })
  }

  private resolveDraft(choice: DraftChoice): void {
    if (!this.pendingDraft) return
    const e = this.pendingDraft.empire.name
    this.pendingDraft = null
    ;(this.root.querySelector('#draft-panel') as HTMLElement).classList.add('hidden')
    this.pushLog('passTo' in choice ? `You passed ${e} to ${this.nameOf(choice.passTo)}` : `You kept ${e}`)
    this.advance(choice)
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
    // Letterbox the board image into the canvas: a centered rect carrying the
    // board's aspect ratio. Land coords are fractions of the board, so projectLand
    // (nx,ny → rect) lands every piece exactly on its territory in the image.
    const pad = 6
    let rw = cw - 2 * pad
    let rh = rw / BOARD_ASPECT
    if (rh > ch - 2 * pad) {
      rh = ch - 2 * pad
      rw = rh * BOARD_ASPECT
    }
    this.rect = { x: (cw - rw) / 2, y: (ch - rh) / 2, w: rw, h: rh }
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
    return placementInfo(
      opt.land,
      opt.kind,
      opt.odds,
      opt.amphibious,
      {
        board: this.game.board,
        pieces: this.game.state.pieces,
        epoch: this.currentEpoch,
        player: this.pending.player,
        empireHasCapital: empire?.hasCapital ?? true,
      },
      opt.defenders ?? 1,
    )
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

  // The per-epoch Victory-Point table — a planning reference (the current epoch's
  // column is highlighted). Presence ×1, Domination ×2, Control ×3 of these.
  private renderVPTable(): void {
    const el = this.root.querySelector('#vptable')
    if (!el) return
    const epochs = [1, 2, 3, 4, 5, 6, 7] as const
    // The human's live tier + VP in each Area this epoch — scoring "depth" at a glance.
    const mine = new Map<string, { tier: string; vp: number }>()
    const humanId = this.opts.humanSeat ? `P${this.opts.humanSeat}` : null
    if (humanId && this.game) {
      const areaOf = (l: string): AreaId | null => (LAND_BY_ID.get(l)?.area as AreaId) ?? null
      const bd = scoreBreakdown(this.game.state.pieces, areaOf, Object.keys(AREA_VALUES) as AreaId[], this.currentEpoch, humanId, (a) => AREA_SIZE.get(a) ?? 0)
      for (const a of bd.areas) mine.set(a.area, { tier: a.tier, vp: a.vp })
    }
    const glyph = (t?: string): string => (t === 'control' ? '★' : t === 'dominance' ? '◆' : t === 'presence' ? '●' : '')
    let html = '<table class="vpt">'
    if (humanId) html += '<caption>★ control ×3 · ◆ dominance ×2 · ● presence ×1 — your standing this epoch</caption>'
    html += '<thead><tr><th></th>'
    for (const e of epochs) html += `<th class="${e === this.currentEpoch ? 'cur' : ''}">${ROMAN[e]}</th>`
    if (humanId) html += '<th class="you">You</th>'
    html += '</tr></thead><tbody>'
    for (const id of Object.keys(AREA_VALUES)) {
      const vals = AREA_VALUES[id]
      html += `<tr><td class="an"><span class="sw" style="background:${areaColor(id)}"></span><span>${esc(AREA_NAMES[id] ?? id)}</span></td>`
      for (const e of epochs) {
        const v = vals[e - 1]
        html += `<td class="${e === this.currentEpoch ? 'cur' : ''}${v ? '' : ' z'}">${v || '·'}</td>`
      }
      if (humanId) {
        const m = mine.get(id)
        html += `<td class="you ${m?.tier ?? ''}">${m ? `${glyph(m.tier)} ${m.vp}` : '·'}</td>`
      }
      html += '</tr>'
    }
    el.innerHTML = html + '</tbody></table>'
  }

  private showVPTable(): void {
    this.renderVPTable()
    const cur = this.root.querySelector('#vpt-cur-epoch')
    if (cur) cur.textContent = ROMAN[this.currentEpoch]
    ;(this.root.querySelector('#vptable-modal') as HTMLElement).classList.remove('hidden')
  }

  private hideVPTable(): void {
    ;(this.root.querySelector('#vptable-modal') as HTMLElement).classList.add('hidden')
  }

  private renderGameOver(result: GameResult): void {
    const el = this.root.querySelector('#gameover') as HTMLElement
    const rows = result.standings
      .map((s, rank) => {
        const i = this.playerOrder.indexOf(s.id)
        return (
          `<div class="go-row${rank === 0 ? ' winner' : ''}">` +
          `<span class="dot" style="background:${playerColor(i)}"></span>` +
          `<span class="go-name">${rank === 0 ? '👑 ' : ''}${esc(s.name)}</span>` +
          `<span class="go-vp">${s.vp}</span></div>`
        )
      })
      .join('')
    el.innerHTML =
      `<div class="evt-box"><h3>Game over — ${esc(this.nameOf(result.winner))} wins</h3>` +
      `<div class="go-list">${rows}</div>` +
      `<div class="muted">Most Victory Points after Epoch VII.</div>` +
      `<div class="evt-actions"><button id="go-again" class="primary">Play Again</button></div></div>`
    el.classList.remove('hidden')
    ;(el.querySelector('#go-again') as HTMLButtonElement).onclick = () => {
      el.classList.add('hidden')
      this.newGame()
    }
  }

  // ── controls ──────────────────────────────────────────────────────────────
  private wireControls(): void {
    const q = <T extends HTMLElement>(s: string) => this.root.querySelector(s) as T
    q<HTMLButtonElement>('#help-btn').onclick = () => this.showHelp()
    q<HTMLButtonElement>('#help-close').onclick = () => this.hideHelp()
    q<HTMLButtonElement>('#rulebook-btn').onclick = () => this.openRulebook()
    q<HTMLButtonElement>('#rb-close').onclick = () => this.closeRulebook()
    q<HTMLButtonElement>('#rb-tab-rules').onclick = () => this.setRbTab('rules')
    q<HTMLButtonElement>('#rb-tab-classic').onclick = () => this.setRbTab('classic')
    q<HTMLButtonElement>('#vpt-btn').onclick = () => this.showVPTable()
    q<HTMLButtonElement>('#vpt-close').onclick = () => this.hideVPTable()
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
      const field = q<HTMLInputElement>('#seed')
      const typed = parseInt(field.value, 10)
      // A fresh random seed each game (so empires + dice vary, not always Egypt).
      // If you TYPE a specific seed it's honoured, for replaying a game.
      const seed = typed && typed !== this.lastSeed ? typed : this.randomSeed()
      this.lastSeed = seed
      field.value = String(seed)
      this.opts = {
        players: parseInt(q<HTMLSelectElement>('#players').value, 10),
        difficulty: q<HTMLSelectElement>('#difficulty').value as Difficulty,
        humanSeat: q<HTMLInputElement>('#human').checked ? 1 : 0,
        seed,
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
  private seaName(sea: string): string {
    return sea.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())
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
    <div class="hud"><span id="epoch">Epoch I / VII</span><button id="vpt-btn" class="help-btn">📊 Scoring Table</button><button id="help-btn" class="help-btn">? How to play</button><button id="rulebook-btn" class="help-btn">📖 Rulebook</button></div>
  </header>
  <div class="body">
    <div class="mapwrap"><canvas id="map"></canvas><div id="event-panel" class="event-panel hidden"></div><div id="start-roll" class="event-panel hidden"></div><div id="draft-panel" class="event-panel hidden"></div><div id="epoch-intro" class="event-panel hidden"></div><div id="gameover" class="event-panel hidden"></div>
      <div id="rulebook" class="event-panel hidden"><div class="evt-box rb-box"><div class="rb-head"><h3>Rulebook</h3><div class="rb-tabs"><button id="rb-tab-rules" class="rb-tab on">Rules</button><button id="rb-tab-classic" class="rb-tab">Classic scans</button></div><button id="rb-close">Close</button></div><div class="rb-body"><div class="rb-rules"><nav class="rb-nav"></nav><div class="rb-content"></div></div><div class="rb-pages hidden"></div></div></div></div>
      <div id="vptable-modal" class="event-panel hidden"><div class="evt-box vpt-box"><div class="rb-head"><h3>Victory Point Table <span class="muted">— base region value by epoch</span></h3><button id="vpt-close">Close</button></div><div id="vptable"></div><div class="vpt-note">Each cell is a region's <b>base (Presence)</b> value in that epoch. <b>Dominance</b> doubles it (×2), <b>Control</b> triples it (×3). The current epoch (<span id="vpt-cur-epoch">I</span>) is highlighted.</div></div></div>
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
            <p>The <b>weakest player drafts first</b> each epoch and gets first pick of the strongest new empire — so leads don't run away. Most Victory Points after Epoch VII wins.</p>
            <h4>Events</h4>
            <p>You hold a fixed hand of cards for the <i>whole game</i> (no refills) and may play up to two before a turn. <b>Leaders</b> attack with 3 dice, <b>Weaponry</b> adds +1 to each die, <b>Fanaticism</b> wins all ties — and <b>Disasters</b> (Volcano, Flood, Fire, Plague) are aimed at an enemy land, wrecking a capital or thinning an army. (More to come — minor empires and the full deck; see the <b>📖 Rulebook</b>.)</p>
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
        <div class="row"><label><input type="checkbox" id="human" checked /> I play (seat 1)</label><label>Seed <input type="number" id="seed" value="1" min="1" style="width:64px" /></label></div>
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
