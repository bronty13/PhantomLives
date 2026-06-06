import { describe, expect, it } from 'vitest';
import {
  easeOutCubic,
  landedIndex,
  pickWinner,
  sectorCrossings,
  sectorStep,
  targetAngle,
  TAU,
} from '../src/wheel-player/spinMath';
import type { WheelChoice } from '../src/shared/model';

const ch = (text: string, weight = 1): WheelChoice => ({ id: text, text, weight });

describe('pickWinner', () => {
  it('is uniform-capable and stays in range', () => {
    const choices = [ch('a'), ch('b'), ch('c')];
    for (const r of [0, 0.34, 0.66, 0.999]) {
      const i = pickWinner(choices, () => r);
      expect(i).toBeGreaterThanOrEqual(0);
      expect(i).toBeLessThan(3);
    }
  });

  it('never lands on a weight-0 choice', () => {
    const choices = [ch('never', 0), ch('always', 5), ch('never2', 0)];
    for (let k = 0; k < 50; k++) {
      const i = pickWinner(choices, () => k / 50);
      expect(i).toBe(1);
    }
  });

  it('respects relative weights', () => {
    // 'big' has weight 9, 'small' weight 1 → r in [0,0.9) picks big.
    const choices = [ch('big', 9), ch('small', 1)];
    expect(pickWinner(choices, () => 0.5)).toBe(0);
    expect(pickWinner(choices, () => 0.95)).toBe(1);
  });

  it('falls back to uniform when all weights are non-positive', () => {
    const choices = [ch('a', 0), ch('b', 0)];
    expect(pickWinner(choices, () => 0.1)).toBe(0);
    expect(pickWinner(choices, () => 0.9)).toBe(1);
  });
});

describe('targetAngle / landedIndex', () => {
  it('round-trips: the target angle lands on the chosen sector', () => {
    for (const n of [1, 2, 5, 12, 30]) {
      for (let i = 0; i < n; i++) {
        const angle = targetAngle(i, n, 5);
        expect(landedIndex(angle, n)).toBe(i);
      }
    }
  });

  it('includes the requested full turns', () => {
    const angle = targetAngle(0, 8, 6);
    expect(angle).toBeGreaterThanOrEqual(6 * TAU);
    expect(angle).toBeLessThan(7 * TAU);
  });
});

describe('sectorCrossings', () => {
  it('counts boundaries swept on an increasing rotation', () => {
    const n = 4; // step = TAU/4
    const step = sectorStep(n);
    expect(sectorCrossings(0, step * 0.5, n)).toBe(0);
    expect(sectorCrossings(0, step * 1.5, n)).toBe(1);
    expect(sectorCrossings(step * 0.5, step * 3.5, n)).toBe(3);
  });
  it('returns 0 when rotation does not advance', () => {
    expect(sectorCrossings(5, 5, 6)).toBe(0);
    expect(sectorCrossings(5, 4, 6)).toBe(0);
  });
});

describe('easeOutCubic', () => {
  it('maps endpoints and decelerates', () => {
    expect(easeOutCubic(0)).toBeCloseTo(0);
    expect(easeOutCubic(1)).toBeCloseTo(1);
    expect(easeOutCubic(0.5)).toBeGreaterThan(0.5); // past halfway early (ease-out)
  });
});
