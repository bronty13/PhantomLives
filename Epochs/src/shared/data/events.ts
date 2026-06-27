// The event deck (SPEC §11). Greater Events: Leaders & Weaponry (attacker +1
// die), Reallocation & Minor Empire (bonus armies). Lesser Events: Coins (spent
// on forts). Counts cover up to 6 players × (3 Greater + 7 Lesser) = 18 + 42.
// Our own flavor names — the effects are the (uncopyrightable) game mechanics.

import type { EventCard, EventEffect } from '../types'

const card = (id: string, cls: 'greater' | 'lesser', name: string, effect: EventEffect): EventCard => ({
  id,
  class: cls,
  name,
  effect,
})

const LEADERS = [
  'Alexander', 'Caesar', 'Cyrus the Great', 'Hannibal', 'Charlemagne',
  'Genghis Khan', 'Saladin', 'Ashoka', 'Ramesses',
]
const WEAPONRY = [
  'Bronze Weapons', 'Iron Weapons', 'War Chariots', 'Heavy Cavalry',
  'Siege Engines', 'Longbowmen', 'Gunpowder',
]
const REALLOCATION = ['Mobilization', 'Mass Levy', 'Conscription', 'Grand Army']
const MINOR_EMPIRE = ['Allied Tribes', 'Mercenary Host', 'Client Kingdom', 'Vassal State']

// [flavor, coins, count] — totals 49 Lesser cards.
const LESSER: Array<[string, number, number]> = [
  ['Trade', 1, 16],
  ['Tribute', 2, 18],
  ['Treasury', 2, 6],
  ['Plunder', 3, 9],
]

export function makeEventDeck(): { greater: EventCard[]; lesser: EventCard[] } {
  const greater: EventCard[] = []
  LEADERS.forEach((n, i) => greater.push(card(`g_leader_${i}`, 'greater', n, { kind: 'leader' })))
  WEAPONRY.forEach((n, i) => greater.push(card(`g_weapon_${i}`, 'greater', n, { kind: 'weaponry' })))
  REALLOCATION.forEach((n, i) =>
    greater.push(card(`g_realloc_${i}`, 'greater', n, { kind: 'reallocation', armies: 3 })),
  )
  MINOR_EMPIRE.forEach((n, i) =>
    greater.push(card(`g_minor_${i}`, 'greater', n, { kind: 'minor_empire', armies: 4 })),
  )

  const lesser: EventCard[] = []
  let li = 0
  for (const [name, coins, count] of LESSER) {
    for (let k = 0; k < count; k++) {
      lesser.push(card(`l_${li++}`, 'lesser', `${name} (${coins})`, { kind: 'coins', coins }))
    }
  }
  return { greater, lesser }
}
