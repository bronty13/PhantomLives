# SlackSucker — Handoff

Snapshot of where the project stands so a future session (human or AI) can pick up without re-deriving everything from the commit history.

Last updated: 2026-05-15. v1.1.x (post-processing pipeline batch) on top of the 1.0 baseline (commit-count derived). 52 tests across 16 Swift Testing suites, all green. Bundle is Developer-ID-signed end-to-end (host app + bundled slackdump).

## What it is

Native macOS GUI for [slackdump](https://github.com/rusq/slackdump). SwiftUI, SwiftPM (no XcodeGen), bundles the slackdump CLI inside the .app at build time. Modeled on `messages-exporter-gui/` — same single-run / live-output / preset / history architecture; substitute slackdump for `export_messages`.

```sh
./build-app.sh && ./install.sh
./run-tests.sh
```

Requires macOS 14+, Swift 5.9+. Tests via Command Line Tools' bundled `Testing.framework` — `./run-tests.sh` handles the rpath dance.

## Architecture at a glance

Top-level SwiftUI `@StateObject` graph injected via `environmentObject`:

- **`SettingsStore`** — JSON-backed (`settings.json`); holds `defaultArchiveOptions`, `selectedWorkspace`, `outputDirOverride`. Forward-compatible with `decodeIfPresent` on new fields.
- **`ArchiveRunner`** — `@MainActor`. Owns the in-flight `Process`, the streamed log lines, and chains the post-archive pipeline (FileOrganizer → ChatExporter → recordHistory). Stdout/stderr → `LineBuffer` → `processLine` → `runStats.absorb`.
- **`WorkspaceService`** — wraps `slackdump workspace list / new / select / del`. The `new` flow pipes a real stdin so prompts ("Overwrite? (y/N)") can be answered.
- **`ChannelService`** — wraps `slackdump list channels -format JSON` + `list users -format JSON`. Decodes via Codable structs (`RawChannel`, `RawUser`), merges DMs against users to humanize partner names, caches per workspace at `channel-cache/<workspace>.json`.
- **`PresetStore`** / **`RunHistoryStore`** — JSON-backed Codable arrays, 50-entry cap on history.
- **`BackupService`** — enum with `runOnLaunchIfDue()`. Called from `SlackSuckerApp.init()` before UI is built. Modeled on Timeliner's reference impl.
- **`FileOrganizer`** — pure enum, called post-archive when toggle is on. Walks `__uploads/<ID>/<name>`, sorts by extension into `Videos/` `Photos/` `Audio/` `Other/`. Collision → `(<FILE_ID>)` suffix.
- **`OrientationBaker`** (1.1) — `CGImageSource` + `CIImage.oriented(forExifOrientation:)` for photos; `ffmpeg -display_rotation 0 -c copy` for videos. Bakes the orientation flag into pixel data and resets it. Runs BEFORE `MetadataStripper` so the orientation hint isn't gone by the time we read it.
- **`MetadataStripper`** (1.1) — Batches paths through `exiftool -@ <argfile>` (one process for the whole run; avoids per-file spawn cost). Strips EXIF/IPTC/XMP destructively in-place. No-ops with a skip log when exiftool isn't on PATH.
- **`TranscriptionService`** (1.1) — Per-file `transcribe.py -i <src> -o <name>.txt -m <model> -q` loop. Async; bridges `Process` termination via `withCheckedContinuation` so UI stays responsive. Binary resolution order: `$SLACKSUCKER_TRANSCRIBE_BIN` → PATH `transcribe` → sibling-checkout `transcribe/transcribe.py`.
- **`HashService`** (1.1) — Single-pass stream-hasher. One `FileHandle.read` loop per file; the same `Data` chunk feeds `Insecure.MD5` / `Insecure.SHA1` / `SHA256` simultaneously so a 1GB file is read exactly once regardless of how many algorithms are selected. Output is GNU-coreutils-compatible `<hex>  <relpath>` lines grouped under `# <ALGO>` section headers.
- **`ChatExporter`** — pure functions + a single `export()` entry point. Shells to `/usr/bin/sqlite3 -json` against `slackdump.sqlite`, decodes message/user/file rows, renders a plain-text transcript with thread indentation and `<@U…>` / `<#C…|name>` / `<https://…|label>` resolution.

### Pipeline overview

```
   form  ──►  ArchiveRequest  ──►  argumentList()  ──►  slackdump archive
                                                              │
                                                              ▼
   ╔═════════════════════════════════════════════════╗
   ║  POST-PROCESSING (only on slackdump exit 0)     ║
   ║                                                 ║
   ║  archive.log written                            ║
   ║       │                                         ║
   ║       ▼                                         ║
   ║  FileOrganizer.organize         (organizeFiles) ║
   ║       │                                         ║
   ║       ▼                                         ║
   ║  OrientationBaker.run           (bakeOrient.)   ║  ◄── 1.1
   ║       │                                         ║
   ║       ▼                                         ║
   ║  MetadataStripper.run           (stripMeta)     ║  ◄── 1.1
   ║       │                                         ║
   ║       ▼                                         ║
   ║  TranscriptionService.run       (transcribe)    ║  ◄── 1.1
   ║       │                                         ║
   ║       ▼                                         ║
   ║  HashService.run                (genHashes)     ║  ◄── 1.1
   ║       │                                         ║
   ║       ▼                                         ║
   ║  ChatExporter.export(runFolder)  (non-WS only)  ║
   ║       │                                         ║
   ║       ▼                                         ║
   ║  runStats.outputBytes                           ║
   ║       │                                         ║
   ║       ▼                                         ║
   ║  history.record(entry)                          ║
   ╚═════════════════════════════════════════════════╝
```

The order is load-bearing in only one place: **OrientationBaker must
run before MetadataStripper**. The stripper wipes the EXIF
`Orientation` tag along with everything else, so anything not yet
baked would visually rotate after the strip. The other steps are
order-independent; HashService comes last so the manifest reflects
the final on-disk state.

### `ArchiveRequest` argv builder

Most scopes flow through the generic path. **Thread URL is special-cased** — slackdump 4.x doesn't fetch attachments when the scope arg is a Slack permalink. The builder rewrites:

```
slackdump archive -o <out> https://x.slack.com/archives/C123/p1700000000123456
```

into:

```
slackdump archive -o <out> -time-from 2023-11-14T22:13:19 -time-to 2023-11-14T22:13:21 C123
```

`ArchiveScope.parseThreadURL` does the extraction (regex against `/archives/(C[A-Z0-9]+)/p(\d+)`; the digit run is split 10-seconds + 6-microseconds). The 2-second UTC window catches just the target message; slackdump's channel-archive flow follows the thread tree from there if it has replies.

### Process spawning patterns

All slackdump invocations go through `Process` with stdout+stderr merged through a `LineBuffer`. `WorkspaceService.addNewWorkspace` additionally connects stdin via a `Pipe` so interactive prompts can be answered programmatically.

For ChatExporter's SQLite reads, we shell to `/usr/bin/sqlite3 -json` rather than linking SQLite3 C API. Trade-off: extra process spawn per query, but no FFI surface, and JSON parse is trivial with `JSONDecoder`.

### Persistence layout

```
~/Library/Application Support/SlackSucker/
├── settings.json              SettingsStore
├── runs.json                  RunHistoryStore (max 50)
├── presets.json               PresetStore
└── channel-cache/
    └── <workspace>.json       ChannelService cache

~/Downloads/SlackSucker/
└── <scope>_<YYYYMMDD_HHmmss>/
    ├── slackdump.sqlite       (and -shm / -wal during run)
    ├── archive.log            captured slackdump stdout
    ├── organize-log.txt       FileOrganizer summary
    ├── __avatars/             untouched profile thumbnails
    ├── Videos/ Photos/ Audio/ Other/
    └── Chat/<scope>.txt       ChatExporter output (non-workspace only)

~/Downloads/SlackSucker backup/
└── SlackSucker-YYYY-MM-DD-HHmmss.zip    BackupService output

~/Library/Caches/slackdump/    slackdump-owned; SlackSucker never reads
```

## Decisions worth knowing

1. **Bundled binary, not PATH lookup**. `SlackSucker.app/Contents/Resources/slackdump` is the only runtime resolution. Reasons: a stray Homebrew upgrade can't drift behavior under us, and end users don't need a separate install step.

2. **slackdump owns auth.** SlackSucker never reads tokens. The "Add workspace…" sheet shells to `slackdump workspace new <name>` which opens slackdump's own EZ-Login Chromium flow. Stdin is wired so the "Overwrite? (y/N)" prompt can be answered via a real alert instead of busy-looping.

3. **JSON over text parsing.** The first iteration parsed `slackdump list channels` text columns. That broke when slackdump's actual `-no-save` flag turned out to be `-no-json` (help text drift). Switched to `-format JSON` + Codable structs. Tests use real-shape JSON fixtures captured from the maintainer's workspace.

4. **Pure-function post-processors.** `FileOrganizer.organize`, `ChatExporter.render`, `ArchiveScope.parseThreadURL`, `WorkspaceService.parseList`, `ChannelService.merge` — all marked `nonisolated static` and unit-tested in isolation. The `ArchiveRunner` just composes them.

5. **`/Applications/` is the runtime home.** TCC entitlements, Launch Services indexing, and iCloud File Provider xattrs all behave better when the app is launched from a single stable path. `install.sh` enforces this; see CLAUDE.md.

## Test coverage

52 tests across 16 suites:

- **ArchiveRequest** — argv shapes for every scope × every flag combo; thread-URL rewrite; scope-slug sanitisation
- **LineBuffer** — `\n` / `\r\n` / bare `\r` overwrite; trailing partial-line drain
- **RunStats** — count regex; phase prefix detection
- **ArchiveRunner helpers** — PATH augmentation idempotency
- **WorkspaceService parser** — slackdump v4 list output; overwrite-prompt detection
- **ChannelService JSON parser** — channel/user JSON shapes; merge; DM partner resolution; archived/deleted filters; tolerant JSON-extraction
- **FileOrganizer** — extension classification; reorg; collision suffix; no-op when uploads absent; idempotent
- **ChatExporter** — thread indentation; mention/channel/URL/entity resolution; file attachments; unknown-user fallback; timestamp formatting
- **SlackdumpBinary** — chmod bit; bundle path resolution
- **Settings & history round-trips** — JSON encode/decode; max-entries cap
- **BackupService** — debounce; retention trim (prefix-scoped); target-dir auto-create; list ordering
- **HashService** (1.1) — known-input SHA-256; multi-algo grouping; empty-algorithms bail-out; symlink + dotfile skip
- **MetadataStripper** (1.1) — log written when exiftool absent / no media; binary discovery
- **OrientationBaker** (1.1) — empty-folder no-op + log; bogus image surfaces .unsupported/.error not a crash; ffmpeg / ffprobe lookup contract
- **TranscriptionService** (1.1) — binary resolver returns nil or a real executable
- **ArchiveOptions backwards compat** (1.1) — 1.0 settings.json decodes cleanly with new fields defaulted off

## What's intentionally NOT here

- **Workspace-wide chat transcript.** Whole-workspace archives skip `ChatExporter` — too many rooms to flatten into one file, and slackdump's own `convert -f html` is better suited.
- **Native Slack API client.** Every read goes through slackdump.
- **Token storage.** SlackSucker never touches `~/Library/Caches/slackdump/provider.bin`.
- **`export` / `dump` slackdump subcommands.** Only `archive`. Run those from the terminal if needed.
- **Per-thread file scoping** for the thread-URL workaround. Channel-with-time-bracket can in rare cases pick up another message in the same 2-second window. The chat transcript shows whatever was archived — if the time bracket accidentally pulls in an adjacent message it'll appear in the .txt. Acceptable trade-off for now.
- **ML-based people-upright orientation inference.** OrientationBaker bakes the EXIF Orientation flag into pixel data; that catches ~90% of "rotated" photos (phones held sideways). What it does NOT do is *infer* up-from-down on files that have no orientation flag at all (screenshots, edited copies, pipeline-stripped content). Doing that reliably requires ML face/horizon detection that fails badly on group shots and content with no people; users who need it should run a dedicated tool after the SlackSucker export.
- **Bundled `transcribe` runtime.** The transcribe.py script self-bootstraps a multi-GB `.venv` on first run, and that bootstrap can't run from inside a signed `.app` bundle. The service relies on the sibling-checkout (or PATH shim) instead.

## Icon

`Resources/AppIcon.icns` is the bundled icon. Generated by `swift Tools/make-icon.swift`, which renders a deep-purple squircle with the 🐙 octopus emoji and four `#` glyphs at multiple resolutions (16/32/128/256/512 + @2x), then runs `iconutil -c icns` to bundle them. The `.icns` is checked in — regenerate after editing `Tools/make-icon.swift` and commit the new artifact. `build-app.sh` copies it into `Contents/Resources/` and `CFBundleIconFile=AppIcon` in the Info.plist points at it.

## Known slackdump quirks (workarounds in code)

| Symptom | Reality | Workaround |
| --- | --- | --- |
| `slackdump workspace list` shows `=> default (file: …)` | Header / footer chrome around column-aligned rows | `WorkspaceService.parseList` matches on the `(file:` marker |
| `slackdump workspace new` busy-loops on `Overwrite? (y/N)` | Slackdump reads EOF from closed stdin and reprompts forever | Pipe stdin; surface a real Yes/No alert; write `y\n` / `N\n` on response |
| `slackdump -workspace foo list channels` errors `flag not defined` | `-workspace` is a subcommand-level flag on `list`, not a global one | Always put `-workspace` after the subcommand |
| `slackdump list channels` dumps `channels-T0…txt` into cwd | `-no-save` mentioned in help is actually called `-no-json` | Use `-no-json`; also pin cwd to `/tmp` in `capture` |
| `slackdump list channels` DMs show `@<external>:U…` | Cryptic encoding for DM partner | Pass `-format JSON` and merge against users table locally |
| `slackdump archive <thread-URL>` skips file downloads | Permalink-scoped archives don't trigger file fetch in 4.x | Rewrite to channel ID + ±1s UTC time bracket around parent TS |
| `slackdump tools redownload` says "no missing files" on broken thread archive | It only validates FILE-table rows; the thread-archive bug skips inserting them in the first place | Same as above — fix at the argv layer, never reach the broken path |

## Open / future work

- **Resume across crashes** — `ArchiveRunner.resume(folder:)` exists for the cancel case. Same affordance for "app crashed mid-archive" would be straightforward; just persist `inflightRequest` on a sync save.
- **MPDM display in picker** — currently shown as `(group) <name>`. Could expand to include member names by reading the channel JSON's members[] array.
- **Notarization** — `build-app.sh` builds with `--options runtime --timestamp` already, so notarisation should be a `xcrun notarytool submit` call away. Not wired into the build script yet because there's no current need to distribute outside the maintainer's machine.
- **`Chat/<scope>.txt` for whole-workspace runs** — could produce one file per channel under `Chat/`. Currently skipped.
- **Threaded run history sidebar** — right now the sidebar shows the most recent 5; a fuller "Recent runs" destination view would round out the experience.

## How to extend

Most new features fall into one of two buckets:

**Post-processing**: another service that hooks after slackdump exits. Pattern: pure `nonisolated static` functions in a new `Services/<Name>.swift`, invoked from `ArchiveRunner.run(_:)` after the FileOrganizer step. Test the pure functions; the runner itself is integration-only.

**slackdump argv tweaks**: edit `ArchiveRequest.argumentList()`. Add a corresponding `@Test` exhaustively comparing the produced argv against an expected `[String]`. The argv builder is pure and well-tested — drift gets caught early.

For UI changes: the form lives in `RootView`, the workspace flow in `WorkspaceSheet`, settings in `Views/Settings/`. The scope picker is segmented (Entire / Channel-DM / Thread URL) and switching auto-refreshes the channel cache if it's empty.
