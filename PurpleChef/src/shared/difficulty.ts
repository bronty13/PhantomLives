/**
 * @file difficulty.ts — the three skill tiers and everything they tune.
 */
import type { DifficultyId, SimConfig } from './types';

export interface DifficultyDef {
  id: DifficultyId;
  label: string;
  blurb: string;
  durationMs: number;
  /** Average ms between order spawns at minute 0. */
  orderIntervalMs: number;
  /** Interval multiplier applied per elapsed minute (orders speed up). */
  intervalRampPerMin: number;
  /** Floor on the ramped interval, as a fraction of the base. */
  intervalFloorFrac: number;
  patienceMs: number;
  /** Which recipe weight column to use when rolling orders. */
  recipeBias: 'simple' | 'balanced' | 'hard';
  // ----- AI chef -----
  aiSpeedMult: number; // vs player speed
  aiThinkMs: number; // reaction delay between decisions
  aiIdleAfterDishMs: number; // breather after serving a dish
  aiServesInOrder: boolean; // protects its combo like a pro
  // ----- kitchen physics -----
  sim: SimConfig;
}

const BASE_SIM: Omit<SimConfig, 'burnMs'> = {
  chefSpeed: 3.4,
  chopMs: 1500,
  cookMs: 6000,
  tipMax: 12,
  missPenalty: 10,
  comboMax: 4,
  plateCapacity: 5
};

export const DIFFICULTIES: Record<DifficultyId, DifficultyDef> = {
  novice: {
    id: 'novice',
    label: 'Novice',
    blurb: 'A gentle simmer. Patient customers, a sleepy rival chef.',
    durationMs: 180_000,
    orderIntervalMs: 21_000,
    intervalRampPerMin: 0.92,
    intervalFloorFrac: 0.7,
    patienceMs: 95_000,
    recipeBias: 'simple',
    aiSpeedMult: 0.45,
    aiThinkMs: 2400,
    aiIdleAfterDishMs: 7000,
    aiServesInOrder: false,
    sim: { ...BASE_SIM, burnMs: 12_000 }
  },
  chef: {
    id: 'chef',
    label: 'Chef',
    blurb: 'A steady boil. Brisk orders and a rival who means business.',
    durationMs: 180_000,
    orderIntervalMs: 15_000,
    intervalRampPerMin: 0.88,
    intervalFloorFrac: 0.6,
    patienceMs: 75_000,
    recipeBias: 'balanced',
    aiSpeedMult: 0.72,
    aiThinkMs: 900,
    aiIdleAfterDishMs: 2000,
    aiServesInOrder: true,
    sim: { ...BASE_SIM, burnMs: 9000 }
  },
  master: {
    id: 'master',
    label: 'Master',
    blurb: 'A roaring flame. Relentless tickets and a machine of a rival.',
    durationMs: 180_000,
    orderIntervalMs: 11_000,
    intervalRampPerMin: 0.85,
    intervalFloorFrac: 0.55,
    patienceMs: 60_000,
    recipeBias: 'hard',
    aiSpeedMult: 0.92,
    aiThinkMs: 350,
    aiIdleAfterDishMs: 250,
    aiServesInOrder: true,
    sim: { ...BASE_SIM, burnMs: 7000 }
  }
};

export function getDifficulty(id: DifficultyId): DifficultyDef {
  return DIFFICULTIES[id];
}
