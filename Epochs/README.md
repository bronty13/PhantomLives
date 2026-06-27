# Epochs

A digital strategy game of **empires that rise and fall across seven epochs**,
played solo against AI opponents. Epochs is an *original* recreation of the
*system* of the 1990s Avalon Hill board game *History of the World* (designed by
the Ragnar Brothers) — own map, own art, own wording, for **private personal
use**. See [`docs/SPEC.md`](docs/SPEC.md) for the full rules + data spec and the
legal posture (we reimplement uncopyrightable mechanics only).

> **Status: v0.6 — full rules + playable UI.** The whole game: 97-territory world,
> 49 historical empires, area-control scoring, **and the event system** (finite
> hands of Leaders/Weaponry/Reallocation/Minor-Empire + Coins→forts). Watch the
> AI or **play a seat** (click-to-place + an event panel), with a scoreboard,
> epoch HUD, and log. 79 tests. **Now a real app:** `./build-app.sh` builds +
> installs a signed `/Applications/Epochs.app`; or `npm run dev:web` (browser) /
> `npm run dev` (Electron) for development. Remaining: AI self-play re-tune, UI
> polish.

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
    mapProjection.ts pure map projection + hit-testing (shared with the UI)
    palette.ts       area + player colors
    data/
      areaValues.ts    the real per-epoch Victory-Point table (13 areas)
      board.ts         GENERATED — the 97-land real-geography world map
      empires.ts       GENERATED — the 49 historical empires (7×7)
      events.ts        the event deck (Greater + Lesser cards)
      fixtureMap.ts    small board for fast deterministic unit tests
      fixtureEmpires.ts small empire deck for unit tests
  main/          # Electron main process (window lifecycle)
  preload/       # contextBridge surface
  renderer/      # the game UI: main.ts (session + controls) + map.ts (Canvas)
scripts/
  world.source.json  # researched roster + geography (edit to retune the map)
  build-data.mjs     # generator → board.ts + empires.ts (npm run gen:data)
tests/           # vitest (combat, scoring, game, heuristic, tournament, worldmap,
                 #         session, projection, events)
docs/SPEC.md     # canonical rules + data model + open questions
```

## Develop / build / test

| Command | What it does |
|---|---|
| `npm install` | Install deps (downloads the Electron binary unless `ELECTRON_SKIP_BINARY_DOWNLOAD=1`). |
| `npm run dev:web` | **Play in a browser** — serves the map UI with Vite (no Electron). Open the printed URL. |
| `npm run dev` | Launch the full Electron app with hot reload. |
| `npm test` | Run the vitest unit suite (engine; no Electron needed). |
| `npm run typecheck` | `tsc --noEmit` over the node + web tsconfig projects. |
| `./build-app.sh` | Build + install to `/Applications/Epochs.app` + relaunch with a freshness proof (repo standard). |

`./build-app.sh` supports `--no-install`, `--no-open`, and `BUILD_ONLY=1`.

> `build-app.sh` / `install.sh` follow the PhantomLives `.app` standard
> (force-kill running instance → `ditto` to `/Applications` → relaunch →
> freshness proof) and are verified end-to-end. The app is **adhoc-signed** (local
> use; not notarized). The icon is generated from `build/icon.svg` via
> `build/make-icon.sh`.

## Default output location

Per repo convention, any user-visible output (saved games, exports) defaults to
`~/Downloads/Epochs/` (created on demand). Caches/config live under
`~/Library/Application Support/Epochs/`. (Not yet wired — placeholder for when
save/load lands.)
