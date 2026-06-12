# Changelog

All notable changes to Purple Chef.

## 1.0.0 — 2026-06-11

Initial release. 🎉

- Overcooked-style single-player cooking race vs. an AI rival ("Chef Byte")
  in mirrored kitchens fed an identical seeded order schedule.
- Three kitchens: Salad Days, Soup's On, Burger Blitz — ASCII-map driven.
- Three difficulty tiers (Novice / Chef / Master) tuning order pace, customer
  patience, recipe mix, kitchen physics (burn timers) and the AI's speed,
  reaction time and discipline.
- Full kitchen sim: crates, chopping boards (stand-to-chop), stoves with
  cook/overcook/burn lifecycle, plate stack, serving window, trash; tips,
  4× in-order combo, expiry penalties, 1–3 stars on auto-scaled thresholds.
- AI chef: reactive errand planner playing through the same SimInput channel
  as the player (same speed caps and interaction rules).
- Keyboard (WASD/arrows + Space/E) and mouse (click-to-move/use with BFS
  pathfinding) controls.
- Procedural canvas art and WebAudio-synthesized SFX + music — zero binary
  assets, identical on macOS and Windows.
- Score history + lifetime stats scoreboard; 12-trophy prize shelf with
  results-screen confetti.
- PhantomLives standards: launch-time auto-backup (zip → `~/Downloads/Purple
  Chef backup/`, 5-min debounce, 14-day retention, full Settings → Backup UI
  with Test/Restore), `build-app.sh` → `install.sh` chain with stale-instance
  kill + process-freshness proof, code-generated `.icns`/`.ico` app icon.
- Tests: 49 vitest cases — recipes/levels/orders/path/sim unit coverage,
  headless full-match integration proving the AI cooks in every kitchen at
  every difficulty, prize folding, and the backup-standard quartet (debounce,
  prefix-scoped retention, dir auto-create, newest-first listing).
