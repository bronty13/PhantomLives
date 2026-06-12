/**
 * @file sim.ts — the kitchen simulation. One KitchenState per chef; the
 * player and the AI run identical rules, fed only through SimInput.
 *
 * Interaction model (Space / click): context-sensitive on the tile the chef
 * faces. Chopping is "stand and work": progress accrues while a chef stands
 * still facing a board whose item is raw & choppable.
 */
import { buildKitchen, getLevel, isWalkable, tileAt } from './levels';
import { buildOrderSchedule } from './orders';
import { INGREDIENTS, getRecipe, plateMatchesRecipe } from './recipes';
import type {
  ActiveOrder,
  Component,
  DifficultyId,
  Item,
  KitchenState,
  SimConfig,
  SimEvent,
  SimInput,
  Tile
} from './types';

const CHEF_RADIUS = 0.32;

export function createKitchen(levelId: string, difficulty: DifficultyId, seed: number): KitchenState {
  const level = getLevel(levelId);
  const built = buildKitchen(level);
  return {
    w: built.w,
    h: built.h,
    grid: built.grid,
    chef: {
      x: built.spawn.x,
      y: built.spawn.y,
      fx: 0,
      fy: 1,
      carrying: null,
      walkPhase: 0,
      chopping: false
    },
    schedule: buildOrderSchedule(level.recipeIds, difficulty, seed),
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
}

function emit(k: KitchenState, e: SimEvent): void {
  k.events.push(e);
}

/** The tile coordinates the chef is standing on. */
export function chefTile(k: KitchenState): { x: number; y: number } {
  return { x: Math.floor(k.chef.x), y: Math.floor(k.chef.y) };
}

/** The station tile the chef is facing (may be null at map edge). */
export function facedTile(k: KitchenState): { tile: Tile; x: number; y: number } | null {
  const t = chefTile(k);
  const x = t.x + Math.round(k.chef.fx);
  const y = t.y + Math.round(k.chef.fy);
  const tile = tileAt(k, x, y);
  return tile ? { tile, x, y } : null;
}

// ---------------------------------------------------------------------------
// Movement
// ---------------------------------------------------------------------------

function moveChef(k: KitchenState, dtMs: number, input: SimInput, cfg: SimConfig): void {
  const c = k.chef;
  let { mx, my } = input;
  const len = Math.hypot(mx, my);
  if (len > 1e-6) {
    mx /= Math.max(1, len);
    my /= Math.max(1, len);
    // Facing snaps to the dominant axis of travel.
    if (Math.abs(mx) >= Math.abs(my)) {
      c.fx = Math.sign(mx);
      c.fy = 0;
    } else {
      c.fx = 0;
      c.fy = Math.sign(my);
    }
    c.walkPhase += dtMs / 90;
  }
  const dist = (cfg.chefSpeed * dtMs) / 1000;

  // Per-axis move + collide so the chef slides along counters.
  const tryAxis = (dx: number, dy: number): void => {
    const nx = c.x + dx;
    const ny = c.y + dy;
    const minX = nx - CHEF_RADIUS;
    const maxX = nx + CHEF_RADIUS;
    const minY = ny - CHEF_RADIUS;
    const maxY = ny + CHEF_RADIUS;
    for (let ty = Math.floor(minY); ty <= Math.floor(maxY); ty++) {
      for (let tx = Math.floor(minX); tx <= Math.floor(maxX); tx++) {
        if (!isWalkable(k.grid, tx, ty)) return; // blocked: cancel this axis
      }
    }
    c.x = nx;
    c.y = ny;
  };
  if (mx !== 0) tryAxis(mx * dist, 0);
  if (my !== 0) tryAxis(0, my * dist);
}

// ---------------------------------------------------------------------------
// Interaction
// ---------------------------------------------------------------------------

function freshIngredient(kind: Component['kind']): Item {
  return { type: 'ing', kind, state: 'raw' };
}

function canPlaceOnPlate(c: Component, cfg: SimConfig, contents: Component[]): boolean {
  if (contents.length >= cfg.plateCapacity) return false;
  if (c.state === 'chopped' || c.state === 'cooked') return true;
  return c.state === 'raw' && INGREDIENTS[c.kind].rawOnPlate;
}

/** Pot accepts chopped cookables; vegetables share, meat cooks alone. */
function potAccepts(pot: NonNullable<Tile['pot']>, comp: Component): boolean {
  if (pot.phase === 'burnt' || pot.phase === 'done') return false;
  if (comp.state !== 'chopped' || !INGREDIENTS[comp.kind].cookable) return false;
  const cap = INGREDIENTS[comp.kind].potCapacity;
  if (pot.contents.length >= cap) return false;
  if (pot.contents.length > 0) {
    const meatIn = pot.contents.some((c) => c.kind === 'meat');
    if (meatIn || comp.kind === 'meat') return false; // meat cooks alone
  }
  return true;
}

function interact(k: KitchenState, cfg: SimConfig): void {
  const faced = facedTile(k);
  if (!faced) return;
  const { tile, x, y } = faced;
  const c = k.chef;
  const carry = c.carrying;

  switch (tile.kind) {
    case 'crate': {
      if (!carry) {
        c.carrying = freshIngredient(tile.crate!);
        emit(k, { type: 'pickup', x, y });
      } else if (carry.type === 'plate') {
        // Convenience: pull a raw-on-plate ingredient (bun) straight onto the plate.
        const comp: Component = { kind: tile.crate!, state: 'raw' };
        if (canPlaceOnPlate(comp, cfg, carry.contents)) {
          carry.contents.push(comp);
          emit(k, { type: 'plateAdd', x, y });
        }
      }
      return;
    }
    case 'plates': {
      if (!carry) {
        c.carrying = { type: 'plate', contents: [] };
        emit(k, { type: 'pickup', x, y });
      }
      return;
    }
    case 'counter': {
      if (!carry && tile.item) {
        c.carrying = tile.item;
        tile.item = null;
        emit(k, { type: 'pickup', x, y });
      } else if (carry && !tile.item) {
        tile.item = carry;
        c.carrying = null;
        emit(k, { type: 'place', x, y });
      } else if (carry?.type === 'ing' && tile.item?.type === 'plate') {
        const comp: Component = { kind: carry.kind, state: carry.state };
        if (canPlaceOnPlate(comp, cfg, tile.item.contents)) {
          tile.item.contents.push(comp);
          c.carrying = null;
          emit(k, { type: 'plateAdd', x, y });
        }
      } else if (carry?.type === 'plate' && tile.item?.type === 'ing') {
        const comp: Component = { kind: tile.item.kind, state: tile.item.state };
        if (canPlaceOnPlate(comp, cfg, carry.contents)) {
          carry.contents.push(comp);
          tile.item = null;
          emit(k, { type: 'plateAdd', x, y });
        }
      }
      return;
    }
    case 'board': {
      if (!carry && tile.item) {
        c.carrying = tile.item;
        tile.item = null;
        tile.chop = 0;
        emit(k, { type: 'pickup', x, y });
      } else if (carry?.type === 'ing' && !tile.item) {
        tile.item = carry;
        tile.chop = 0;
        c.carrying = null;
        emit(k, { type: 'place', x, y });
      } else if (carry?.type === 'plate' && tile.item?.type === 'ing') {
        const comp: Component = { kind: tile.item.kind, state: tile.item.state };
        if (canPlaceOnPlate(comp, cfg, carry.contents)) {
          carry.contents.push(comp);
          tile.item = null;
          tile.chop = 0;
          emit(k, { type: 'plateAdd', x, y });
        }
      }
      return;
    }
    case 'stove': {
      const pot = tile.pot!;
      if (carry?.type === 'ing') {
        const comp: Component = { kind: carry.kind, state: carry.state };
        if (potAccepts(pot, comp)) {
          // Adding to a partially-cooked pot dilutes progress proportionally.
          pot.progress = (pot.progress * pot.contents.length) / (pot.contents.length + 1);
          pot.contents.push(comp);
          pot.phase = 'cooking';
          pot.burn = 0;
          c.carrying = null;
          emit(k, { type: 'potAdd', x, y });
        }
      } else if (carry?.type === 'plate' && pot.phase === 'done') {
        if (carry.contents.length + pot.contents.length <= cfg.plateCapacity) {
          carry.contents.push(...pot.contents);
          pot.contents = [];
          pot.phase = 'idle';
          pot.progress = 0;
          pot.burn = 0;
          emit(k, { type: 'soupPoured', x, y });
        }
      } else if (!carry && pot.phase === 'burnt') {
        pot.contents = [];
        pot.phase = 'idle';
        pot.progress = 0;
        pot.burn = 0;
        emit(k, { type: 'potCleared', x, y });
      }
      return;
    }
    case 'serve': {
      if (carry?.type !== 'plate' || carry.contents.length === 0) return;
      // Prefer the oldest order the plate satisfies (protects the combo).
      const match = k.orders.find((o) => plateMatchesRecipe(carry.contents, o.recipeId));
      if (!match) {
        emit(k, { type: 'serveBad', x, y });
        return;
      }
      serveOrder(k, match, x, y, cfg);
      c.carrying = null;
      return;
    }
    case 'trash': {
      if (!carry) return;
      if (carry.type === 'plate') {
        if (carry.contents.length > 0) {
          carry.contents = [];
          emit(k, { type: 'trash', x, y });
        }
      } else {
        c.carrying = null;
        emit(k, { type: 'trash', x, y });
      }
      return;
    }
    case 'floor':
      return;
  }
}

function serveOrder(k: KitchenState, order: ActiveOrder, x: number, y: number, cfg: SimConfig): void {
  const recipe = getRecipe(order.recipeId);
  const age = k.timeMs - order.spawnedAtMs;
  const remainingFrac = Math.max(0, 1 - age / order.patienceMs);
  const tip = Math.round(cfg.tipMax * remainingFrac);
  const isOldest = k.orders[0]?.id === order.id;
  let points: number;
  if (isOldest) {
    points = recipe.basePoints + tip * k.combo;
    k.combo = Math.min(cfg.comboMax, k.combo + 1);
  } else {
    points = recipe.basePoints + tip;
    k.combo = 1;
  }
  k.maxCombo = Math.max(k.maxCombo, k.combo);
  k.score += points;
  k.served += 1;
  k.orders = k.orders.filter((o) => o.id !== order.id);
  emit(k, { type: 'serveOk', x, y, points, recipeId: order.recipeId });
  // Track best patience fraction for the Lightning Ladle trophy.
  if (remainingFrac > (k as KitchenStateWithBest).bestServeFrac) {
    (k as KitchenStateWithBest).bestServeFrac = remainingFrac;
  }
}

/** bestServeFrac rides along on KitchenState without polluting the base type. */
export interface KitchenStateWithBest extends KitchenState {
  bestServeFrac: number;
}

// ---------------------------------------------------------------------------
// Passive processes: chopping, cooking, order spawn/expiry
// ---------------------------------------------------------------------------

function tickChopping(k: KitchenState, dtMs: number, input: SimInput, cfg: SimConfig): void {
  const c = k.chef;
  c.chopping = false;
  const moving = Math.hypot(input.mx, input.my) > 1e-6;
  if (moving || c.carrying) return;
  const faced = facedTile(k);
  if (!faced || faced.tile.kind !== 'board') return;
  const item = faced.tile.item;
  if (!item || item.type !== 'ing' || item.state !== 'raw' || !INGREDIENTS[item.kind].choppable) return;
  const before = faced.tile.chop ?? 0;
  const after = before + dtMs / cfg.chopMs;
  faced.tile.chop = after;
  c.chopping = true;
  // A little tick event roughly every quarter for chop SFX pacing.
  if (Math.floor(after * 4) > Math.floor(before * 4)) {
    emit(k, { type: 'chopTick', x: faced.x, y: faced.y });
  }
  if (after >= 1) {
    item.state = 'chopped';
    faced.tile.chop = 0;
    emit(k, { type: 'chopDone', x: faced.x, y: faced.y });
  }
}

function tickStoves(k: KitchenState, dtMs: number, cfg: SimConfig): void {
  for (let y = 0; y < k.h; y++) {
    for (let x = 0; x < k.w; x++) {
      const pot = k.grid[y][x].pot;
      if (!pot) continue;
      if (pot.phase === 'cooking') {
        pot.progress += dtMs / cfg.cookMs;
        if (pot.progress >= 1) {
          pot.progress = 1;
          pot.phase = 'done';
          pot.burn = 0;
          for (const comp of pot.contents) comp.state = 'cooked';
          emit(k, { type: 'cookDone', x, y });
        }
      } else if (pot.phase === 'done') {
        pot.burn += dtMs / cfg.burnMs;
        if (pot.burn >= 1) {
          pot.burn = 1;
          pot.phase = 'burnt';
          emit(k, { type: 'burnt', x, y });
        }
      }
    }
  }
}

function tickOrders(k: KitchenState, cfg: SimConfig): void {
  while (
    k.nextScheduleIdx < k.schedule.length &&
    k.schedule[k.nextScheduleIdx].atMs <= k.timeMs
  ) {
    const s = k.schedule[k.nextScheduleIdx++];
    k.orders.push({
      id: k.nextOrderId++,
      recipeId: s.recipeId,
      spawnedAtMs: k.timeMs,
      patienceMs: s.patienceMs
    });
    emit(k, { type: 'orderNew', x: 0, y: 0, recipeId: s.recipeId });
  }
  const expired = k.orders.filter((o) => k.timeMs - o.spawnedAtMs >= o.patienceMs);
  if (expired.length) {
    k.orders = k.orders.filter((o) => k.timeMs - o.spawnedAtMs < o.patienceMs);
    for (const o of expired) {
      k.missed += 1;
      k.score = Math.max(0, k.score - cfg.missPenalty);
      k.combo = 1;
      emit(k, { type: 'orderExpired', x: 0, y: 0, points: -cfg.missPenalty, recipeId: o.recipeId });
    }
  }
}

// ---------------------------------------------------------------------------
// Main tick
// ---------------------------------------------------------------------------

export function tick(k: KitchenState, dtMs: number, input: SimInput, cfg: SimConfig): void {
  if ((k as KitchenStateWithBest).bestServeFrac === undefined) {
    (k as KitchenStateWithBest).bestServeFrac = 0;
  }
  k.timeMs += dtMs;
  moveChef(k, dtMs, input, cfg);
  if (input.interact) interact(k, cfg);
  tickChopping(k, dtMs, input, cfg);
  tickStoves(k, dtMs, cfg);
  tickOrders(k, cfg);
}

/** Drain pending events (renderer calls once per frame). */
export function drainEvents(k: KitchenState): SimEvent[] {
  const ev = k.events;
  k.events = [];
  return ev;
}
