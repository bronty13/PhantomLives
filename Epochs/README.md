# Epochs

A digital strategy game of **empires that rise and fall across seven epochs**,
played solo against AI opponents. Epochs is an *original* recreation of the
*system* of the 1990s Avalon Hill board game *History of the World* (designed by
the Ragnar Brothers) — own map, own art, own wording, for **private personal
use**. See [`docs/SPEC.md`](docs/SPEC.md) for the full rules + data spec and the
legal posture (we reimplement uncopyrightable mechanics only).

> **Status: v0.2 — playable headless game.** A full 7-epoch game runs
> end-to-end and deterministically: catch-up draft → empire setup → expansion +
> combat → monuments → scoring → pre-eminence → ranked winner, with stub AI
> bots, all unit-tested against a small fixture map (42 tests). Still to come:
> the real 102-land board, the 49 empires, the event deck, the tunable heuristic
> AI, and the map UI (see `docs/SPEC.md` §14).

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
    bot.ts           Bot interface + GreedyStubBot / RandomBot
    sim.ts           headless game runner (runHeadlessGame / formatResult)
    data/
      areaValues.ts    the real per-epoch Victory-Point table (13 areas)
      fixtureMap.ts    small placeholder board until the real one is transcribed
      fixtureEmpires.ts synthetic empire deck until the 49 empires are transcribed
  main/          # Electron main process (window lifecycle)
  preload/       # contextBridge surface
  renderer/      # UI (placeholder: renders the VP table from the engine)
tests/           # vitest unit tests (combat, scoring, game)
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
