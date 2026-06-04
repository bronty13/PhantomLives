# `install.sh` standard for `.app` subprojects

**Every PhantomLives macOS-app subproject (anything with a `build-app.sh` that produces a `.app` bundle) ships an `install.sh`, and `build-app.sh` auto-chains into it.** Building defaults to *build + install + relaunch* — one command does everything. This rule was made unconditional in 2026-05-19 because the conditional gating below was producing accidentally-divergent dev workflows across subprojects.

The conditional rationale still applies (the *why* below is still load-bearing), it's just now applied universally:

- TCC entitlements (Full Disk Access, Accessibility, Automation) key grants on the `(team ID, bundle ID, cdhash)` tuple — running from `/Applications/<App>.app` keeps Launch Services + System Settings → Privacy from spawning duplicate stale entries on every rebuild.
- URL schemes, AppleScript dictionaries, Shortcuts intents, Spotlight metadata — all bind to the resolved bundle path that Launch Services indexes.
- Daily-use launching from Spotlight / Dock / Cmd+Tab needs a stable bundle path.

Pure CLI tools, Python scripts, and dev-only utilities are still exempt — they don't have `build-app.sh` to begin with.

## What `install.sh` does

Three steps, in order:

1. **Quit the running copy** — `osascript -e 'tell application "<AppName>" to quit' >/dev/null 2>&1 || true`. Give Launch Services a moment (`sleep 1`) to release the bundle lock.
2. **Replace `/Applications/<AppName>.app`** — `rm -rf` then `ditto --noextattr <project-dir>/<AppName>.app /Applications/<AppName>.app`. `ditto --noextattr` matters: it strips the iCloud File Provider xattrs that re-attach mid-copy and break `codesign --verify`.
3. **Relaunch** — `open /Applications/<AppName>.app`. Skip with a `--no-open` flag for CI / scripted use.

The script lives at the subproject root (`<SubProject>/install.sh`), is `chmod +x`-ed in git, refuses to run when the local `<App>.app` doesn't exist yet (run `./build-app.sh` first), and tolerates a missing `/Applications/<AppName>.app` (first install).

Reference implementation: `SlackSucker/install.sh`.

## `build-app.sh` chain

Every `build-app.sh` ends with this canonical block after the build succeeds:

```bash
# Auto-install: replace /Applications/<App>.app and relaunch. Opt out
# with `--no-install` (CI builds, signature inspection) or `--no-open`
# (install without focus-stealing relaunch). Per the install.sh standard.
if [ "${BUILD_ONLY:-0}" != "1" ] && [[ ! " $* " =~ " --no-install " ]]; then
    INSTALL_FLAGS=""
    if [[ " $* " =~ " --no-open " ]]; then INSTALL_FLAGS="--no-open"; fi
    if [ -x "$(dirname "$0")/install.sh" ]; then
        "$(dirname "$0")/install.sh" $INSTALL_FLAGS
    fi
fi
```

The `BUILD_ONLY=1` env-var override is for one-off invocations from scripts that genuinely want only the .app bundle (PR previews, signature checks). The `--no-install` flag is the same idea on the command line.

## Developer workflow

```sh
./build-app.sh                       # build + install + relaunch
./build-app.sh --no-open             # build + install, no focus steal
./build-app.sh --no-install          # build only (legacy behavior)
BUILD_ONLY=1 ./build-app.sh          # same, via env
./install.sh                          # re-install last-built bundle
./install.sh --no-open               # re-install without launching
```

The pre-2026-05-19 two-line idiom (`./build-app.sh && ./install.sh`) still works (install.sh is idempotent — running it twice just does the kill-replace-relaunch cycle twice), but it's redundant now.

## Why `/Applications/`, not the project tree?

- **TCC stability**: macOS Privacy & Security entries follow the cdhash of the *exact path* that was authorised. Running from `~/Documents/GitHub/PhantomLives/<Sub>/<App>.app` and from `/Applications/<App>.app` would each accumulate their own Full Disk Access grant; rebuilds in the project tree rotate the cdhash and force re-granting permissions on every iteration.
- **Launch Services hygiene**: launching the same `.app` from two paths makes Spotlight / Cmd+Tab pick a phantom copy after Finder auto-renames duplicates to ` 2.app` / ` 3.app`. Pinning to `/Applications/` and rebuilding through ditto eliminates the duplicates entirely.
- **No iCloud File Provider interference**: the project tree may be inside `~/Documents/GitHub/…` which is iCloud-synced on many maintainers' machines. The File Provider re-attaches `com.apple.fileprovider.fpfs#P` and `com.apple.FinderInfo` xattrs to `.app` bundles at arbitrary times, which trips `codesign --verify`. `/Applications/` is local-only.

## Per-session Claude permission

The `rm -rf /Applications/<AppName>.app` + `ditto * /Applications/<AppName>.app` operations live behind the auto-mode classifier's "modifying shared infrastructure" gate. To let Claude run `install.sh` end-to-end without prompting, add the matching rules to `.claude/settings.local.json`:

```json
"Bash(rm -rf /Applications/<AppName>.app)",
"Bash(ditto --noextattr * /Applications/<AppName>.app)",
"Bash(osascript -e 'tell application \"<AppName>\" to quit')",
"Bash(open /Applications/<AppName>.app)"
```

Substitute `<AppName>` per subproject. These are scoped per project, so the permissions stay narrow.
