// The event deck (SPEC §11 / docs/AUTHENTIC-RULES §12). Interim simplified shape
// (greater + lesser) pending the full 9-colour-pile rebuild (task #29). Greater:
// Leader (3 dice) / Weaponry (+1/die) / Fanaticism (win ties) / Reallocation &
// Minor Empire (bonus armies). Lesser: the targeted DISASTERS (aimed at an enemy
// Land before a turn). Our own flavor names; the effects are the (uncopyrightable)
// game mechanics.

import type { EventCard, EventEffect } from '../types'

/** Plain-English card text (our own wording of the mechanics) + when it's played:
 *  'during' = during your turn (combat buffs); 'before' = before your turn, aimed
 *  at an enemy Land (disasters). Drives the event panel + tooltips. */
export function describeEffect(e: EventEffect): { text: string; timing: 'during' | 'before' } {
  switch (e.kind) {
    case 'leader':
      return { text: 'Your attacking armies roll 3 dice (keep the highest) for the rest of this turn.', timing: 'during' }
    case 'weaponry':
      return { text: 'Add +1 to each of your attack dice for the rest of this turn.', timing: 'during' }
    case 'fanaticism':
      return { text: 'Your empire wins every tied combat roll while attacking this turn.', timing: 'during' }
    case 'reallocation':
      return { text: `Call up the fleets — raise ${e.armies} extra ground armies this turn.`, timing: 'during' }
    case 'minor_empire':
      return { text: `A minor people rallies to you — ${e.armies} extra armies this turn.`, timing: 'during' }
    case 'siegecraft':
      return { text: 'Enemy forts give no defence against your attacks this turn.', timing: 'during' }
    case 'surprise_attack':
      return { text: 'Your attacks ignore difficult-terrain and amphibious defence this turn.', timing: 'during' }
    case 'extra_armies':
      return {
        text: e.needsCapital
          ? `Your capital's administration raises ${e.armies} extra armies this turn.`
          : `A surge of settlers — ${e.armies} extra armies this turn.`,
        timing: 'during',
      }
    case 'disaster_structure': {
      const where = e.terrain === 'coastal' ? 'a coastal enemy land' : e.terrain === 'mountain' ? 'a mountain enemy land' : 'any enemy land'
      return { text: `Strike ${where}: raze its city, fort, or monument (a capital is reduced to a city).`, timing: 'before' }
    }
    case 'plague':
      return { text: 'Strike an enemy land: its army rolls 4 dice — a single 1 wipes it out.', timing: 'before' }
    case 'pestilence':
      return { text: 'Strike an enemy land (3 dice) — and it spreads: each adjacent enemy army rolls 2. A 1 kills.', timing: 'before' }
    case 'famine':
      return { text: "Strike an enemy region: every army in that whole Area rolls 2 dice — each 1 starves.", timing: 'before' }
  }
}

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
const SIEGECRAFT = ['Siegecraft', 'Sapper Corps', 'Siege Towers']
const SURPRISE = ['Surprise Attack', 'Ambush', 'Forced March']
const POP_EXPLOSION = ['Population Boom', 'Fertile Years', 'Settlers']
const CIVIL_SERVICE = ['Civil Service', 'Bureaucracy', 'Imperial Administration']

// Targeted disasters (Lesser, aimed at an enemy Land before a turn): [name, effect, count].
const DISASTERS: Array<[string, EventEffect, number]> = [
  ['Great Flood', { kind: 'disaster_structure', terrain: 'coastal' }, 2],
  ['Volcano', { kind: 'disaster_structure', terrain: 'mountain' }, 4],
  ['Great Fire', { kind: 'disaster_structure', terrain: 'any' }, 6],
  ['Plague', { kind: 'plague' }, 6],
  ['Pestilence', { kind: 'pestilence' }, 4],
  ['Famine', { kind: 'famine' }, 4],
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
  SIEGECRAFT.forEach((n, i) => greater.push(card(`g_siege_${i}`, 'greater', n, { kind: 'siegecraft' })))
  SURPRISE.forEach((n, i) => greater.push(card(`g_surprise_${i}`, 'greater', n, { kind: 'surprise_attack' })))
  POP_EXPLOSION.forEach((n, i) =>
    greater.push(card(`g_pop_${i}`, 'greater', n, { kind: 'extra_armies', armies: 2, needsCapital: false })),
  )
  CIVIL_SERVICE.forEach((n, i) =>
    greater.push(card(`g_civil_${i}`, 'greater', n, { kind: 'extra_armies', armies: 2, needsCapital: true })),
  )
  const lesser: EventCard[] = []
  let di = 0
  for (const [name, effect, count] of DISASTERS) {
    for (let k = 0; k < count; k++) lesser.push(card(`l_dis_${di++}`, 'lesser', name, effect))
  }
  return { greater, lesser }
}
