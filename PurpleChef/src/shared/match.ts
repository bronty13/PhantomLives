/**
 * @file match.ts — orchestrates one player-vs-AI round: two identical
 * kitchens fed the same order schedule, one clock, one winner.
 */
import { aiStep, createBrain, type AIBrain } from './ai';
import { getDifficulty, type DifficultyDef } from './difficulty';
import { starThresholds, starsForScore } from './orders';
import { createKitchen, tick, type KitchenStateWithBest } from './sim';
import type { DifficultyId, KitchenState, MatchResult, SimInput } from './types';

export interface Match {
  levelId: string;
  difficulty: DifficultyId;
  diff: DifficultyDef;
  player: KitchenState;
  ai: KitchenState;
  brain: AIBrain;
  durationMs: number;
  timeLeftMs: number;
  thresholds: [number, number, number];
  over: boolean;
}

export function createMatch(levelId: string, difficulty: DifficultyId, seed: number): Match {
  const diff = getDifficulty(difficulty);
  const player = createKitchen(levelId, difficulty, seed);
  const ai = createKitchen(levelId, difficulty, seed);
  return {
    levelId,
    difficulty,
    diff,
    player,
    ai,
    brain: createBrain(),
    durationMs: diff.durationMs,
    timeLeftMs: diff.durationMs,
    thresholds: starThresholds(player.schedule, difficulty),
    over: false
  };
}

/** Advance both kitchens. Returns true while the match is still running. */
export function tickMatch(m: Match, dtMs: number, playerInput: SimInput): boolean {
  if (m.over) return false;
  const step = Math.min(dtMs, m.timeLeftMs);

  tick(m.player, step, playerInput, m.diff.sim);

  const servedBefore = m.ai.served;
  const aiInput = aiStep(m.ai, m.brain, step, m.diff);
  // The AI moves on the same legs as the player; its handicap is reaction
  // time + speed, applied here by scaling its movement vector.
  const scaled: SimInput = {
    mx: aiInput.mx * m.diff.aiSpeedMult,
    my: aiInput.my * m.diff.aiSpeedMult,
    interact: aiInput.interact
  };
  tick(m.ai, step, scaled, m.diff.sim);
  if (m.ai.served > servedBefore) {
    m.brain.idleMs += m.diff.aiIdleAfterDishMs; // a satisfied breather
  }

  m.timeLeftMs -= step;
  if (m.timeLeftMs <= 0) {
    m.timeLeftMs = 0;
    m.over = true;
  }
  return !m.over;
}

/** Snapshot the final result (caller stamps the date). */
export function matchResult(m: Match, atIso: string): MatchResult {
  const p = m.player;
  const stars = starsForScore(p.score, m.thresholds);
  return {
    at: atIso,
    levelId: m.levelId,
    difficulty: m.difficulty,
    playerScore: p.score,
    aiScore: m.ai.score,
    won: p.score > m.ai.score,
    tied: p.score === m.ai.score,
    stars,
    served: p.served,
    missed: p.missed,
    maxCombo: p.maxCombo,
    bestServeFrac: (p as KitchenStateWithBest).bestServeFrac ?? 0
  };
}
