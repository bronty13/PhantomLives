/**
 * @file ai.ts — the rival AI chef.
 *
 * A reactive policy, not a scripted plan: every think-tick it looks at its
 * kitchen and decides the single most useful next errand. It plays through
 * the exact same SimInput channel as the player — same speed caps, same
 * interaction rules — so difficulty comes only from reaction time, movement
 * speed, and discipline (tuned in difficulty.ts).
 *
 * Facing trick: the sim updates facing from movement input, and walking into
 * a counter pins position while still turning the chef. The AI exploits this:
 * to face a station it simply pushes toward it for a tick.
 */
import type { DifficultyDef } from './difficulty';
import { INGREDIENTS, getRecipe, missingForRecipe, plateMatchesRecipe, plateSubsetOfRecipe } from './recipes';
import { adjacentStandTile, findPath, findTiles, type Pt } from './path';
import { chefTile } from './sim';
import type { Component, Item, KitchenState, SimInput, Tile } from './types';

export interface AIBrain {
  thinkMs: number; // countdown to next decision
  idleMs: number; // post-serve breather
  target: Pt | null; // station tile to use
  standTile: Pt | null; // floor tile to stand on
  path: Pt[]; // waypoints (tile coords) still to visit
  wantInteract: boolean;
  waitAtBoard: boolean; // stand still until the board item is chopped
  facePushMs: number; // how long we've been pushing to face the target
}

export function createBrain(): AIBrain {
  return {
    thinkMs: 0,
    idleMs: 0,
    target: null,
    standTile: null,
    path: [],
    wantInteract: false,
    waitAtBoard: false,
    facePushMs: 0
  };
}

const IDLE: SimInput = { mx: 0, my: 0, interact: false };

// ---------------------------------------------------------------------------
// Kitchen queries
// ---------------------------------------------------------------------------

function dist(a: Pt, b: Pt): number {
  return Math.abs(a.x - b.x) + Math.abs(a.y - b.y);
}

function nearest(from: Pt, tiles: Pt[]): Pt | null {
  let best: Pt | null = null;
  let bestD = Infinity;
  for (const t of tiles) {
    const d = dist(from, t);
    if (d < bestD) {
      bestD = d;
      best = t;
    }
  }
  return best;
}

function stagedPlate(k: KitchenState): { pt: Pt; plate: Extract<Item, { type: 'plate' }> } | null {
  for (let y = 0; y < k.h; y++) {
    for (let x = 0; x < k.w; x++) {
      const t = k.grid[y][x];
      if ((t.kind === 'counter' || t.kind === 'board') && t.item?.type === 'plate') {
        return { pt: { x, y }, plate: t.item };
      }
    }
  }
  return null;
}

/** The order the AI is working toward: oldest whose recipe can absorb `plate`. */
function currentDish(k: KitchenState, plateContents: Component[]): string | null {
  for (const o of k.orders) {
    if (plateSubsetOfRecipe(plateContents, o.recipeId)) return o.recipeId;
  }
  return null;
}

/** Eventual components already "in flight" around the kitchen. */
function inFlightComponents(k: KitchenState): Component[] {
  const out: Component[] = [];
  for (let y = 0; y < k.h; y++) {
    for (let x = 0; x < k.w; x++) {
      const t = k.grid[y][x];
      if (t.item?.type === 'ing') {
        const info = INGREDIENTS[t.item.kind];
        // A raw choppable on a board will become chopped; chopped cookables
        // will become cooked, etc. Count the most-finished plausible form.
        if (t.item.state === 'raw' && info.choppable) {
          out.push({ kind: t.item.kind, state: info.cookable ? 'cooked' : 'chopped' });
        } else if (t.item.state === 'chopped' && info.cookable) {
          out.push({ kind: t.item.kind, state: 'cooked' });
        } else {
          out.push({ kind: t.item.kind, state: t.item.state });
        }
      }
      if (t.pot) for (const c of t.pot.contents) out.push({ kind: c.kind, state: 'cooked' });
    }
  }
  const carry = k.chef.carrying;
  if (carry?.type === 'ing') {
    const info = INGREDIENTS[carry.kind];
    if (carry.state === 'raw' && info.choppable) {
      out.push({ kind: carry.kind, state: info.cookable ? 'cooked' : 'chopped' });
    } else if (carry.state === 'chopped' && info.cookable) {
      out.push({ kind: carry.kind, state: 'cooked' });
    } else {
      out.push({ kind: carry.kind, state: carry.state });
    }
  }
  return out;
}

function subtract(needs: Component[], have: Component[]): Component[] {
  const left = [...needs];
  for (const c of have) {
    // A chopped in-flight component can satisfy a chopped need, etc. We match
    // on the *eventual* state, which inFlightComponents already normalized —
    // but a chopped need vs an in-flight 'cooked' projection of the same kind
    // should also cancel (cheese is never cookable, so this only affects
    // soup/meat kinds where chopped needs don't appear in recipes).
    let i = left.findIndex((n) => n.kind === c.kind && n.state === c.state);
    if (i < 0) i = left.findIndex((n) => n.kind === c.kind);
    if (i >= 0) left.splice(i, 1);
  }
  return left;
}

// ---------------------------------------------------------------------------
// Errand helpers
// ---------------------------------------------------------------------------

function goUse(k: KitchenState, brain: AIBrain, station: Pt, opts?: { wait?: boolean }): boolean {
  const from = chefTile(k);
  const stand = adjacentStandTile(k.grid, station, from);
  if (!stand) return false;
  const path = findPath(k.grid, from, stand);
  if (!path) return false;
  brain.target = station;
  brain.standTile = stand;
  brain.path = path.slice(1); // drop current tile
  brain.wantInteract = !opts?.wait;
  brain.waitAtBoard = !!opts?.wait;
  brain.facePushMs = 0;
  return true;
}

function tilesOf(k: KitchenState, pred: (t: Tile, x: number, y: number) => boolean): Pt[] {
  return findTiles(k.grid, pred);
}

function freeCounter(k: KitchenState, near: Pt): Pt | null {
  return nearest(near, tilesOf(k, (t) => t.kind === 'counter' && !t.item));
}

// ---------------------------------------------------------------------------
// The decision policy
// ---------------------------------------------------------------------------

function decide(k: KitchenState, brain: AIBrain): void {
  const chef = k.chef;
  const carry = chef.carrying;
  const me = chefTile(k);

  // ----- Carrying a plate -----
  if (carry?.type === 'plate') {
    if (carry.contents.length > 0 && k.orders.some((o) => plateMatchesRecipe(carry.contents, o.recipeId))) {
      const serve = nearest(me, tilesOf(k, (t) => t.kind === 'serve'));
      if (serve && goUse(k, brain, serve)) return;
    }
    const dish = currentDish(k, carry.contents);
    if (!dish) {
      // Plate holds junk no active order wants — bin the contents.
      if (carry.contents.length > 0) {
        const trash = nearest(me, tilesOf(k, (t) => t.kind === 'trash'));
        if (trash && goUse(k, brain, trash)) return;
      }
      brain.idleMs = 250;
      return;
    }
    const missing = missingForRecipe(carry.contents, dish);
    // Pour a finished pot whose entire contents we still need.
    const pourable = tilesOf(k, (t) => {
      if (t.kind !== 'stove' || t.pot?.phase !== 'done') return false;
      const left = [...missing];
      for (const c of t.pot.contents) {
        const i = left.findIndex((m) => m.kind === c.kind && m.state === 'cooked');
        if (i < 0) return false;
        left.splice(i, 1);
      }
      return true;
    });
    const pour = nearest(me, pourable);
    if (pour && goUse(k, brain, pour)) return;
    // Absorb a needed prepared component sitting out.
    const absorbable = tilesOf(k, (t) => {
      if ((t.kind !== 'counter' && t.kind !== 'board') || t.item?.type !== 'ing') return false;
      return missing.some((m) => m.kind === (t.item as { kind: Component['kind'] }).kind && m.state === (t.item as { state: Component['state'] }).state);
    });
    const absorb = nearest(me, absorbable);
    if (absorb && goUse(k, brain, absorb)) return;
    // Pull raw-on-plate ingredients (bun) straight from the crate.
    const rawNeed = missing.find((m) => m.state === 'raw' && INGREDIENTS[m.kind].rawOnPlate);
    if (rawNeed) {
      const crate = nearest(me, tilesOf(k, (t) => t.kind === 'crate' && t.crate === rawNeed.kind));
      if (crate && goUse(k, brain, crate)) return;
    }
    // Anything left needs prep we can't do with full hands — stage the plate.
    if (missing.length > 0) {
      const counter = freeCounter(k, me);
      if (counter && goUse(k, brain, counter)) return;
    }
    brain.idleMs = 250;
    return;
  }

  // ----- Carrying an ingredient -----
  if (carry?.type === 'ing') {
    const staged = stagedPlate(k);
    const dishFor = (contents: Component[]): string | null => currentDish(k, contents);
    const neededBySomeOrder = k.orders.some((o) =>
      missingForRecipe(staged?.plate.contents ?? [], o.recipeId).some(
        (m) =>
          m.kind === carry.kind &&
          (m.state === carry.state ||
            (m.state === 'chopped' && carry.state === 'raw' && INGREDIENTS[carry.kind].choppable) ||
            (m.state === 'cooked' && carry.state !== 'cooked' && INGREDIENTS[carry.kind].cookable))
      )
    );
    if (!neededBySomeOrder) {
      const trash = nearest(me, tilesOf(k, (t) => t.kind === 'trash'));
      if (trash && goUse(k, brain, trash)) return;
    }
    if (carry.state === 'raw' && INGREDIENTS[carry.kind].choppable) {
      const board = nearest(me, tilesOf(k, (t) => t.kind === 'board' && !t.item));
      if (board && goUse(k, brain, board)) return;
      brain.idleMs = 300; // all boards busy; wait a beat
      return;
    }
    if (carry.state === 'chopped' && INGREDIENTS[carry.kind].cookable) {
      // Needs cooking for the current dish.
      const dish = dishFor(staged?.plate.contents ?? []);
      const wantsCooked =
        !dish || getRecipe(dish).needs.some((n) => n.kind === carry.kind && n.state === 'cooked');
      if (wantsCooked) {
        const stove = nearest(
          me,
          tilesOf(k, (t) => {
            const pot = t.pot;
            if (t.kind !== 'stove' || !pot) return false;
            if (pot.phase === 'burnt' || pot.phase === 'done') return false;
            const cap = INGREDIENTS[carry.kind].potCapacity;
            if (pot.contents.length >= cap) return false;
            if (pot.contents.length > 0) {
              if (pot.contents.some((c) => c.kind === 'meat') || carry.kind === 'meat') return false;
            }
            return true;
          })
        );
        if (stove && goUse(k, brain, stove)) return;
        // No pot free — park the ingredient and deal with pots next think.
        const counter = freeCounter(k, me);
        if (counter && goUse(k, brain, counter)) return;
        brain.idleMs = 300;
        return;
      }
    }
    // A finished (chopped / cooked / raw-on-plate) component: deliver to plate.
    if (staged) {
      if (goUse(k, brain, staged.pt)) return;
    }
    const counter = freeCounter(k, me);
    if (counter && goUse(k, brain, counter)) return;
    brain.idleMs = 300;
    return;
  }

  // ----- Empty-handed -----
  // 1. A burnt pot is dead weight: scrape it.
  const burnt = nearest(me, tilesOf(k, (t) => t.kind === 'stove' && t.pot?.phase === 'burnt'));
  if (burnt && goUse(k, brain, burnt)) return;

  if (k.orders.length === 0) {
    brain.idleMs = 400;
    return;
  }

  const staged = stagedPlate(k);

  // 2. A staged plate that already satisfies an order: grab it (then the
  //    carrying-a-plate branch walks it to the window).
  if (
    staged &&
    staged.plate.contents.length > 0 &&
    k.orders.some((o) => plateMatchesRecipe(staged.plate.contents, o.recipeId))
  ) {
    if (goUse(k, brain, staged.pt)) return;
  }

  // 3. A finished pot wants a plate underneath it, pronto.
  const doneStove = tilesOf(k, (t) => t.kind === 'stove' && t.pot?.phase === 'done');
  if (doneStove.length > 0) {
    if (staged) {
      if (goUse(k, brain, staged.pt)) return; // pick the plate up
    } else {
      const stack = nearest(me, tilesOf(k, (t) => t.kind === 'plates'));
      if (stack && goUse(k, brain, stack)) return;
    }
  }

  // 4. Chopped produce on a board: collect it.
  const choppedBoard = nearest(
    me,
    tilesOf(k, (t) => t.kind === 'board' && t.item?.type === 'ing' && t.item.state === 'chopped')
  );
  if (choppedBoard && goUse(k, brain, choppedBoard)) return;

  // 5. Raw produce on a board: stand there and chop.
  const rawBoard = nearest(
    me,
    tilesOf(
      k,
      (t) =>
        t.kind === 'board' &&
        t.item?.type === 'ing' &&
        t.item.state === 'raw' &&
        INGREDIENTS[t.item.kind].choppable
    )
  );
  if (rawBoard && goUse(k, brain, rawBoard, { wait: true })) return;

  // 6. Stage a plate early so finished components have a home.
  const dish = currentDish(k, staged?.plate.contents ?? []) ?? k.orders[0].recipeId;
  if (!staged) {
    const stack = nearest(me, tilesOf(k, (t) => t.kind === 'plates'));
    if (stack && goUse(k, brain, stack)) return;
  }

  // 7. Fetch the next missing raw ingredient for the current dish.
  const baseContents = staged?.plate.contents ?? [];
  const missing = subtract(missingForRecipe(baseContents, dish), inFlightComponents(k));
  const fetchable = missing.find((m) => m.state !== 'raw' || INGREDIENTS[m.kind].rawOnPlate);
  if (fetchable && !(fetchable.state === 'raw' && INGREDIENTS[fetchable.kind].rawOnPlate)) {
    const crate = nearest(me, tilesOf(k, (t) => t.kind === 'crate' && t.crate === fetchable.kind));
    if (crate && goUse(k, brain, crate)) return;
  }
  // Raw-on-plate components (bun) are pulled while holding the plate; if
  // that's all that's missing, go pick the staged plate up.
  if (fetchable && staged && fetchable.state === 'raw' && INGREDIENTS[fetchable.kind].rawOnPlate) {
    if (goUse(k, brain, staged.pt)) return;
  }

  // 8. Everything's in flight (e.g. soup cooking) — breathe.
  brain.idleMs = 350;
}

// ---------------------------------------------------------------------------
// Per-tick controller: walk the path, face the station, act
// ---------------------------------------------------------------------------

export function aiStep(k: KitchenState, brain: AIBrain, dtMs: number, diff: DifficultyDef): SimInput {
  const chef = k.chef;

  if (brain.idleMs > 0) {
    brain.idleMs -= dtMs;
    return IDLE;
  }

  // Serve breather: when the kitchen just scored, novice AIs daydream.
  // (handled by caller bumping idleMs on serveOk events)

  // Walk the path.
  if (brain.path.length > 0) {
    const wp = brain.path[0];
    const tx = wp.x + 0.5;
    const ty = wp.y + 0.5;
    const dx = tx - chef.x;
    const dy = ty - chef.y;
    if (Math.hypot(dx, dy) < 0.15) {
      brain.path.shift();
      return aiStep(k, brain, 0, diff); // immediately consider next waypoint
    }
    const len = Math.hypot(dx, dy) || 1;
    return { mx: dx / len, my: dy / len, interact: false };
  }

  // At the stand tile (or no errand at all).
  if (brain.target && brain.standTile) {
    const stand = brain.standTile;
    const offX = stand.x + 0.5 - chef.x;
    const offY = stand.y + 0.5 - chef.y;
    if (Math.hypot(offX, offY) > 0.2) {
      // Drifted (collision nudge) — walk back onto the stand tile.
      const len = Math.hypot(offX, offY) || 1;
      return { mx: offX / len, my: offY / len, interact: false };
    }
    const needFx = Math.sign(brain.target.x - stand.x);
    const needFy = Math.sign(brain.target.y - stand.y);
    const facingRight = chef.fx === needFx && chef.fy === needFy;
    if (!facingRight && brain.facePushMs < 400) {
      brain.facePushMs += dtMs;
      // Push into the station: position pins against the counter, facing turns.
      return { mx: needFx * 0.6, my: needFy * 0.6, interact: false };
    }
    if (brain.wantInteract) {
      brain.wantInteract = false;
      if (!brain.waitAtBoard) {
        brain.target = null;
        brain.standTile = null;
      }
      brain.thinkMs = Math.min(brain.thinkMs, 120);
      return { mx: 0, my: 0, interact: true };
    }
    if (brain.waitAtBoard) {
      const t = k.grid[brain.target.y]?.[brain.target.x];
      const stillRaw = t?.kind === 'board' && t.item?.type === 'ing' && t.item.state === 'raw';
      if (stillRaw) return IDLE; // sim chops while we stand here
      brain.waitAtBoard = false;
      brain.target = null;
      brain.standTile = null;
      brain.thinkMs = 0;
      return IDLE;
    }
    brain.target = null;
    brain.standTile = null;
  }

  // Think.
  brain.thinkMs -= dtMs;
  if (brain.thinkMs <= 0) {
    brain.thinkMs = diff.aiThinkMs;
    decide(k, brain);
  }
  return IDLE;
}
