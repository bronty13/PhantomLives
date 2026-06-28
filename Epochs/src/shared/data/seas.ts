// Sea vs Ocean classification (the board's light-blue seas vs dark-blue oceans).
//   - OCEANS (open water): fleets of any number of players coexist, no naval combat,
//     and they score nothing.
//   - SEAS (enclosed/marginal): host naval combat (a fleet entering one with an enemy
//     fleet must fight), and score +1 to whoever controls one with a fleet.
// The five great oceans are oceans; everything else is a sea.
import type { SeaId } from '../types'

export const OCEANS: ReadonlySet<SeaId> = new Set<SeaId>([
  'atlantic',
  'pacific',
  'indian_ocean',
  'arctic_ocean',
  'southern_ocean',
])

export const isOcean = (sea: SeaId): boolean => OCEANS.has(sea)
