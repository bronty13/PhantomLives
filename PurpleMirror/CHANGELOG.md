# Changelog

All notable changes to PurpleMirror are documented here.

## Unreleased

- **Remote hosts — monitor & control jobs on another Mac over SSH.** PurpleMirror can now watch
  the launchd jobs on a *remote* Mac (e.g. the dedicated archive "runner") alongside local ones,
  so the same instance on Vortex or MB14 sees everything in one place. Add a host under
  **Settings ▸ Hosts** (SSH user / host / optional identity file) with a **Test connection**
  button; its jobs appear grouped by host (e.g. "Runner · Photos"). Status, logs, and **Run Now**
  work remotely; schedule editing (enable/disable/interval) stays local-only for now. An
  unreachable host degrades gracefully (its jobs are kept and shown as unreachable, never dropped)
  and a slow/asleep host can't stall the refresh (per-host concurrent refresh, `BatchMode`+
  `ConnectTimeout`, SSH ControlMaster multiplexing). New `MonitoredHost`/`HostStore`/`HostContext`/
  `SSHCommand`; existing single-local-host installs are unchanged. (11 unit tests for the pure
  seams: argv builder, plist-from-bytes, host persistence.)

- **New menu actions: Eject Drives + Restart Safely…** A one-click guard against
  the macOS Tahoe 26 shutdown hang, where `diskarbitrationd` wedges in-kernel
  trying to unmount a still-mounted external drive (see `docs/reboot-hangs.md`).
  **Eject Drives** unmounts every external volume (discovered dynamically — any
  count of client drives — and *graceful only*, never forced, so client media is
  never yanked mid-write). **Restart Safely…** confirms, unmounts all externals,
  then restarts (falls back to "restart manually" if Automation access isn't
  granted). If a drive is busy it reports which and refuses to restart, rather
  than restart into a hang. `RebootSafeService` with pure, unit-tested parsers
  (5 tests). This is the GUI equivalent of the repo-root `reboot-safe` CLI.

- **New monitored bot: Favorites Harvest.** Profiles `com.bronty13.harvest-favorites`
  (the AppleScript agent that copies newly-Favorited Apple Music tracks into the
  "My Picks [PL]" playlist) under the **Bots** group. A tailored `.harvestFavorites`
  log parser surfaces its `OK favorited=M added=N mypicks_total=T` lines as
  "*T picks in My Picks*" (with a "*+N new*" detail), an "*Idle — Music not running*"
  skip, or a failure; the 24-hour tally sums new favorites harvested. (5 tests.)

- **Release zip opens cleanly on any Mac, however it's unzipped.** A plain
  `ditto -c -k` stored codesign's `com.apple.provenance` xattrs as AppleDouble
  (`._name`) sidecars; `unzip`/browser extractors leave them as `._Autoupdate`,
  `._Sparkle`, … in `Sparkle.framework`, which a clean Mac rejects as *"unsealed
  contents present in the root directory of an embedded framework"* (the *"could
  not verify is free of malware"* prompt). `Scripts/release.sh` now strips xattrs
  and zips with `--norsrc --noextattr`, plus an unzip-based gate that fails the
  release on any `._*` / staple / strict-codesign problem. (Fleet-wide fix.)

## 1.17.0 — 2026-06-16

- **A paused job no longer looks like a problem.** An agent that's intentionally unloaded
  (auto-run off — e.g. the Photo Archive while the off-site B2 seed runs) was rendered with the
  orange "Attention" warning glyph, identical to a job that actually needs looking at. It now has
  its own calm **`.paused` health state** ("Auto-run off", neutral `pause.circle` glyph in a
  secondary tint). `health()` maps an unloaded agent to `.paused` instead of `.warning`; a genuine
  attention state still comes only from a loaded agent whose last run failed (`.error`) or whose
  log shows a swallowed failure. `.paused` severity ranks below `.warning`/`.error` (so a
  deliberately-disabled job never drags the menu-bar glyph into an alarm) but above
  `.healthy`/`.running` (so an all-paused set still surfaces the pause glyph rather than a
  misleading checkmark). Tests updated (+1 case each in classification and severity ordering).

## 1.16.0 — 2026-06-15

- **Monitor brew-autoupdate.** PurpleMirror now recognizes `com.user.brew-autoupdate` (the Homebrew
  auto-update agent) — shown as "Homebrew Auto-Update" under a new **Maintenance** group — with a
  tailored `.brewAutoupdate` parser for its bracketed-timestamp stdout log. Because the script exits
  0 even when `brew` reports errors, health is read from the log's "[ERROR] ERRORS (N)" line:
  status shows "Updated packages" / "Up to date" / "Updated with N error(s)" (the last as a warning)
  / "Running…", with the run duration as detail. `shouldManage` now also admits any explicitly
  profiled label, not just the repo namespaces. Tests +7.
  - Note: brew-autoupdate is **calendar-scheduled** (`StartCalendarInterval`), so its "Run every"
    interval isn't meaningful — enable/disable, Run Now, and View Log work as normal.

## 1.15.1 — 2026-06-15

- **Fix: group headers + the menu-bar glyph could show a stale status after a job recovered.** A
  job's health lives on its `JobController`; when it changed, only that job's row (which observes the
  controller) re-rendered — the group header glyph and the aggregate menu-bar glyph (which `MenuView`
  derives from `JobsModel`) stayed frozen, because `JobsModel` didn't re-publish on a child change.
  `JobsModel` now forwards each `JobController`'s `objectWillChange`, so the whole menu re-renders
  when any job's status changes. (Surfaced by the ATW bot's section showing "error" after its run had
  already gone green.)

## 1.15.0 — 2026-06-15

- **Obsidian status now shows what changed, and counts toward the 24h tally.** The sync script now
  logs per-run deltas ("Updated K of N markdown file(s)" / "No markdown changes"); PurpleMirror's
  Obsidian parser prefers that for the status line ("Updated 3 files" / "Up to date") instead of the
  static total ("Mirrored 456 files"), and the **24h tally** now sums those deltas for Obsidian
  (previously excluded). Old logs that only have the "Mirrored N" total still fall back cleanly and
  are left out of the tally (a total isn't a delta). Tests +3 (52 total).

## 1.14.0 — 2026-06-15

- **Recognize the ATW repost bot** (`com.bronty13.atw-repost-bot`) as a first-class job: "ATW Repost
  Bot" under a new **Bots** group, with a tailored `.atwRepost` log parser that surfaces "Reposted N
  listing(s)" / "Up to date — nothing to repost" / "Run failed", and feeds the 24h tally (sum of
  reposts submitted per pass). The bot is a Node/Playwright agent that runs hourly via launchd
  (single-pass per invocation); it's auto-discovered like the rest, this just gives it a proper name
  + status + tally. Tests +4.

## 1.13.0 — 2026-06-15

- **24-hour "new items" tally.** Each job now shows how many new items it found/archived in the last
  24 hours, summed across that window's runs: a per-job badge ("… · 12 in 24h"), a per-source total
  on each group header ("12 new / 24h"), and a grand total in the menu header ("… · 37 new in 24h").
  Kind-aware so the numbers mean something: pull archives sum their per-run deltas (`staged N NEW`),
  Tier-1 archivers sum `+N new …`, the photo archive sums `N new items`, and the Obsidian mirror —
  which re-mirrors the whole set every run — is excluded rather than reported as a misleading sum.
- Tests: +6 covering the windowing, per-kind summing, the no-new-items-is-zero (not nil) case, and
  the excluded kinds.

## 1.12.0 — 2026-06-15

- **Settings and Logs both use a grouped sidebar now, not "tabs across the top."** The old
  segmented/dropdown job pickers became unreadable once a dozen+ jobs were managed (photo archive,
  messages, notes, reminders, safari, voice memos, calls, calendar, books, podcasts, stickies,
  landing pages, Obsidian…). Both windows now have a fixed-width left **sidebar that lists every job
  grouped by source** (each with a health glyph + count); Settings shows the selected job's
  schedule/locations on the right (under a name+status header), and the Logs window shows that job's
  log (the in-toolbar picker is gone; the toolbar now just names the selected job + its controls).
  Selection is shared, so picking a job in one window carries to the other.
- Internal: a single reusable `JobSidebar` view backs both windows, and the health→color mapping
  (previously duplicated 3× in `MenuView`) is now one `SyncStatusParser.Health.color` extension
  reused by the menu and the sidebar.

## 1.11.0 — 2026-06-15

- **Recognize PurpleAttic's local Photo Archive job** (`com.bronty13.PurpleAttic.archive`)
  with a tailored "Photo Archive" profile (group "Photos") and a new `.purpleAttic` log
  parser. It reads pattic's run log (`~/Library/Logs/PurpleAttic/scheduler.out.log`) and
  surfaces live status: **Archive up to date**, **Waiting for drives** (a drive isn't
  attached — a clean no-op), **Skipped (already running)** (the single-writer lock held),
  the current phase while a run is mid-flight, the per-destination **off-site tally** (e.g.
  Backblaze B2), and run failures. This is distinct from the external-source *pull* jobs,
  which keep the `.purpleAtticSync` parser.

## 1.10.0 — 2026-06-14

- **Recognize the per-source Landing Page job** (`external-index-sync.<id>` → "External Landing Page Sync — <Id>"), grouped under its source.

## 1.9.0 — 2026-06-14

- **Recognize Podcasts + Stickies external jobs** (Phase-3 small wins).

## 1.8.0 — 2026-06-14

- **Recognize the Phase-2 kinds: Calendar + Books** (`external-calendar-sync.<id>`,
  `external-books-sync.<id>`). They group under their source like the rest.

## 1.7.0 — 2026-06-14

- **Jobs are now grouped by source.** With many per-source archives (photo,
  messages, notes, reminders, safari, voice memos, calls…), the menu groups jobs
  under a collapsible header per source (e.g. **Rachel**), with that group's
  worst-health glyph and a job count. Each job still runs/enables/schedules
  **individually** (Run Now + View Log per row); rows now show the compact kind
  ("Photo", "Voice Memos", …) since the group header carries the source name.
  Obsidian / unknown agents fall under their own groups. The list scrolls when tall.

## 1.6.0 — 2026-06-14

- **Recognize the Tier-1 apple-archiver job kinds: Safari, Voice Memos, Calls.**
  Adds `external-safari-sync.<id>`, `external-voicememos-sync.<id>`, and
  `external-calls-sync.<id>` to the pattern recognizer. The activity-log path is
  now derived from the label *token* (not the display name), so multi-word kinds
  like "Voice Memos" map correctly to `external-voicememos-sync-<id>.log`.

## 1.5.0 — 2026-06-14

- **Recognize the new external-source job kinds: Notes + Reminders.** Adds
  `com.bronty13.external-notes-sync.<id>` → "External Notes Sync — <Id>" and
  `external-reminders-sync.<id>` → "External Reminders Sync — <Id>" to the
  pattern-based recognizer (alongside Photo + Messages), with the matching
  PurpleAttic-style log parsing and derived activity-log paths. Driven by
  `apple-archiver`. Still no source name in code.

## 1.4.0 — 2026-06-14

- **Generic, config-driven external-source profiles (no source name in code).**
  PurpleAttic's per-source archive jobs are now labelled
  `com.bronty13.external-photo-sync.<id>` / `external-messages-sync.<id>`.
  PurpleMirror recognizes them by *pattern* and derives the display name +
  activity-log path from the label's kind + source id — e.g.
  `…external-photo-sync.<id>` → "External Photo Sync — <Id>". Onboarding a new
  source (configured in PurpleAttic's `external-sources.json`) needs no PurpleMirror
  change; the row appears automatically with the right name.

## 1.3.0 — 2026-06-14

- **Tailored profile for PurpleAttic's Apple Messages archive job** — gives the
  per-source messages sync a friendly name, its real activity log, and
  PurpleAttic-style log parsing (staged N new / no new items / pull exit), so it
  reads like the photo-sync row. (Superseded by the generic recognizer in 1.4.0.)

## 1.2.0 — 2026-06-13

- **Multi-job background-jobs dashboard.** PurpleMirror is no longer Obsidian-only:
  it now **auto-discovers every PhantomLives launchd agent** in
  `~/Library/LaunchAgents` (labels under `com.phantomlives.*` / `com.bronty13.*`)
  and shows one row per job. Out of the box that surfaces both the **Obsidian
  Sync** and PurpleAttic's per-source archive jobs; any agent added later appears
  automatically (no relaunch).
- **Full per-job control.** Each job has its own **Run Now**, **enable/disable**,
  and **interval** controls, plus its **own log** in the log window (pick the job
  from the toolbar). Known jobs get tailored status parsing — Obsidian shows
  "Mirrored N files", external archives show "Staged N new / No new items / Pull
  failed (exit N)"; unknown jobs get a generic last-line summary.
- **Two scheduling backends.** Script-managed jobs (Obsidian) still go through the
  script's `--install-agent` / `--uninstall-agent`. Plist-managed jobs (PurpleAttic's
  hand-written agents) are controlled directly: enable/disable via
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
