# Epochs

A digital strategy game of **empires that rise and fall across seven epochs**,
played solo against AI opponents. Epochs is an *original* recreation of the
*system* of the 1990s Avalon Hill board game *History of the World* (designed by
the Ragnar Brothers) — own map, own art, own wording, for **private personal
use**. See [`docs/SPEC.md`](docs/SPEC.md) for the full rules + data spec and the
legal posture (we reimplement uncopyrightable mechanics only).

> **Status: v0.4 — the real world.** A full 7-epoch game runs end-to-end and
> deterministically on a **97-territory real-geography world map** with the **49
> historical empires**, driven by **`HeuristicBot`** (which beats 3 stub bots
> ~97% on the real board). 61 tests. Still to come: the event system, the map UI,
> and the first packaged app (see `docs/SPEC.md` §14). The world is generated from
> `scripts/world.source.json` via `npm run gen:data`; AI weights are still
> provisional — re-tune via self-play.

## Stack

TypeScript + **Electron 31** + Vite (electron-vite), modeled on `PurpleChef`.
The game logic lives in a pure-TS engine under **`src/shared/`** with **no
Electron/DOM imports**, so it is fully unit-testable headlessly and reusable
across main, renderer, and tests.

```
src/
  shared/        # pure game brain — engine + data (no Electron/DOM)
    types.ts         entity types (Land, Area, EmpireCard, BoardPiece, MapData…)
    rng.ts           seeded deterministic RNG (mulberry32)
    combat.ts        dice combat: closed-form odds + seeded resolution
    scoring.ts       presence/dominance/control area scoring + structures
    board.ts         queryable map wrapper (adjacency, sea index, areas)
    game.ts          the Game state machine + applyCapture (the turn loop)
    bot.ts           Bot interface + GreedyStubBot / RandomBot (+ BotView)
    heuristicBot.ts  the real AI: marginal-expected-VP bot + difficulty levels
    sim.ts           headless runner + tournament harness (runMatch/tournament)
    data/
      areaValues.ts    the real per-epoch Victory-Point table (13 areas)
      board.ts         GENERATED — the 97-land real-geography world map
      empires.ts       GENERATED — the 49 historical empires (7×7)
      fixtureMap.ts    small board for fast deterministic unit tests
      fixtureEmpires.ts small empire deck for unit tests
  main/          # Electron main process (window lifecycle)
  preload/       # contextBridge surface
  renderer/      # UI (placeholder: renders the VP table from the engine)
scripts/
  world.source.json  # researched roster + geography (edit to retune the map)
  build-data.mjs     # generator → board.ts + empires.ts (npm run gen:data)
tests/           # vitest (combat, scoring, game, heuristic, tournament, worldmap)
docs/SPEC.md     # canonical rules + data model + open questions
```

## Develop / build / test

| Command | What it does |
|---|---|
| `npm install` | Install deps (downloads the Electron binary unless `ELECTRON_SKIP_BINARY_DOWNLOAD=1`). |
| `npm run dev` | Launch the app with hot reload (electron-vite). |
| `npm test` | Run the vitest unit suite (engine; no Electron needed). |
| `npm run typecheck` | `tsc --noEmit` over the node + web tsconfig projects. |
| `./build-app.sh` | Build + install to `/Applications/Epochs.app` + relaunch with a freshness proof (repo standard). |

`./build-app.sh` supports `--no-install`, `--no-open`, and `BUILD_ONLY=1`.

> **Note:** `build-app.sh` / `install.sh` follow the PhantomLives `.app` standard
> but have not yet been exercised end-to-end (they need the Electron binary and a
> first real packaged build). Treat them as ready-to-validate, not yet proven.

## Default output location

Per repo convention, any user-visible output (saved games, exports) defaults to
`~/Downloads/Epochs/` (created on demand). Caches/config live under
`~/Library/Application Support/Epochs/`. (Not yet wired — placeholder for when
save/load lands.)
