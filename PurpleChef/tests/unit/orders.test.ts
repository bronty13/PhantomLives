import { describe, expect, it } from 'vitest';
import { buildOrderSchedule, starThresholds, starsForScore } from '../../src/shared/orders';
import { getLevel } from '../../src/shared/levels';

const RECIPES = getLevel('salad-days').recipeIds;

describe('orders', () => {
  it('same seed → identical schedule (fair race)', () => {
    const a = buildOrderSchedule(RECIPES, 'chef', 1234);
    const b = buildOrderSchedule(RECIPES, 'chef', 1234);
    expect(a).toEqual(b);
    expect(a.length).toBeGreaterThan(3);
  });

  it('different seeds → different schedules', () => {
    const a = buildOrderSchedule(RECIPES, 'chef', 1);
    const b = buildOrderSchedule(RECIPES, 'chef', 2);
    expect(JSON.stringify(a)).not.toBe(JSON.stringify(b));
  });

  it('harder difficulties yield more orders', () => {
    const novice = buildOrderSchedule(RECIPES, 'novice', 7);
    const master = buildOrderSchedule(RECIPES, 'master', 7);
    expect(master.length).toBeGreaterThan(novice.length);
  });

  it('schedules only contain known recipes within the round', () => {
    for (const s of buildOrderSchedule(RECIPES, 'master', 99)) {
      expect(RECIPES).toContain(s.recipeId);
      expect(s.atMs).toBeGreaterThan(0);
      expect(s.patienceMs).toBeGreaterThan(0);
    }
  });

  it('star thresholds are ascending and stars map correctly', () => {
    const sched = buildOrderSchedule(RECIPES, 'chef', 5);
    const [s1, s2, s3] = starThresholds(sched, 'chef');
    expect(s1).toBeLessThan(s2);
    expect(s2).toBeLessThan(s3);
    expect(starsForScore(0, [s1, s2, s3])).toBe(0);
    expect(starsForScore(s1, [s1, s2, s3])).toBe(1);
    expect(starsForScore(s2, [s1, s2, s3])).toBe(2);
    expect(starsForScore(s3 + 50, [s1, s2, s3])).toBe(3);
  });
});
