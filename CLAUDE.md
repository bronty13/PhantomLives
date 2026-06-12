# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Research Before Guessing

- For third-party APIs/schemas (Slack manifests, CloudKit, Tauri ACL, electron-builder, GitHub Actions workflows), research official docs FIRST before attempting code. Do not paste-and-retry.
- When debugging environment issues (Finder-launched apps, signing, permissions), check PATH/entitlements/capabilities before blaming the tool.

## Cross-Mac dev setup

**This repo must live at `~/dev/PhantomLives/`. It must NOT live anywhere under `~/Documents/` or `~/Desktop/`.** The maintainer works across two Macs with different usernames; `~/dev/` is consistent on both and stays out of iCloud's reach — `~/Documents/` is iCloud-synced and corrupts build artifacts (` 2`-suffixed dupes), throttles `mv`/`ditto`, and slows every syscall.

→ Full detail (why `~/Documents/` breaks builds, how to migrate a checkout out of it, the per-Mac one-time setup checklist for Xcode / signing / Sparkle / notarytool / Homebrew / git hooks) is in **`docs/cross-mac-dev-setup.md`** — read it when migrating a checkout or setting up a new machine.

## Repository shape

PhantomLives is a polyglot monorepo of **independent personal/utility projects**, not a single application. Each top-level directory is its own self-contained project with its own README, CHANGELOG, install script, tests, and version number. There is no top-level build, lint, or test command — work always happens inside one subproject at a time.

Stacks in use across subprojects: Bash, Python (with self-bootstrapping `.venv`s), Swift (SwiftPM + SwiftUI macOS apps).

### Nested git repositories

Two subdirectories are **separate git repos**, not part of PhantomLives. Run `git` inside their directory; commits made from the repo root will not include them, and pushing the outer repo will not push them. They surface as untracked entries in the outer repo's `git status` — leave them alone (don't `git add` them):

- `video-analyzer/` — fork of `byjlw/video-analyzer` (different `origin`)
- `ClipperInfo/` — `bronty13/ClipperInfo` (a standalone info/landing page; `index.html`)

Everything else (including `MusicJournal/`, `fsearch/`, `PurpleIRC/`, `messages-exporter/`, etc.) lives in the outer `bronty13/PhantomLives` repo. (`MusicJournal/` was briefly an independent repo before being imported into PhantomLives at commit `58f3d35`.)

## Repo-level utilities

A small number of scripts live at the **repo root** and operate across the
whole monorepo rather than inside one subproject:

- **`sync-md-to-obsidian.sh`** — one-way, incremental mirror of every
  git-tracked `.md` file into a real `PhantomLives/` folder inside an Obsidian
  vault, for reading the docs in Obsidian. Optionally self-installs a launchd
  agent (`--install-agent [interval]` / `--uninstall-agent`) that refreshes
  hourly. The vault is usually iCloud-synced, which (a) strips symlinks — so
  the mirror must be a real folder, not a symlink — and (b) is TCC-protected,
  so the **background agent requires a one-time Full Disk Access grant on
  `/bin/bash`** to write there. → Full detail (the iCloud/symlink + TCC/FDA
  rationale, why git-tracked precision over an rsync `*.md` filter, cross-Mac
  setup, operational commands) is in **`docs/obsidian-sync.md`**.

## Release-hygiene rules (from `.github/copilot-instructions.md`)

These apply to **every** code, config, script, test, or doc change. Do not skip them — most subprojects already follow them rigorously:

1. Bump the version number consistently across script, docs, and any version output the tool prints.
2. Add a CHANGELOG entry describing what changed and why.
3. Update affected docs (`README.md`, and `USER_MANUAL.md` where one exists).
4. Update in-code version constants and any comments that describe behavior you changed.
5. Add or update tests for bug fixes, regressions, and new behavior.
6. Update operational files (config defaults, installers, helper scripts, command help text) when relevant.
7. If a hygiene item genuinely doesn't apply, explicitly say why in the commit/PR notes.

## Molly release messaging — a love note from Molly to Sallie

**Every time we cut a Molly release, replace the auto-generated GitHub release body with a hand-crafted, 200%-cute first-person message from Molly to Sallie — and update USER_MANUAL.md + other Sallie-facing docs (`WHATS_NEW_*.md`, in-app help) in the same voice. A doc out of step with the app is a release blocker.**

→ The full voice guide, tone rules, message skeleton, required content (diff window, Windows-only test steps, concrete click path, regression check), and `gh release edit` workflow live in **`docs/molly-release-messaging.md`** — read it before cutting any Molly release.

## SQL migrations are immutable

Once a migration file has been added to a release (committed to `main` AND/OR applied to any developer's local database), **never edit it**. `tauri-plugin-sql` and similar runtime migrators hash the migration file at every launch and refuse to start when the hash doesn't match the stored value — that's the "migration N was previously applied but has been modified" crash.

To change schema or data already covered by a shipped migration:

- **Add a new migration** (e.g. `017_xxx.sql`) that applies the change via `ALTER TABLE`, `UPDATE`, or a table-rebuild dance.
- A new install runs both the original migration and the follow-up in sequence, landing at the same end state as an existing install that only runs the follow-up.

This applies even to comment-only edits — the file's bytes are what get hashed.

**Guardrail** (SideMolly reference): `cargo test migration_immutability` re-hashes every shipped migration at compile time and asserts against a frozen `EXPECTED_MIGRATION_HASHES` constant. Adding a new migration produces a clear "append `(N, "<hash>"),` to the constant" message; editing an existing one fails with "migration N has been modified post-ship — revert and add a new migration instead." See `SideMolly/src-tauri/src/lib.rs::migration_immutability` for the pattern; lift verbatim into any other PhantomLives subproject that uses migration files.

Incident reference: SideMolly v0.13.1 (2026-05-24) — edited migration 013 in place to change a `DEFAULT` value, broke launch for every install that had run v0.13.0. Fixed by reverting 013 to its v0.13.0 bytes; migration 014 already covered the data update.

## Default output location

Every PhantomLives tool that writes user-visible output (exports, transcripts, reports, generated files, baselines, etc.) **must** default its output path to:

```
~/Downloads/<project-or-app-name>/
```

The folder name matches the subproject directory or the app's display name (e.g. `~/Downloads/messages-exporter-gui/`, `~/Downloads/transcribe/`, `~/Downloads/MacSysInfo/`). Tools that further organize each run into a timestamped subfolder do so *inside* this directory (e.g. `~/Downloads/messages-exporter-gui/<contact>_<YYYYMMDD_HHMMSS>/`).

Rules:

- The default must be created on demand — don't fail if `~/Downloads/<name>/` doesn't exist yet; `mkdir -p` it.
- Users can override (CLI flag, Settings pane, env var) but the override must persist (UserDefaults / config file) so it sticks across runs.
- Document the default in `README.md` and `USER_MANUAL.md`.
- Internal caches, logs, and config still live under `~/Library/Application Support/<name>/` or `~/.config/<name>/` — this rule is only for things the user is meant to find and open.

## Auto-backup-on-launch

Every PhantomLives app that owns persistent user data (a SQLite DB, JSON store, or settings bundle the user can't easily recreate) **must** run an automatic backup on launch (zip of `~/Library/Application Support/<AppName>/` → `~/Downloads/<AppName> backup/`, 14-day retention, 5-min debounce, never throws) **and** ship the full Settings → Backup UI. Both are ship blockers if missing.

→ Full spec (filename convention, retention/debounce/failure behavior, complete required-UI checklist, required tests, and the `Timeliner` reference implementation) is in **`docs/auto-backup-on-launch.md`** — read it when adding or auditing backup support.

## Sidebar layout: avoid `NavigationSplitView`

**For new macOS apps: do NOT use `NavigationSplitView` for the top-level sidebar. Use a manual `HStack` with a fixed-width `.frame(width:)` sidebar** (the MusicJournal/PurpleReel pattern). `NavigationSplitView` on macOS 14+ does not reliably honor its column-width constraints and mis-restores persisted divider state — this codebase has burned through three+ fix attempts.

→ The bug writeup, copy-verbatim `ContentView` + `WindowStateGuard` code, reference files, and the list of apps still on `NavigationSplitView` (retrofit on next touch) are in **`docs/sidebar-layout.md`** — read it before building a new app's top-level layout or touching window-state code.

## `install.sh` standard for `.app` subprojects

**Every PhantomLives macOS-app subproject (anything with a `build-app.sh` that produces a `.app` bundle) ships an `install.sh`, and `build-app.sh` auto-chains into it** — so `./build-app.sh` defaults to *build + install (to `/Applications/<App>.app` via `ditto --noextattr`) + relaunch*, with `--no-install` / `--no-open` / `BUILD_ONLY=1` opt-outs. Installing to `/Applications/` (not the project tree) keeps TCC grants, Launch Services, and codesigning stable. Pure CLI/Python tools are exempt.

→ Full detail (the three install steps, the canonical `build-app.sh` chain block, developer-workflow command table, the `/Applications/` rationale, and the `.claude/settings.local.json` permission rules) is in **`docs/install-sh-standard.md`** — read it when creating or fixing a subproject's `install.sh`/`build-app.sh`.

## App-icon standard for `.app` subprojects

**Every PhantomLives macOS-app subproject generates its app icon *deterministically from code* — `Scripts/generate-icon.swift` → `iconutil` → `AppIcon.icns` — wired into the bundle via `CFBundleIconFile` (or, for asset-catalog apps, an `AppIcon.appiconset` compiled to `Assets.car`). No binary icon source (PNG/`.icns`/`.xcassets` blobs) is the source of truth.** Code-generation is the *multi-machine* requirement: the maintainer's two Macs sync only through git at `~/dev/`, and a plain-text generator diffs/merges cleanly and rebuilds byte-identical on either host — a checked-in binary asset would drift, bloat the repo, and (if a checkout ever strays under `~/Documents/`) catch iCloud `' 2'`-dupe corruption. An app showing the generic Swift icon in Finder/Dock is **not done**.

The trap to avoid: `PlistBuddy Set :CFBundleIconFile` **silently no-ops when the key is absent** — always declare the key in the source `Info.plist` *and* use set-or-add (`Set … || Add … string …`) in `build-app.sh`, doing the icon install before codesign. (Incident: PurpleArchive shipped no icon from first release to v1.0.714 for exactly this reason.)

→ Full detail (the multi-machine rationale, both wiring mechanisms, the canonical `build-app.sh` icon block, the silent-`Set` incident, and the headless verification checklist) is in **`docs/app-icon-standard.md`** — read it when creating or fixing a subproject's icon. After any icon change also run the **Icon / UI change verification sequence** below.

## Per-subproject commands

| Subproject | Build / Run | Tests |
|---|---|---|
| `PurpleIRC/` (Swift, SwiftUI macOS app) | `./build-app.sh` → `PurpleIRC.app` (or `swift build`; `CONFIG=debug` for debug). UI only activates from the `.app` bundle. | `./run-tests.sh` — wrapper that adds `Testing.framework` rpath for Command Line Tools setups; plain `swift test` works with full Xcode. |
| `MusicJournal/` (Swift, SwiftUI macOS app) | XcodeGen project (`project.yml`); regenerate with `xcodegen generate`, build via `MusicJournal.xcodeproj`. Depends on GRDB. | `xcodebuild test` (no test targets currently configured in `project.yml`). |
| `Timeliner/` (Swift, SwiftUI macOS app) | `./build-app.sh` → `Timeliner.app` (XcodeGen + GRDB; produces a Developer-ID-signed `.app`). Auto-runs the launch-time backup standard (see `docs/auto-backup-on-launch.md`). | `./run-tests.sh` — XCTest, 18 tests across migration / Codable / search / export / backup. |
| `SlackSucker/` (Swift, SwiftUI macOS app wrapping the `slackdump` CLI) | `./build-app.sh` → `SlackSucker.app` (plain SwiftPM; bundles the slackdump binary from `$SLACKDUMP_BIN` or `which slackdump`; Developer-ID-signed). Then `./install.sh` to deploy to `/Applications/`. Auto-runs the launch-time backup standard (see `docs/auto-backup-on-launch.md`). | `./run-tests.sh` — Swift Testing, 41 tests across argv building / line buffer / stdout parsing / channel JSON parser / file organizer / chat exporter / settings round-trip / backup debounce + retention + listing. |
| `PurplePDF/` (TypeScript, Electron 31 + React 18 + Vite, cross-platform macOS/Windows PDF reader & editor) | `./build-app.sh` → `Purple PDF.app` in `/Applications/` (host-arch, adhoc-signed, build + install + relaunch in one shot; `--no-install` / `--no-open` / `BUILD_ONLY=1` opt-outs). `npm install` runs automatically on first invocation. Universal2 release DMG via `scripts/build-app.sh` or `npm run dist:mac` (needs Apple Developer ID + notarization env). | `npm test` — vitest, 22 tests across `projectOrder`, `autosave`, `images-to-pdf`, `bump-and-log`, and a smoke test. `npm run typecheck` for `tsc --noEmit` against `tsconfig.node.json` + `tsconfig.web.json`. |
| `PurpleTree/` (TypeScript, Electron 31 + React 18 + Vite, cross-platform macOS/Windows disk-space analyzer & file-cleanup utility — TreeSize/WinDirStat/DaisyDisk equivalent) | `./build-app.sh` → `Purple Tree.app` in `/Applications/` (host-arch, adhoc-signed, build + install + relaunch; `--no-install` / `--no-open` / `BUILD_ONLY=1` opt-outs). `npm install` runs automatically on first invocation. Universal2 release DMG via `npm run dist:mac`. Scan engine runs in a Node `worker_thread` (`src/main/scan/scanWorker.ts`, a 2nd electron-vite main input). ESM-only deps (`d3-hierarchy`, `xxhash-wasm`) are excluded from `externalizeDepsPlugin` so they bundle as CJS. | `npm test` — vitest, 53 unit tests (`protectedPaths`, `dupePipeline`, `tokens`, `report`, `tree`, `backup`) + 1 built-worker integration test (`tests/integration/scanWorker.test.ts`). `npm run typecheck` for `tsc --noEmit` against `tsconfig.node.json` + `tsconfig.web.json`. |
| `PurpleMind/` (TypeScript, **Tauri 2** + React 19 + Vite + Tailwind + SQLite, cross-platform macOS/Windows mindmap studio — MindNode equivalent) | `./build-app.sh` → `PurpleMind.app` in `/Applications/` (`pnpm tauri build`, adhoc-signed, build + install + relaunch; `--no-install` / `--no-open` / `BUILD_ONLY=1` opt-outs). `pnpm install` runs automatically. Dev: `pnpm tauri:dev` (Vite on **port 1422**). Windows `.exe` + signed updater feed come from CI on a `purplemind-v*` tag. Auto-runs the launch-time backup standard. Uses `tauri-plugin-sql` migrations (immutability-guarded) + `tauri-plugin-clipboard-manager`. | `./run-tests.sh` — `cargo test --lib` (18: backup, camelCase boundary, migration smoke + immutability) **and** `pnpm test` (vitest: pure libs `autoLayout`/bilateral, `branchStyle`, `visibility`, `ribbon`, `markdownOutline`, `mapSerialize`, `mermaid` + DOM tests `Sidebar`/`ExportMenu` via RTL+jsdom). `pnpm typecheck` for `tsc -b --noEmit`. |
| `PurpleMark/` (Swift, SwiftUI macOS app — native Markdown editor + default `.md` handler + Finder Quick Look previewer, OpenMark-style) | `./build-app.sh` → `PurpleMark.app` in `/Applications/` (XcodeGen, Developer-ID-or-adhoc-signed, build + install + relaunch; `--no-install` / `--no-open` / `BUILD_ONLY=1` opt-outs). Five targets: app, `PurpleMarkRenderCore` framework (bundled offline markdown-it + Mermaid + KaTeX + the Finder thumbnail renderer), `PurpleMarkQuickLook` `QLPreviewProvider` (spacebar preview) + `PurpleMarkThumbnail` `QLThumbnailProvider` (content-aware `.md` icon) app-extensions, tests. Single-pane Document⇄Markdown toggle; multi-document in-app tabs (single `Window` scene); custom theme editor (ThemeColors via inline CSS vars, persisted); first-run "set as default" prompt; Sparkle 2 auto-update (`Scripts/release.sh` → notarized+stapled DMG + appcast; see `RELEASING.md`); auto-runs the launch-time backup standard (scoped to prefs/recents — docs are user files). | `./run-tests.sh` — XCTest, 33 tests (outline parse, doc stats, standalone-HTML render + font inlining, thumbnail preview-lines, backup zip/retention, HTML export, settings round-trip, file filtering). |
| `PurpleAttic/` (Swift, SwiftUI macOS app — Photos-library archiver: osxphotos export → verified 3-copy archive, a guarded PhotoKit purge, and a launchd scheduler) | `./build-app.sh` → `PurpleAttic.app` in `/Applications/` (plain SwiftPM, Developer-ID-or-adhoc-signed, build + install + relaunch; `--no-install` / `--no-open` / `BUILD_ONLY=1` opt-outs). Bundles the `pattic` CLI inside the `.app`. Needs `osxphotos` (`pipx install osxphotos`) + `exiftool` at runtime; `rsync` ships with macOS. Auto-runs the launch-time backup standard (config only — the photo archive has its own 3-copy strategy). Purge ships **OFF**; deletion is PhotoKit and GUI-only (never in the CLI/scheduler). See `PurpleAttic/HANDOFF.md`. | `swift test` — 39 tests (retention predicate, osxphotos argv, Optimize-Storage library guard, Cryptomator vault status, purge planner + ≥2-copy verify, schedule/launchd plist). |
| `PurpleSpace/` (TypeScript, Electron 31 + React 19 + Vite, macOS Notion-style personal workspace — nested pages, BlockNote block editor, database tables) | `./build-app.sh` → `Purple Space.app` in `/Applications/` (host-arch, adhoc-signed, build + install + relaunch; `--no-install` / `--no-open` / `BUILD_ONLY=1` opt-outs). Embeds the open-source **`convex-local-backend`** (pinned tag; staged into `resources/` from the convex CLI's binary cache by `scripts/fetch-backend.sh`) — spawned on launch at `127.0.0.1:47800`, no Convex account/docker/network; data in `~/Library/Application Support/Purple Space/convex/`. After editing `convex/` functions run `npm run deploy-functions` (build-app.sh always does). Auto-runs the launch-time backup standard (backup happens BEFORE the backend starts so the SQLite is quiescent). | `npm test` — vitest, 37 tests (backup, tree, db sort/filter/markdown). `npm run typecheck` for both tsconfig projects. |
| `PurpleChef/` (TypeScript, Electron 31 + Canvas 2D, cross-platform macOS/Windows **game** — Overcooked-style cooking race vs. an AI chef) | `./build-app.sh` → `Purple Chef.app` in `/Applications/` (host-arch, adhoc-signed, build + install + relaunch; `--no-install` / `--no-open` / `BUILD_ONLY=1` opt-outs). `npm install` runs automatically on first invocation. Windows installer via `npm run dist:win`. Pure-logic game brain lives in `src/shared/` (sim, AI, levels, recipes, prizes — no Electron/DOM imports). All art/SFX generated from code (canvas + WebAudio); icon via `python3 build/make_icon.py`. Auto-runs the launch-time backup standard. | `npm test` — vitest, 49 tests (recipes/levels/orders/path/sim units, headless full-match AI integration per kitchen × difficulty, prizes, backup debounce/retention/auto-create/ordering). `npm run typecheck` for `tsc --noEmit` against both tsconfigs. |
| `messages-exporter/` (Python) | `./install.sh` (user) or `./install.sh --system` (sudo). Then `export_messages "<contact>" --start ... --end ...`. Requires Full Disk Access for the terminal. | `python3 test_export_messages.py` |
| `fsearch/` (Bash) | `./install.sh` (user) or `./install.sh --system`. Run as `fsearch ...`. | `./test_fsearch.sh` (also `fsearch-test` smoke script) |
| `brew-autoupdate/` (Bash + launchd) | `bash install.sh` — installs to `~/.config/brew-autoupdate/`, sets up launchd, creates the `brew-logs` viewer. | `bash test_brew_autoupdate.sh` |
| `transcribe/` (Python, Apple MLX) | `python3 transcribe.py -i <file>` — auto-creates `.venv`, installs deps (mlx, mlx-whisper, mlx-lm), and re-execs itself inside it on first run. Apple Silicon only. | No test suite. |
| `tictactoe/` (Python) | `python3 tictactoe.py` | `python3 test_tictactoe.py` |
| `diskspace/` (Python, single-file) | `python3 diskspace.py` | No test suite. |
| `macsysinfo/` (Bash) | `./MacSysInfo.sh` (supports `--json`, `--csv`, baseline save/compare, section filters). | No test suite. |
| `video-analyzer/` (Python, separate repo) | `pip install -e .` then `video-analyzer ...`. See its own `readme.md`. | `python3 test_prompt_loading.py` |
| `claude-servicenow-integration/` | Documentation only — no code. |
| `assessment/` | Empty data/log/session scaffolding; no code. |

When a subproject's Python code uses a self-bootstrapping `.venv` (e.g. `transcribe`, `messages-exporter` after install), do **not** create your own venv on top — the script's shebang or first-run logic handles it.

## PurpleIRC architecture (the largest subproject)

`PurpleIRC/HANDOFF.md` is the canonical architecture snapshot — read it before non-trivial changes. A quick mental model (`ChatModel` → `IRCConnection` → `IRCClient`, the `IRCConnectionEvent` fan-out, `EncryptedJSON`/`KeyStore` persistence, git-derived bundle versioning, and the "must launch from the `.app` bundle" rule) is in **`docs/purpleirc-architecture.md`** — read it before working in PurpleIRC.

## Git Workflow

- **Before starting work on a subproject, run a quick `git pull --rebase` from the repo root.** The maintainer works across two Macs and pushes directly to `main`, so the remote routinely advances between sessions. Rebasing up front keeps history linear and avoids the stash → rebase → resolve-conflict dance that a stale local `main` forces at push time. If the working tree is dirty, `git stash` first, rebase, then `git stash pop`.
- Always verify the current working directory (cwd) matches the intended project before running git init, commit, or push.
- After committing, always push to remote unless explicitly told otherwise — downstream tools (e.g., /ultraplan) require pushed commits.
- Never sweep unrelated changes into commits; run `git status` and `git diff --staged` before committing.
- Use feature branches and PRs when direct push to main is blocked.

## Build & Verify

- **End-of-task default: build + install + launch — every time, no asking.**
  For any subproject that ships a `build-app.sh` (i.e. has a `.app` bundle
  — Molly, SideMolly, PurpleIRC, MusicJournal, Timeliner, SlackSucker,
  PurplePDF, PurpleTree, PurpleMind, PurpleLife, MasterClipper, PurpleReel,
  PurpleDedup, PurpleTracker, PurpleAttic, and any future siblings), finish every code-touching
  task by running `./build-app.sh` from the subproject root. That script
  builds the `.app`, replaces `/Applications/<App>.app` via
  `install.sh`, and relaunches the app — one command, three actions,
  every time. Treat this as the default state of "done": **not run = not
  done**. Opt-out cases (must be stated in the response):
  - Doc-only change with no runtime impact (README typo fix, comment
    cleanup) — note explicitly that the build was skipped and why.
  - Tests are failing — fix them first, then build.
  - User explicitly said don't build / don't install in this turn.
- **NEVER substitute `npm run build && ./install.sh` (or `./install.sh`
  alone) for `./build-app.sh` on Electron apps.** `npm run build` only
  rebuilds the JS into `out/`; it does NOT repackage the `.app`.
  `install.sh` copies the *pre-packaged* bundle from `dist/`, so this
  combo ships a STALE binary to `/Applications` while still printing
  "Launching" as if it worked. Only `build-app.sh` runs
  `electron-builder --dir` to regenerate `dist/` first. (Incident:
  PurpleTree v1.0.2–v1.1.1 were "shipped" this way; `/Applications`
  stayed frozen at v1.0.1 across 6 builds and no fix reached the user.)
- **MANDATORY post-install freshness proof — every time, no exceptions.**
  After `build-app.sh`, you must PROVE the running app is the binary you
  just built — not merely that a file on disk changed. Two layers:
  1. **Process-freshness (the real guarantee).** `install.sh` force-kills
     every running instance, waits until it's gone, `open -n`s a new one,
     and asserts the running process's start time is **≥ the new binary's
     mtime**, printing `Verified: <App> <version> running fresh (pid …,
     started …)`. You MUST see that line. Its absence = the install did
     not prove freshness = **not done**.
  2. **Version string (secondary).** `defaults read
     "/Applications/<App>.app/Contents/Info.plist"
     CFBundleShortVersionString` should match `package.json` (Electron) or
     the git-derived version (Swift). NOTE: this check alone is **not
     sufficient** — Swift versions are git-derived, so two builds between
     commits report the *same* number and a stale instance passes the
     version check. Trust the process-freshness proof, not the version.
- **Stale running applications — the recurring failure mode, now closed.**
  A graceful quit (`osascript … quit`, Cmd-Q, `sleep` then `open`) can be
  **blocked indefinitely**: a quit-confirmation dialog (PurpleIRC has
  one), an unsaved-changes prompt, or a hung run loop leaves the old
  process alive, and a plain `open` then re-focuses the STALE copy while
  printing "Launching" as if it worked. **Never trust a graceful quit to
  have terminated an app.** Every app `install.sh` MUST: (a) `pkill -9 -f
  "<App>.app/Contents/MacOS/<App>"` in a loop until `pgrep` shows it gone,
  aborting if it won't die; (b) relaunch with `open -n`; (c) prove
  freshness via process-start-time ≥ binary-mtime. If you ever find an
  app's `install.sh` still on the graceful-quit-only pattern, **harden it
  to the four-step standard before shipping** — do not work around it
  per-turn. Reference: `PurpleIRC/install.sh`; full spec in
  `docs/install-sh-standard.md` → "What install.sh does".
- After UI/icon changes on macOS, always force-clear icon caches (`touch app bundle`, `killall Finder Dock`) and rebuild — visible icon updates often need a second cache-bust pass.
- After any build, launch the app and confirm the change is visible before declaring done.
- Run the full test suite before committing; report pass/fail count (e.g., '455/455 passing').

### Icon / UI change verification sequence

After any icon or UI change:
1. Rebuild.
2. `touch /Applications/<App>.app`
3. `killall Finder Dock`
4. Relaunch the app.
5. Report what you **visually see**, not just that the build succeeded.

## Swift app build prerequisites (read before invoking `build-app.sh`)

Three environment gotchas with misleading diagnostics: (1) `#Preview` macros need full Xcode (`sudo xcode-select -s /Applications/Xcode.app`), else `PreviewsMacros … not found`; (2) Sparkle apps need `SPARKLE_PUBLIC_KEY` in the env or the updater dies with an EdDSA-key error; (3) ` 2`-suffixed dupes in `.build/` are iCloud corruption — `rm -rf .build` and get the repo out of `~/Documents/`.

→ Full symptoms, error text, and recovery steps for all three are in **`docs/swift-build-prerequisites.md`** — read it when a Swift `build-app.sh` fails in a confusing way (and before assuming a tool bug).

## File Hygiene

- Watch for and remove duplicate/stray files (e.g., 'RootView 2.swift', duplicate headings in markdown) — they break builds silently.
- Never clobber existing documentation sections; read before overwriting.
