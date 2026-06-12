# Purple Chef 👩‍🍳💜

A deliciously chaotic, Overcooked-style cooking showdown for macOS and Windows:
**you versus Chef Byte**, a rival AI chef, in mirrored kitchens racing the same
ticket stream. Chop, cook, plate and serve faster than the machine before the
clock hits zero.

Version **1.0.0** · Electron 31 + TypeScript + Canvas 2D · part of the
PhantomLives monorepo.

![What it is](USER_MANUAL.md)

## The game

- **Three kitchens**: Salad Days (chop & plate), Soup's On (pots, flames and a
  center island), Burger Blitz (the full grill brigade).
- **Three difficulties**: Novice 🌱, Chef 🍳, Master 🌶️ — tuning order pace,
  customer patience, recipe mix, and how fast/smart the rival AI plays.
- **Single player vs. AI**: both kitchens receive the *identical* seeded order
  schedule, so the race is provably fair. The AI plays through the exact same
  simulation input channel as you — same speed caps, same interaction rules.
- **Mouse and keyboard**: WASD/arrows + Space/E, or just click stations and
  your chef walks over and uses them (BFS pathfinding).
- **Scoring like the real thing**: base price + patience-scaled tip, a 4×
  in-order combo multiplier, penalties for expired tickets, 1–3 stars per
  match.
- **Score history & prizes**: every match is recorded (scoreboard with
  lifetime stats) and 12 cute trophies await — from the Bronze Whisk to the
  Grand Slam Garnish.

## Build & run (dev)

```bash
./build-app.sh        # build + install to /Applications + relaunch (macOS)
npm run dev           # hot-reload dev loop
npm test              # vitest — 49 tests
npm run typecheck     # tsc, node + web configs
```

`./build-app.sh` follows the PhantomLives standard: host-arch unpacked build,
then `install.sh` force-quits any running copy, installs to
`/Applications/Purple Chef.app`, relaunches, and proves process freshness.

Release artifacts: `npm run dist:mac` (universal2 DMG; needs Developer ID env)
and `npm run dist:win` (NSIS installer for Windows x64).

## Data & backup

- Save data (score history, trophies, prefs):
  `~/Library/Application Support/Purple Chef/` (macOS) / `%APPDATA%/Purple Chef/` (Windows).
- Launch-time auto-backup per the PhantomLives standard: zip to
  `~/Downloads/Purple Chef backup/`, 14-day retention, 5-minute debounce, full
  Settings → Backup UI (run-now / test / restore / reveal).

## Architecture

```
src/shared/    pure game brain (no Electron/DOM) — fully unit-tested
  types.ts       domain types
  recipes.ts     ingredients, dishes, multiset matching
  levels.ts      ASCII kitchen maps → tile grids
  difficulty.ts  the three tiers (orders, patience, AI tuning, physics)
  orders.ts      seeded deterministic order schedule + star thresholds
  sim.ts         the kitchen simulation (move/chop/cook/plate/serve/burn)
  ai.ts          the rival chef: reactive errand planner over SimInput
  match.ts       two kitchens, one clock, one winner
  prizes.ts      trophies + lifetime record folding
  path.ts        BFS pathfinding (AI + click-to-move share it)
src/main/      Electron main: window, JSON store, backup service, IPC
src/preload/   typed contextBridge API (window.purpleChef)
src/renderer/  canvas art (draw.ts), WebAudio sfx (sfx.ts), screens (main.ts)
```

All art and audio are **generated from code** — no binary assets, identical
rendering on both platforms.

## Icon

`python3 build/make_icon.py` (PIL) regenerates `icon_master_1024.png`,
`icon.icns` and `icon.ico` deterministically — per the PhantomLives app-icon
standard.
