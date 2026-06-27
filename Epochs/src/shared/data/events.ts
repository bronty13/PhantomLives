// The event deck (SPEC §11 / docs/AUTHENTIC-RULES §12). Greater Events kept for
// now: Leaders & Weaponry (attacker +1 die), Reallocation & Minor Empire (bonus
// armies). The Lesser deck is EMPTY pending the authentic 9-colour-pile rebuild
// (task #29) — the old "Coins" Lesser deck was a wrong-edition mechanic (the AH
// 1993 game has no coins). Our own flavor names; the effects are the
// (uncopyrightable) game mechanics.

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
  // Lesser deck is rebuilt in the authentic 9-pile event system (task #29).
  return { greater, lesser: [] }
}
