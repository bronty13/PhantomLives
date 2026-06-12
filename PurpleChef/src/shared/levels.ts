/**
 * @file levels.ts — kitchen layouts as ASCII maps.
 *
 * Legend:
 *   #  counter            .  floor              @  chef spawn (floor)
 *   D  chopping board     S  stove (built-in pot/pan)
 *   P  plate stack        W  serving window     X  trash bin
 *   L/T/O/M/B/C  crates: Lettuce/Tomato/Onion/Meat/Bun/Cheese
 */
import type { IngredientKind, KitchenState, Tile } from './types';

export interface LevelDef {
  id: string;
  name: string;
  tagline: string;
  map: string[];
  recipeIds: string[];
}

export const LEVELS: LevelDef[] = [
  {
    id: 'salad-days',
    name: 'Salad Days',
    tagline: 'Chop, plate, serve — learn the ropes, no flames attached.',
    map: [
      '#PP#DD#TT##',
      '#.........#',
      'W.........L',
      '#....@....#',
      'W.........T',
      '#.........#',
      '#.........L',
      '#XX#DD#####'
    ],
    recipeIds: ['leafy-salad', 'garden-salad', 'tomato-salad']
  },
  {
    id: 'soups-on',
    name: "Soup's On",
    tagline: 'Three in the pot, eyes on the flame — don’t let it burn!',
    map: [
      '#PP#SS#SS##',
      '#.........#',
      'W.........T',
      '#..#####..#',
      'W.........T',
      '#....@....#',
      '#.........O',
      '#XX#DD#DDO#'
    ],
    recipeIds: ['tomato-salad', 'tomato-soup', 'onion-soup']
  },
  {
    id: 'burger-blitz',
    name: 'Burger Blitz',
    tagline: 'Grill patties, stack tall, serve hot. The full kitchen brigade.',
    map: [
      '#PP#SS#SS##',
      '#.........#',
      'W.........M',
      '#....@....#',
      'W.........B',
      '#.........C',
      '#.........T',
      '#XX#DD#DDL#'
    ],
    recipeIds: ['burger', 'cheeseburger', 'deluxe-burger']
  }
];

export function getLevel(id: string): LevelDef {
  const l = LEVELS.find((x) => x.id === id);
  if (!l) throw new Error(`unknown level: ${id}`);
  return l;
}

const CRATE_CHARS: Record<string, IngredientKind> = {
  L: 'lettuce',
  T: 'tomato',
  O: 'onion',
  M: 'meat',
  B: 'bun',
  C: 'cheese'
};

export interface BuiltKitchen {
  grid: Tile[][];
  w: number;
  h: number;
  spawn: { x: number; y: number };
}

/** Parse an ASCII map into a fresh tile grid. Throws on malformed maps. */
export function buildKitchen(level: LevelDef): BuiltKitchen {
  const rows = level.map;
  const h = rows.length;
  const w = rows[0].length;
  let spawn: { x: number; y: number } | null = null;
  const grid: Tile[][] = [];
  for (let y = 0; y < h; y++) {
    if (rows[y].length !== w) throw new Error(`level ${level.id}: row ${y} width mismatch`);
    const row: Tile[] = [];
    for (let x = 0; x < w; x++) {
      const ch = rows[y][x];
      let tile: Tile;
      if (ch === '.') tile = { kind: 'floor' };
      else if (ch === '@') {
        tile = { kind: 'floor' };
        spawn = { x: x + 0.5, y: y + 0.5 };
      } else if (ch === '#') tile = { kind: 'counter', item: null };
      else if (ch === 'D') tile = { kind: 'board', item: null, chop: 0 };
      else if (ch === 'S') tile = { kind: 'stove', pot: { contents: [], progress: 0, burn: 0, phase: 'idle' } };
      else if (ch === 'P') tile = { kind: 'plates' };
      else if (ch === 'W') tile = { kind: 'serve' };
      else if (ch === 'X') tile = { kind: 'trash' };
      else if (CRATE_CHARS[ch]) tile = { kind: 'crate', crate: CRATE_CHARS[ch] };
      else throw new Error(`level ${level.id}: unknown map char '${ch}'`);
      row.push(tile);
    }
    grid.push(row);
  }
  if (!spawn) throw new Error(`level ${level.id}: no spawn (@)`);
  return { grid, w, h, spawn };
}

export function isWalkable(grid: Tile[][], x: number, y: number): boolean {
  if (y < 0 || y >= grid.length || x < 0 || x >= grid[0].length) return false;
  return grid[y][x].kind === 'floor';
}

/** Every crate kind a level actually contains (sanity for recipes/tests). */
export function levelCrateKinds(built: BuiltKitchen): Set<IngredientKind> {
  const kinds = new Set<IngredientKind>();
  for (const row of built.grid) for (const t of row) if (t.kind === 'crate' && t.crate) kinds.add(t.crate);
  return kinds;
}

export function tileAt(k: KitchenState, x: number, y: number): Tile | null {
  if (y < 0 || y >= k.h || x < 0 || x >= k.w) return null;
  return k.grid[y][x];
}
