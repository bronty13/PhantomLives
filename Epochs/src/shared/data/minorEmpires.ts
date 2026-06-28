// The 7 Minor Empires (SPEC §11 / docs/AUTHENTIC-RULES §12) — one per Epoch. Playing
// the Minor-Empire event summons that epoch's minor people: a SECOND empire-turn
// (build + expand its own small dynasty) that scores for you. Shaped as EmpireCards
// so the engine reuses setupEmpire/expandGen. Stats are game facts (our own data);
// navigation is land-only here (seas/fleets not modelled yet).
import type { EmpireCard, EpochId } from '../types'

const minor = (epoch: EpochId, name: string, strength: number, startLand: string, hasCapital: boolean): EmpireCard => ({
  id: `m${epoch}_${name.toLowerCase().replace(/[^a-z]/g, '_')}`,
  name,
  epoch,
  order: 0, // minor empires draft before the main turn; order is informational
  strength,
  startLand,
  navigation: { seas: [] },
  hasCapital,
})

export const MINOR_EMPIRES: Record<EpochId, EmpireCard> = {
  1: minor(1, 'Hittites', 3, 'eastern_anatolia', true),
  2: minor(2, 'Phoenicia', 3, 'levant', true),
  3: minor(3, 'Mayans', 2, 'mexican_valley', true),
  4: minor(4, 'Anglo-Saxons', 3, 'baltic_seaboard', false),
  5: minor(5, 'Fujiwara', 3, 'honshu', true),
  6: minor(6, 'Safavids', 3, 'persian_plateau', true),
  7: minor(7, 'Japan', 5, 'honshu', true),
}
