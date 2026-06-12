import { describe, expect, it } from 'vitest';
import { LEVELS, buildKitchen, isWalkable } from '../../src/shared/levels';
import { adjacentStandTile, findPath } from '../../src/shared/path';

describe('levels', () => {
  it('all maps parse with a spawn point', () => {
    for (const level of LEVELS) {
      const built = buildKitchen(level);
      expect(built.w).toBeGreaterThan(5);
      expect(built.h).toBeGreaterThan(5);
      expect(isWalkable(built.grid, Math.floor(built.spawn.x), Math.floor(built.spawn.y))).toBe(true);
    }
  });

  it('every station is reachable from the spawn', () => {
    for (const level of LEVELS) {
      const built = buildKitchen(level);
      const from = { x: Math.floor(built.spawn.x), y: Math.floor(built.spawn.y) };
      for (let y = 0; y < built.h; y++) {
        for (let x = 0; x < built.w; x++) {
          const t = built.grid[y][x];
          if (t.kind === 'floor' || t.kind === 'counter') continue;
          const stand = adjacentStandTile(built.grid, { x, y }, from);
          expect(stand, `${level.id}: ${t.kind} at ${x},${y} unreachable`).not.toBeNull();
        }
      }
    }
  });

  it('every floor tile is connected to the spawn', () => {
    for (const level of LEVELS) {
      const built = buildKitchen(level);
      const from = { x: Math.floor(built.spawn.x), y: Math.floor(built.spawn.y) };
      for (let y = 0; y < built.h; y++) {
        for (let x = 0; x < built.w; x++) {
          if (built.grid[y][x].kind !== 'floor') continue;
          expect(findPath(built.grid, from, { x, y }), `${level.id}: floor ${x},${y} isolated`).not.toBeNull();
        }
      }
    }
  });

  it('each level has plates, serve, trash and at least one board or stove', () => {
    for (const level of LEVELS) {
      const built = buildKitchen(level);
      const kinds = new Set<string>();
      for (const row of built.grid) for (const t of row) kinds.add(t.kind);
      expect(kinds.has('plates')).toBe(true);
      expect(kinds.has('serve')).toBe(true);
      expect(kinds.has('trash')).toBe(true);
      expect(kinds.has('board') || kinds.has('stove')).toBe(true);
    }
  });
});
