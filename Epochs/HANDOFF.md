# Epochs — Handoff

The architecture + current-state snapshot. Read this before non-trivial changes.
`docs/SPEC.md` is the canonical rules/data spec; this file is the orientation map.

## What it is

An original digital recreation of the *system* of Avalon Hill's *History of the
World* (Ragnar Brothers), solo vs AI, in TypeScript + Electron. **Legal posture:
mechanics only.** We reimplement uncopyrightable game mechanics in our own code,
with our own map, our own event-card names, and our own prose. The owner's
**scanned board and rulebook pages are git-ignored and never committed**
(`src/renderer/public/board.jpg`, `src/renderer/public/rulebook/`,
`art/board-source.*`, `art/board-crop.*`) — they are bundled into the *local* build
for personal use only. **Before every commit, verify no scans are staged**
(`git diff --staged --name-only | grep -iE 'board\.jpg|board-source|board-crop|rulebook/page|public/rulebook'`).

## Status (v0.46) — source-verified on both axes

Beyond the original fidelity pass, the game has been audited against **primary source**
on two axes and corrected: every **rule** against the 12-page rulebook (with the worked
**sample game** encoded as a regression oracle, `tests/sample-game.test.ts`), and every
**empire** against its physical card (`docs/CARD-AUDIT.md`). Key outcomes:

- **Per-unit placement** (rulebook §4): no buy phase — each Strength unit is placed one
  at a time as an army / fleet / fort via a docked mode-toggle (`awaitPlacement` carries
  `frontier` + `seas` + `fortLands`). Monuments are player-sited within the forced tier.
- **Audit fixes**: turn order by Empire Card # (not draft order); Sumeria's capital;
  monuments unaffected by conquest (stay the builder's); fleet **ports** (a fleet without
  a controlled coastal land is destroyed) + unlimited oceans; the Caspian admits no fleets.
- **Roster corrected to the cards**: the missing **Inca** restored; ~24 start-lands,
  navigation, turn order, and Aztec strength fixed against the authoritative cards.
- **Debunked by the oracle/source** (already faithful — do NOT "fix"): the combat dice
  model, forts = +1, no capital defensive bonus, the VP table, and the whole monument
  rule-set. See `docs/RULE-AUDIT.md`'s maintainer notes before acting on any audit lead.

The original five-slice **fidelity pass** is below; everything is tested (**~138 tests**,
clean difficulty ladder ≈ 72 / 75 / 85 %):

- **Scoring tiers** — presence ×1, **dominance ≥3 lands & most**, **control = every
  land in the area**; +structures (capital 2 / city 1 / monument 1); **+1 per
  controlled enclosed sea**. All via `scoreBreakdown` (single source of truth).
- **Draft** — opening die roll (lowest drafts first in Epoch I), then catch-up by
  **cumulative Strength**; **Keep/Pass** (keep the drawn empire or gift it to an
  empire-less player); the empire draw is **random** (face-down).
- **Buy phase** — split Strength across **armies / fleets / forts** (`awaitBuy`);
  navigation empires must build ≥1 fleet.
- **Expansion** — up to **3 armies per land** (reinforce your own holdings);
  multi-round assaults vs a stack; barren lands impassable; sea-reach **requires a
  fleet** in the sea (Ship Building / Naval Supremacy bypass).
- **Naval game** — fleets are pieces in seas (`state.fleets`); naval combat in
  enclosed seas, coexistence in the 5 open oceans (`data/seas.ts`); sea scoring.
- **Combat** — attacker 2 dice / defender 1 (+2 difficult/strait/amphibious), fort
  +1, ties reroll. Conquest: capital→city, city sacked, fort falls, monuments persist.
  **Marauder** (capital-less) empires score **+1 VP per enemy structure razed**
  (authentic; kept despite an old task note to remove it).
- **Events** — the deck is **9 colour-piles of 7** (7 Greater boon piles + 2 Lesser
  disaster piles); each player is dealt **one card from each pile** at setup.
  ~19 effects across combat / economy / naval / Minor-Empire / disaster families.
- **Retreating** — an army on a new empire's occupied Start Land retreats to an
  adjacent friendly land (never overseas), else is eliminated.
- **Neutral Sumerians** — 4 owner-less armies seeded from Lower Tigris before Epoch I.
- **UI** — board-scan basemap; interactive panels (opening roll, Keep/Pass draft, Buy
  Units, events, epoch intro); fleets + army-stack badges drawn on the map; live
  VP-table "You" column; in-app **Rulebook** (own-words + a sample game, with a
  "Classic scans" tab); how-to-play; scoreboard, HUD, log.

## Architecture

**Pure engine in `src/shared/` (no Electron/DOM imports)** — headlessly testable.
The UI in `src/renderer/` drives it.

- **`game.ts`** — the heart. `Game.play()` is a **generator** yielding typed
  `GameEvent`s; it pauses for human input at suspension points
  (`awaitDraft`, `awaitBuy`, `awaitEvents`, `awaitEventTarget`, `awaitPlacement`)
  and resumes via `.next(PlayInput)`. `run()` drains it for all-AI games. Turn flow:
  `startRoll → (per epoch) epochStart → draft → (per empire) turnStart → events →
  [minorEmpire] → setup → buy → expand → build → score → turnEnd → epochEnd → gameEnd`.
- **`scoring.ts`** — `scoreBreakdown` (areas/structures/seas) is THE score; everything
  derives from it. `areaTier(own, rivals, areaSize)` is land-count based.
- **`combat.ts`** — closed-form odds + seeded `resolveAssault` (one round); the
  multi-round land assault and naval combat both loop it.
- **`heuristicBot.ts`** — the AI (marginal-expected-VP). Difficulty = a random-move
  handicap (easy 0.70 / medium 0.38 / hard 0.0). `chooseDraft` / `chooseEvents` /
  `chooseExpansion`; the bot **spreads rather than stacks** (good area play) and uses
  **conquer odds** `P(round)^defenders` so it doesn't over-attack stacks.
- **`renderer/main.ts`** — session loop, the interactive panels, the buy/draft logic;
  `pending*` flags gate the auto-loop while a human decision is open.

### Data pipeline (generated; don't hand-edit the outputs)

`scripts/world.source.json` (geography + 48 empires) **+** `scripts/coords.json`
(name→[x,y], registered to the board scan) **→ `node scripts/build-data.mjs` →**
`src/shared/data/board.ts` + `empires.ts`. Adjacency in `world.source.json` is the
**true land borders read off the board** (a reader workflow), plus short straits;
the 5 overseas landmasses (Americas, Australasia, sub-Saharan Africa) connect only by
sea. Coastlines (`seas:` per territory) gate fleet reach. After editing the source,
regenerate and run `npm test`. `scripts/rulebook-to-md.mjs` regenerates the Obsidian
markdown copy of the in-app rulebook (own content only).

## Build / test

- `./build-app.sh` — build + install `/Applications/Epochs.app` + relaunch + freshness
  proof (the repo standard; `--no-install` / `--no-open` / `BUILD_ONLY=1` opt-outs).
- `npm test` — vitest (120). `npm run typecheck` — tsc over both tsconfigs.
- `npm run dev:web` (browser) / `npm run dev` (Electron) for development.
- **Watch the tournament test** after any change touching combat, scoring, the AI, or
  card frequencies — it asserts a monotonic hard > medium > easy ladder and is the
  canary for balance regressions.

## Conventions & gotchas

- A new player-decision = a new generator suspension point + a `PlayInput` variant +
  a renderer panel guarded by a `pending*` flag. This pattern is why each interactive
  feature was additive — follow it.
- `owner: null` = a neutral piece (the Sumerians); scoring/frontier already handle it.
- Migrations/data: regenerate `board.ts`/`empires.ts` from source, never hand-edit.
- Seeded RNG everywhere (`mulberry32`); the UI varies the seed per New Game for
  variety but the engine stays deterministic for tests.

## Remaining / optional (not fidelity gaps)

Save/load (the `~/Downloads/Epochs/` default is a placeholder); polish (richer
animation, sound); an end-game summary screen. The rules are complete.
