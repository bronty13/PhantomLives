# Changelog

All notable changes to PurpleMirror are documented here.

## 1.2.0 — 2026-06-13

- **Multi-job background-jobs dashboard.** PurpleMirror is no longer Obsidian-only:
  it now **auto-discovers every PhantomLives launchd agent** in
  `~/Library/LaunchAgents` (labels under `com.phantomlives.*` / `com.bronty13.*`)
  and shows one row per job. Out of the box that surfaces both the **Obsidian
  Sync** and PurpleAttic's **Rachel Photo Sync**; any agent added later appears
  automatically (no relaunch).
- **Full per-job control.** Each job has its own **Run Now**, **enable/disable**,
  and **interval** controls, plus its **own log** in the log window (pick the job
  from the toolbar). Known jobs get tailored status parsing — Obsidian shows
  "Mirrored N files", Rachel shows "Staged N new / No new items / Pull failed
  (exit N)"; unknown jobs get a generic last-line summary.
- **Two scheduling backends.** Script-managed jobs (Obsidian) still go through the
  script's `--install-agent` / `--uninstall-agent`. Plist-managed jobs (Rachel's
  hand-written agent) are controlled directly: enable/disable via
  `launchctl bootstrap/bootout`, and an interval change **safely rewrites only the
  plist's `StartInterval`** (keeping a backup and restoring it if the reload fails)
  so an operational backup plist can't be left broken.
- **Menu-bar glyph reflects the worst job's health**; per-job failure
  notifications (once per failed run) now name the job.
- Internals: `SyncController` → one `JobController` per agent owned by a new
  `JobsModel`; new pure, unit-tested `LaunchAgentPlist` (descriptor parse +
  `StartInterval` edit) and `JobRegistry` (discovery filter + profiles). Tests
  grew 10 → 28.

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
- Build hygiene: plain `./build-app.sh` dev builds skip notarization (gated on
  `NOTARIZE=1`, which only `Scripts/release.sh` sets) — local builds stay fast
  and Developer-ID-signed; notarization is reserved for tagged releases.

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
