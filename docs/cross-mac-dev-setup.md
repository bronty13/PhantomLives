# Cross-Mac dev setup

**This repo must live at `~/dev/PhantomLives/`. It must NOT live anywhere under `~/Documents/` or `~/Desktop/`.** The maintainer works across two Macs with different usernames; `~/dev/` is consistent on both and stays out of iCloud's reach.

## Why `~/Documents/` is broken for dev work

macOS's "Desktop & Documents Folders" iCloud sync (System Settings → Apple ID → iCloud Drive → Options) makes `~/Documents/` an iCloud-managed location. The iCloud File Provider (`bird` + `fileproviderd`) intercepts every filesystem syscall on iCloud-managed paths. For a polyglot monorepo like this one the consequences are catastrophic:

- **Build artifacts get duplicated and corrupted across machines.** SwiftPM's `.build/`, Cargo's `target/`, Electron's `dist/`, npm's `node_modules/`, Xcode's `DerivedData/` all sync to iCloud whether you want them to or not — `.gitignore` is irrelevant because iCloud doesn't read it. When Mac A's artifacts collide with Mac B's, iCloud renames the conflict with a ` 2` suffix: `Sparkle 2/`, `GRDB 2.swift/`, `RootView 2.swift`, `dist 2/`, `PurpleIRC 2.app/`, `WHATS_NEW_1.13 2.md`. The build manifest still references the unsuffixed name, so SwiftPM fails with `the package manifest at … cannot be accessed`, npm fails with `MODULE_NOT_FOUND`, etc.
- **`mv` is no longer atomic.** Trying to move a tree out of `~/Documents/` (even to another local path) is intercepted by `fileproviderd` and routed through a per-file async copy that pegs CPU at 100 % and crawls. `ditto` and `cp -a` are throttled the same way. A 12 GB move that should be a metadata rename takes 10+ hours and may hang.
- **Per-file syscalls are slow.** Every `stat`, `open`, `write` on a path under `~/Documents/` may have to consult `fileproviderd` first. Builds with thousands of files take measurably longer than at `~/dev/`.

## Migrating an existing checkout out of `~/Documents/`

If you find yourself with a repo at `~/Documents/GitHub/PhantomLives/`, do **NOT** try to `mv`, `cp`, `ditto`, or `rsync` it to `~/dev/`. iCloud will block or wreck the operation. The reliable path:

1. `cd ~/Documents/GitHub/PhantomLives && git status` — note uncommitted modifications and untracked source files you care about.
2. `git diff > /tmp/dirty.patch` — capture all working-tree modifications in one file.
3. `git clone https://github.com/<owner>/PhantomLives.git ~/dev/PhantomLives` — fresh clone from origin bypasses iCloud entirely. Takes seconds.
4. `cd ~/dev/PhantomLives && git apply /tmp/dirty.patch` — restore modifications.
5. `rsync -a` the untracked source files you want to keep. Skip anything with a ` 2` in the name — those are iCloud corruption, not real source.
6. Copy `.claude/settings.local.json` and rewrite any hardcoded `/Users/<name>/Documents/GitHub/PhantomLives/…` paths to `~/dev/PhantomLives/…`.
7. Verify with a representative build (`PurpleDedup/build-app.sh`, `Molly/build-app.sh`, etc.) before deleting OLD.
8. `rm -rf ~/Documents/GitHub/PhantomLives`. iCloud will be slow but eventually clears, and the deletion will sync to other Macs — make sure they're ready or have already been migrated.

Clean clone is ~141 MB. OLD was 12 GB because of accumulated build caches. None of that needs to move.

## Per-Mac setup checklist (do once per machine)

The repo content is shared via git, but these pieces live in macOS Keychain / system settings and have to be set up on each machine independently — do not try to sync them via iCloud or Dropbox:

1. **Full Xcode selected:** `sudo xcode-select -s /Applications/Xcode.app`. Required for any subproject using SwiftUI `#Preview {}` macros (the `PreviewsMacros` plugin only ships with full Xcode, not Command Line Tools).
2. **Apple Developer ID signing identity** in the login Keychain. `security find-identity -v -p codesigning` should list `Developer ID Application: <Name> (TEAMID)`. Subprojects' `build-app.sh` auto-detects this; without it, the script falls back to ad-hoc signing (works locally, breaks notarization).
3. **Sparkle EdDSA private key** in the login Keychain for Sparkle-using apps (currently PurpleDedup). The public half goes into `~/.zshrc` as `SPARKLE_PUBLIC_KEY`. See `docs/swift-build-prerequisites.md` section 2 for details.
4. **Notarytool keychain profile** for release builds: `xcrun notarytool store-credentials "<App>-Notary" --apple-id <id> --team-id <id>`. Per-subproject; only needed when cutting a release from this Mac.
5. **Homebrew prereqs** vary per subproject — see each subproject's README. Common: `rust`, `pnpm`, `librsvg`, `imagemagick`, `slackdump`.
6. **Git hooks** are NOT carried by `git clone` — re-run any subproject's hook installer after cloning. Installers: `PurplePDF/scripts/install-git-hooks.sh` (single-project hook for PurplePDF) and `PurpleTree/scripts/install-git-hooks.sh` (a **dispatching** hook that runs every `*/scripts/bump-and-log.mjs` under the repo root — each no-ops unless its own subproject is staged, so it's safe to share; prefer running this one). Either installs a pre-commit hook that auto-bumps the touched subproject's patch version + prepends a CHANGELOG entry. Without it, version bumps must be done by hand.
