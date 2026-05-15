# SlackSucker

Native macOS GUI for [slackdump](https://github.com/rusq/slackdump). Pick a workspace, narrow to a single channel / DM / thread (or take the whole workspace), and pull the conversation — plus files, avatars, and a plain-text transcript — onto your local disk.

```
Workspace → SQLite + organized files + readable .txt
                ▲                ▲
             slackdump        SlackSucker
            (bundled)         post-processing
```

SlackSucker never reimplements Slack's API and never sees an auth token. It drives the bundled `slackdump` binary and reorganizes the result.

## Quick start

```sh
brew install slackdump          # build-time dep; gets bundled into the .app
./build-app.sh                  # produces ./SlackSucker.app
./install.sh                    # quit running copy, replace /Applications/, relaunch
```

Two-script flow (`build` → `install`) is the PhantomLives standard for `.app` projects — see `INSTALL.md` for the why.

## What it does

| Step | Tool | Output |
| --- | --- | --- |
| Workspace auth | `slackdump workspace new <name>` | encrypted creds at `~/Library/Caches/slackdump/` |
| Pick a scope | SlackSucker UI | `ArchiveRequest` value type |
| Archive | bundled `slackdump archive` | `slackdump.sqlite` + `__uploads/<FILE_ID>/<name>` |
| Reorganize files | `FileOrganizer` | `Videos/` `Photos/` `Audio/` `Other/` at run-folder root |
| Render transcript | `ChatExporter` (SQLite → text) | `Chat/<scope>.txt` with mentions resolved |
| Auto-backup | `BackupService` (launch hook) | `~/Downloads/SlackSucker backup/SlackSucker-<ts>.zip` |

End state of a typical channel run:

```
~/Downloads/SlackSucker/<scope>_<YYYYMMDD_HHmmss>/
├── slackdump.sqlite           Source of truth — untouched
├── archive.log                Captured slackdump stdout
├── organize-log.txt           FileOrganizer summary
├── __avatars/                 Profile thumbnails (kept as-is)
├── Videos/                    .mp4 .mov .m4v .mkv .webm …
├── Photos/                    .jpg .png .heic .webp .gif …
├── Audio/                     .mp3 .m4a .wav .ogg .flac …
├── Other/                     PDFs, docs, archives, anything else
└── Chat/
    └── <scope>.txt            Plain-text transcript
```

`Chat/` is only produced for targeted scopes (channel / DM / thread URL), not for whole-workspace archives — too many conversations to flatten into one file.

## Where things live

| Thing | Path | Editable? |
| --- | --- | --- |
| Archive runs | `~/Downloads/SlackSucker/<scope>_<timestamp>/` | Settings → output folder |
| Settings, run history, presets, channel cache | `~/Library/Application Support/SlackSucker/` | edit in-app or open the JSON |
| Auto-backups | `~/Downloads/SlackSucker backup/SlackSucker-*.zip` | Settings → Backup |
| Slack workspace credentials | `~/Library/Caches/slackdump/` | slackdump-owned; SlackSucker never touches it |

## Build / test / install

```sh
./build-app.sh                 # release build (CONFIG=debug also supported)
SLACKDUMP_BIN=/path/to/slackdump ./build-app.sh   # bundle a specific slackdump
./run-tests.sh                 # 41 tests across 11 Swift Testing suites
./install.sh                   # replace /Applications/SlackSucker.app, relaunch
./install.sh --no-open         # same, but leave the new copy unlaunched
```

`build-app.sh` derives the version from git (`CFBundleShortVersionString = 1.0.<commit-count>`, `CFBundleVersion = <count>.<short-sha>`) and signs both the host app and the bundled slackdump helper with `Developer ID Application: Robert Olen (SRKV8T38CD)` when the cert is in the keychain, ad-hoc otherwise.

## Architecture mental model

- **`ArchiveRunner`** spawns `Resources/slackdump archive …`, streams stdout into a SwiftUI-observable buffer, and chains post-processing on success.
- **`FileOrganizer`** walks `__uploads/<FILE_ID>/<name>` and moves each file into `Videos/` / `Photos/` / `Audio/` / `Other/` by extension. Name collisions get a `(<FILE_ID>)` suffix instead of overwriting.
- **`ChatExporter`** shells out to `/usr/bin/sqlite3 -json` against `slackdump.sqlite`, decodes the rows with Codable, formats messages chronologically with thread replies indented under their parent, and resolves `<@U…>` / `<#C…|name>` / `<https://…|label>` markup inline.
- **`BackupService`** zips `~/Library/Application Support/SlackSucker/` on launch (5-min debounce, 14-day retention, prefix-scoped trim). Reference impl per `PhantomLives/CLAUDE.md`.
- **`WorkspaceService` / `ChannelService`** wrap `slackdump workspace …` and `slackdump list …` respectively, parse the JSON output, cache the channel/user list per workspace.

`HANDOFF.md` has the deeper dive. `DESIGN.md` explains the workarounds (notably the thread-URL substitution).

## What's not in scope

- We don't ship our own Slack API client. Every read goes through slackdump.
- We don't store auth tokens. Slackdump's encrypted cache is the canonical store; SlackSucker only invokes `workspace list/new/select/del`.
- We don't support slackdump's `export` (Slack-import-compatible directory) or `dump` (legacy JSON) formats — run those from the terminal if you need them.
- Whole-workspace runs don't produce a `Chat/` transcript. Slackdump's own `view` / `convert -f html` is the better tool for navigating many rooms.

## License

Personal-use utility, same as the rest of PhantomLives. Slackdump itself is GPL-3.0; SlackSucker only invokes it as a child process, never linking against it.
