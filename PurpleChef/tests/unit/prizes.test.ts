import { describe, expect, it } from 'vitest';
import { EMPTY_SAVE, TROPHIES, evaluatePrizes, foldResult } from '../../src/shared/prizes';
import type { MatchResult, SaveData } from '../../src/shared/types';

function result(over: Partial<MatchResult> = {}): MatchResult {
  return {
    at: '2026-06-11T10:00:00.000Z',
    levelId: 'salad-days',
    difficulty: 'novice',
    playerScore: 100,
    aiScore: 50,
    won: true,
    tied: false,
    stars: 2,
    served: 6,
    missed: 1,
    maxCombo: 2,
    bestServeFrac: 0.5,
    ...over
  };
}

describe('prizes', () => {
  it('first match earns Order Up!, Rookie Rosette and Bronze Whisk', () => {
    const save = foldResult(EMPTY_SAVE, result());
    expect(save.trophies['first-dish']).toBeTruthy();
    expect(save.trophies['first-win']).toBeTruthy();
    expect(save.trophies['bronze-whisk']).toBeTruthy();
    expect(save.trophies['silver-spatula']).toBeUndefined();
  });

  it('trophies are never re-awarded', () => {
    const s1 = foldResult(EMPTY_SAVE, result());
    const s2Result = result({ at: '2026-06-12T10:00:00.000Z' });
    const newly = evaluatePrizes(s2Result, { ...foldResult(s1, s2Result), trophies: s1.trophies });
    expect(newly.map((t) => t.id)).not.toContain('first-win');
  });

  it('totals fold correctly and losses reset the streak', () => {
    let save: SaveData = EMPTY_SAVE;
    save = foldResult(save, result());
    save = foldResult(save, result({ won: false, aiScore: 999 }));
    save = foldResult(save, result());
    expect(save.totals.matchesPlayed).toBe(3);
    expect(save.totals.wins).toBe(2);
    expect(save.totals.winStreak).toBe(1);
    expect(save.totals.dishesServed).toBe(18);
  });

  it('hat trick requires three consecutive wins', () => {
    let save: SaveData = EMPTY_SAVE;
    save = foldResult(save, result());
    save = foldResult(save, result());
    expect(save.trophies['hat-trick']).toBeUndefined();
    save = foldResult(save, result());
    expect(save.trophies['hat-trick']).toBeTruthy();
  });

  it('grand slam needs master wins on all three kitchens', () => {
    let save: SaveData = EMPTY_SAVE;
    save = foldResult(save, result({ difficulty: 'master', levelId: 'salad-days' }));
    save = foldResult(save, result({ difficulty: 'master', levelId: 'soups-on' }));
    expect(save.trophies['grand-slam']).toBeUndefined();
    save = foldResult(save, result({ difficulty: 'master', levelId: 'burger-blitz' }));
    expect(save.trophies['grand-slam']).toBeTruthy();
  });

  it('lightning ladle and spotless service trigger on their stats', () => {
    const save = foldResult(EMPTY_SAVE, result({ bestServeFrac: 0.95, missed: 0, served: 5 }));
    expect(save.trophies['lightning-ladle']).toBeTruthy();
    expect(save.trophies['perfect-service']).toBeTruthy();
  });

  it('every trophy id is unique', () => {
    const ids = TROPHIES.map((t) => t.id);
    expect(new Set(ids).size).toBe(ids.length);
  });
});
