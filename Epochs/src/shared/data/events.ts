// The event deck (SPEC §11 / docs/AUTHENTIC-RULES §12). Interim simplified shape
// (greater + lesser) pending the full 9-colour-pile rebuild (task #29). Greater:
// Leader (3 dice) / Weaponry (+1/die) / Fanaticism (win ties) / Reallocation &
// Minor Empire (bonus armies). Lesser: the targeted DISASTERS (aimed at an enemy
// Land before a turn). Our own flavor names; the effects are the (uncopyrightable)
// game mechanics.

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
const FANATICISM = ['Fanaticism', 'Holy War', 'Zealotry', 'Martyrdom']
const REALLOCATION = ['Mobilization', 'Mass Levy', 'Conscription', 'Grand Army']
const MINOR_EMPIRE = ['Allied Tribes', 'Mercenary Host', 'Client Kingdom', 'Vassal State']

// Targeted disasters (Lesser, aimed at an enemy Land before a turn): [name, effect, count].
const DISASTERS: Array<[string, EventEffect, number]> = [
  ['Great Flood', { kind: 'disaster_structure', terrain: 'coastal' }, 2],
  ['Volcano', { kind: 'disaster_structure', terrain: 'mountain' }, 4],
  ['Great Fire', { kind: 'disaster_structure', terrain: 'any' }, 6],
  ['Plague', { kind: 'plague' }, 6],
]

export function makeEventDeck(): { greater: EventCard[]; lesser: EventCard[] } {
  const greater: EventCard[] = []
  LEADERS.forEach((n, i) => greater.push(card(`g_leader_${i}`, 'greater', n, { kind: 'leader' })))
  WEAPONRY.forEach((n, i) => greater.push(card(`g_weapon_${i}`, 'greater', n, { kind: 'weaponry' })))
  FANATICISM.forEach((n, i) => greater.push(card(`g_fanatic_${i}`, 'greater', n, { kind: 'fanaticism' })))
  REALLOCATION.forEach((n, i) =>
    greater.push(card(`g_realloc_${i}`, 'greater', n, { kind: 'reallocation', armies: 3 })),
  )
  MINOR_EMPIRE.forEach((n, i) =>
    greater.push(card(`g_minor_${i}`, 'greater', n, { kind: 'minor_empire', armies: 4 })),
  )
  const lesser: EventCard[] = []
  let di = 0
  for (const [name, effect, count] of DISASTERS) {
    for (let k = 0; k < count; k++) lesser.push(card(`l_dis_${di++}`, 'lesser', name, effect))
  }
  return { greater, lesser }
}
