# Changelog

All notable changes to PurpleMirror are documented here.

## 1.1.0 — 2026-06-13

- **Sparkle 2 auto-update.** The app now self-updates: a "Check for Updates…"
  item in the menu, automatic daily background checks, and a notarized/EdDSA-signed
  release feed (`appcast.xml` via raw.githubusercontent). Cut releases with
  `./Scripts/release.sh` (see `RELEASING.md`). Reuses the shared PhantomLives
  Developer-ID cert, `PurpleDedup-Notary` profile, and Sparkle key.
- **Live log tail.** The log window now auto-refreshes and follows the end of the
  log every 1.5s (toggle "Live tail"); still has manual Refresh + Last-200-lines.
- **Failure alerts.** PurpleMirror posts a macOS notification when a sync run
  fails (non-zero exit), once per failed run, in addition to turning the menu-bar
  glyph red. Requests notification permission on first launch.
- Menu now shows the running version.

## 1.0.0 — 2026-06-13

Initial release.

- Menu-bar (`MenuBarExtra`, `LSUIElement`) companion for the repo's
  `sync-md-to-obsidian.sh` Markdown→Obsidian mirror.
- **Status panel**: health glyph in the menu bar (up-to-date / syncing /
  auto-sync-off / failed), last sync time, files mirrored, auto-sync state +
  interval, last result, and target vault.
- **Sync Now**: kickstarts the installed launchd agent (honoring its baked-in
  vault), or runs the script directly if the agent isn't installed.
- **Settings**: toggle automatic background sync (install/uninstall the agent),
  change the interval (presets + custom minutes), and view/choose the script
  path + see the target vault.
- **View Log** window: tails `~/Library/Logs/phantomlives-obsidian-sync.log`
  with refresh, reveal-in-Finder, and open-in-Console.
- Thin GUI by design — the shell script remains the single source of truth; the
  app never reimplements the mirror logic.
- Icon generated deterministically from `Scripts/generate-icon.swift`.
- 9 unit tests over the pure status-parsing/formatting logic.
