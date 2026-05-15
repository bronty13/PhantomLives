# Installing SlackSucker

## Prerequisites

1. **macOS 14 (Sonoma) or newer.** The SwiftPM target is `.macOS(.v14)`.
2. **Xcode Command Line Tools** (or full Xcode). Test:
   ```sh
   swift --version       # → 5.9 or newer
   sqlite3 --version     # → 3.x (ships with macOS)
   ```
3. **slackdump on PATH** at build time:
   ```sh
   brew install slackdump
   which slackdump       # /opt/homebrew/bin/slackdump
   ```
   The version present here gets copied verbatim into `SlackSucker.app/Contents/Resources/slackdump`, code-signed with the host app, and used at runtime. You don't need slackdump on PATH after the build is done.

### Optional Homebrew dependencies (per-feature)

None of these are required to install or run SlackSucker. Each one unlocks a specific post-processing toggle; without it, the toggle either skips silently or logs a one-line "tool not installed" notice in the live log and the rest of the run still completes.

| Tool | Install | Unlocks |
| --- | --- | --- |
| `exiftool` | `brew install exiftool` | "Strip metadata" toggle |
| `ffmpeg` | `brew install ffmpeg` | Video orientation baking (photos work without it) |
| `transcribe/` checked out alongside SlackSucker | `git clone` the PhantomLives repo (already done if you're reading this) | "Transcribe A/V" toggle. Apple Silicon only. First run pulls multi-GB MLX-Whisper weights. |

Hashing has no external dependency — `CryptoKit` ships with the OS.

## Build + install

```sh
cd PhantomLives/SlackSucker
./build-app.sh            # produces ./SlackSucker.app
./install.sh              # replaces /Applications/SlackSucker.app and relaunches
```

That's the whole flow. Two scripts because they have different blast radii: `build-app.sh` only touches the project tree, `install.sh` writes to `/Applications/`.

### One-liner for iteration

```sh
./build-app.sh && ./install.sh
```

After any source change, this rebuilds and re-deploys in ~10 seconds.

### Variants

```sh
CONFIG=debug ./build-app.sh                  # debug build, same output path
SLACKDUMP_BIN=/path/to/slackdump ./build-app.sh   # bundle a specific slackdump
./install.sh --no-open                       # replace /Applications/ but don't relaunch
```

## What `install.sh` actually does

1. **Quits the running app** via `osascript -e 'tell application "SlackSucker" to quit'`, then `sleep 1` so Launch Services releases the bundle lock.
2. **Removes `/Applications/SlackSucker.app`** if present. If it's not present (first install), continues without error.
3. **Copies the freshly built `./SlackSucker.app`** to `/Applications/SlackSucker.app` via `ditto --noextattr`. The `--noextattr` flag strips iCloud File Provider extended attributes that would otherwise re-attach mid-copy and break codesign verification.
4. **Launches** the new `/Applications/` copy via `open /Applications/SlackSucker.app` (skip with `--no-open`).

It refuses to run if `./SlackSucker.app` doesn't exist yet — you have to build first.

## Why install to `/Applications/`?

PhantomLives convention; see `PhantomLives/CLAUDE.md` → "install.sh standard for `.app` subprojects" for the full rationale. Short version:

- macOS Privacy & Security (TCC) grants follow the cdhash of the path that was authorised. Running from `~/Documents/GitHub/…/SlackSucker.app` and from `/Applications/SlackSucker.app` would each accumulate their own permission entries.
- Launching the same `.app` from two paths produces phantom ` 2.app` / ` 3.app` clones in Launch Services. `/Applications/` is the stable home that avoids this entirely.
- The project tree may be inside iCloud-synced `~/Documents/GitHub/…`. iCloud's File Provider re-attaches `FinderInfo` xattrs to `.app` bundles at random, which can break `codesign --verify`. `/Applications/` is local-only.

## First-run setup

1. Launch from `/Applications/SlackSucker.app` (Spotlight, Dock, or `open /Applications/SlackSucker.app`).
2. Click **Manage…** in the sidebar's WORKSPACE section.
3. Click **Add workspace…**, type your workspace URL or name (or leave blank for `default`), click **Sign in**.
4. Slackdump's EZ-Login 3000 opens a controlled browser window. Sign in to Slack there. The sheet streams progress.
5. When the new workspace appears in the list, click **Select** next to it.

After that, the Channel / DM picker auto-fetches the channel + user list. The first refresh takes a few seconds; subsequent opens load from the cached JSON at `~/Library/Application Support/SlackSucker/channel-cache/<workspace>.json`.

## Uninstalling

```sh
osascript -e 'tell application "SlackSucker" to quit'
rm -rf /Applications/SlackSucker.app
```

If you also want to nuke the cached state (settings, run history, presets, channel cache, backups):

```sh
rm -rf "$HOME/Library/Application Support/SlackSucker"
rm -rf "$HOME/Downloads/SlackSucker backup"
```

Slackdump's own auth credentials live at `~/Library/Caches/slackdump/` and are *not* SlackSucker-owned. Run `slackdump workspace del <name>` from the terminal if you want to wipe those, or just `rm -rf ~/Library/Caches/slackdump`.

## Letting Claude Code run `install.sh` without prompting

`install.sh` writes to `/Applications/`, which is gated by Claude Code's auto-mode classifier. To allow it for this project only, add to `.claude/settings.local.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(rm -rf /Applications/SlackSucker.app)",
      "Bash(ditto --noextattr * /Applications/SlackSucker.app)",
      "Bash(osascript -e 'tell application \"SlackSucker\" to quit')",
      "Bash(open /Applications/SlackSucker.app)"
    ]
  }
}
```

## Troubleshooting

- **`slackdump binary not found in app bundle`** in the running app. The `build-app.sh` step didn't find slackdump on PATH. Run `which slackdump` to verify, or set `SLACKDUMP_BIN=/path/to/slackdump ./build-app.sh`.
- **`ditto: No destination`** when running `install.sh` from a pasted terminal line. The shell broke the command across a line wrap. Always invoke as `./install.sh`, not by retyping the underlying commands.
- **`codesign --verify` reports issues** after `build-app.sh`. Usually iCloud xattrs re-attached during the post-build copy. Build again — `build-app.sh` assembles + signs the bundle in `/tmp` first to avoid this, but if iCloud is being especially aggressive, a second pass clears it.
- **App won't launch from `/Applications/`** after install. Right-click → Open the first time for ad-hoc-signed builds. Developer-ID-signed builds (the maintainer's setup) won't show this.
- **Permission entries piling up** in System Settings → Privacy & Security. That's the duplicate-bundle problem `install.sh` exists to avoid — make sure you're not also launching `~/Documents/GitHub/…/SlackSucker.app` directly.
