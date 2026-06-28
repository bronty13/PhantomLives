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
      return { text: "Summon this epoch's Minor Empire — a second dynasty that builds and expands for you before your main turn (and scores).", timing: 'during' }
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
    case 'found_kingdom':
      return { text: 'A vassal kingdom rises — raise a fortified city (city + fort) on one of your lands after you expand.', timing: 'during' }
    case 'ship_building':
      return { text: 'Launch a fleet — your empire may sail EVERY sea this turn, reaching any coast in the world.', timing: 'during' }
    case 'naval_supremacy':
      return { text: 'Rule the waves — sail every sea this turn, and your sea-borne landings ignore terrain and amphibious defence.', timing: 'during' }
    case 'barbarians':
      return { text: 'Barbarians pour from the wastes onto an enemy land bordering a barren region — raze its structure and its army rolls 3 dice (a 1 routs it).', timing: 'before' }
    case 'pirates':
      return { text: 'Corsairs raid a coastal enemy land — pillage its structure and its army rolls 2 dice (a 1 routs it).', timing: 'before' }
    case 'storm_at_sea':
      return { text: "A storm batters a coastal enemy land — its army rolls 4 dice; a single 1 wrecks it.", timing: 'before' }
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
const SURPRISE = ['Surprise Attack', 'Ambush', 'Forced March', 'Night Raid']
const POP_EXPLOSION = ['Population Boom', 'Fertile Years', 'Settlers', 'Good Harvest']
const CIVIL_SERVICE = ['Civil Service', 'Bureaucracy', 'Imperial Administration']
const KINGDOMS = ['Rising Kingdom', 'Vassal Realm', 'Petty Kingdom']
const SHIP_BUILDING = ['Ship Building', 'Shipyards', 'Naval Yards']
const NAVAL_SUPREMACY = ['Naval Supremacy', 'Command of the Sea', 'Thalassocracy']

/**
 * The event deck as **9 colour-piles of 7 cards** (SPEC §11 / original): seven boon
 * piles (Greater) and two disaster piles (Lesser). At setup one card is dealt from
 * EACH pile to every player, so a hand is one card of each of the nine kinds. Names
 * are our own flavour; the effects are the (uncopyrightable) mechanics.
 */
export function makeEventDeck(): EventCard[][] {
  let id = 0
  const g = (name: string, effect: EventEffect): EventCard => card(`e${id++}`, 'greater', name, effect)
  const l = (name: string, effect: EventEffect): EventCard => card(`e${id++}`, 'lesser', name, effect)
  const n = (count: number, name: string, effect: EventEffect, mk: typeof g): EventCard[] =>
    Array.from({ length: count }, () => mk(name, effect))

  return [
    // ── seven Greater (boon) piles ──
    LEADERS.slice(0, 7).map((name) => g(name, { kind: 'leader' })),
    WEAPONRY.map((name) => g(name, { kind: 'weaponry' })),
    [
      ...FANATICISM.map((name) => g(name, { kind: 'fanaticism' })),
      ...SIEGECRAFT.map((name) => g(name, { kind: 'siegecraft' })),
    ], // Holy War
    [
      ...SURPRISE.map((name) => g(name, { kind: 'surprise_attack' })),
      ...NAVAL_SUPREMACY.map((name) => g(name, { kind: 'naval_supremacy' })),
    ], // Cunning
    [
      ...SHIP_BUILDING.map((name) => g(name, { kind: 'ship_building' })),
      ...REALLOCATION.map((name) => g(name, { kind: 'reallocation', armies: 3 })),
    ], // Seafaring
    [
      ...POP_EXPLOSION.map((name) => g(name, { kind: 'extra_armies', armies: 2, needsCapital: false })),
      ...KINGDOMS.map((name) => g(name, { kind: 'found_kingdom' })),
    ], // Migration
    [
      ...CIVIL_SERVICE.map((name) => g(name, { kind: 'extra_armies', armies: 2, needsCapital: true })),
      ...MINOR_EMPIRE.map((name) => g(name, { kind: 'minor_empire' })),
    ], // Statecraft
    // ── two Lesser (disaster) piles ──
    [
      ...n(2, 'Great Flood', { kind: 'disaster_structure', terrain: 'coastal' }, l),
      ...n(2, 'Volcano', { kind: 'disaster_structure', terrain: 'mountain' }, l),
      ...n(3, 'Great Fire', { kind: 'disaster_structure', terrain: 'any' }, l),
    ], // Cataclysm
    [
      ...n(2, 'Plague', { kind: 'plague' }, l),
      l('Pestilence', { kind: 'pestilence' }),
      l('Famine', { kind: 'famine' }),
      l('Barbarians', { kind: 'barbarians' }),
      l('Pirates', { kind: 'pirates' }),
      l('Storm at Sea', { kind: 'storm_at_sea' }),
    ], // Pestilence
  ]
}
