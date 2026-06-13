# Changelog

All notable changes to PurpleMirror are documented here.

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
