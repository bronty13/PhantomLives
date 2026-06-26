// A small, deterministic fixture empire deck (4 empires per epoch, start lands
// among the fixture map) so the game loop can run BEFORE the real 49-empire
// roster is transcribed (SPEC §14). NOT real History-of-the-World data — clearly
// synthetic placeholders. No RNG: the deck is identical every run.

import type { EmpireCard } from '../types'
import { EPOCHS } from '../types'

const START_LANDS = [
  'mesopotamia',
  'egypt',
  'greece',
  'anatolia',
  'levant',
  'carthage',
  'persia',
  'libya',
  'italy',
]

const EMPIRES_PER_EPOCH = 4

export function makeFixtureEmpires(): EmpireCard[] {
  const out: EmpireCard[] = []
  for (const epoch of EPOCHS) {
    for (let order = 1; order <= EMPIRES_PER_EPOCH; order++) {
      const idx = ((epoch - 1) * EMPIRES_PER_EPOCH + (order - 1)) % START_LANDS.length
      out.push({
        id: `e${epoch}_${order}`,
        name: `Empire ${epoch}.${order}`,
        epoch,
        order,
        // 3..7, varying by epoch+order so the draft has meaningful spread
        strength: 3 + ((epoch + order) % 5),
        startLand: START_LANDS[idx],
        navigation: order % 2 === 0 ? { all: true } : { seas: ['eastern_med'] },
        // one Marauder (no capital) per epoch, the highest-order empire
        hasCapital: order !== EMPIRES_PER_EPOCH,
      })
    }
  }
  return out
}

export const FIXTURE_EMPIRES: EmpireCard[] = makeFixtureEmpires()
