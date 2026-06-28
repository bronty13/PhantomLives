# Changelog

All notable changes to Epochs are recorded here.

## [0.16.1] — 2026-06-27

### Fixed
- **Expansion adjacency is now the board's TRUE land borders.** Replaced the
  position-derived (Delaunay) adjacency — which couldn't see water and kept
  inventing cross-sea/cross-terrain borders — with the **actual drawn borders read
  off the board** (a 16-reader workflow listing which province lines physically
  touch, ≥2 votes per edge). 184 real land borders. No more Europe→western-China,
  Spain→Caribbean, or island teleports — expansion offers only genuinely-bordering
  provinces.
  - Short straits added for near-shore islands (Crete↔Greece, Britain↔Gaul/Ireland,
    Japan, Sumatra, Ceylon, Madagascar) so island-homeland empires can play; one
    reader-gapped real border restored (Arabia↔Palestine, verified on the board).
  - The **Americas, Australasia, and sub-Saharan Africa are correctly separate
    overseas landmasses** — sealed by ocean or the impassable Sahara, reachable by
    sea once navigation lands. The generator/tests treat these as expected; only an
    Old-World mainland split warns.
- **AI difficulty handicap widened** (easy 0.50 / medium 0.28 / hard 0.0) for the
  new geography. Hard >> easy is clear (~61%); adjacent tiers sit within sample
  noise (the test now asserts monotonic direction + a clear endpoint margin).

## [0.16.0] — 2026-06-27

Event system, slice 3 — combat & build boons + an AI difficulty re-tune.

### Added
- **Four new Greater event effects** (the catalog grows toward the full deck):
  - **Siegecraft** — enemy forts give no defence against your attacks this turn.
  - **Surprise Attack** — your attacks ignore difficult-terrain / amphibious defence.
  - **Population Boom / Settlers** — +2 armies this turn (no capital needed).
  - **Civil Service / Bureaucracy** — +2 armies if you hold a Capital.
  Wired through `TurnEffects` (`ignoreForts`, `ignoreTerrain`) + `combatContext`;
  the bot folds them into its combat/build event picks. Each reads clearly in the
  parchment event panel (`describeEffect`).

### Changed
- **AI difficulty re-tuned to a clean monotonic ladder.** The old `easy` overlay
  added timidity (only safe attacks), which played *safe* and scored ~even with
  medium on the new board + richer events. Replaced with a pure random-move
  handicap (easy 0.42 / medium 0.20 / hard 0.0): hard > medium > easy is now clear
  (56.7 / 61.3 / 62.9%). Resolves the long-standing difficulty-spread drift.

### Deferred (need fleets/seas, not built yet)
- Naval Supremacy, Pirates, Ship Building, Storm at Sea, Trade Bonus. Still to come:
  the disaster variants (Pestilence/Famine/Black Death), Kingdoms, Migrants,
  Barbarians, and the big one — true Minor Empires (a second empire-turn).

## [0.15.1] — 2026-06-27

### Fixed
- **Expansion now obeys adjacency** (the rule: place units into spaces adjacent to
  one you already hold). The position-derived Delaunay adjacency had connected
  provinces across open water — including two transatlantic bridges (Southern
  Iberia↔West Indies, Albion↔Appalachia) — letting expansion jump oceans. Removed
  the bridges + 12 high-confidence cross-sea edges; longest remaining border is now
  a real one (0.133). No province is isolated.
- The **Americas are now correctly a separate overseas landmass** (reachable by sea
  once navigation lands — not by land). The generator + tests recognise this as
  expected rather than a connectivity error; only a split in the Old-World mainland
  warns.

## [0.15.0] — 2026-06-27

The complete board. South America is in, all 13 areas, re-registered to a flat
scan that finally captured the whole map.

### Changed
- **Re-registered to the complete board scan** (the owner re-shot it flat with the
  top-left corner in frame). Swapped the basemap (now the true ~1.45 aspect, was a
  too-wide crop missing the corner) and re-read every province's position on it via
  the registration workflow (16 readers), matched against the known province set so
  stray reads auto-dropped. **100 provinces across all 13 areas.**
- **South America added** (`south_america` area): Brazil, Patagonia, Northern &
  Southern Andes, Amazonia (impassable), Guiana Highlands — with transatlantic
  bridges (Appalachia↔Albion, West Indies↔Southern Iberia) so the Americas stay
  reachable under land-only movement (sea movement is still to come). Sardinia
  dropped — a phantom that read zero times across a thorough pass.
- Adjacency re-derived (Delaunay), 1 connected component; all 49 empire homelands
  still resolve. Tests updated (100 lands / 13 areas / 8 barren / 18 resource).

### Note
- The complete-board adjacency flattened the AI difficulty curve further (hard now
  barely edges medium, 50.4%). **Re-tuning the ε-greedy handicap for the new
  geography is now genuinely needed** — a near-term follow-up.

## [0.14.1] — 2026-06-27

The events were the weak spot — you saw bare card names with no idea what they did.
Now they read like the original's Event window.

### Changed
- **Event panel rebuilt as parchment event cards.** Each card shows its name, epoch
  band, *when* to play (during your turn vs before it, aimed at an enemy land), and
  a plain-English description of its effect — Greater (combat boons) and Lesser
  (disasters) sections, click to select, Play/Skip. New shared `describeEffect()`
  (our own wording of the mechanics) drives the text; `.evt-card` parchment CSS.

### Note
- The deck itself is still the interim hand (combat boons + the four disasters) —
  the full 9-colour-pile rebuild with the remaining ~25 effects + true Minor
  Empires is still task #29; the panel is now ready to present them clearly.

## [0.14.0] — 2026-06-27

The play experience begins — you play by default, and your empire rises with drama.
(Phase 35, slice 1 of: epoch intro → keep/pass draft → empire panel → full
parchment shell.)

### Added
- **Epoch intro splash** — when your empire rises each epoch, a parchment card
  announces it (EPOCH N + era, a player-coloured seal, the empire name, and its
  homeland / strength / capital / navigation), pausing until you "Take command".
  AI turns roll on without interruption. The first taste of the cohesive antique
  look. (`turnStart` → `pendingIntro`; new `#epoch-intro` panel + `.intro-*` CSS.)

### Changed
- **You play by default** — new games seat you as P1 (the "I play" box defaults on),
  so Epochs opens as a game you play rather than one you watch.

## [0.13.0] — 2026-06-27

The board IS the map. The game now plays on the real History of the World board.

### Changed
- **Territories registered to the photographed board.** Replaced the generated
  geography with **95 real provinces** read off the board scan via a parallel
  registration workflow (two readers per region + consolidation), then cleaned and
  ground-truthed: the whole Old World (Europe, Middle East — Lower/Middle/Upper
  Tigris, Anatolia, Persia, Levant, Zagros, Arabia; India — Indus, Ganges, Deccan,
  Ghats, Hindu Kush; China — 7 provinces; SE Asia; Africa; Australia; British
  Isles; Scandinavia; Japan/Korea) **plus North America** (Pacific Seaboard, Great
  Plains/Lakes, Appalachia, Deep South, Mexican Valley, Central America, West
  Indies). Each land's (x,y) is a fraction of the board scan; adjacency is
  Delaunay-derived (1 connected component); areas + terrain + resources assigned.
- **The renderer draws the board scan as the basemap** and only the live game layer
  on top — army counters, structures, rings, hover. The parchment Voronoi map is
  retired (the real board carries the geography/labels/regions). Calibration mode
  retained (off) for re-registering.
- **All 49 empire homelands remapped** to the new province names (Sumeria → Lower
  Tigris, Egypt → Nile Delta, Indus Valley → Upper Indus, …) so empires spawn on
  real lands.

### Known / next
- **South America** (6 provinces: Brazil, Patagonia, the Andes, Amazonia, Guiana
  Highlands) is on the physical board but was folded out of frame in the flat scan,
  so it's pending a basemap that includes it (its scoring Area is absent for now —
  12 of 13). No empire starts there.
- The new geography **compressed the AI difficulty spread** (still monotonic
  hard > medium > easy, tighter margins) — re-tuning the ε-greedy handicap is a
  follow-up.
- North-America province positions are approximate (close-up-read); the scan still
  shows their true names, so it's cosmetic.

## [0.12.2] — 2026-06-27

### Changed
- **The Victory Point Table moved out of the sidebar into its own popout dialog**
  (a 📊 Scoring Table button in the top bar, alongside How to play / Rulebook).
  In the narrow sidebar the table was cramped and its region names were truncated
  to "…" (unreadable). In the dialog every region name reads in full, each with a
  colour swatch, the seven epoch columns I–VII, the current epoch highlighted, and
  a footnote on the Presence / Dominance (×2) / Control (×3) multipliers. It's
  reference-on-demand — there when you want it, out of the way when you don't.

## [0.12.1] — 2026-06-27

### Added
- **Victory Point Table** reference panel in the sidebar — the per-epoch value of
  every region, current epoch highlighted, for planning your moves.
- **Resource symbols** on the map — a region-coloured gem on each resource land
  (pairs of these build Monuments).
- **Impassable lands** (Siberia, Amazonia, Sahara, the deserts, etc.) now carry a
  stippled desert texture so they read as un-enterable; mountains (ridgelines) and
  forests (stipple) clearer.

### Note
- The map's *shape* fidelity is still limited by the procedural Voronoi approach
  and the generic territory set — making it match the board's actual lines &
  proportions needs the territory data rebuilt to the board (task #34, next).

## [0.12.0] — 2026-06-27

The look & feel pivot — an antique parchment board (phase 1 of recreating the
nostalgic experience; the interactive "you play it" phase follows).

### Changed
- **The map is now an antique parchment board**, not abstract dots. Original
  generated art on the real geography: an ocean ground, **Voronoi territories**
  (pure `src/shared/voronoi.ts`, cached per layout) tinted with soft watercolour
  region colours and sepia coastlines, **ridgeline mountains**, forest stipple,
  **calligraphic italic labels**, a **compass rose**, and a burnt-edge frame. The
  game layer is restyled to match: armies are **square counters** with a
  crossed-swords emblem, structures keep ★/◆/▲/▮, and the active-empire ring,
  placeable rings, hover tooltip and effects sit on top. `map.ts` rewritten;
  `palette.ts` gains the parchment tints.

### Next (the pivot continues)
- Rebuild the territory data to the **board's authentic territories** (Lower
  Tigris, Eastern Anatolia, Turanian Plain…) so the map matches the board exactly.
- The interactive experience: **you play by default** — Epoch intro splash,
  Keep/Pass empire draft, the Empire panel, Event windows, click-to-take-your-turn
  — all in the warm parchment style. (The surrounding shell is still the dark UI
  for now; it gets the parchment treatment in that phase.)

## [0.11.2] — 2026-06-27

Event system, slice 2 — targeting + disasters.

### Added
- **Targeting infrastructure**: events can now be aimed at a target Land. The bot
  computes its own target (`EventView` gained `board` + `pieces`; `EventChoice`
  carries `lesserTarget`); a human seat gets an `awaitEventTarget` step — the legal
  targets light up and you click one. Pure, deterministic.
- **Disasters** (the Lesser deck): **Volcano / Great Fire / Great Flood**
  (structure-wreckers — raze a city/fort/monument, reduce a capital to a city, by
  terrain: mountain / any / coastal) and **Plague** (the target army rolls 4 dice; a
  '1' kills it). The AI aims them at an opponent's most valuable legal target
  (capitals first, rich areas). The renderer logs each disaster + bursts an fx at
  the target.
- Integration test: disasters reliably fire in AI games; structure/plague effects
  covered. The difficulty ladder still holds (its margins compress with the new
  board variance: hard 58% vs medium, 72% vs easy).

### Notes
- Remaining disasters (Pestilence/Famine/Black Death/Storm-at-Sea), and the other
  targeted families (Kingdoms, Rebellion, Civil War, Crusade, Barbarians, Treachery)
  + the fleet cards are later slices. The hand is still the interim 3 Greater + 2
  Lesser; the full 9-pile deck comes with task #29's conclusion.

## [0.11.1] — 2026-06-27

Event system, slice 1 — the combat-modifier events.

### Added
- **Leader / Weaponry / Fanaticism** now work as real combat events (the payoff of
  the v0.11 combat rewrite). The combat engine gained attacker modifiers:
  `attackerKeptBonus` (Weaponry = +1 to each attacker die) and `attackerWinsTies`
  (Fanaticism = win all ties this turn, using the tie mass `combatOdds` deliberately
  preserves); Leader stays "3 dice". New `winProb(odds, tieRule)` and
  `winProbForContext()` honour these. Threaded through `TurnEffects` →
  `combatContext` → resolution; the AI plays them on strong attacking empires.
  Fanaticism cards added to the deck.

### Notes
- Remaining event work (task #29): the full 9-colour-pile deck + the other ~25
  effects (disasters, minor empires, Treachery, the targeted/fleet cards) — several
  need a target-selection step and fleets, so they land in later slices. The full
  card list is in the in-app **📖 Rulebook** and docs/AUTHENTIC-RULES §12.

## [0.11.0] — 2026-06-27

Authentic combat + the wrong-edition mechanics removed (fidelity rebuild, P0).

### Changed
- **Combat to the real rules** (docs/AUTHENTIC-RULES §5): an exact **tie is
  REROLLED** (was "both armies removed"); the **defender caps at 2 dice** (no more
  defender-rolls-3 for straits/amphibious); the **fort is a simple +1** that
  absorbs no losses and falls with the last army (no multi-round shielding).
  `combatOdds` still returns the raw single-roll PMF; new `winProb()` gives the
  effective post-reroll win chance. AI combat EV, tooltips, clash colours and SPEC
  §7 all updated. The difficulty ladder holds (hard 62% vs medium, 80% vs easy).

### Removed
- **Coins** and **pre-eminence markers** — both belong to the later Z-Man edition,
  not the owner's AH 1993 game. Gone from the engine, types, scoring, UI (the
  game-over screen is now plain "most VP wins" — no hidden reveal), SPEC §10–§12,
  and tests. The Lesser event deck is **empty** pending the authentic 9-pile
  rebuild (task #29); the Greater deck (Leader/Weaponry/Reallocation/Minor Empire)
  stands for now.

## [0.10.1] — 2026-06-27

### Added
- **📖 Rulebook viewer** — a top-bar button opens the original scanned rulebook +
  sample-game pages, packaged into the local build. The scans live in
  `src/renderer/public/rulebook/` (**git-ignored** — the owner's own scans, bundled
  into their personal build, never committed). Degrades gracefully with a note if
  the folder isn't present on a given machine.

## [0.10.0] — 2026-06-27

Authentic empire roster (fidelity rebuild, phase 2).

### Changed
- **The 49-empire roster is now the real one** (`docs/AUTHENTIC-RULES.md` §11),
  transcribed from the owner's physical epoch cards: authentic names, **real
  strengths** (Persia 15, Romans 25, Mongols/Britain 20 — was a 3–9 band), the
  correct **9 marauders** (Aryans, Scythians, Celts, Hsiung-Nu, Goths, Huns,
  Vikings, Seljuk Turks, Mongols), and the right epochs (**Mongols are Epoch V**).
  Regenerated `empires.ts` from `world.source.json`. 88 tests green; the AI
  difficulty ladder still holds (hard 60% vs medium, 92% vs easy).

### Notes (flagged for later phases)
- Start-lands are mapped to the nearest *current* territory (the coarse 97-land
  map); a board-accurate territory rebuild will make them exact.
- Sumeria still appears as a drafted Epoch-I empire (should become a neutral
  pre-game seed); Inca/Aztec share one card (only Aztec listed); Spain & Portugal
  share Iberia. These are engine-phase follow-ups.

## [0.9.0] — 2026-06-27

Map overhaul — it reads as a real map now. (Phase 1 of a fidelity pass driven by
a research+audit of the real History-of-the-World rules; see below for what's
still missing.)

### Changed
- **The map looks like a map.** Blue ocean (vertical gradient) instead of flat
  near-black; same-region territories fuse into soft **continent silhouettes**;
  brighter, more-saturated region tints (earthy land colors that never read as
  ocean); bigger territory nodes; **territory labels** with collision-culling so
  dense regions stay legible; readable adjacency edges; gold resource rings.
- **Projection fixed.** The view now **fits the territories' bounding box** with
  the equirectangular 2:1 correction (one x-unit = twice the longitude of a
  y-unit), so continents are proportional and the empty Pacific no longer wastes
  half the canvas. `map.ts` + `main.ts` (resize/bbox-fit) + `palette.ts`.

### Known gaps (next phases of the fidelity build)
A research+audit pass found Epochs faithfully implements land scoring + combat,
but is **missing sea/ocean scoring (fleets), the disaster/targeting half of the
event deck, and true minor empires**, and the per-epoch area-value table may be
unverified. Those are the next phases (engine + complete in-app rules), pending
authentic values transcribed from the physical board.

## [0.8.1] — 2026-06-27

### Added
- **In-app "How to play"** — a rules overlay (goal, a turn, region scoring
  presence/dominance/control, combat, the catch-up draft, events, pre-eminence,
  watch-vs-play, the map key) that **shows on first load** and pauses the game
  until you dismiss it, and is reopenable anytime via the **"? How to play"**
  button in the top bar. Our own wording (legal posture unchanged). Fixes: on
  launch it wasn't clear how to play.

## [0.8.0] — 2026-06-27

UI polish — nicer to watch, better to play. (Designed via a 3-perspective design
panel → prioritized plan.)

### Added
- **Animated effects layer** (`src/renderer/anim.ts`) — a self-stopping
  `requestAnimationFrame` overlay (render-only, so the engine stays
  deterministic): army **spawns** pulse in, **combat** plays a win/tie/loss clash
  (green/amber/red) at the contested land with the attacker's win% floating up,
  and **+VP** floats over the scoring empire. Auto-play pacing now waits for the
  current animation to finish.
- **Decision support** when you play a seat: placeable lands ring by kind —
  **green = settle, blue = reclaim, red→amber = attack (color = odds)**, dashed
  for amphibious — and a hover **tooltip** shows the verb, exact combat odds, the
  region VP swing (presence→dominance etc.), and structure captures — all from
  the engine's own scoring (`src/shared/boardInsight.ts`).
- **Whose-turn clarity** — the active player gets a colored status pill, a
  highlighted scoreboard row, and a white "live-army" ring on its territories.
- **Regions panel** — who leads each scoring area this epoch, its value, tier,
  and banked VP (contested marked).
- **Game-over overlay** with a staggered **pre-eminence reveal** (the hidden
  markers flip face-up and bump each total) + Play Again.
- VP **bars** in the scoreboard (CSS-tweened), structure-glyph halos for
  legibility.
- Tests → **88** (+9, `boardInsight.test.ts`): the pure placement-preview and
  area-control math (verified against the engine's scoring).

### Changed
- Bumped to 0.8.0. `MapRenderState` / `drawMap` extended (placeable is now a Map
  with kind+odds; active-player + epoch + tooltip lines).

## [0.7.0] — 2026-06-27

Smarter AI + proper difficulty, via self-play tuning.

### Changed
- **AI weights tuned by self-play.** A coordinate-descent search on the real
  world board (`tests/tuning.test.ts`, env-guarded `TUNE=1`) found a stronger
  `DEFAULT_WEIGHTS` that beats the previous default **~77%** head-to-head. The
  bot is now more **risk-averse** (`riskAversion` 0.5 → 0.75 — stops flinging
  armies into low-odds attacks) and **less spiteful** (`denialBase` 0.6 → 0.35 —
  grows itself before denying opponents).
- **Difficulty is now a monotonic ε-greedy dial** (`randomMoveProb`): `hard`
  plays the tuned peak; `medium`/`easy` play a random legal move with prob.
  0.16 / 0.40 (easy also myopic + timid). Fixes the old non-monotonic ladder —
  now **`hard > medium > easy`** holds by construction (observed 60% / 74% / 83%,
  asserted in `tests/tournament.test.ts`). The old `tieEps` jitter was
  scale-tiny and never a real skill axis.

### Added
- `randomMoveProb` weight + `tests/tuning.test.ts` (the reproducible self-play
  search harness).

## [0.6.1] — 2026-06-26

Packaged as a real macOS app.

### Added
- **App icon** — `build/icon.svg` (plain-text source) + `build/make-icon.sh`
  (rsvg-convert → iconset → `iconutil` → `icon.icns`), a globe of player-colored
  territories circled by an epoch orbit. Generated deterministically (no
  committed binary); wired into electron-builder.
- **`build-app.sh` works end-to-end**: type-check → test → generate icon →
  `electron-vite build` → `electron-builder --mac dir` → **adhoc-sign** (required
  for Apple Silicon) → `install.sh` (force-kill any running instance → `ditto`
  to `/Applications/Epochs.app` → relaunch → **freshness proof**). Verified:
  `Epochs 0.6.1 running fresh`.

### Notes
- Local-use app: adhoc-signed, not notarized (no Developer ID / Sparkle). It's a
  real double-clickable `/Applications/Epochs.app` now, not just `npm run dev`.
- The generated `icon.icns`/`icon.png` and `dist/` are gitignored; only the SVG +
  generator are committed.

## [0.6.0] — 2026-06-26

The event system — the last major rules gap. Each player now manages a finite
hand of event cards across the whole game.

### Added
- **Events (SPEC §11).** Each player is dealt a fixed **3 Greater + 7 Lesser**
  hand at game start (seeded, disjoint, no refills). Before each turn a player
  may play **≤1 Greater + ≤1 Lesser**:
  - **Leader / Weaponry** (Greater) → attacker rolls **+1 die** this turn.
  - **Reallocation / Minor Empire** (Greater) → **bonus armies** this turn.
  - **Coins** (Lesser) → buy **forts** on your best-held lands — which finally
    activates the multi-round fort combat that's been in `resolveAssault` since
    v0.1.
- `data/events.ts` — the deck (24 Greater + 49 Lesser, our own flavor names).
- **AI event policy** (`HeuristicBot.chooseEvents`): press the attack on strong
  empires, bulk up weak ones, fort established ones — spaced so the finite hand
  lasts.
- **Human event UI:** a panel before your turn to play or skip cards (the engine
  yields `awaitEvents`; the renderer resolves it). Fort glyph (▮) on the map.
- Tests → **79** (+7, `events.test.ts`): deck composition, dealing (disjoint
  hands), events-played + forts in a full game, finite-hand depletion, ≤1
  fort/land, and the human play-and-consume path.

### Changed
- The engine deals hands in the constructor (shifts RNG → game outcomes differ
  from v0.5, but determinism/invariants hold). The AI is now *stronger* (it uses
  events; the stub bots don't) — hard vs 3×greedy rose to ~98%.
- Bumped to 0.6.0.

### Notes
- **Minor Empire** is simplified to bonus armies (not a full separate sub-empire)
  — documented in `game.ts` + SPEC §16. The whole game's rules are now modeled.

## [0.5.0] — 2026-06-26

You can finally *see and play* it. An interactive Canvas world-map UI on a
step-driven engine — watch the AI fight across the world, or play a seat.

### Added
- **Step-driven engine.** `Game.play()` is now a generator that yields a typed
  `GameEvent` after each action (epoch/draft/turn/setup/placement/score/
  pre-eminence/…); `run()` drains it (all 67 prior tests unchanged). A human
  seat (`PlayerConfig.isHuman`, `bot` now optional) yields `awaitPlacement` and
  resumes with the clicked land. Same engine drives both headless play and the UI.
- **World-map renderer** (`src/renderer/`, vanilla TS + Canvas 2D): the 97
  territories at real geographic positions, area-tinted, adjacency edges, armies
  (player-colored), structures (★ capital / ◆ city / ▲ monument), resource dots,
  hover labels, and placeable highlights. Scoreboard, epoch/turn HUD, and an
  event log.
- **Controls:** New Game (3–6 players, AI difficulty, seed, "I play seat 1"),
  Step, Auto-play with a speed slider, and click-to-place during your turn.
- **Geographic coordinates** for all 97 territories (`scripts/coords.json`,
  folded into the generated `board.ts` as `x`/`y`); pure projection + hit-testing
  in `src/shared/mapProjection.ts`; colors in `src/shared/palette.ts`.
- `npm run dev:web` — serve the renderer in a plain browser (no Electron needed).
- Tests → **72** (+5): step-generator event sequence + human-input path
  (`session.test.ts`), and projection/hit-testing (`projection.test.ts`).

### Changed
- Bumped to 0.5.0. The renderer placeholder is replaced by the real game UI.

### Notes
- The Canvas visuals were verified by type-check + Vite build-graph resolution +
  unit tests of the pure layers; pixel-level appearance is verified by running it
  (`npm run dev:web` → open the printed URL). Events data/system still deferred.

## [0.4.0] — 2026-06-26

The real world. Epochs now plays on a full 97-territory world map with the 49
historical empires — no more 9-land fixture for the actual game.

### Added
- **`src/shared/data/board.ts`** (generated) — an **original real-geography
  world map**: 97 lands across the 13 Areas, 29 seas/oceans, symmetric adjacency
  (one connected component, land + sea), 18 resource lands, 8 barren lands, and
  difficult terrain (mountain ranges, the Great Wall, straits).
- **`src/shared/data/empires.ts`** (generated) — the **49-empire roster**
  (7 epochs × 7): real historical empires (Sumer → British/Russian/Qing) in their
  homelands, with calibrated strengths, navigation, and marauder flags.
- **`scripts/world.source.json`** + **`scripts/build-data.mjs`** (`npm run
  gen:data`) — the researched roster/geography and a deterministic generator that
  emits the board + empires (symmetrizes adjacency, validates, reports). Retune by
  editing the JSON and regenerating. (Built via a multi-agent research workflow:
  3 epoch-group roster passes + geography → synthesis.)
- **`tests/worldmap.test.ts`** (+10 tests, **61 total**): structural invariants
  (adjacency symmetry, connectivity, counts, valid empire starts/seas) and a full
  real-board game (≤1 army/land, no army on barren, ≤1 monument/land, ranked
  winner, determinism).

### Changed
- `sim.ts` (`runMatch` / `runHeadlessGame` / tournaments) now defaults to the
  **world map + 49 empires**; `runMatch` accepts `{ mapData, deck }` to override.
  On the real board the AI is far stronger: HeuristicBot(hard) beats 3×
  GreedyStubBot **97%** (was 56% on the fixture) — foresight finally has room.
- Bumped to 0.4.0; added the `gen:data` script.

### Notes
- The board is **our own** real-geography map (uncopyrightable geography +
  historical facts), faithful to the AH framework (13 Areas + VP table + 7 epochs
  + ~100-land scale), not a copy of the unavailable AH board.
- **Events remain unmodeled** (engine + data both deferred). AI difficulty weights
  are still provisional — re-tune via self-play now that the real board exists.

## [0.3.0] — 2026-06-26

Real AI opponents. `HeuristicBot` replaces `GreedyStubBot` as the default brain
and beats the baselines decisively in headless tournaments.

### Added
- **`HeuristicBot`** (`src/shared/heuristicBot.ts`): a tunable, deterministic
  marginal-expected-VP placement bot. Scores each move as
  `scoreArea(after) − scoreArea(before)` (engine-parity), summed over remaining
  epochs and discounted by a board-aware survival factor, plus structure
  capture, monuments, and leader-weighted **denial**, with enemy attacks folded
  by closed-form combat odds against an opportunity-cost floor. Difficulty
  (`easy`/`medium`/`hard`) and personas are pure weight overlays; all jitter is
  seeded (`hash01`), never `Math.random`. Designed via a multi-agent design
  panel (3 philosophies → synthesis); see `docs/SPEC.md` §15.
- **`BotView` extended** with a live `pieces` snapshot, `standings`,
  `monumentsBuilt`, `seed`, and `armiesRemaining` so a bot can compute area
  tiers, denial, and survival. The engine rebuilds the view on **every**
  placement (fixes a latent stale-snapshot bug — `state.pieces` is reassigned on
  each mutation).
- **Tournament harness** in `sim.ts`: `runMatch`, `tournament`, bot factories
  (`heuristic`/`greedy`/`random`), and `seeds()`.
- Tests → **51 total** (+9): `HeuristicBot` decision logic (own_old fix, capital
  capture, determinism, legality, no-`Math.random` source scan) and
  seat-averaged win-rate tournaments proving HeuristicBot ≫ GreedyStubBot /
  RandomBot and that the difficulty knob is monotonic at the extreme.

### Changed
- `runHeadlessGame` now uses `HeuristicBot` (default `medium`).
- Bumped to 0.3.0 (script + preload).

### Notes
- AI weights are **provisional fixture placeholders** — the tiny 9-land fixture
  overfits long-horizon weights (so `hard` doesn't cleanly beat `medium` there);
  re-tune via self-play once the real board lands (`docs/SPEC.md` §14/§15).
- `GreedyStubBot` is retained as a weak baseline (its `own_old` over-valuation
  makes it actually worse than random — which is what motivated the real bot).

## [0.2.0] — 2026-06-26

The engine is now a **playable, deterministic, headless game**: a full 7-epoch
4-player match runs end-to-end and produces sane, close standings.

### Added
- **Game-loop engine** (`src/shared/game.ts`): the `Game` state machine — epoch
  loop, lowest-VP-first catch-up draft, empire setup, army-by-army expansion
  with land/sea reachability and combat, monument building, per-turn area +
  structure scoring, pre-eminence draws, and finalize/ranking.
- **`Board`** (`board.ts`): queryable map wrapper (adjacency, sea→lands index,
  area lookups) built from a `MapData`.
- **Bot seam** (`bot.ts`): `Bot` interface, `GreedyStubBot` (weighted-scoring
  placeholder), and `RandomBot`. The engine hands the bot a legal frontier; the
  bot picks a target.
- **Fixture content** (`data/fixtureEmpires.ts`) + `FIXTURE_MAP_DATA`, and a
  headless runner (`sim.ts`, `runHeadlessGame` / `formatResult`).
- `applyCapture()` — a **pure, directly-tested** sack/pillage function.
- 15 new tests (combat + scoring + game = **42 total**): full-game completion,
  determinism, board invariants, and the regression tests below.

### Fixed (found by an adversarial multi-agent engine review)
- **`onOccupy` self-raze (high):** sack/pillage lacked an ownership guard, so
  re-occupying your OWN land (the bot's constant `own_old` move) destroyed your
  own cities, downgraded your own capitals, and paid Marauders a bogus self-raze
  bonus — silently corrupting the VP that decides the winner. Now enemy-only.
- **Monument stacking (medium):** `monumentPlacement`'s fallback could stack a
  2nd/3rd monument on an already-monumented land, inflating structure VP. Now
  returns null when unplaceable (one monument per land, SPEC §8.2).
- **Draft modulo wrap (low):** with more players than empires (5–6 players on the
  fixture deck), `draft()` handed two players the same empire/start land. Now
  each empire is drafted at most once; surplus players sit out.
- Forward-looking: `resolveExpansion` now honors `resolveAssault`'s
  `fortDestroyed` flag on all outcomes (dormant until fort placement lands).

### Changed
- Bumped to 0.2.0 (script + preload version constant).

## [0.1.0] — 2026-06-26

Initial scaffold + engine core.

### Added
- **Rules & data spec** (`docs/SPEC.md`): the full 7-epoch ruleset (turn loop,
  catch-up draft, expansion, combat dice system + odds table, structure
  reduction, monuments, presence/dominance/control area scoring with the
  complete per-epoch Victory-Point table, pre-eminence markers, event system),
  the TypeScript data model, the data-entry backlog, and the open rules
  questions to resolve against the source.
- **Project scaffold**: Electron 31 + Vite (electron-vite) + TypeScript, with a
  pure-TS engine under `src/shared/` (no Electron/DOM imports), Electron main +
  preload, a placeholder renderer that draws the VP table from the engine, and a
  vitest test harness.
- **Engine core**:
  - `combat.ts` — closed-form combat odds (`combatOdds`, `pmfMaxOfK`), seeded
    single-round and forted multi-round resolution.
  - `scoring.ts` — area control tiers (presence/dominance/control) and structure
    scoring against the VP table.
  - `rng.ts` — seeded deterministic RNG (mulberry32); the engine never calls
    `Math.random()`.
  - `data/areaValues.ts` — the real 13-area × 7-epoch VP table.
  - `data/fixtureMap.ts` — a small placeholder board so the engine and tests run
    before the full board is transcribed.
- **Tests**: vitest coverage of combat odds (exact for standard combat), seeded
  resolution, fort effects, and area/structure scoring.
- Repo-standard `build-app.sh` / `install.sh` (build → install to
  `/Applications` → relaunch with freshness proof) — present, pending first
  end-to-end validation.

### Notes
- Original recreation of the *system* of *History of the World* (Ragnar Brothers
  / Avalon Hill) for private personal use; uses original assets and reworded
  rules. Not affiliated with Hasbro, Z-Man Games, Rio Grande Games, or the
  Ragnar Brothers. Not legal advice.
