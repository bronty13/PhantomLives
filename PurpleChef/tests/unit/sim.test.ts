import { describe, expect, it } from 'vitest';
import { DIFFICULTIES } from '../../src/shared/difficulty';
import { createKitchen, drainEvents, tick, type KitchenStateWithBest } from '../../src/shared/sim';
import type { KitchenState, SimInput } from '../../src/shared/types';

const CFG = DIFFICULTIES.chef.sim;
const IDLE: SimInput = { mx: 0, my: 0, interact: false };
const ACT: SimInput = { mx: 0, my: 0, interact: true };

/** Park the chef on a floor tile facing a direction. */
function placeChef(k: KitchenState, x: number, y: number, fx: number, fy: number): void {
  k.chef.x = x + 0.5;
  k.chef.y = y + 0.5;
  k.chef.fx = fx;
  k.chef.fy = fy;
}

function findTile(k: KitchenState, kind: string, crate?: string): { x: number; y: number } {
  for (let y = 0; y < k.h; y++) {
    for (let x = 0; x < k.w; x++) {
      const t = k.grid[y][x];
      if (t.kind === kind && (!crate || t.crate === crate)) return { x, y };
    }
  }
  throw new Error(`no ${kind} tile`);
}

/** A floor tile adjacent to `pt`, with facing toward pt. */
function standAt(k: KitchenState, pt: { x: number; y: number }): { x: number; y: number; fx: number; fy: number } {
  for (const [dx, dy] of [
    [0, 1],
    [0, -1],
    [1, 0],
    [-1, 0]
  ] as const) {
    const x = pt.x + dx;
    const y = pt.y + dy;
    if (y >= 0 && y < k.h && x >= 0 && x < k.w && k.grid[y][x].kind === 'floor') {
      return { x, y, fx: -dx, fy: -dy };
    }
  }
  throw new Error('no stand tile');
}

function useStation(k: KitchenState, pt: { x: number; y: number }): void {
  const s = standAt(k, pt);
  placeChef(k, s.x, s.y, s.fx, s.fy);
  tick(k, 16, ACT, CFG);
}

describe('sim: movement & collision', () => {
  it('chef cannot walk through counters', () => {
    const k = createKitchen('salad-days', 'chef', 1);
    placeChef(k, 1, 1, 0, -1);
    for (let i = 0; i < 100; i++) tick(k, 16, { mx: 0, my: -1, interact: false }, CFG);
    expect(k.chef.y).toBeGreaterThan(1); // stayed inside the kitchen
  });

  it('facing snaps to dominant movement axis', () => {
    const k = createKitchen('salad-days', 'chef', 1);
    tick(k, 16, { mx: 1, my: 0.2, interact: false }, CFG);
    expect(k.chef.fx).toBe(1);
    expect(k.chef.fy).toBe(0);
  });
});

describe('sim: chop → plate → serve (salad flow)', () => {
  it('serves a leafy salad and scores base + tip × combo', () => {
    const k = createKitchen('salad-days', 'chef', 1);
    // Force a known first order.
    k.schedule = [{ atMs: 0, recipeId: 'leafy-salad', patienceMs: 60_000 }];
    tick(k, 16, IDLE, CFG); // spawn the order
    expect(k.orders).toHaveLength(1);

    // Grab lettuce from the crate.
    const crate = findTile(k, 'crate', 'lettuce');
    useStation(k, crate);
    expect(k.chef.carrying).toMatchObject({ type: 'ing', kind: 'lettuce', state: 'raw' });

    // Put it on a board and stand there until chopped.
    const board = findTile(k, 'board');
    useStation(k, board);
    expect(k.chef.carrying).toBeNull();
    for (let i = 0; i < 200; i++) tick(k, 16, IDLE, CFG);
    expect(k.grid[board.y][board.x].item).toMatchObject({ state: 'chopped' });

    // Grab a plate, scoop the chopped lettuce off the board.
    const plates = findTile(k, 'plates');
    useStation(k, plates);
    expect(k.chef.carrying?.type).toBe('plate');
    useStation(k, board);
    expect(k.chef.carrying).toMatchObject({ type: 'plate' });
    expect((k.chef.carrying as { contents: unknown[] }).contents).toHaveLength(1);

    // Serve.
    const before = k.score;
    const serve = findTile(k, 'serve');
    useStation(k, serve);
    expect(k.chef.carrying).toBeNull();
    expect(k.served).toBe(1);
    expect(k.orders).toHaveLength(0);
    // base 20 + tip up to 12 (combo 1 on first serve)
    expect(k.score - before).toBeGreaterThanOrEqual(20);
    expect(k.score - before).toBeLessThanOrEqual(20 + CFG.tipMax);
    expect(k.combo).toBe(2); // oldest-order serve bumps the combo
    expect((k as KitchenStateWithBest).bestServeFrac).toBeGreaterThan(0.9);
  });

  it('rejects a wrong dish at the window', () => {
    const k = createKitchen('salad-days', 'chef', 1);
    k.schedule = [{ atMs: 0, recipeId: 'garden-salad', patienceMs: 60_000 }];
    tick(k, 16, IDLE, CFG);
    k.chef.carrying = { type: 'plate', contents: [{ kind: 'lettuce', state: 'chopped' }] };
    const serve = findTile(k, 'serve');
    useStation(k, serve);
    expect(k.served).toBe(0);
    expect(k.chef.carrying?.type).toBe('plate'); // still holding it
    expect(drainEvents(k).some((e) => e.type === 'serveBad')).toBe(true);
  });
});

describe('sim: cooking', () => {
  it('cooks tomato soup, pours onto plate, burns if neglected', () => {
    const k = createKitchen('soups-on', 'chef', 1);
    k.schedule = [];
    const stove = findTile(k, 'stove');
    const pot = k.grid[stove.y][stove.x].pot!;

    // Drop 3 chopped tomatoes in.
    for (let i = 0; i < 3; i++) {
      k.chef.carrying = { type: 'ing', kind: 'tomato', state: 'chopped' };
      useStation(k, stove);
      expect(k.chef.carrying).toBeNull();
    }
    expect(pot.contents).toHaveLength(3);
    expect(pot.phase).toBe('cooking');

    // Capacity: a 4th tomato is refused.
    k.chef.carrying = { type: 'ing', kind: 'tomato', state: 'chopped' };
    useStation(k, stove);
    expect(k.chef.carrying).not.toBeNull();
    k.chef.carrying = null;

    // Let it cook.
    for (let i = 0; i < 1000 && pot.phase !== 'done'; i++) tick(k, 16, IDLE, CFG);
    expect(pot.phase).toBe('done');
    expect(pot.contents.every((c) => c.state === 'cooked')).toBe(true);

    // Pour onto a plate.
    k.chef.carrying = { type: 'plate', contents: [] };
    useStation(k, stove);
    expect((k.chef.carrying as { contents: unknown[] }).contents).toHaveLength(3);
    expect(pot.phase).toBe('idle');

    // Now burn one: meat alone, cook, then neglect.
    k.chef.carrying = { type: 'ing', kind: 'meat', state: 'chopped' };
    useStation(k, stove);
    for (let i = 0; i < 3000 && pot.phase !== 'burnt'; i++) tick(k, 16, IDLE, CFG);
    expect(pot.phase).toBe('burnt');

    // Burnt pot can't pour; empty-handed interact scrapes it clean.
    k.chef.carrying = null;
    useStation(k, stove);
    expect(pot.phase).toBe('idle');
    expect(pot.contents).toHaveLength(0);
  });

  it('meat cooks alone and vegetables never share with it', () => {
    const k = createKitchen('burger-blitz', 'chef', 1);
    k.schedule = [];
    const stove = findTile(k, 'stove');
    const pot = k.grid[stove.y][stove.x].pot!;
    k.chef.carrying = { type: 'ing', kind: 'meat', state: 'chopped' };
    useStation(k, stove);
    expect(pot.contents).toHaveLength(1);
    k.chef.carrying = { type: 'ing', kind: 'tomato', state: 'chopped' };
    useStation(k, stove);
    expect(k.chef.carrying).not.toBeNull(); // refused
  });
});

describe('sim: orders & combo', () => {
  it('expired orders cost points, a miss, and the combo', () => {
    const k = createKitchen('salad-days', 'chef', 1);
    k.schedule = [{ atMs: 0, recipeId: 'leafy-salad', patienceMs: 1000 }];
    k.score = 50;
    k.combo = 3;
    for (let i = 0; i < 100; i++) tick(k, 16, IDLE, CFG);
    expect(k.orders).toHaveLength(0);
    expect(k.missed).toBe(1);
    expect(k.score).toBe(50 - CFG.missPenalty);
    expect(k.combo).toBe(1);
  });

  it('score never goes negative', () => {
    const k = createKitchen('salad-days', 'chef', 1);
    k.schedule = [
      { atMs: 0, recipeId: 'leafy-salad', patienceMs: 500 },
      { atMs: 10, recipeId: 'leafy-salad', patienceMs: 500 }
    ];
    for (let i = 0; i < 100; i++) tick(k, 16, IDLE, CFG);
    expect(k.missed).toBe(2);
    expect(k.score).toBe(0);
  });

  it('serving out of order resets the combo to 1', () => {
    const k = createKitchen('salad-days', 'chef', 1);
    k.schedule = [
      { atMs: 0, recipeId: 'garden-salad', patienceMs: 60_000 },
      { atMs: 0, recipeId: 'leafy-salad', patienceMs: 60_000 }
    ];
    tick(k, 16, IDLE, CFG);
    expect(k.orders).toHaveLength(2);
    k.combo = 3;
    k.chef.carrying = { type: 'plate', contents: [{ kind: 'lettuce', state: 'chopped' }] };
    const serve = findTile(k, 'serve');
    useStation(k, serve);
    expect(k.served).toBe(1);
    expect(k.combo).toBe(1); // leafy-salad was the *second* ticket
  });

  it('bun hops onto a held plate straight from the crate', () => {
    const k = createKitchen('burger-blitz', 'chef', 1);
    k.schedule = [];
    k.chef.carrying = { type: 'plate', contents: [] };
    const crate = findTile(k, 'crate', 'bun');
    useStation(k, crate);
    expect((k.chef.carrying as { contents: unknown[] }).contents).toMatchObject([
      { kind: 'bun', state: 'raw' }
    ]);
  });

  it('trash empties a plate but keeps it, and eats loose items', () => {
    const k = createKitchen('salad-days', 'chef', 1);
    k.schedule = [];
    const trash = findTile(k, 'trash');
    k.chef.carrying = { type: 'plate', contents: [{ kind: 'lettuce', state: 'chopped' }] };
    useStation(k, trash);
    expect(k.chef.carrying).toMatchObject({ type: 'plate', contents: [] });
    k.chef.carrying = { type: 'ing', kind: 'tomato', state: 'raw' };
    useStation(k, trash);
    expect(k.chef.carrying).toBeNull();
  });
});
