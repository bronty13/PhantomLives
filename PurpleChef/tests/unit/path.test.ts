import { describe, expect, it } from 'vitest';
import { buildKitchen, getLevel } from '../../src/shared/levels';
import { adjacentStandTile, findPath } from '../../src/shared/path';

describe('path', () => {
  const built = buildKitchen(getLevel('soups-on'));

  it('finds a path around the center island', () => {
    const p = findPath(built.grid, { x: 1, y: 2 }, { x: 9, y: 2 });
    expect(p).not.toBeNull();
    expect(p![0]).toEqual({ x: 1, y: 2 });
    expect(p![p!.length - 1]).toEqual({ x: 9, y: 2 });
    // Consecutive steps are 4-adjacent.
    for (let i = 1; i < p!.length; i++) {
      const d = Math.abs(p![i].x - p![i - 1].x) + Math.abs(p![i].y - p![i - 1].y);
      expect(d).toBe(1);
    }
  });

  it('returns a single-tile path when start == goal', () => {
    expect(findPath(built.grid, { x: 1, y: 1 }, { x: 1, y: 1 })).toHaveLength(1);
  });

  it('refuses unreachable / non-floor targets', () => {
    expect(findPath(built.grid, { x: 1, y: 1 }, { x: 0, y: 0 })).toBeNull();
  });

  it('adjacentStandTile picks a floor tile next to a station', () => {
    // Serve window on the left wall.
    let serve: { x: number; y: number } | null = null;
    for (let y = 0; y < built.h; y++) {
      for (let x = 0; x < built.w; x++) {
        if (built.grid[y][x].kind === 'serve') serve = { x, y };
      }
    }
    const stand = adjacentStandTile(built.grid, serve!, { x: 5, y: 5 });
    expect(stand).not.toBeNull();
    expect(built.grid[stand!.y][stand!.x].kind).toBe('floor');
    expect(Math.abs(stand!.x - serve!.x) + Math.abs(stand!.y - serve!.y)).toBe(1);
  });
});
