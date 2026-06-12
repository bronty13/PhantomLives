/**
 * @file main.ts — renderer orchestrator: screens, input, game loop, HUD.
 */
import { DIFFICULTIES } from '@shared/difficulty';
import { LEVELS, getLevel } from '@shared/levels';
import { createMatch, matchResult, tickMatch, type Match } from '@shared/match';
import { adjacentStandTile, findPath, type Pt } from '@shared/path';
import { TROPHIES } from '@shared/prizes';
import { getRecipe } from '@shared/recipes';
import { chefTile, drainEvents } from '@shared/sim';
import type {
  DifficultyId,
  KitchenState,
  MatchResult,
  Preferences,
  SaveData,
  SimEvent,
  SimInput
} from '@shared/types';
import {
  AI_SKIN,
  PLAYER_SKIN,
  drawDishIcon,
  drawKitchen,
  drawLogo,
  renderLevelPreview,
  stepFx,
  type Fx
} from './draw';
import { sfx, setMusicEnabled, setSoundEnabled, startMusic, stopMusic } from './sfx';

const api = window.purpleChef;

// ---------------------------------------------------------------------------
// App state
// ---------------------------------------------------------------------------

let prefs: Preferences;
let save: SaveData;
let selLevel = LEVELS[0].id;
let selDifficulty: DifficultyId = 'novice';
let match: Match | null = null;
let paused = false;
let matchEnding = false;
let rafId = 0;
let lastT = 0;
const fxYou: Fx[] = [];
const fxAi: Fx[] = [];
let lowTickSecond = -1;

// ---------------------------------------------------------------------------
// DOM helpers
// ---------------------------------------------------------------------------

const $ = <T extends HTMLElement = HTMLElement>(sel: string): T => {
  const el = document.querySelector<T>(sel);
  if (!el) throw new Error(`missing element: ${sel}`);
  return el;
};

function showScreen(id: string): void {
  document.querySelectorAll('.screen').forEach((s) => s.classList.remove('active'));
  $(`#screen-${id}`).classList.add('active');
  if (id === 'setup') renderSetup();
  if (id === 'scores') renderScores();
  if (id === 'trophies') renderTrophies();
  if (id === 'settings') void renderSettings();
}

document.querySelectorAll<HTMLElement>('[data-nav]').forEach((btn) => {
  btn.addEventListener('click', () => {
    sfx.click();
    const dest = btn.dataset.nav!;
    if (dest !== 'game' && match) stopMatch();
    showScreen(dest);
  });
});

// ---------------------------------------------------------------------------
// Input: keyboard + click-to-move
// ---------------------------------------------------------------------------

const keys = new Set<string>();
let interactQueued = false;

interface ClickPlan {
  path: Pt[];
  station: Pt | null;
  facePushMs: number;
  interacted: boolean;
}
let clickPlan: ClickPlan | null = null;

window.addEventListener('keydown', (e) => {
  if (e.repeat) return;
  if (['Space', 'KeyE', 'Enter'].includes(e.code)) {
    if (match && !paused) {
      interactQueued = true;
      e.preventDefault();
    }
    return;
  }
  if (e.code === 'Escape' && match && !matchEnding) {
    togglePause();
    return;
  }
  keys.add(e.code);
  if (['KeyW', 'KeyA', 'KeyS', 'KeyD', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.code)) {
    clickPlan = null; // keyboard overrides mouse plan
  }
});
window.addEventListener('keyup', (e) => keys.delete(e.code));
window.addEventListener('blur', () => keys.clear());

function keyboardMove(): { mx: number; my: number; active: boolean } {
  const mx =
    (keys.has('KeyD') || keys.has('ArrowRight') ? 1 : 0) -
    (keys.has('KeyA') || keys.has('ArrowLeft') ? 1 : 0);
  const my =
    (keys.has('KeyS') || keys.has('ArrowDown') ? 1 : 0) -
    (keys.has('KeyW') || keys.has('ArrowUp') ? 1 : 0);
  return { mx, my, active: mx !== 0 || my !== 0 };
}

/** Build the player's SimInput for this tick (keyboard wins over click plan). */
function playerInput(k: KitchenState, dtMs: number): SimInput {
  const kb = keyboardMove();
  let interact = interactQueued;
  interactQueued = false;

  if (kb.active || !clickPlan) {
    return { mx: kb.mx, my: kb.my, interact };
  }

  const plan = clickPlan;
  const chef = k.chef;
  // Walk remaining waypoints.
  while (plan.path.length > 0) {
    const wp = plan.path[0];
    const dx = wp.x + 0.5 - chef.x;
    const dy = wp.y + 0.5 - chef.y;
    if (Math.hypot(dx, dy) < 0.15) {
      plan.path.shift();
      continue;
    }
    const len = Math.hypot(dx, dy) || 1;
    return { mx: dx / len, my: dy / len, interact };
  }
  // Arrived. Face the station, then interact once.
  if (plan.station) {
    const me = chefTile(k);
    const needFx = Math.sign(plan.station.x - me.x);
    const needFy = Math.sign(plan.station.y - me.y);
    const facing = chef.fx === needFx && chef.fy === needFy;
    if (!facing && plan.facePushMs < 350) {
      plan.facePushMs += dtMs;
      return { mx: needFx * 0.6, my: needFy * 0.6, interact };
    }
    if (!plan.interacted) {
      plan.interacted = true;
      clickPlan = null;
      return { mx: 0, my: 0, interact: true };
    }
  }
  clickPlan = null;
  return { mx: 0, my: 0, interact };
}

function onCanvasClick(e: MouseEvent): void {
  if (!match || paused || matchEnding) return;
  const cv = $('#cv-you') as unknown as HTMLCanvasElement;
  const rect = cv.getBoundingClientRect();
  const k = match.player;
  const ts = rect.width / k.w;
  const tx = Math.floor((e.clientX - rect.left) / ts);
  const ty = Math.floor((e.clientY - rect.top) / ts);
  if (tx < 0 || ty < 0 || tx >= k.w || ty >= k.h) return;
  const tile = k.grid[ty][tx];
  const from = chefTile(k);
  if (tile.kind === 'floor') {
    const path = findPath(k.grid, from, { x: tx, y: ty });
    if (path) clickPlan = { path: path.slice(1), station: null, facePushMs: 0, interacted: false };
  } else {
    const stand = adjacentStandTile(k.grid, { x: tx, y: ty }, from);
    if (!stand) return;
    const path = findPath(k.grid, from, stand);
    if (path) clickPlan = { path: path.slice(1), station: { x: tx, y: ty }, facePushMs: 0, interacted: false };
  }
}

// ---------------------------------------------------------------------------
// Setup screen
// ---------------------------------------------------------------------------

function bestFor(levelId: string, difficulty: DifficultyId): number {
  let best = 0;
  for (const h of save.history) {
    if (h.levelId === levelId && h.difficulty === difficulty) best = Math.max(best, h.playerScore);
  }
  return best;
}

function renderSetup(): void {
  const lc = $('#level-cards');
  lc.innerHTML = '';
  for (const level of LEVELS) {
    const card = document.createElement('div');
    card.className = 'level-card' + (level.id === selLevel ? ' selected' : '');
    const cv = document.createElement('canvas');
    cv.width = 220;
    cv.height = 150;
    renderLevelPreview(cv, level.id);
    const h3 = document.createElement('h3');
    h3.textContent = level.name;
    const p = document.createElement('p');
    p.textContent = level.tagline;
    const best = document.createElement('div');
    best.className = 'lvl-best';
    const b = bestFor(level.id, selDifficulty);
    best.textContent = b > 0 ? `★ Best (${DIFFICULTIES[selDifficulty].label}): ${b}` : '';
    card.append(cv, h3, p, best);
    card.addEventListener('click', () => {
      sfx.click();
      selLevel = level.id;
      renderSetup();
    });
    lc.appendChild(card);
  }
  const dc = $('#difficulty-cards');
  dc.innerHTML = '';
  const emo: Record<DifficultyId, string> = { novice: '🌱', chef: '🍳', master: '🌶️' };
  for (const d of Object.values(DIFFICULTIES)) {
    const card = document.createElement('div');
    card.className = 'difficulty-card' + (d.id === selDifficulty ? ' selected' : '');
    card.innerHTML = `<div class="demoji">${emo[d.id]}</div><h3>${d.label}</h3><p>${d.blurb}</p>`;
    card.addEventListener('click', () => {
      sfx.click();
      selDifficulty = d.id;
      renderSetup();
    });
    dc.appendChild(card);
  }
}

$('#btn-start').addEventListener('click', () => {
  sfx.click();
  startMatch();
});

// ---------------------------------------------------------------------------
// Match lifecycle
// ---------------------------------------------------------------------------

function startMatch(): void {
  const seed = (Date.now() ^ (Math.random() * 0x7fffffff)) >>> 1;
  match = createMatch(selLevel, selDifficulty, seed);
  paused = false;
  matchEnding = false;
  fxYou.length = 0;
  fxAi.length = 0;
  clickPlan = null;
  lowTickSecond = -1;
  ticketEls.clear();
  $('#orders-you').innerHTML = '';
  $('#orders-ai').innerHTML = '';
  $<HTMLElement>('#hud-name-you').textContent = prefs.chefName || 'You';
  $('#results-name-you').textContent = prefs.chefName || 'You';
  showScreen('game');
  runCountdown();
}

function runCountdown(): void {
  const overlay = $('#countdown-overlay');
  const num = $('#countdown-num');
  overlay.classList.remove('hidden');
  let n = 3;
  num.textContent = String(n);
  sfx.countdown();
  syncCanvases();
  renderFrame(0); // show the kitchen behind the countdown
  const iv = setInterval(() => {
    n--;
    if (n > 0) {
      num.textContent = String(n);
      sfx.countdown();
    } else {
      clearInterval(iv);
      num.textContent = 'GO!';
      sfx.go();
      setTimeout(() => {
        overlay.classList.add('hidden');
        lastT = performance.now();
        rafId = requestAnimationFrame(loop);
        startMusic();
      }, 550);
    }
  }, 800);
}

function togglePause(): void {
  if (!match || matchEnding) return;
  paused = !paused;
  $('#pause-overlay').classList.toggle('hidden', !paused);
  if (paused) {
    cancelAnimationFrame(rafId);
    stopMusic();
  } else {
    lastT = performance.now();
    rafId = requestAnimationFrame(loop);
    startMusic();
  }
}

$('#btn-resume').addEventListener('click', () => {
  sfx.click();
  togglePause();
});
$('#btn-quit').addEventListener('click', () => {
  sfx.click();
  stopMatch();
  showScreen('title');
});
$('#btn-rematch').addEventListener('click', () => {
  sfx.click();
  startMatch();
});

function stopMatch(): void {
  cancelAnimationFrame(rafId);
  stopMusic();
  match = null;
  paused = false;
  $('#pause-overlay').classList.add('hidden');
  $('#countdown-overlay').classList.add('hidden');
}

// ---------------------------------------------------------------------------
// Game loop
// ---------------------------------------------------------------------------

function loop(t: number): void {
  if (!match || paused) return;
  const dt = Math.min(50, t - lastT);
  lastT = t;

  const input = playerInput(match.player, dt);
  const running = tickMatch(match, dt, input);

  handleEvents(drainEvents(match.player), fxYou, true);
  handleEvents(drainEvents(match.ai), fxAi, false);
  stepFx(fxYou, dt);
  stepFx(fxAi, dt);

  renderFrame(t / 1000);
  updateHud();

  if (running) {
    rafId = requestAnimationFrame(loop);
  } else if (!matchEnding) {
    matchEnding = true;
    setTimeout(() => void finishMatch(), 900);
  }
}

function handleEvents(events: SimEvent[], fx: Fx[], isPlayer: boolean): void {
  for (const ev of events) {
    const { x, y } = ev;
    switch (ev.type) {
      case 'chopTick':
        if (isPlayer) sfx.chop();
        fx.push({ kind: 'puff', x: x + 0.5, y: y + 0.3, vx: 0, vy: -0.6, age: 0, life: 320, color: 'rgba(255,255,255,0.8)' });
        break;
      case 'chopDone':
        if (isPlayer) sfx.chopDone();
        fx.push({ kind: 'star', x: x + 0.5, y: y + 0.2, vx: 0, vy: -0.8, age: 0, life: 500 });
        break;
      case 'pickup':
        if (isPlayer) sfx.pickup();
        break;
      case 'place':
        if (isPlayer) sfx.place();
        break;
      case 'potAdd':
        if (isPlayer) sfx.potAdd();
        break;
      case 'plateAdd':
        if (isPlayer) sfx.plateAdd();
        fx.push({ kind: 'star', x: x + 0.5, y: y + 0.2, vx: 0, vy: -0.7, age: 0, life: 400, color: '#a78bfa' });
        break;
      case 'cookDone':
        if (isPlayer) sfx.cookDone();
        fx.push({ kind: 'text', x: x + 0.5, y: y - 0.1, vx: 0, vy: -0.7, age: 0, life: 900, text: 'Ding!', color: '#4ade80', size: 0.3 });
        break;
      case 'soupPoured':
        if (isPlayer) sfx.soupPoured();
        break;
      case 'burnt':
        if (isPlayer) sfx.burnt();
        fx.push({ kind: 'text', x: x + 0.5, y: y - 0.2, vx: 0, vy: -0.5, age: 0, life: 1100, text: 'Burnt!', color: '#fb7185', size: 0.32 });
        break;
      case 'potCleared':
        if (isPlayer) sfx.potCleared();
        break;
      case 'trash':
        if (isPlayer) sfx.trash();
        fx.push({ kind: 'puff', x: x + 0.5, y: y + 0.3, vx: 0, vy: -0.4, age: 0, life: 350, color: 'rgba(150,150,160,0.8)' });
        break;
      case 'serveOk': {
        if (isPlayer) sfx.serveOk();
        fx.push({ kind: 'text', x: x + 1.2, y: y + 0.4, vx: 0.3, vy: -0.9, age: 0, life: 1300, text: `+${ev.points}`, color: '#fbbf24', size: 0.42 });
        for (let i = 0; i < 6; i++) {
          fx.push({ kind: 'star', x: x + 0.5, y: y + 0.5, vx: Math.cos(i) * 1.4, vy: Math.sin(i) * 1.4 - 0.6, age: 0, life: 650, color: i % 2 ? '#fbbf24' : '#f472b6' });
        }
        break;
      }
      case 'serveBad':
        if (isPlayer) sfx.serveBad();
        fx.push({ kind: 'text', x: x + 1.0, y: y + 0.4, vx: 0, vy: -0.6, age: 0, life: 900, text: 'Nope!', color: '#fb7185', size: 0.3 });
        break;
      case 'orderNew':
        if (isPlayer) sfx.orderNew();
        break;
      case 'orderExpired':
        if (isPlayer) sfx.orderExpired();
        fx.push({ kind: 'text', x: 1.6, y: 0.8, vx: 0, vy: 0.5, age: 0, life: 1200, text: `${ev.points}`, color: '#fb7185', size: 0.4 });
        break;
    }
  }
}

// ---------------------------------------------------------------------------
// Rendering + HUD
// ---------------------------------------------------------------------------

interface PanelCtx {
  cv: HTMLCanvasElement;
  ctx: CanvasRenderingContext2D;
  ts: number;
}
let panelYou: PanelCtx | null = null;
let panelAi: PanelCtx | null = null;

function syncCanvases(): void {
  if (!match) return;
  const make = (id: string): PanelCtx => {
    const cv = $(id) as unknown as HTMLCanvasElement;
    const holder = cv.parentElement!;
    const k = match!.player;
    const dpr = window.devicePixelRatio || 1;
    const ts = Math.max(20, Math.floor(Math.min(holder.clientWidth / k.w, holder.clientHeight / k.h)));
    cv.style.width = `${ts * k.w}px`;
    cv.style.height = `${ts * k.h}px`;
    cv.width = Math.round(ts * k.w * dpr);
    cv.height = Math.round(ts * k.h * dpr);
    const ctx = cv.getContext('2d')!;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    return { cv, ctx, ts };
  };
  panelYou = make('#cv-you');
  panelAi = make('#cv-ai');
}

window.addEventListener('resize', () => {
  if (match) syncCanvases();
});

function renderFrame(time: number): void {
  if (!match) return;
  if (!panelYou || !panelAi) syncCanvases();
  drawKitchen(panelYou!.ctx, match.player, panelYou!.ts, PLAYER_SKIN, time, fxYou);
  drawKitchen(panelAi!.ctx, match.ai, panelAi!.ts, AI_SKIN, time, fxAi);
  syncTickets('#orders-you', match.player);
  syncTickets('#orders-ai', match.ai);
}

const ticketEls = new Map<string, HTMLElement>();

function syncTickets(holderSel: string, k: KitchenState): void {
  const holder = $(holderSel);
  const alive = new Set<string>();
  for (const o of k.orders) {
    const key = `${holderSel}:${o.id}`;
    alive.add(key);
    let el = ticketEls.get(key);
    if (!el) {
      el = document.createElement('div');
      el.className = 'ticket';
      const cv = document.createElement('canvas');
      cv.width = 52;
      cv.height = 52;
      drawDishIcon(cv, o.recipeId);
      cv.title = getRecipe(o.recipeId).name;
      const bar = document.createElement('div');
      bar.className = 'pbar';
      bar.innerHTML = '<i></i>';
      el.append(cv, bar);
      holder.appendChild(el);
      ticketEls.set(key, el);
    }
    const frac = Math.max(0, 1 - (k.timeMs - o.spawnedAtMs) / o.patienceMs);
    const bar = el.querySelector<HTMLElement>('.pbar i')!;
    bar.style.width = `${frac * 100}%`;
    bar.style.background = frac > 0.5 ? 'var(--good)' : frac > 0.25 ? 'var(--warn)' : 'var(--bad)';
    el.classList.toggle('urgent', frac <= 0.25);
  }
  for (const [key, el] of ticketEls) {
    if (key.startsWith(holderSel) && !alive.has(key)) {
      el.remove();
      ticketEls.delete(key);
    }
  }
}

function updateHud(): void {
  if (!match) return;
  $('#hud-score-you').textContent = String(match.player.score);
  $('#hud-score-ai').textContent = String(match.ai.score);
  $('#hud-combo-you').textContent = match.player.combo > 1 ? `×${match.player.combo}🔥` : '';
  $('#hud-combo-ai').textContent = match.ai.combo > 1 ? `×${match.ai.combo}🔥` : '';
  const secs = Math.ceil(match.timeLeftMs / 1000);
  const timer = $('#hud-timer');
  timer.textContent = `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, '0')}`;
  const low = secs <= 15 && secs > 0;
  timer.classList.toggle('low', low);
  if (low && secs !== lowTickSecond) {
    lowTickSecond = secs;
    sfx.timeLow();
  }
}

// ---------------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------------

async function finishMatch(): Promise<void> {
  if (!match) return;
  stopMusic();
  const result = matchResult(match, new Date().toISOString());
  const m = match;
  match = null;

  let newTrophyIds: string[] = [];
  try {
    const out = await api.recordResult(result);
    save = out.save;
    newTrophyIds = out.newTrophyIds;
  } catch {
    // persistence failure shouldn't hide the results screen
  }

  showScreen('results');
  const banner = $('#results-banner');
  if (result.won) {
    banner.textContent = 'You Win! 🎉';
    sfx.win();
    spawnConfetti();
  } else if (result.tied) {
    banner.textContent = "It's a Tie! 🤝";
    sfx.win();
  } else {
    banner.textContent = 'Chef Byte Wins 🤖';
    sfx.lose();
  }
  $('#results-score-you').textContent = String(result.playerScore);
  $('#results-score-ai').textContent = String(result.aiScore);
  $('#results-sub-you').textContent =
    `${result.served} served · ${result.missed} missed · best combo ×${result.maxCombo}`;
  $('#results-sub-ai').textContent = `${m.ai.served} served · ${m.ai.missed} missed`;

  const starsEl = $('#results-stars');
  starsEl.innerHTML = '';
  for (let i = 0; i < 3; i++) {
    const star = document.createElement('span');
    star.className = 'star';
    star.textContent = '⭐';
    starsEl.appendChild(star);
    if (i < result.stars) {
      setTimeout(() => {
        star.classList.add('lit');
        sfx.trophy();
      }, 600 + i * 450);
    }
  }

  const tr = $('#results-trophies');
  tr.innerHTML = '';
  newTrophyIds.forEach((id, i) => {
    const def = TROPHIES.find((t) => t.id === id);
    if (!def) return;
    const toast = document.createElement('div');
    toast.className = 'trophy-toast';
    toast.style.animationDelay = `${1.4 + i * 0.35}s`;
    toast.textContent = `${def.emoji} New prize: ${def.name}!`;
    tr.appendChild(toast);
  });
  if (newTrophyIds.length) setTimeout(() => sfx.trophy(), 1500);
}

function spawnConfetti(): void {
  const box = $('#confetti-box');
  box.innerHTML = '';
  const colors = ['#a78bfa', '#f472b6', '#fbbf24', '#4ade80', '#60a5fa', '#fb7185'];
  for (let i = 0; i < 90; i++) {
    const c = document.createElement('div');
    c.className = 'confetto';
    c.style.left = `${Math.random() * 100}%`;
    c.style.background = colors[i % colors.length];
    c.style.animationDuration = `${2.4 + Math.random() * 2.2}s`;
    c.style.animationDelay = `${Math.random() * 1.4}s`;
    c.style.transform = `rotate(${Math.random() * 360}deg)`;
    box.appendChild(c);
  }
  setTimeout(() => (box.innerHTML = ''), 6500);
}

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------

function renderScores(): void {
  const sum = $('#scores-summary');
  const t = save.totals;
  const winRate = t.matchesPlayed ? Math.round((t.wins / t.matchesPlayed) * 100) : 0;
  const bestEver = save.history.reduce((b, h) => Math.max(b, h.playerScore), 0);
  sum.innerHTML = '';
  for (const [label, value] of [
    ['Matches', String(t.matchesPlayed)],
    ['Wins', String(t.wins)],
    ['Win rate', `${winRate}%`],
    ['Streak', String(t.winStreak)],
    ['Best score', String(bestEver)],
    ['Dishes served', String(t.dishesServed)]
  ]) {
    const card = document.createElement('div');
    card.className = 'sum-card';
    card.innerHTML = `<b>${value}</b><span>${label}</span>`;
    sum.appendChild(card);
  }

  const tbody = $('#scores-table tbody');
  tbody.innerHTML = '';
  const recent = [...save.history].reverse().slice(0, 100);
  for (const h of recent) {
    const tr = document.createElement('tr');
    const when = new Date(h.at);
    const res = h.won ? '<span class="win">Win</span>' : h.tied ? '<span class="tie">Tie</span>' : '<span class="loss">Loss</span>';
    tr.innerHTML =
      `<td>${when.toLocaleDateString()} ${when.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</td>` +
      `<td>${getLevel(h.levelId).name}</td>` +
      `<td>${DIFFICULTIES[h.difficulty].label}</td>` +
      `<td><b>${h.playerScore}</b></td><td>${h.aiScore}</td>` +
      `<td>${res}</td><td>${'⭐'.repeat(h.stars) || '—'}</td>` +
      `<td>${h.served}</td><td>${h.missed}</td><td>×${h.maxCombo}</td>`;
    tbody.appendChild(tr);
  }
  if (recent.length === 0) {
    tbody.innerHTML = '<tr><td colspan="10" style="opacity:.6;padding:22px">No matches yet — go cook something!</td></tr>';
  }
}

// ---------------------------------------------------------------------------
// Trophies
// ---------------------------------------------------------------------------

function renderTrophies(): void {
  const grid = $('#trophy-grid');
  grid.innerHTML = '';
  for (const t of [...TROPHIES].sort((a, b) => a.rank - b.rank)) {
    const earnedAt = save.trophies[t.id];
    const card = document.createElement('div');
    card.className = 'trophy-card' + (earnedAt ? '' : ' locked');
    card.innerHTML =
      `<div class="t-emoji">${earnedAt ? t.emoji : '🔒'}</div>` +
      `<h3>${t.name}</h3><p>${t.blurb}</p>` +
      `<div class="t-date">${earnedAt ? 'Earned ' + new Date(earnedAt).toLocaleDateString() : ''}</div>`;
    grid.appendChild(card);
  }
}

// ---------------------------------------------------------------------------
// Settings (incl. the Backup standard UI)
// ---------------------------------------------------------------------------

function fmtBytes(n: number): string {
  if (n > 1048576) return `${(n / 1048576).toFixed(1)} MB`;
  if (n > 1024) return `${(n / 1024).toFixed(0)} KB`;
  return `${n} B`;
}

function setBkStatus(msg: string, isErr = false): void {
  const el = $('#bk-status');
  el.textContent = msg;
  el.classList.toggle('err', isErr);
}

async function renderSettings(): Promise<void> {
  prefs = await api.getPrefs();
  ($('#set-name') as HTMLInputElement).value = prefs.chefName;
  ($('#set-sound') as HTMLInputElement).checked = prefs.soundEnabled;
  ($('#set-music') as HTMLInputElement).checked = prefs.musicEnabled;
  ($('#bk-enabled') as HTMLInputElement).checked = prefs.autoBackupEnabled;
  ($('#bk-retention') as HTMLInputElement).value = String(prefs.backupRetentionDays);
  $('#bk-path').textContent = prefs.backupPath;
  $('#bk-last').textContent = prefs.lastBackupMs ? new Date(prefs.lastBackupMs).toLocaleString() : 'never';
  await renderBackupList();
}

async function renderBackupList(): Promise<void> {
  const list = $('#bk-list');
  const backups = await api.backup.list();
  list.innerHTML = '';
  if (backups.length === 0) {
    list.innerHTML = '<div style="opacity:.55;font-size:13px;padding:4px 2px">No backups yet.</div>';
    return;
  }
  for (const b of backups.slice(0, 12)) {
    const row = document.createElement('div');
    row.className = 'bk-row';
    const name = document.createElement('span');
    name.className = 'bk-name';
    name.textContent = `${b.name} · ${fmtBytes(b.sizeBytes)}`;
    const grow = document.createElement('span');
    grow.className = 'grow';
    const mk = (label: string, fn: () => void): HTMLButtonElement => {
      const btn = document.createElement('button');
      btn.className = 'btn small';
      btn.textContent = label;
      btn.addEventListener('click', fn);
      return btn;
    };
    row.append(
      name,
      grow,
      mk('Test', async () => {
        setBkStatus('Testing…');
        const r = await api.backup.test(b.path);
        setBkStatus(
          r.ok ? `✓ Archive OK — ${r.fileCount} file(s)${r.hasSave ? ', save data present' : ''}` : `Archive failed: ${r.error ?? 'unreadable'}`,
          !r.ok
        );
      }),
      mk('Restore', async () => {
        if (!confirm(`Restore "${b.name}"?\n\nYour current data will be safety-backed-up first, then replaced.`)) return;
        setBkStatus('Restoring…');
        const r = await api.backup.restore(b.path);
        if (r.ok) {
          save = await api.getSave();
          await renderSettings();
          setBkStatus('✓ Restored. Scores and trophies reloaded.');
        } else {
          setBkStatus(`Restore failed: ${r.error}`, true);
        }
      }),
      mk('Reveal', () => void api.backup.revealFile(b.path))
    );
    list.appendChild(row);
  }
}

$('#set-name').addEventListener('change', async (e) => {
  prefs = await api.setPrefs({ chefName: (e.target as HTMLInputElement).value.trim() || 'Chef You' });
});
$('#set-sound').addEventListener('change', async (e) => {
  prefs = await api.setPrefs({ soundEnabled: (e.target as HTMLInputElement).checked });
  setSoundEnabled(prefs.soundEnabled);
});
$('#set-music').addEventListener('change', async (e) => {
  prefs = await api.setPrefs({ musicEnabled: (e.target as HTMLInputElement).checked });
  setMusicEnabled(prefs.musicEnabled);
});
$('#bk-enabled').addEventListener('change', async (e) => {
  prefs = await api.setPrefs({ autoBackupEnabled: (e.target as HTMLInputElement).checked });
});
$('#bk-retention').addEventListener('change', async (e) => {
  const v = Math.max(0, Math.min(365, Number((e.target as HTMLInputElement).value) || 0));
  prefs = await api.setPrefs({ backupRetentionDays: v });
  (e.target as HTMLInputElement).value = String(v);
});
$('#bk-choose').addEventListener('click', async () => {
  const next = await api.backup.chooseDir();
  if (next) {
    prefs = next;
    $('#bk-path').textContent = prefs.backupPath;
    await renderBackupList();
  }
});
$('#bk-default').addEventListener('click', async () => {
  const defs = await api.getDefaultPrefs();
  prefs = await api.setPrefs({ backupPath: defs.backupPath });
  $('#bk-path').textContent = prefs.backupPath;
  await renderBackupList();
});
$('#bk-reveal').addEventListener('click', () => void api.backup.reveal());
$('#bk-run').addEventListener('click', async () => {
  setBkStatus('Backing up…');
  const r = await api.backup.run();
  if (r.ok) {
    prefs = await api.getPrefs();
    $('#bk-last').textContent = prefs.lastBackupMs ? new Date(prefs.lastBackupMs).toLocaleString() : 'never';
    setBkStatus('✓ Backup complete.');
    await renderBackupList();
  } else {
    setBkStatus(`Backup failed: ${r.error}`, true);
  }
});

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------

async function boot(): Promise<void> {
  prefs = await api.getPrefs();
  save = await api.getSave();
  setSoundEnabled(prefs.soundEnabled);
  setMusicEnabled(prefs.musicEnabled);
  drawLogo($('#logo-canvas') as unknown as HTMLCanvasElement);
  $('#app-version').textContent = await api.version();
  ($('#cv-you') as unknown as HTMLCanvasElement).addEventListener('click', onCanvasClick);
  showScreen('title');
}

void boot();
