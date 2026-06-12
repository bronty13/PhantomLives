import { describe, expect, it } from 'vitest';
import { LEVELS } from '../../src/shared/levels';
import { createMatch, matchResult, tickMatch } from '../../src/shared/match';
import type { SimInput } from '../../src/shared/types';

const IDLE: SimInput = { mx: 0, my: 0, interact: false };

/** Run a whole match headless with an idle player; the AI plays for real. */
function runMatch(levelId: string, difficulty: 'novice' | 'chef' | 'master', seed: number) {
  const m = createMatch(levelId, difficulty, seed);
  let guard = 0;
  while (tickMatch(m, 50, IDLE) && guard++ < 100_000) {
    m.player.events.length = 0; // headless: nobody drains events
    m.ai.events.length = 0;
  }
  return m;
}

describe('match: the AI chef actually cooks', () => {
  it.each(LEVELS.map((l) => l.id))('AI serves dishes and scores in %s (chef difficulty)', (levelId) => {
    const m = runMatch(levelId, 'chef', 424242);
    expect(m.over).toBe(true);
    expect(m.ai.served).toBeGreaterThanOrEqual(2);
    expect(m.ai.score).toBeGreaterThan(0);
  });

  it('harder tiers field a busier AI (more dishes served)', () => {
    const novice = runMatch('salad-days', 'novice', 777);
    const chef = runMatch('salad-days', 'chef', 777);
    const master = runMatch('salad-days', 'master', 777);
    expect(chef.ai.served).toBeGreaterThan(novice.ai.served);
    expect(master.ai.served).toBeGreaterThan(chef.ai.served);
  });

  it('both kitchens receive the identical order schedule', () => {
    const m = createMatch('soups-on', 'chef', 31337);
    expect(m.player.schedule).toEqual(m.ai.schedule);
  });

  it('an idle player loses to the AI', () => {
    const m = runMatch('salad-days', 'novice', 9);
    const r = matchResult(m, '2026-06-11T00:00:00.000Z');
    expect(r.won).toBe(false);
    expect(r.playerScore).toBe(0);
    expect(r.aiScore).toBeGreaterThan(0);
  });

  it('matchResult snapshots scores and metadata', () => {
    const m = runMatch('salad-days', 'chef', 5150);
    const r = matchResult(m, '2026-06-11T12:00:00.000Z');
    expect(r.levelId).toBe('salad-days');
    expect(r.difficulty).toBe('chef');
    expect(r.aiScore).toBe(m.ai.score);
    expect(r.stars).toBeGreaterThanOrEqual(0);
    expect(r.stars).toBeLessThanOrEqual(3);
  });
});
