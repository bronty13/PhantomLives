// Pure spin physics — no DOM, deterministic given an injected `rnd`. The wheel
// component decides the winner FIRST, then animates to the angle that lands it
// under the fixed top pointer. Canvas drawing uses the same convention: sector i
// spans local angle [i·step, (i+1)·step) measured clockwise from the top (12
// o'clock), the pointer sits at the top, and `rotation` is applied clockwise.

import type { WheelChoice } from '../shared/model';

export const TAU = Math.PI * 2;

/** Angular width of one sector, in radians. */
export function sectorStep(n: number): number {
  return n > 0 ? TAU / n : TAU;
}

/**
 * Weighted random winner index. `weight` 0 (or negative) can never win. If every
 * weight is non-positive the wheel falls back to uniform odds so it never jams.
 * `rnd` returns [0, 1); inject `Math.random` in the app, a seed in tests.
 */
export function pickWinner(choices: readonly WheelChoice[], rnd: () => number): number {
  const n = choices.length;
  if (n === 0) return 0;
  const total = choices.reduce((sum, c) => sum + Math.max(0, c.weight), 0);
  if (total <= 0) return Math.min(n - 1, Math.floor(rnd() * n));
  let r = rnd() * total;
  for (let i = 0; i < n; i++) {
    r -= Math.max(0, choices[i].weight);
    if (r < 0) return i;
  }
  return n - 1; // floating-point guard
}

/**
 * Clockwise rotation (radians) that brings sector `index`'s center under the top
 * pointer, plus `turns` full revolutions for the spin. Always positive/forward.
 */
export function targetAngle(index: number, n: number, turns: number): number {
  const step = sectorStep(n);
  const base = (TAU - ((index + 0.5) * step) % TAU + TAU) % TAU;
  return turns * TAU + base;
}

/** Which sector sits under the top pointer at a given rotation (inverse of targetAngle). */
export function landedIndex(rotation: number, n: number): number {
  const step = sectorStep(n);
  const pointerLocal = ((-rotation) % TAU + TAU) % TAU;
  return Math.min(n - 1, Math.floor(pointerLocal / step));
}

/**
 * How many sector boundaries swept past the pointer between two (increasing)
 * rotations — drives the tick sounds. Rotation only grows during a spin.
 */
export function sectorCrossings(prevRotation: number, rotation: number, n: number): number {
  const step = sectorStep(n);
  if (rotation <= prevRotation) return 0;
  return Math.floor(rotation / step) - Math.floor(prevRotation / step);
}

/** Ease-out cubic — fast start, gentle deceleration to the resting angle. */
export function easeOutCubic(t: number): number {
  const u = 1 - t;
  return 1 - u * u * u;
}
