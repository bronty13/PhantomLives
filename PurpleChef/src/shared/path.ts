/**
 * @file path.ts — BFS pathfinding on the kitchen floor grid.
 *
 * Used by the AI chef and by the player's click-to-move. Paths are lists of
 * tile coordinates (integers); callers steer toward successive tile centers.
 */
import { isWalkable } from './levels';
import type { Tile } from './types';

export interface Pt {
  x: number;
  y: number;
}

const DIRS: Pt[] = [
  { x: 1, y: 0 },
  { x: -1, y: 0 },
  { x: 0, y: 1 },
  { x: 0, y: -1 }
];

/** BFS from `from` to `to` over floor tiles. Returns tile path including both ends, or null. */
export function findPath(grid: Tile[][], from: Pt, to: Pt): Pt[] | null {
  if (from.x === to.x && from.y === to.y) return [from];
  if (!isWalkable(grid, to.x, to.y)) return null;
  const w = grid[0].length;
  const key = (p: Pt): number => p.y * w + p.x;
  const prev = new Map<number, number>();
  const queue: Pt[] = [from];
  prev.set(key(from), -1);
  while (queue.length) {
    const cur = queue.shift()!;
    for (const d of DIRS) {
      const nx = cur.x + d.x;
      const ny = cur.y + d.y;
      if (!isWalkable(grid, nx, ny)) continue;
      const nk = ny * w + nx;
      if (prev.has(nk)) continue;
      prev.set(nk, key(cur));
      if (nx === to.x && ny === to.y) {
        const path: Pt[] = [{ x: nx, y: ny }];
        let k = key(cur);
        while (k !== -1) {
          path.unshift({ x: k % w, y: Math.floor(k / w) });
          k = prev.get(k)!;
        }
        return path;
      }
      queue.push({ x: nx, y: ny });
    }
  }
  return null;
}

/**
 * Best floor tile adjacent to a (non-walkable) station tile, reachable from
 * `from` — the spot a chef should stand to use the station. Null if boxed in.
 */
export function adjacentStandTile(grid: Tile[][], station: Pt, from: Pt): Pt | null {
  let best: Pt | null = null;
  let bestLen = Infinity;
  for (const d of DIRS) {
    const cand = { x: station.x + d.x, y: station.y + d.y };
    if (!isWalkable(grid, cand.x, cand.y)) continue;
    const p = findPath(grid, from, cand);
    if (p && p.length < bestLen) {
      bestLen = p.length;
      best = cand;
    }
  }
  return best;
}

/** All station tiles of a kind (with optional crate filter). */
export function findTiles(
  grid: Tile[][],
  pred: (t: Tile, x: number, y: number) => boolean
): Pt[] {
  const out: Pt[] = [];
  for (let y = 0; y < grid.length; y++) {
    for (let x = 0; x < grid[0].length; x++) {
      if (pred(grid[y][x], x, y)) out.push({ x, y });
    }
  }
  return out;
}
