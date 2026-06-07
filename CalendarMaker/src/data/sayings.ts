// Helpers over the sayings catalog. The pool is the seeded sayings (sayings-data.ts)
// plus any the user added (stored in IndexedDB and passed in as `custom`). Sayings
// are selected at random (with reroll); there is no manual browse picker.

import type { FillerEntry } from '../model/types';
import { SAYINGS } from './sayings-data';

export { SAYINGS };

/** Combined random pool: seeded sayings + user-added custom ones. */
export function sayingPool(custom: FillerEntry[] = []): FillerEntry[] {
  return [...SAYINGS, ...custom];
}

export function getRandomSaying(pool: FillerEntry[] = SAYINGS, rand: () => number = Math.random): FillerEntry {
  if (pool.length === 0) {
    return { id: 'saying-empty', kind: 'saying', text: '' };
  }
  return pool[Math.floor(rand() * pool.length)];
}

/** A different random saying than `excludeId` when possible (for reroll). */
export function rerollSaying(pool: FillerEntry[] = SAYINGS, excludeId: string | undefined, rand: () => number = Math.random): FillerEntry {
  if (pool.length <= 1) return getRandomSaying(pool, rand);
  let pick = getRandomSaying(pool, rand);
  let guard = 0;
  while (pick.id === excludeId && guard++ < 8) pick = getRandomSaying(pool, rand);
  return pick;
}
