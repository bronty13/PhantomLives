# Purple Chef — User Manual 👩‍🍳💜

Welcome to your kitchen! This little book tells you everything about out-cooking
**Chef Byte**, your tireless robot rival.

## 1. What you're playing

Purple Chef is a one-round cooking race. You and Chef Byte each get an
**identical kitchen** and the **identical stream of customer orders**. Cook,
plate and serve as many tickets as you can in three minutes. More points wins.

## 2. Controls

| Action | How |
|---|---|
| Move | `W` `A` `S` `D` or arrow keys |
| Pick up / put down / pour / serve | `Space` or `E` (context-sensitive on the tile you face) |
| Walk somewhere with the mouse | Click a floor tile |
| Use a station with the mouse | Click the station — your chef walks over and uses it |
| Pause | `Esc` |

Chopping is automatic: stand facing a cutting board that has a choppable
ingredient on it, keep your hands empty and stand still — your chef chops away.

## 3. The stations

- **Crates** 🧺 — infinite ingredients. Face one and press Space to grab.
  (Holding a plate at the **bun crate** drops a bun straight onto the plate.)
- **Cutting board** 🔪 — place a raw ingredient, stand there, it gets chopped.
- **Stove** 🍲 — accepts **chopped** cookables. Soup wants **3 of the same
  veg**; a patty cooks **alone**. Watch the ring: yellow = cooking, green =
  done. A done pot left sizzling **catches fire** — scrape a burnt pot with
  empty hands.
- **Plate stack** 🍽️ — grab a clean plate. Hold the plate against prepared
  food (board, counter, done pot) to scoop it on.
- **Serving window** 🛎️ — face it holding a finished dish to serve. Wrong
  dish? It politely bounces.
- **Trash** 🗑️ — eats whatever you're holding (a held plate is emptied, not
  discarded).

## 4. Scoring

- Each dish pays its **base price + tip**. The tip shrinks as the customer's
  patience bar drains (green → yellow → red).
- Serving tickets **in order** grows a combo multiplier on your tips:
  ×2, ×3, up to **×4**. Serving out of order, or letting a ticket expire,
  resets it.
- An expired ticket costs **10 points** and a miss on your record.
- Score thresholds earn you **⭐ / ⭐⭐ / ⭐⭐⭐** per match (they scale with the
  kitchen and difficulty).

## 5. Difficulties

| | Orders | Patience | Chef Byte |
|---|---|---|---|
| **Novice** 🌱 | relaxed | very patient | slow, sleepy, long coffee breaks |
| **Chef** 🍳 | brisk | normal | quick and disciplined |
| **Master** 🌶️ | relentless | short | nearly perfect — bring your A-game |

## 6. Kitchens

1. **Salad Days** — lettuce & tomato, boards only. Learn the flow.
2. **Soup's On** — pots, a center island, and the eternal question: *did I
   leave the stove on?*
3. **Burger Blitz** — patties on the grill, cheese on the board, stack it tall.

## 7. Scoreboard & prizes

- **Scoreboard** 📋 — every match is saved: date, kitchen, difficulty, both
  scores, stars, dishes served/missed, best combo, plus lifetime totals.
- **Trophy Shelf** 🏆 — twelve prizes, from your first served dish (*Order
  Up!*) to winning every kitchen on Master (*Grand Slam Garnish*). New prizes
  pop with confetti on the results screen.

## 8. Settings

- **Chef name**, **sound effects**, **music** toggles.
- **Backup** — Purple Chef automatically zips your scores & settings to
  `~/Downloads/Purple Chef backup/` each launch (14-day retention by default).
  From Settings you can change the folder, run a backup now, **Test** an
  archive, **Restore** one (a safety backup is taken first), or reveal the
  folder in Finder.

## 9. Where things live

- Save data: `~/Library/Application Support/Purple Chef/` (macOS),
  `%APPDATA%/Purple Chef/` (Windows).
- Backups: `~/Downloads/Purple Chef backup/` (created on demand; configurable
  and persistent in Settings).

Happy cooking — may your combo never break! 💜
