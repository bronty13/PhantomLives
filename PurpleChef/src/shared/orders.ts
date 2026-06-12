/**
 * @file orders.ts — deterministic order schedule + star thresholds.
 *
 * The whole schedule is generated up front from a seed so the player's and
 * the AI's kitchens receive *identical* ticket streams — a fair race.
 */
import { getDifficulty } from './difficulty';
import { getRecipe } from './recipes';
import { mulberry32, weightedPick } from './rng';
import type { DifficultyId, ScheduledOrder } from './types';

export function buildOrderSchedule(
  recipeIds: string[],
  difficulty: DifficultyId,
  seed: number
): ScheduledOrder[] {
  const diff = getDifficulty(difficulty);
  const rng = mulberry32(seed);
  const out: ScheduledOrder[] = [];
  const weights = recipeIds.map((id) => getRecipe(id).weight[diff.recipeBias]);

  // First ticket lands right away so there's no dead air at the whistle.
  let t = 1500;
  while (t < diff.durationMs - 15_000) {
    out.push({
      atMs: Math.round(t),
      recipeId: weightedPick(rng, recipeIds, weights),
      patienceMs: diff.patienceMs
    });
    const minutes = t / 60_000;
    const ramp = Math.max(diff.intervalFloorFrac, Math.pow(diff.intervalRampPerMin, minutes));
    const jitter = 0.75 + rng() * 0.5; // ±25%
    t += diff.orderIntervalMs * ramp * jitter;
  }
  return out;
}

/**
 * Score thresholds for 1/2/3 stars, derived from what the schedule is
 * actually worth so they auto-scale with level + difficulty.
 */
export function starThresholds(schedule: ScheduledOrder[], difficulty: DifficultyId): [number, number, number] {
  const diff = getDifficulty(difficulty);
  let potential = 0;
  for (const o of schedule) {
    // Assume an average serve banks the base plus about half the max tip.
    potential += getRecipe(o.recipeId).basePoints + diff.sim.tipMax / 2;
  }
  const round10 = (n: number): number => Math.max(10, Math.round(n / 10) * 10);
  return [round10(potential * 0.25), round10(potential * 0.45), round10(potential * 0.68)];
}

export function starsForScore(score: number, thresholds: [number, number, number]): 0 | 1 | 2 | 3 {
  if (score >= thresholds[2]) return 3;
  if (score >= thresholds[1]) return 2;
  if (score >= thresholds[0]) return 1;
  return 0;
}
