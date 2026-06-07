// Helpers over the generated sayings catalog (sayings-data.ts). Sayings are
// selected at random (with reroll); there is no manual browse picker.

import type { FillerEntry } from '../model/types';
import { SAYINGS } from './sayings-data';

export { SAYINGS };

export function getRandomSaying(rand: () => number = Math.random): FillerEntry {
  if (SAYINGS.length === 0) {
    return { id: 'saying-empty', kind: 'saying', text: '' };
  }
  return SAYINGS[Math.floor(rand() * SAYINGS.length)];
}

/** A different random saying than `excludeId` when possible (for reroll). */
export function rerollSaying(excludeId: string | undefined, rand: () => number = Math.random): FillerEntry {
  if (SAYINGS.length <= 1) return getRandomSaying(rand);
  let pick = getRandomSaying(rand);
  let guard = 0;
  while (pick.id === excludeId && guard++ < 8) pick = getRandomSaying(rand);
  return pick;
}
