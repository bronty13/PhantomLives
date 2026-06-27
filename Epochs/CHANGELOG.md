# Changelog

All notable changes to Epochs are recorded here.

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
