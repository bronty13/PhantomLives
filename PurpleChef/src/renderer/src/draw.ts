/**
 * @file draw.ts — all procedural canvas art: kitchens, chefs, food, FX.
 *
 * Everything is drawn from code (no image assets) so the look is identical
 * on macOS and Windows and the repo stays binary-free per house style.
 */
import { buildKitchen, getLevel } from '@shared/levels';
import { getRecipe } from '@shared/recipes';
import type { Component, Item, KitchenState, Tile } from '@shared/types';

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------

const FLOOR_A = '#fbf1df';
const FLOOR_B = '#f5e6cb';
const COUNTER_TOP = '#cabcf0';
const COUNTER_SIDE = '#a795d8';
const BOARD_WOOD = '#e7c08a';
const BOARD_WOOD_DARK = '#c89c63';
const STOVE_BODY = '#54506b';
const STOVE_DARK = '#3f3c52';
const POT_METAL = '#8d93a8';
const CRATE_WOOD = '#d8a86d';
const CRATE_DARK = '#b08049';
const SERVE_BG = '#7c5cd6';
const TRASH_GRAY = '#9aa1b0';
const PLATE_WHITE = '#ffffff';
const PLATE_RIM = '#d8dbe4';

export interface Fx {
  kind: 'text' | 'puff' | 'steam' | 'spark' | 'star';
  x: number; // tile coords
  y: number;
  vx: number;
  vy: number;
  age: number;
  life: number;
  text?: string;
  color?: string;
  size?: number;
}

export function stepFx(fx: Fx[], dtMs: number): void {
  for (const f of fx) {
    f.age += dtMs;
    f.x += (f.vx * dtMs) / 1000;
    f.y += (f.vy * dtMs) / 1000;
  }
  for (let i = fx.length - 1; i >= 0; i--) {
    if (fx[i].age >= fx[i].life) fx.splice(i, 1);
  }
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

function rr(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, r);
}

function circle(ctx: CanvasRenderingContext2D, x: number, y: number, r: number): void {
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
}

// ---------------------------------------------------------------------------
// Ingredients & items
// ---------------------------------------------------------------------------

/** Draw a single component centered at (cx, cy); s ≈ half-size in px. */
export function drawComponent(
  ctx: CanvasRenderingContext2D,
  c: Component,
  cx: number,
  cy: number,
  s: number
): void {
  ctx.save();
  ctx.translate(cx, cy);
  switch (c.kind) {
    case 'tomato':
      if (c.state === 'raw') {
        ctx.fillStyle = '#ef4444';
        circle(ctx, 0, 0, s);
        ctx.fill();
        ctx.fillStyle = '#fca5a5';
        circle(ctx, -s * 0.3, -s * 0.32, s * 0.26);
        ctx.fill();
        ctx.fillStyle = '#16a34a';
        rr(ctx, -s * 0.32, -s * 1.08, s * 0.64, s * 0.34, s * 0.14);
        ctx.fill();
      } else if (c.state === 'chopped') {
        ctx.fillStyle = '#ef4444';
        for (const [dx, dy] of [[-0.45, 0.1], [0.1, -0.25], [0.45, 0.25]] as const) {
          ctx.beginPath();
          ctx.moveTo(dx * s, dy * s - s * 0.4);
          ctx.lineTo(dx * s + s * 0.42, dy * s + s * 0.3);
          ctx.lineTo(dx * s - s * 0.42, dy * s + s * 0.3);
          ctx.closePath();
          ctx.fill();
        }
      } else {
        ctx.fillStyle = '#e0452f'; // soup
        circle(ctx, 0, 0, s);
        ctx.fill();
        ctx.fillStyle = '#f08060';
        circle(ctx, -s * 0.25, -s * 0.2, s * 0.3);
        ctx.fill();
      }
      break;
    case 'onion':
      if (c.state === 'raw') {
        ctx.fillStyle = '#fde68a';
        circle(ctx, 0, 0, s);
        ctx.fill();
        ctx.fillStyle = '#fbbf77';
        rr(ctx, -s * 0.14, -s * 1.15, s * 0.28, s * 0.4, s * 0.1);
        ctx.fill();
        ctx.strokeStyle = '#eab308';
        ctx.lineWidth = Math.max(1, s * 0.1);
        ctx.beginPath();
        ctx.arc(0, 0, s * 0.6, -0.6, 1.4);
        ctx.stroke();
      } else if (c.state === 'chopped') {
        ctx.strokeStyle = '#facc15';
        ctx.lineWidth = Math.max(1.5, s * 0.18);
        for (const [dx, dy, r] of [[-0.4, 0.05, 0.4], [0.25, -0.2, 0.34], [0.3, 0.32, 0.28]] as const) {
          circle(ctx, dx * s, dy * s, r * s);
          ctx.stroke();
        }
      } else {
        ctx.fillStyle = '#e9b949';
        circle(ctx, 0, 0, s);
        ctx.fill();
        ctx.fillStyle = '#f6d77c';
        circle(ctx, -s * 0.25, -s * 0.2, s * 0.3);
        ctx.fill();
      }
      break;
    case 'lettuce':
      if (c.state === 'raw') {
        ctx.fillStyle = '#65a30d';
        circle(ctx, 0, 0, s);
        ctx.fill();
        ctx.fillStyle = '#84cc16';
        for (const [dx, dy] of [[-0.4, -0.25], [0.35, -0.3], [0, 0.3], [0.45, 0.2], [-0.45, 0.3]] as const) {
          circle(ctx, dx * s, dy * s, s * 0.42);
          ctx.fill();
        }
      } else {
        ctx.fillStyle = '#84cc16';
        for (const [dx, dy] of [[-0.5, 0.15], [-0.1, -0.2], [0.35, 0.2], [0.1, 0.35]] as const) {
          rr(ctx, dx * s - s * 0.22, dy * s - s * 0.16, s * 0.46, s * 0.34, s * 0.12);
          ctx.fill();
        }
        ctx.fillStyle = '#a3e635';
        rr(ctx, -s * 0.15, -s * 0.05, s * 0.4, s * 0.3, s * 0.1);
        ctx.fill();
      }
      break;
    case 'meat':
      if (c.state === 'raw') {
        ctx.fillStyle = '#f87171';
        rr(ctx, -s, -s * 0.55, s * 2, s * 1.1, s * 0.5);
        ctx.fill();
        ctx.fillStyle = '#fecaca';
        rr(ctx, -s * 0.55, -s * 0.22, s * 0.7, s * 0.4, s * 0.2);
        ctx.fill();
      } else if (c.state === 'chopped') {
        ctx.fillStyle = '#ef6a6a';
        rr(ctx, -s * 0.95, -s * 0.5, s * 1.9, s, s * 0.45);
        ctx.fill();
        ctx.strokeStyle = '#b91c1c';
        ctx.lineWidth = Math.max(1, s * 0.1);
        ctx.beginPath();
        ctx.moveTo(-s * 0.3, -s * 0.5);
        ctx.lineTo(-s * 0.3, s * 0.5);
        ctx.moveTo(s * 0.3, -s * 0.5);
        ctx.lineTo(s * 0.3, s * 0.5);
        ctx.stroke();
      } else {
        ctx.fillStyle = '#92400e';
        rr(ctx, -s, -s * 0.55, s * 2, s * 1.1, s * 0.5);
        ctx.fill();
        ctx.strokeStyle = '#5b2706';
        ctx.lineWidth = Math.max(1, s * 0.12);
        ctx.beginPath();
        ctx.moveTo(-s * 0.55, -s * 0.2);
        ctx.lineTo(s * 0.55, -s * 0.2);
        ctx.moveTo(-s * 0.55, s * 0.2);
        ctx.lineTo(s * 0.55, s * 0.2);
        ctx.stroke();
      }
      break;
    case 'bun':
      ctx.fillStyle = '#f59e0b';
      ctx.beginPath();
      ctx.arc(0, 0, s, Math.PI, 0);
      ctx.closePath();
      ctx.fill();
      ctx.fillStyle = '#fbbf24';
      rr(ctx, -s, 0, s * 2, s * 0.4, s * 0.18);
      ctx.fill();
      ctx.fillStyle = '#fffbeb';
      for (const [dx, dy] of [[-0.4, -0.45], [0, -0.62], [0.4, -0.45]] as const) {
        ctx.save();
        ctx.translate(dx * s, dy * s);
        ctx.rotate(-0.4);
        rr(ctx, -s * 0.09, -s * 0.05, s * 0.18, s * 0.1, s * 0.05);
        ctx.fill();
        ctx.restore();
      }
      break;
    case 'cheese':
      if (c.state === 'raw') {
        ctx.fillStyle = '#fbbf24';
        ctx.beginPath();
        ctx.moveTo(-s, s * 0.6);
        ctx.lineTo(s, s * 0.6);
        ctx.lineTo(s, -s * 0.1);
        ctx.lineTo(-s, -s * 0.75);
        ctx.closePath();
        ctx.fill();
        ctx.fillStyle = '#f59e0b';
        circle(ctx, s * 0.3, s * 0.18, s * 0.16);
        ctx.fill();
        circle(ctx, -s * 0.25, 0, s * 0.12);
        ctx.fill();
      } else {
        ctx.fillStyle = '#fcd34d';
        for (const [dx, dy] of [[-0.45, 0], [0.05, -0.2], [0.4, 0.22], [-0.05, 0.3]] as const) {
          rr(ctx, dx * s - s * 0.24, dy * s - s * 0.18, s * 0.5, s * 0.36, s * 0.08);
          ctx.fill();
        }
      }
      break;
  }
  ctx.restore();
}

/** Soup detection: 3 cooked same-kind veg on a plate renders as a bowl. */
function soupKind(contents: Component[]): Component['kind'] | null {
  if (contents.length === 3 && contents.every((c) => c.state === 'cooked' && c.kind === contents[0].kind)) {
    return contents[0].kind;
  }
  return null;
}

export function drawItem(ctx: CanvasRenderingContext2D, item: Item, cx: number, cy: number, s: number): void {
  if (item.type === 'ing') {
    drawComponent(ctx, { kind: item.kind, state: item.state }, cx, cy, s);
    return;
  }
  // Plate
  ctx.save();
  ctx.translate(cx, cy);
  ctx.fillStyle = PLATE_RIM;
  ctx.beginPath();
  ctx.ellipse(0, s * 0.15, s * 1.25, s * 0.95, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = PLATE_WHITE;
  ctx.beginPath();
  ctx.ellipse(0, s * 0.05, s * 1.15, s * 0.85, 0, 0, Math.PI * 2);
  ctx.fill();
  const soup = soupKind(item.contents);
  if (soup) {
    ctx.fillStyle = soup === 'tomato' ? '#e0452f' : '#e9b949';
    ctx.beginPath();
    ctx.ellipse(0, s * 0.02, s * 0.85, s * 0.6, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = 'rgba(255,255,255,0.35)';
    ctx.beginPath();
    ctx.ellipse(-s * 0.25, -s * 0.12, s * 0.3, s * 0.16, -0.4, 0, Math.PI * 2);
    ctx.fill();
  } else {
    // Stack components: burger-style bottom-up if bun present, else scatter.
    const hasBun = item.contents.some((c) => c.kind === 'bun');
    if (hasBun) {
      const order: Record<string, number> = { bun: 0, meat: 1, cheese: 2, tomato: 3, lettuce: 4 };
      const sorted = [...item.contents].sort((a, b) => (order[a.kind] ?? 9) - (order[b.kind] ?? 9));
      let yy = s * 0.25;
      for (const c of sorted) {
        drawComponent(ctx, c, 0, yy, s * 0.52);
        yy -= s * 0.34;
      }
    } else {
      const n = item.contents.length;
      item.contents.forEach((c, i) => {
        const ang = (i / Math.max(1, n)) * Math.PI * 2;
        const rad = n > 1 ? s * 0.34 : 0;
        drawComponent(ctx, c, Math.cos(ang) * rad, Math.sin(ang) * rad * 0.6, s * 0.5);
      });
    }
  }
  ctx.restore();
}

/** A finished dish on a plate, for order tickets and previews. */
export function drawDishIcon(canvas: HTMLCanvasElement, recipeId: string): void {
  const ctx = canvas.getContext('2d')!;
  const w = canvas.width;
  const recipe = getRecipe(recipeId);
  ctx.clearRect(0, 0, w, w);
  drawItem(ctx, { type: 'plate', contents: recipe.needs }, w / 2, w / 2 + w * 0.06, w * 0.3);
}

// ---------------------------------------------------------------------------
// Tiles
// ---------------------------------------------------------------------------

function drawTileBase(ctx: CanvasRenderingContext2D, t: Tile, x: number, y: number, ts: number): void {
  const px = x * ts;
  const py = y * ts;
  if (t.kind === 'floor') {
    ctx.fillStyle = (x + y) % 2 === 0 ? FLOOR_A : FLOOR_B;
    ctx.fillRect(px, py, ts, ts);
    return;
  }
  // Station base: a chunky counter block with a soft 2.5-D lip.
  ctx.fillStyle = COUNTER_SIDE;
  ctx.fillRect(px, py, ts, ts);
  ctx.fillStyle = t.kind === 'stove' ? STOVE_BODY : t.kind === 'serve' ? SERVE_BG : COUNTER_TOP;
  rr(ctx, px + 1, py + 1, ts - 2, ts - 5, ts * 0.16);
  ctx.fill();
}

function drawStation(
  ctx: CanvasRenderingContext2D,
  t: Tile,
  x: number,
  y: number,
  ts: number,
  time: number
): void {
  const px = x * ts;
  const py = y * ts;
  const cx = px + ts / 2;
  const cy = py + ts / 2;
  switch (t.kind) {
    case 'crate': {
      ctx.fillStyle = CRATE_WOOD;
      rr(ctx, px + ts * 0.1, py + ts * 0.08, ts * 0.8, ts * 0.78, ts * 0.1);
      ctx.fill();
      ctx.strokeStyle = CRATE_DARK;
      ctx.lineWidth = Math.max(1.5, ts * 0.045);
      rr(ctx, px + ts * 0.1, py + ts * 0.08, ts * 0.8, ts * 0.78, ts * 0.1);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(px + ts * 0.1, py + ts * 0.34);
      ctx.lineTo(px + ts * 0.9, py + ts * 0.34);
      ctx.stroke();
      if (t.crate) drawComponent(ctx, { kind: t.crate, state: 'raw' }, cx, cy + ts * 0.1, ts * 0.21);
      break;
    }
    case 'board': {
      ctx.fillStyle = BOARD_WOOD;
      rr(ctx, px + ts * 0.08, py + ts * 0.12, ts * 0.84, ts * 0.66, ts * 0.12);
      ctx.fill();
      ctx.strokeStyle = BOARD_WOOD_DARK;
      ctx.lineWidth = Math.max(1, ts * 0.03);
      rr(ctx, px + ts * 0.08, py + ts * 0.12, ts * 0.84, ts * 0.66, ts * 0.12);
      ctx.stroke();
      // Little knife, parked when idle.
      ctx.save();
      ctx.translate(px + ts * 0.78, py + ts * 0.26);
      ctx.rotate(0.5);
      ctx.fillStyle = '#cfd6e4';
      rr(ctx, -ts * 0.04, -ts * 0.16, ts * 0.08, ts * 0.22, ts * 0.03);
      ctx.fill();
      ctx.fillStyle = '#6b4f2a';
      rr(ctx, -ts * 0.035, 0.04 * ts, ts * 0.07, ts * 0.12, ts * 0.03);
      ctx.fill();
      ctx.restore();
      if (t.item) drawItem(ctx, t.item, cx, cy + ts * 0.04, ts * 0.2);
      if ((t.chop ?? 0) > 0) {
        // Chop progress bar
        ctx.fillStyle = 'rgba(0,0,0,0.25)';
        rr(ctx, px + ts * 0.16, py + ts * 0.8, ts * 0.68, ts * 0.1, ts * 0.05);
        ctx.fill();
        ctx.fillStyle = '#4ade80';
        rr(ctx, px + ts * 0.16, py + ts * 0.8, ts * 0.68 * Math.min(1, t.chop ?? 0), ts * 0.1, ts * 0.05);
        ctx.fill();
      }
      break;
    }
    case 'stove': {
      ctx.fillStyle = STOVE_DARK;
      circle(ctx, cx, cy, ts * 0.36);
      ctx.fill();
      const pot = t.pot!;
      // Pot
      ctx.fillStyle = POT_METAL;
      circle(ctx, cx, cy, ts * 0.3);
      ctx.fill();
      ctx.fillStyle = '#6e7488';
      circle(ctx, cx, cy, ts * 0.25);
      ctx.fill();
      // Handles
      ctx.strokeStyle = POT_METAL;
      ctx.lineWidth = Math.max(2, ts * 0.05);
      ctx.beginPath();
      ctx.moveTo(cx - ts * 0.38, cy);
      ctx.lineTo(cx - ts * 0.28, cy);
      ctx.moveTo(cx + ts * 0.28, cy);
      ctx.lineTo(cx + ts * 0.38, cy);
      ctx.stroke();
      if (pot.contents.length > 0) {
        const k = pot.contents[0].kind;
        const liquid =
          pot.phase === 'burnt' ? '#26222e' : k === 'tomato' ? '#e0452f' : k === 'onion' ? '#e9b949' : '#8a4b22';
        ctx.fillStyle = liquid;
        circle(ctx, cx, cy, ts * 0.22);
        ctx.fill();
        if (k === 'meat' && pot.phase !== 'burnt') {
          drawComponent(ctx, pot.contents[0], cx, cy, ts * 0.13);
        }
        // Bubbles while cooking
        if (pot.phase === 'cooking') {
          ctx.fillStyle = 'rgba(255,255,255,0.5)';
          for (let i = 0; i < 3; i++) {
            const bx = cx + Math.sin(time * 3 + i * 2.1) * ts * 0.1;
            const by = cy + Math.cos(time * 2.4 + i * 1.7) * ts * 0.08;
            circle(ctx, bx, by, ts * (0.025 + 0.012 * Math.sin(time * 5 + i)));
            ctx.fill();
          }
        }
      }
      // Progress ring
      if (pot.phase === 'cooking' || pot.phase === 'done') {
        ctx.strokeStyle = pot.phase === 'done' ? '#4ade80' : '#fbbf24';
        ctx.lineWidth = Math.max(2, ts * 0.06);
        ctx.beginPath();
        ctx.arc(cx, cy, ts * 0.4, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * (pot.phase === 'done' ? 1 : pot.progress));
        ctx.stroke();
      }
      if (pot.phase === 'done') {
        // Burn warning creeping in
        if (pot.burn > 0.5) {
          const blink = Math.sin(time * 8) > 0;
          if (blink) {
            ctx.font = `${ts * 0.34}px sans-serif`;
            ctx.textAlign = 'center';
            ctx.fillText('⚠️', cx + ts * 0.3, py + ts * 0.3);
          }
        } else {
          ctx.font = `${ts * 0.3}px sans-serif`;
          ctx.textAlign = 'center';
          ctx.fillText('✅', cx + ts * 0.32, py + ts * 0.32);
        }
      }
      if (pot.phase === 'burnt') {
        // Flames!
        for (let i = 0; i < 4; i++) {
          const fx = cx + (i - 1.5) * ts * 0.14;
          const h = ts * (0.18 + 0.08 * Math.sin(time * 9 + i * 1.9));
          ctx.fillStyle = i % 2 ? '#f97316' : '#fbbf24';
          ctx.beginPath();
          ctx.moveTo(fx - ts * 0.06, cy);
          ctx.quadraticCurveTo(fx, cy - h * 2, fx + ts * 0.06, cy);
          ctx.closePath();
          ctx.fill();
        }
      }
      break;
    }
    case 'plates': {
      for (let i = 0; i < 3; i++) {
        const off = i * ts * 0.07;
        ctx.fillStyle = PLATE_RIM;
        ctx.beginPath();
        ctx.ellipse(cx, cy + ts * 0.12 - off, ts * 0.3, ts * 0.2, 0, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = PLATE_WHITE;
        ctx.beginPath();
        ctx.ellipse(cx, cy + ts * 0.09 - off, ts * 0.26, ts * 0.165, 0, 0, Math.PI * 2);
        ctx.fill();
      }
      break;
    }
    case 'serve': {
      // Hatch with awning stripes + bell.
      ctx.fillStyle = '#5b3fb8';
      rr(ctx, px + ts * 0.12, py + ts * 0.14, ts * 0.76, ts * 0.6, ts * 0.1);
      ctx.fill();
      ctx.fillStyle = '#2e2347';
      rr(ctx, px + ts * 0.18, py + ts * 0.22, ts * 0.64, ts * 0.4, ts * 0.08);
      ctx.fill();
      for (let i = 0; i < 4; i++) {
        ctx.fillStyle = i % 2 ? '#f472b6' : '#fdf6ec';
        rr(ctx, px + ts * (0.12 + i * 0.19), py + ts * 0.06, ts * 0.19, ts * 0.12, ts * 0.03);
        ctx.fill();
      }
      ctx.font = `${ts * 0.3}px sans-serif`;
      ctx.textAlign = 'center';
      ctx.fillText('🛎️', cx, py + ts * 0.92);
      break;
    }
    case 'trash': {
      ctx.fillStyle = TRASH_GRAY;
      rr(ctx, px + ts * 0.22, py + ts * 0.26, ts * 0.56, ts * 0.56, ts * 0.08);
      ctx.fill();
      ctx.fillStyle = '#7d8494';
      rr(ctx, px + ts * 0.16, py + ts * 0.16, ts * 0.68, ts * 0.14, ts * 0.06);
      ctx.fill();
      ctx.fillStyle = '#646b7c';
      rr(ctx, px + ts * 0.42, py + ts * 0.1, ts * 0.16, ts * 0.1, ts * 0.04);
      ctx.fill();
      break;
    }
    case 'counter': {
      if (t.item) drawItem(ctx, t.item, cx, cy, ts * 0.21);
      break;
    }
    case 'floor':
      break;
  }
}

// ---------------------------------------------------------------------------
// Chef
// ---------------------------------------------------------------------------

export interface ChefSkin {
  body: string;
  bodyDark: string;
  isRobot: boolean;
}

export const PLAYER_SKIN: ChefSkin = { body: '#8b5cf6', bodyDark: '#6d28d9', isRobot: false };
export const AI_SKIN: ChefSkin = { body: '#2dd4bf', bodyDark: '#0d9488', isRobot: true };

function drawChef(
  ctx: CanvasRenderingContext2D,
  k: KitchenState,
  ts: number,
  skin: ChefSkin,
  time: number
): void {
  const c = k.chef;
  const px = c.x * ts;
  const py = c.y * ts;
  const r = ts * 0.34;
  const bob = Math.abs(Math.sin(c.walkPhase)) * ts * 0.05;
  const chopBob = c.chopping ? Math.abs(Math.sin(time * 14)) * ts * 0.06 : 0;

  ctx.save();
  ctx.translate(px, py - bob - chopBob);

  // Shadow
  ctx.fillStyle = 'rgba(0,0,0,0.18)';
  ctx.beginPath();
  ctx.ellipse(0, r * 0.95 + bob + chopBob, r * 0.85, r * 0.3, 0, 0, Math.PI * 2);
  ctx.fill();

  // Body
  ctx.fillStyle = skin.body;
  ctx.beginPath();
  ctx.ellipse(0, 0, r, r * 1.05, 0, 0, Math.PI * 2);
  ctx.fill();

  // Apron
  ctx.fillStyle = '#ffffff';
  ctx.beginPath();
  ctx.ellipse(0, r * 0.42, r * 0.62, r * 0.5, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = skin.bodyDark;
  ctx.beginPath();
  ctx.ellipse(0, r * 0.42, r * 0.62, r * 0.5, 0, Math.PI * 0.15, Math.PI * 0.85);
  ctx.fill();

  // Face orientation nudge
  const fx = c.fx * r * 0.28;
  const fy = c.fy * r * 0.22;

  // Eyes
  ctx.fillStyle = '#241b3a';
  circle(ctx, -r * 0.26 + fx, -r * 0.25 + fy, r * 0.1);
  ctx.fill();
  circle(ctx, r * 0.26 + fx, -r * 0.25 + fy, r * 0.1);
  ctx.fill();
  // Blush
  ctx.fillStyle = 'rgba(244,114,182,0.55)';
  circle(ctx, -r * 0.45 + fx, -r * 0.02 + fy, r * 0.12);
  ctx.fill();
  circle(ctx, r * 0.45 + fx, -r * 0.02 + fy, r * 0.12);
  ctx.fill();
  // Smile
  ctx.strokeStyle = '#241b3a';
  ctx.lineWidth = Math.max(1.2, r * 0.07);
  ctx.beginPath();
  ctx.arc(fx, -r * 0.04 + fy, r * 0.16, 0.25, Math.PI - 0.25);
  ctx.stroke();

  // Hat
  if (skin.isRobot) {
    ctx.fillStyle = '#cbd5e1';
    rr(ctx, -r * 0.5, -r * 1.18, r, r * 0.34, r * 0.12);
    ctx.fill();
    ctx.strokeStyle = '#94a3b8';
    ctx.lineWidth = Math.max(1, r * 0.06);
    ctx.beginPath();
    ctx.moveTo(0, -r * 1.18);
    ctx.lineTo(0, -r * 1.5);
    ctx.stroke();
    ctx.fillStyle = '#f472b6';
    circle(ctx, 0, -r * 1.58, r * 0.12 + Math.sin(time * 4) * r * 0.02);
    ctx.fill();
  } else {
    ctx.fillStyle = '#ffffff';
    rr(ctx, -r * 0.52, -r * 1.28, r * 1.04, r * 0.5, r * 0.14);
    ctx.fill();
    circle(ctx, -r * 0.3, -r * 1.32, r * 0.26);
    ctx.fill();
    circle(ctx, 0.02 * r, -r * 1.45, r * 0.3);
    ctx.fill();
    circle(ctx, r * 0.32, -r * 1.32, r * 0.26);
    ctx.fill();
  }

  // Carried item floats in front of the chef.
  if (c.carrying) {
    drawItem(ctx, c.carrying, c.fx * r * 0.9, -r * 0.6 + c.fy * r * 0.55, r * 0.5);
  }
  ctx.restore();
}

// ---------------------------------------------------------------------------
// FX
// ---------------------------------------------------------------------------

function drawFx(ctx: CanvasRenderingContext2D, fx: Fx[], ts: number): void {
  for (const f of fx) {
    const t = f.age / f.life;
    const alpha = 1 - t;
    const px = f.x * ts;
    const py = f.y * ts;
    ctx.save();
    ctx.globalAlpha = Math.max(0, alpha);
    if (f.kind === 'text') {
      ctx.font = `800 ${(f.size ?? 0.34) * ts}px 'Avenir Next', sans-serif`;
      ctx.textAlign = 'center';
      ctx.lineWidth = ts * 0.06;
      ctx.strokeStyle = 'rgba(36,27,58,0.85)';
      ctx.strokeText(f.text ?? '', px, py);
      ctx.fillStyle = f.color ?? '#ffffff';
      ctx.fillText(f.text ?? '', px, py);
    } else if (f.kind === 'puff') {
      ctx.fillStyle = f.color ?? 'rgba(255,255,255,0.8)';
      circle(ctx, px, py, ts * 0.1 * (1 + t * 1.6));
      ctx.fill();
    } else if (f.kind === 'steam') {
      ctx.fillStyle = 'rgba(255,255,255,0.55)';
      circle(ctx, px + Math.sin(f.age / 130) * ts * 0.06, py, ts * 0.08 * (1 + t));
      ctx.fill();
    } else if (f.kind === 'spark' || f.kind === 'star') {
      ctx.fillStyle = f.color ?? '#fbbf24';
      ctx.translate(px, py);
      ctx.rotate(f.age / 90);
      const s = ts * 0.1 * (1 - t * 0.5);
      ctx.beginPath();
      for (let i = 0; i < 5; i++) {
        const a = (i * 2 * Math.PI) / 5 - Math.PI / 2;
        const a2 = a + Math.PI / 5;
        ctx.lineTo(Math.cos(a) * s, Math.sin(a) * s);
        ctx.lineTo(Math.cos(a2) * s * 0.45, Math.sin(a2) * s * 0.45);
      }
      ctx.closePath();
      ctx.fill();
    }
    ctx.restore();
  }
}

// ---------------------------------------------------------------------------
// Kitchen panel
// ---------------------------------------------------------------------------

export function drawKitchen(
  ctx: CanvasRenderingContext2D,
  k: KitchenState,
  ts: number,
  skin: ChefSkin,
  time: number,
  fx: Fx[]
): void {
  ctx.clearRect(0, 0, k.w * ts, k.h * ts);
  for (let y = 0; y < k.h; y++) for (let x = 0; x < k.w; x++) drawTileBase(ctx, k.grid[y][x], x, y, ts);
  for (let y = 0; y < k.h; y++) for (let x = 0; x < k.w; x++) drawStation(ctx, k.grid[y][x], x, y, ts, time);

  // Highlight the tile the chef is facing (subtle, helps aiming).
  const tx = Math.floor(k.chef.x) + Math.round(k.chef.fx);
  const ty = Math.floor(k.chef.y) + Math.round(k.chef.fy);
  if (ty >= 0 && ty < k.h && tx >= 0 && tx < k.w && k.grid[ty][tx].kind !== 'floor') {
    ctx.strokeStyle = 'rgba(255,255,255,0.65)';
    ctx.lineWidth = Math.max(2, ts * 0.05);
    rr(ctx, tx * ts + 2, ty * ts + 2, ts - 4, ts - 4, ts * 0.16);
    ctx.stroke();
  }

  drawChef(ctx, k, ts, skin, time);
  drawFx(ctx, fx, ts);
}

// ---------------------------------------------------------------------------
// Previews & logo
// ---------------------------------------------------------------------------

export function renderLevelPreview(canvas: HTMLCanvasElement, levelId: string): void {
  const level = getLevel(levelId);
  const built = buildKitchen(level);
  const ts = Math.floor(Math.min(canvas.width / built.w, canvas.height / built.h));
  const ctx = canvas.getContext('2d')!;
  const k: KitchenState = {
    w: built.w,
    h: built.h,
    grid: built.grid,
    chef: { x: built.spawn.x, y: built.spawn.y, fx: 0, fy: 1, carrying: null, walkPhase: 0, chopping: false },
    schedule: [],
    nextScheduleIdx: 0,
    nextOrderId: 1,
    orders: [],
    timeMs: 0,
    score: 0,
    combo: 1,
    maxCombo: 1,
    served: 0,
    missed: 0,
    events: []
  };
  ctx.save();
  ctx.translate(
    Math.floor((canvas.width - built.w * ts) / 2),
    Math.floor((canvas.height - built.h * ts) / 2)
  );
  for (let y = 0; y < k.h; y++) for (let x = 0; x < k.w; x++) drawTileBase(ctx, k.grid[y][x], x, y, ts);
  for (let y = 0; y < k.h; y++) for (let x = 0; x < k.w; x++) drawStation(ctx, k.grid[y][x], x, y, ts, 0);
  drawChef(ctx, k, ts, PLAYER_SKIN, 0);
  ctx.restore();
}

/** Title logo: a beaming chef over a frying pan. */
export function drawLogo(canvas: HTMLCanvasElement): void {
  const ctx = canvas.getContext('2d')!;
  const w = canvas.width;
  const h = canvas.height;
  ctx.clearRect(0, 0, w, h);
  const cx = w / 2;

  // Pan
  ctx.fillStyle = '#3f3c52';
  ctx.beginPath();
  ctx.ellipse(cx, h * 0.78, w * 0.3, h * 0.1, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = '#54506b';
  ctx.beginPath();
  ctx.ellipse(cx, h * 0.74, w * 0.3, h * 0.1, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = '#26222e';
  ctx.beginPath();
  ctx.ellipse(cx, h * 0.74, w * 0.24, h * 0.075, 0, 0, Math.PI * 2);
  ctx.fill();
  // Handle
  ctx.strokeStyle = '#54506b';
  ctx.lineWidth = w * 0.04;
  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(cx + w * 0.29, h * 0.74);
  ctx.lineTo(cx + w * 0.46, h * 0.68);
  ctx.stroke();

  // Chef head popping out of the pan
  const r = w * 0.17;
  const cy = h * 0.52;
  ctx.fillStyle = '#8b5cf6';
  ctx.beginPath();
  ctx.ellipse(cx, cy, r, r * 1.02, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = '#241b3a';
  ctx.beginPath();
  ctx.arc(cx - r * 0.3, cy - r * 0.15, r * 0.11, 0, Math.PI * 2);
  ctx.arc(cx + r * 0.3, cy - r * 0.15, r * 0.11, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = 'rgba(244,114,182,0.6)';
  ctx.beginPath();
  ctx.arc(cx - r * 0.52, cy + r * 0.1, r * 0.14, 0, Math.PI * 2);
  ctx.arc(cx + r * 0.52, cy + r * 0.1, r * 0.14, 0, Math.PI * 2);
  ctx.fill();
  ctx.strokeStyle = '#241b3a';
  ctx.lineWidth = r * 0.08;
  ctx.beginPath();
  ctx.arc(cx, cy + r * 0.15, r * 0.2, 0.25, Math.PI - 0.25);
  ctx.stroke();
  // Toque
  ctx.fillStyle = '#ffffff';
  ctx.beginPath();
  ctx.roundRect(cx - r * 0.55, cy - r * 1.35, r * 1.1, r * 0.55, r * 0.14);
  ctx.fill();
  ctx.beginPath();
  ctx.arc(cx - r * 0.32, cy - r * 1.38, r * 0.28, 0, Math.PI * 2);
  ctx.arc(cx + 0.02 * r, cy - r * 1.52, r * 0.32, 0, Math.PI * 2);
  ctx.arc(cx + r * 0.34, cy - r * 1.38, r * 0.28, 0, Math.PI * 2);
  ctx.fill();

  // Floating goodies
  drawComponent(ctx, { kind: 'tomato', state: 'raw' }, cx - w * 0.32, h * 0.3, w * 0.05);
  drawComponent(ctx, { kind: 'lettuce', state: 'raw' }, cx + w * 0.33, h * 0.26, w * 0.05);
  drawComponent(ctx, { kind: 'cheese', state: 'raw' }, cx - w * 0.38, h * 0.55, w * 0.045);
  drawComponent(ctx, { kind: 'bun', state: 'raw' }, cx + w * 0.38, h * 0.5, w * 0.05);

  // Sparkles
  ctx.fillStyle = '#fbbf24';
  for (const [sx, sy, ss] of [
    [0.2, 0.14, 0.018],
    [0.78, 0.12, 0.014],
    [0.12, 0.42, 0.012],
    [0.88, 0.36, 0.016]
  ] as const) {
    ctx.save();
    ctx.translate(w * sx, h * sy);
    const s = w * ss * 2.4;
    ctx.beginPath();
    for (let i = 0; i < 4; i++) {
      const a = (i * Math.PI) / 2;
      ctx.lineTo(Math.cos(a) * s, Math.sin(a) * s);
      ctx.lineTo(Math.cos(a + Math.PI / 4) * s * 0.35, Math.sin(a + Math.PI / 4) * s * 0.35);
    }
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }
}
