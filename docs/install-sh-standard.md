# `install.sh` standard for `.app` subprojects

**Every PhantomLives macOS-app subproject (anything with a `build-app.sh` that produces a `.app` bundle) ships an `install.sh`, and `build-app.sh` auto-chains into it.** Building defaults to *build + install + relaunch* — one command does everything. This rule was made unconditional in 2026-05-19 because the conditional gating below was producing accidentally-divergent dev workflows across subprojects.

The conditional rationale still applies (the *why* below is still load-bearing), it's just now applied universally:

- TCC entitlements (Full Disk Access, Accessibility, Automation) key grants on the `(team ID, bundle ID, cdhash)` tuple — running from `/Applications/<App>.app` keeps Launch Services + System Settings → Privacy from spawning duplicate stale entries on every rebuild.
- URL schemes, AppleScript dictionaries, Shortcuts intents, Spotlight metadata — all bind to the resolved bundle path that Launch Services indexes.
- Daily-use launching from Spotlight / Dock / Cmd+Tab needs a stable bundle path.

Pure CLI tools, Python scripts, and dev-only utilities are still exempt — they don't have `build-app.sh` to begin with.

## What `install.sh` does

Four steps, in order — **steps 1 and 4 are the anti-stale-instance guarantee and must never be weakened** (see CLAUDE.md → "Stale running applications"):

1. **Force-terminate every running copy, and wait until it's actually gone.** A graceful `osascript -e 'tell application "<AppName>" to quit'` is fine as a *first* nudge, but it can be **blocked indefinitely** — a quit-confirmation dialog (PurpleIRC has one), an unsaved-changes prompt, or a hung run loop all leave the old process alive. So follow it with a `pkill -9` loop that polls until `pgrep` reports the process gone, matched by the **executable path** (`<App>.app/Contents/MacOS/<App>`) so unrelated processes are never hit. If the process still won't die after the timeout, **abort** — never copy over a survivor, because the next step's `open` would just re-focus it.
2. **Replace `/Applications/<AppName>.app`** — `rm -rf` then `ditto --noextattr <project-dir>/<AppName>.app /Applications/<AppName>.app`. `ditto --noextattr` matters: it strips the iCloud File Provider xattrs that re-attach mid-copy and break `codesign --verify`.
3. **Relaunch a guaranteed-new instance** — `open -n /Applications/<AppName>.app`. The `-n` flag forces a brand-new instance instead of re-focusing a survivor. Skip with a `--no-open` flag for CI / scripted use.
4. **Prove the running process is the new one.** Capture the new binary's mtime (`stat -f %m`) before `open`, then poll for the launched PID and assert its start time (`ps -o lstart=` → epoch) is **≥ binary mtime**. If the running process predates the binary, a stale instance survived — **abort loudly**. On success, print one line the caller can grep: `Verified: <App> <version> running fresh (pid …, started …)`.

Why step 4 and not "just check `CFBundleShortVersionString`": Swift app versions are **git-derived** (`1.0.<commit-count>`), so two builds between commits report the *same* version — a version-string check passes even when the running app is stale. Process-start-time vs binary-mtime is the only check that actually proves freshness.

The script lives at the subproject root (`<SubProject>/install.sh`), is `chmod +x`-ed in git, refuses to run when the local `<App>.app` doesn't exist yet (run `./build-app.sh` first), and tolerates a missing `/Applications/<AppName>.app` (first install).

Reference implementation: **`PurpleIRC/install.sh`** (the hardened four-step version above). Older app `install.sh`s still on the graceful-quit-only pattern are stale-instance hazards — retrofit them to this on next touch.

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
"Bash(pkill -9 -f <AppName>.app/Contents/MacOS/<AppName>)",
"Bash(open -n /Applications/<AppName>.app)"
```

Substitute `<AppName>` per subproject. These are scoped per project, so the permissions stay narrow.

## Remote (SSH) builds: adhoc-sign automatically

`build-app.sh` **adhoc-signs when it detects an SSH session** (`SSH_CONNECTION` set), because
`codesign` with a Developer ID identity needs the login keychain's private key, which an SSH session
cannot unlock — it fails `errSecInternalComponent` and breaks a remote `build-app.sh`, forcing a
manual local build. Adhoc signing needs no keychain and is fine for dev/local installs; Developer ID
+ notarization is only required for actual releases (`Scripts/release.sh`, run locally). The guard
lives in `detect_codesign_identity()`:

```sh
if [ -n "${SSH_CONNECTION:-}" ] && [ -z "${FORCE_DEVID:-}" ]; then echo "-"; return; fi
```

Set `FORCE_DEVID=1` to Dev-ID-sign over SSH anyway (needs the keychain unlocked in that ssh session).
**New `.app` subprojects must include this guard** so `build-app.sh` works over SSH on any node.

**Companion gotcha — run-at-login agents must NOT use `KeepAlive`.** A launch agent that keeps the app
alive respawns it instantly when `install.sh` kills the old instance, so the freshness-proof kill loop
can never swap the binary ("could not terminate running <App>"). Use **`RunAtLoad` only** with
`/usr/bin/open -a <App>` (not the raw binary), so the app auto-starts at login but doesn't fight
installs. (Incident 2026-07-01: MB14's PurpleMirror autostart agent had `KeepAlive` + ran the binary
directly → every remote install failed until it was converted to the open-based RunAtLoad-only form.)
