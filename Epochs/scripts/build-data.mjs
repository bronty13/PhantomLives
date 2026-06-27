// Generates src/shared/data/board.ts + empires.ts from scripts/world.source.json
// (the researched empire roster + world geography). Run: `node scripts/build-data.mjs`.
// The generated TS is committed; the engine never runs this script at build time.
// Re-run after editing world.source.json to retune the map.

import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const src = JSON.parse(readFileSync(join(root, 'scripts/world.source.json'), 'utf8'))
const coords = JSON.parse(readFileSync(join(root, 'scripts/coords.json'), 'utf8'))

const AREA_IDS = [
  'middle_east', 'north_africa', 'china', 'india', 'southern_europe',
  'northern_europe', 'southeast_asia', 'eurasia', 'north_america',
  'south_america', 'nippon', 'africa', 'australia',
]
const TERRAINS = new Set(['forest', 'mountain', 'strait', 'great_wall'])

const slug = (n) =>
  n.replace(/\(.*?\)/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '')
const list = (s) => (s || '').split(',').map((x) => x.trim()).filter(Boolean)

const warnings = []
const warn = (m) => warnings.push(m)

// ── nodes ──────────────────────────────────────────────────────────────────
const seas = new Set(src.geography.seas.map(slug))
const terrs = []
for (const area of src.geography.areas) {
  if (!AREA_IDS.includes(area.areaId)) warn(`unknown area id: ${area.areaId}`)
  for (const t of area.territories) {
    const id = slug(t.name)
    const terrain = list(t.terrain).map(slug).filter((x) => {
      if (!TERRAINS.has(x)) {
        warn(`territory ${id}: dropped unknown terrain "${x}"`)
        return false
      }
      return true
    })
    const seaBorders = list(t.seas).map(slug).filter((x) => {
      if (!seas.has(x)) {
        warn(`territory ${id}: sea "${x}" not in sea list`)
        return false
      }
      return true
    })
    const xy = coords[t.name]
    if (!xy) warn(`territory ${id}: no coordinates for "${t.name}"`)
    terrs.push({
      id,
      name: t.name,
      area: area.areaId,
      barren: !!t.barren,
      difficultTerrain: terrain,
      hasResource: !!t.resource,
      seaBorders,
      x: xy ? xy[0] : 0.5,
      y: xy ? xy[1] : 0.5,
      neighborsHint: t.neighborsHint || '',
    })
  }
}
const ids = new Set(terrs.map((t) => t.id))
const byId = Object.fromEntries(terrs.map((t) => [t.id, t]))

// ── symmetric land adjacency ────────────────────────────────────────────────
const adj = new Map(terrs.map((t) => [t.id, new Set()]))
for (const t of terrs) {
  for (const raw of list(t.neighborsHint)) {
    const nid = slug(raw)
    if (nid === t.id) continue
    if (!ids.has(nid)) {
      warn(`territory ${t.id}: unresolved neighbor "${raw}"`)
      continue
    }
    adj.get(t.id).add(nid)
    adj.get(nid).add(t.id) // symmetrize
  }
}
for (const t of terrs) t.borders = [...adj.get(t.id)].sort()

// ── connectivity check (land + sea, over non-barren) ────────────────────────
const full = new Map(terrs.map((t) => [t.id, new Set(adj.get(t.id))]))
const seaMembers = new Map()
for (const t of terrs) for (const s of t.seaBorders) {
  if (!seaMembers.has(s)) seaMembers.set(s, [])
  seaMembers.get(s).push(t.id)
}
for (const mem of seaMembers.values()) for (const a of mem) for (const b of mem) if (a !== b) full.get(a).add(b)
const nb = terrs.filter((t) => !t.barren).map((t) => t.id)
const nbSet = new Set(nb)
const seen = new Set()
let components = 0
for (const start of nb) {
  if (seen.has(start)) continue
  components++
  const stack = [start]
  seen.add(start)
  while (stack.length) {
    const c = stack.pop()
    for (const n of full.get(c)) if (nbSet.has(n) && !seen.has(n)) { seen.add(n); stack.push(n) }
  }
}
if (components !== 1) warn(`non-barren graph has ${components} components (want 1)`)

// ── empires ─────────────────────────────────────────────────────────────────
const empires = src.empires.map((e) => {
  const startLand = slug(e.homelandTerritory)
  if (!ids.has(startLand)) warn(`empire ${e.name}: start land "${e.homelandTerritory}" missing`)
  else if (byId[startLand].barren) warn(`empire ${e.name}: starts on BARREN land ${startLand}`)
  const navRaw = (e.navigationSeas || '').trim().toLowerCase()
  let navigation
  if (navRaw === 'all') navigation = { all: true }
  else if (navRaw === 'none' || navRaw === '') navigation = { seas: [] }
  else {
    const navSeas = list(e.navigationSeas).map(slug).filter((x) => {
      if (!seas.has(x)) { warn(`empire ${e.name}: nav sea "${x}" not in sea list`); return false }
      return true
    })
    navigation = { seas: navSeas }
  }
  return {
    id: `e${e.epoch}_${slug(e.name)}`,
    name: e.name,
    epoch: e.epoch,
    order: e.order,
    strength: e.strength,
    startLand,
    navigation,
    hasCapital: !!e.hasCapital,
  }
})

// ── emit ────────────────────────────────────────────────────────────────────
const j = (v) => JSON.stringify(v)
const navStr = (n) => (n.all ? '{ all: true }' : `{ seas: ${j(n.seas)} }`)

const boardTs = `// AUTO-GENERATED by scripts/build-data.mjs from scripts/world.source.json — DO NOT EDIT.
// An ORIGINAL real-geography world map (${terrs.length} territories across the 13 Areas) faithful
// to the History of the World framework. Geography & historical empires are facts;
// retune by editing world.source.json and re-running the generator.

import type { AreaDef, Land, LandId, MapData, SeaId } from '../types'
import { AREA_NAMES, valueByEpoch } from './areaValues'

export const WORLD_SEAS: SeaId[] = ${j([...seas].sort())}

export const WORLD_LANDS: Land[] = [
${terrs
  .map(
    (t) =>
      `  { id: ${j(t.id)}, name: ${j(t.name)}, area: ${j(t.area)}, barren: ${t.barren}, difficultTerrain: ${j(t.difficultTerrain)}, hasResource: ${t.hasResource}, x: ${t.x}, y: ${t.y}, borders: ${j(t.borders)}, seaBorders: ${j(t.seaBorders)} },`,
  )
  .join('\n')}
]

const LANDS_BY_AREA = new Map<string, LandId[]>()
for (const l of WORLD_LANDS) {
  if (l.area == null) continue
  const list = LANDS_BY_AREA.get(l.area) ?? []
  list.push(l.id)
  LANDS_BY_AREA.set(l.area, list)
}

export const WORLD_AREAS: AreaDef[] = [...LANDS_BY_AREA.keys()].map((id) => ({
  id,
  name: AREA_NAMES[id] ?? id,
  lands: LANDS_BY_AREA.get(id) ?? [],
  valueByEpoch: valueByEpoch(id),
}))

export const WORLD_MAP_DATA: MapData = {
  lands: WORLD_LANDS,
  areas: WORLD_AREAS,
  seas: WORLD_SEAS,
}
`

const empiresTs = `// AUTO-GENERATED by scripts/build-data.mjs from scripts/world.source.json — DO NOT EDIT.
// The 49-empire roster (7 epochs x 7), real historical empires in their homelands.

import type { EmpireCard } from '../types'

export const WORLD_EMPIRES: EmpireCard[] = [
${empires
  .map(
    (e) =>
      `  { id: ${j(e.id)}, name: ${j(e.name)}, epoch: ${e.epoch}, order: ${e.order}, strength: ${e.strength}, startLand: ${j(e.startLand)}, navigation: ${navStr(e.navigation)}, hasCapital: ${e.hasCapital} },`,
  )
  .join('\n')}
]
`

writeFileSync(join(root, 'src/shared/data/board.ts'), boardTs)
writeFileSync(join(root, 'src/shared/data/empires.ts'), empiresTs)

// ── report ──────────────────────────────────────────────────────────────────
const epochCounts = {}
for (const e of empires) epochCounts[e.epoch] = (epochCounts[e.epoch] || 0) + 1
console.log(`Generated board.ts: ${terrs.length} lands, ${[...seas].length} seas`)
console.log(`  barren: ${terrs.filter((t) => t.barren).length} | resource: ${terrs.filter((t) => t.hasResource).length}`)
console.log(`  difficult terrain: ${terrs.filter((t) => t.difficultTerrain.length).length} | connected components: ${components}`)
console.log(`Generated empires.ts: ${empires.length} empires | per epoch: ${j(epochCounts)}`)
console.log(`marauders: ${empires.filter((e) => !e.hasCapital).length}`)
if (warnings.length) {
  console.log(`\nWARNINGS (${warnings.length}):`)
  for (const w of warnings) console.log('  - ' + w)
} else {
  console.log('\nNo warnings — clean generation.')
}
